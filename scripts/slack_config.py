"""Shared parts of logbook's Slack posting: settings, the thread marker, and the GitHub
and Slack calls. slack.py builds the stages on these; tests fake `gh` and the Slack API
(LOGBOOK_SLACK_API) at exactly these seams."""

import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OK, OFF, NO_TOKEN, FAILED = 0, 10, 11, 12
STAGES = ("brief", "approve", "debrief", "close")
# Stages whose page is attached; the marker keeps the hash of the page last posted for each.
PAGE_STAGES = ("brief", "debrief")

CHANNEL_LINE = re.compile(r"^- Slack 채널: `([A-Z0-9]+)`\s*$", re.M)
MARKER = re.compile(r"<!-- logbook:slack ([^>]*?) -->")


class Failure(Exception):
    """A Slack, GitHub or Chrome call failed; the message is the one line for the chat."""


def toplevel(directory):
    """The working tree root of `directory`, or `directory` itself outside git."""
    out = subprocess.run(["git", "-C", directory, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    return Path(out.stdout.strip() if out.returncode == 0 else directory)


def main_checkout(directory):
    """The main checkout: the folder above the shared .git, also from a linked worktree."""
    out = subprocess.run(["git", "-C", directory, "rev-parse", "--path-format=absolute",
                          "--git-common-dir"], capture_output=True, text=True)
    if out.returncode == 0 and out.stdout.strip().endswith("/.git"):
        return Path(out.stdout.strip()).parent
    return toplevel(directory)


def channel(directory):
    """The Slack channel ID from AGENTS.md (committed, so the whole team shares it), or None."""
    agents = toplevel(directory) / "AGENTS.md"
    if not agents.is_file():
        return None
    m = CHANNEL_LINE.search(agents.read_text(encoding="utf-8"))
    return m.group(1) if m else None


def tracker(directory):
    """repo, base and account from .logbook/config.json in the main checkout."""
    path = main_checkout(directory) / ".logbook" / "config.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    return {k: data.get(k, "") for k in ("repo", "base", "account")}


def token():
    return os.environ.get("LOGBOOK_SLACK_TOKEN", "").strip()


def api_base():
    return os.environ.get("LOGBOOK_SLACK_API", "https://slack.com/api").rstrip("/")


# ---------------------------------------------------------------- thread marker

def parse_marker(body):
    """{channel, ts, brief, debrief} from an issue comment body, or None."""
    m = MARKER.search(body or "")
    if not m:
        return None
    fields = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
    if not fields.get("channel") or not fields.get("ts"):
        return None
    return {k: fields.get(k, "") for k in ("channel", "ts") + PAGE_STAGES}


def format_marker(mark):
    parts = [f"channel={mark['channel']}", f"ts={mark['ts']}"]
    parts += [f"{s}={mark[s]}" for s in PAGE_STAGES if mark.get(s)]
    return "<!-- logbook:slack " + " ".join(parts) + " -->"


def marker_comment(mark, permalink):
    """The issue comment that records the thread: a visible link and the hidden marker."""
    link = f"Slack 쓰레드: {permalink}" if permalink else "Slack 쓰레드를 만들었습니다."
    return f"{link}\n\n{format_marker(mark)}\n"


# ---------------------------------------------------------------- GitHub (gh)

class GitHub:
    """The gh calls slack.py makes. Every call goes through `gh api` or `gh issue view`
    with GH_TOKEN for the tracker's account, so a fake gh on PATH can answer them."""

    def __init__(self, repo, account):
        self.repo = repo
        self.env = dict(os.environ)
        if account:
            out = subprocess.run(["gh", "auth", "token", "--user", account],
                                 capture_output=True, text=True)
            if out.returncode == 0 and out.stdout.strip():
                self.env["GH_TOKEN"] = out.stdout.strip()

    def _run(self, args):
        try:
            out = subprocess.run(["gh", *args], capture_output=True, text=True, env=self.env)
        except FileNotFoundError:
            raise Failure("gh를 찾지 못했습니다")
        if out.returncode != 0:
            raise Failure(f"gh {args[0]} 실패: {(out.stderr or out.stdout).strip()[:200]}")
        return out.stdout

    def issue(self, number):
        """{title, url, state}"""
        return json.loads(self._run(["issue", "view", str(number), "--repo", self.repo,
                                     "--json", "title,url,state"]))

    def comments(self, number):
        """[{id, body}] oldest first."""
        out = self._run(["api", "--paginate", f"repos/{self.repo}/issues/{number}/comments",
                         "--jq", ".[] | {id, body}"])
        return [json.loads(line) for line in out.splitlines() if line.strip()]

    def add_comment(self, number, body):
        """The new comment's id."""
        out = self._run(["api", "-X", "POST", f"repos/{self.repo}/issues/{number}/comments",
                         "-f", f"body={body}", "--jq", ".id"])
        return int(out.strip())

    def edit_comment(self, comment_id, body):
        self._run(["api", "-X", "PATCH", f"repos/{self.repo}/issues/comments/{comment_id}",
                   "-f", f"body={body}", "--jq", ".id"])

    def login(self):
        return self._run(["api", "user", "--jq", ".login"]).strip()


# ---------------------------------------------------------------- Slack Web API

def slack_call(method, params, tok):
    """POST a Web API method as a form (JSON for list-valued params) and return its JSON.
    Raises Failure when the HTTP call fails or Slack answers ok=false."""
    data = {k: json.dumps(v) if isinstance(v, (list, dict)) else str(v)
            for k, v in params.items() if v is not None}
    req = urllib.request.Request(
        f"{api_base()}/{method}", data=urllib.parse.urlencode(data).encode(),
        headers={"Authorization": f"Bearer {tok}",
                 "Content-Type": "application/x-www-form-urlencoded; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode())
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Failure(f"Slack {method} 호출 실패: {e}")
    if not body.get("ok"):
        raise Failure(f"Slack {method} 실패: {body.get('error', 'unknown')}")
    return body


def upload_bytes(url, content, filename, tok):
    """Send a file's bytes to the URL files.getUploadURLExternal handed out."""
    req = urllib.request.Request(url, data=content, method="POST",
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Content-Type": "application/octet-stream"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            if resp.status >= 300:
                raise Failure(f"Slack 파일 업로드 실패({filename}): HTTP {resp.status}")
    except (urllib.error.URLError, OSError) as e:
        raise Failure(f"Slack 파일 업로드 실패({filename}): {e}")
