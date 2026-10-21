"""Shared parts of logbook's Slack posting: settings, the thread marker, and the GitHub
and Slack calls. slack.py builds the stages on these; tests fake `gh` and the Slack API
(LOGBOOK_SLACK_API) at exactly these seams."""

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

OK, OFF, NO_TOKEN, FAILED = 0, 10, 11, 12
# The stages a reply can belong to, in the order an issue meets them, with their label.
STAGES = {
    "design": "시안 승인",
    "brief": "브리핑",
    "approve": "브리핑 승인",
    "wave": "묶음 끝",
    "check": "확인할 결과",
    "pr": "PR",
    "debrief": "디브리핑",
    "close": "머지와 닫힘",
    "feedback": "피드백 요약",
}
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
    """The Slack channel ID: the AGENTS.md line (committed, so the whole team shares it),
    else LOGBOOK_SLACK_CHANNEL, a personal default for every project, else None. A worktree
    cut before the line was committed falls back to the main checkout's copy."""
    for root in (toplevel(directory), main_checkout(directory)):
        agents = root / "AGENTS.md"
        if agents.is_file():
            m = CHANNEL_LINE.search(agents.read_text(encoding="utf-8"))
            if m:
                return m.group(1)
    default = os.environ.get("LOGBOOK_SLACK_CHANNEL", "").strip()
    if default and not re.fullmatch(r"[A-Z0-9]+", default):
        # A name such as #dev would make the thread but fail every upload and reply read.
        raise Failure(f"LOGBOOK_SLACK_CHANNEL에는 채널 이름이 아니라 C0123ABCD 같은 채널 ID를 넣어야 합니다: {default}")
    return default or None


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

# Comment authors whose thread marker is trusted: people with write access to the repository.
# Anyone else could leave a marker that points logbook's posts at another thread.
TRUSTED_AUTHORS = ("OWNER", "MEMBER", "COLLABORATOR")

# channel and ts locate the thread, brief and debrief hold the hash of the page last posted
# for that stage, and read is the ts of the newest reply `replies` has handed out.
MARKER_FIELDS = ("channel", "ts") + PAGE_STAGES + ("read",)


def parse_marker(body, expected_channel=None):
    """{channel, ts, brief, debrief, read} from an issue comment body, or None. With
    expected_channel, a marker naming another channel is ignored, so a comment anyone can
    add cannot send the issue's pages to a channel of their choosing."""
    m = MARKER.search(body or "")
    if not m:
        return None
    fields = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
    if not fields.get("channel") or not fields.get("ts"):
        return None
    if expected_channel and fields["channel"] != expected_channel:
        return None
    return {k: fields.get(k, "") for k in MARKER_FIELDS}


def format_marker(mark):
    parts = [f"{k}={mark[k]}" for k in MARKER_FIELDS if mark.get(k)]
    return "<!-- logbook:slack " + " ".join(parts) + " -->"


def replace_marker(body, mark):
    """The comment body with its marker rewritten, keeping the visible link as it is."""
    return MARKER.sub(lambda _: format_marker(mark), body, count=1)


def marker_comment(mark, permalink):
    """The issue comment that records the thread: a visible link and the hidden marker."""
    link = f"Slack 쓰레드: {permalink}" if permalink else "Slack 쓰레드를 만들었습니다."
    return f"{link}\n\n{format_marker(mark)}\n"


# ---------------------------------------------------------------- GitHub (gh)

class GitHub:
    """The gh calls slack.py makes. Every call goes through `gh api` or `gh issue view`
    with GH_TOKEN for the tracker's account, so a fake gh on PATH can answer them."""

    def __init__(self, repo, account):
        if not repo:
            raise Failure("저장소를 알 수 없습니다. /rulebook으로 .logbook/config.json을 만드세요")
        self.repo = repo
        # Plain, uncolored JSON one object per line, whatever the caller's terminal settings.
        self.env = {k: v for k, v in os.environ.items()
                    if k not in ("GH_FORCE_TTY", "CLICOLOR_FORCE")}
        self.env["NO_COLOR"] = "1"
        if account:
            try:
                out = subprocess.run(["gh", "auth", "token", "--user", account],
                                     capture_output=True, text=True, env=self.env)
            except FileNotFoundError:
                raise Failure("gh를 찾지 못했습니다")
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
        return _json(self._run(["issue", "view", str(number), "--repo", self.repo,
                                "--json", "title,url,state"]))

    def comments(self, number):
        """[{id, body, author_association}] oldest first."""
        out = self._run(["api", "--paginate", f"repos/{self.repo}/issues/{number}/comments",
                         "--jq", ".[] | {id, body, author_association}"])
        return [_json(line) for line in out.splitlines() if line.strip()]

    def add_comment(self, number, body):
        """The new comment's id."""
        out = self._run(["api", "-X", "POST", f"repos/{self.repo}/issues/{number}/comments",
                         "-f", f"body={body}", "--jq", ".id"])
        try:
            return int(out.strip())
        except ValueError:
            raise Failure(f"gh가 댓글 번호 대신 다른 값을 돌려줬습니다: {out.strip()[:80]}")

    def edit_comment(self, comment_id, body):
        self._run(["api", "-X", "PATCH", f"repos/{self.repo}/issues/comments/{comment_id}",
                   "-f", f"body={body}", "--jq", ".id"])

    def login(self):
        return self._run(["api", "user", "--jq", ".login"]).strip()


def _json(text):
    try:
        return json.loads(text)
    except ValueError:
        raise Failure(f"gh 출력을 JSON으로 읽지 못했습니다: {text.strip()[:80]}")


# ---------------------------------------------------------------- Slack Web API

def slack_call(method, params, tok):
    """POST a Web API method as a form (JSON for list-valued params) and return its JSON.
    Raises Failure when the HTTP call fails or Slack answers ok=false."""
    data = {k: json.dumps(v) if isinstance(v, (list, dict, bool)) else str(v)
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


def upload_bytes(url, content, filename, tok, retry_delay=2):
    """Send a file's bytes to the URL files.getUploadURLExternal handed out. Slack's upload
    host now and then answers 504 for a moment, so a server error or a network error is
    tried once more after a short pause."""
    req = urllib.request.Request(url, data=content, method="POST",
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Content-Type": "application/octet-stream"})
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                if resp.status >= 300:
                    raise Failure(f"Slack 파일 업로드 실패({filename}): HTTP {resp.status}")
                return
        except urllib.error.HTTPError as e:
            if attempt == 1 and e.code >= 500:
                time.sleep(retry_delay)
                continue
            raise Failure(f"Slack 파일 업로드 실패({filename}): {e}")
        except (urllib.error.URLError, OSError) as e:
            if attempt == 1:
                time.sleep(retry_delay)
                continue
            raise Failure(f"Slack 파일 업로드 실패({filename}): {e}")
