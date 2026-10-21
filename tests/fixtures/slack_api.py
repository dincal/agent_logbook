"""A fake Slack Web API for tests/run.sh.

usage: python3 slack_api.py <port-file> <log-file>

Binds 127.0.0.1 on a free port, writes the port to <port-file> and serves until killed.
Every request appends one JSON line {"method", "params"} to <log-file> (chat.postMessage
also records the "ts" it handed out). The text and blocks of every chat.postMessage are
remembered by ts and replaced on chat.update. Environment:
  FAKE_SLACK_REPLIES  path of a JSON file holding the messages conversations.replies returns
                      (read on every call; when unset or missing, only the parent is returned:
                      the remembered message when there is one, else a bare one)
  FAKE_SLACK_FAIL     a method name that answers {"ok": false, "error": "fake_failure"}
  FAKE_SLACK_INVALID_BLOCKS
                      when set, files.completeUploadExternal with "blocks" answers
                      {"ok": false, "error": "invalid_blocks"}; without blocks it still succeeds
  FAKE_SLACK_SETTINGS path of a JSON object read on every request; its keys (the two names
                      above) override the environment, so a test can turn them on for one run
"""

import json
import os
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2]
LOCK = threading.Lock()
STATE = {"ts": 0, "file": 0}
# ts -> {"ts", "user", "text", "blocks"} of the messages chat.postMessage made.
MESSAGES = {}


def setting(name):
    """FAKE_SLACK_SETTINGS' value for `name` when the file has it, else the environment's."""
    path = os.environ.get("FAKE_SLACK_SETTINGS", "")
    if path:
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        if isinstance(data, dict) and name in data:
            return str(data[name] or "")
    return os.environ.get(name, "")


def parse_blocks(params):
    """The "blocks" param as a list, None when absent (or not JSON)."""
    raw = params.get("blocks")
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


def remember(ts, params, update=False):
    with LOCK:
        msg = MESSAGES.get(ts)
        if msg is None:
            if update:
                return
            msg = MESSAGES[ts] = {"ts": ts, "user": "U0BOT", "text": ""}
        msg["text"] = params.get("text", "")
        blocks = parse_blocks(params)
        if blocks is None:
            msg.pop("blocks", None)
        else:
            msg["blocks"] = blocks


def log(entry):
    with LOCK, open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def next_ts():
    with LOCK:
        STATE["ts"] += 1
        return f"1700000000.{STATE['ts']:06d}"


def next_file():
    with LOCK:
        STATE["file"] += 1
        return STATE["file"]


def replies(params):
    """The thread's messages, newer than `oldest` when given (Slack's default is exclusive)."""
    ts = params.get("ts", "")
    with LOCK:
        known = MESSAGES.get(ts)
        parent = json.loads(json.dumps(known)) if known else {"ts": ts, "user": "U0PARENT",
                                                              "text": "parent"}
    path = os.environ.get("FAKE_SLACK_REPLIES", "")
    try:
        with open(path, encoding="utf-8") as f:
            messages = json.load(f)
    except (OSError, ValueError):
        messages = [parent]
    oldest = params.get("oldest")
    if oldest:
        messages = [m for m in messages
                    if m.get("ts") == params.get("ts") or float(m["ts"]) > float(oldest)]
    try:
        limit = int(params.get("limit") or 0)
    except ValueError:
        limit = 0
    if limit > 0:
        messages = messages[:limit]
    return {"ok": True, "messages": messages, "has_more": False}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.do_POST()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        path = urllib.parse.urlparse(self.path)
        parts = [p for p in path.path.split("/") if p]
        if len(parts) == 2 and parts[0] == "upload":
            # While the file FAKE_SLACK_UPLOAD_5XX names exists, the next upload answers 504
            # once (the file is removed), as Slack's upload host sometimes does.
            flaky = os.environ.get("FAKE_SLACK_UPLOAD_5XX")
            if flaky and os.path.exists(flaky):
                os.remove(flaky)
                log({"method": "upload-504", "params": {"id": parts[1]}})
                self.send_response(504)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            log({"method": "upload", "params": {"id": parts[1], "bytes": len(raw)}})
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"OK")
            return
        method = parts[-1] if parts else ""
        form = urllib.parse.parse_qs(raw.decode("utf-8", "replace"), keep_blank_values=True)
        form.update(urllib.parse.parse_qs(path.query, keep_blank_values=True))
        params = {k: v[-1] for k, v in form.items()}
        entry = {"method": method, "params": params}
        if setting("FAKE_SLACK_FAIL") == method:
            log(entry)
            self.answer({"ok": False, "error": "fake_failure"})
            return
        if method == "chat.postMessage":
            ts = next_ts()
            entry["ts"] = ts
            remember(ts, params)
            log(entry)
            self.answer({"ok": True, "channel": params.get("channel", ""), "ts": ts})
            return
        log(entry)
        port = self.server.server_address[1]
        if method == "chat.delete":
            self.answer({"ok": True, "channel": params.get("channel", ""), "ts": params.get("ts", "")})
        elif method == "chat.getPermalink":
            self.answer({"ok": True, "permalink": f"https://slack.example/p/{params.get('message_ts', '')}"})
        elif method == "files.getUploadURLExternal":
            n = next_file()
            self.answer({"ok": True, "upload_url": f"http://127.0.0.1:{port}/upload/{n}",
                         "file_id": f"F{n}"})
        elif method == "files.completeUploadExternal":
            if setting("FAKE_SLACK_INVALID_BLOCKS") and "blocks" in params:
                self.answer({"ok": False, "error": "invalid_blocks"})
            else:
                self.answer({"ok": True, "files": []})
        elif method == "conversations.replies":
            self.answer(replies(params))
        elif method == "chat.update":
            remember(params.get("ts", ""), params, update=True)
            self.answer({"ok": True, "ts": params.get("ts", "")})
        elif method == "auth.test":
            self.answer({"ok": True, "user_id": "U0BOT"})
        elif method == "users.info":
            uid = params.get("user", "")
            self.answer({"ok": True, "user": {"id": uid, "name": uid.lower(),
                                              "profile": {"display_name": f"Name-{uid}"}}})
        else:
            self.answer({"ok": False, "error": "unknown_method"})


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    tmp = PORT_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(server.server_address[1]))
    os.replace(tmp, PORT_FILE)
    server.serve_forever()


if __name__ == "__main__":
    main()
