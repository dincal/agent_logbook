"""The thread, post and replies commands behind scripts/slack.sh.

Each issue gets one Slack thread, recorded by a hidden marker in an issue comment. `thread`
posts the parent message, `post` replies in the thread with a stage's text and attachments,
and `replies` hands out the replies people added since the last call. The settings and the
GitHub and Slack calls come from slack_config.py; the last stdout line is one line for the chat.
"""

import argparse
import hashlib
import json
import re
import sys
import tempfile
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from slack_config import (  # noqa: E402
    FAILED, MARKER_FIELDS, NO_TOKEN, OFF, OK, PAGE_STAGES, STAGES, TRUSTED_AUTHORS, Failure, GitHub,
    channel, marker_comment, parse_marker, replace_marker, slack_call, token, tracker,
    upload_bytes,
)

PERMALINK = re.compile(r"Slack 쓰레드: (\S+)")


class Context:
    """What every command needs: the channel, the token and the tracker's GitHub."""

    def __init__(self, chan, tok, directory):
        self.chan = chan
        self.tok = tok
        conf = tracker(directory)
        self.account = conf["account"]
        self.gh = GitHub(conf["repo"], conf["account"])

    def call(self, method, **params):
        return slack_call(method, params, self.tok)


# ---------------------------------------------------------------- small helpers

def _field(resp, key, method):
    """A field Slack must return; a missing one is a failure, not a traceback."""
    if key not in resp:
        raise Failure(f"Slack {method} 응답에 {key}가 없습니다")
    return resp[key]


def _escape(text):
    """Escape the three characters Slack mrkdwn reserves."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _object_particle(word):
    """을 or 를 after `word`, read the Korean way (PR -> 피알을)."""
    last = word[-1]
    if "가" <= last <= "힣":
        return "을" if (ord(last) - 0xAC00) % 28 else "를"
    return "을" if last.upper() in "LMNR" else "를"


def _ts(value):
    try:
        return Decimal(value)
    except (InvalidOperation, TypeError):
        return Decimal(0)


def _read_bytes(path, what):
    try:
        return Path(path).read_bytes()
    except OSError as e:
        raise Failure(f"{what}을 읽지 못했습니다: {path} ({e.__class__.__name__})")


def _issue_number(value):
    digits = value.lstrip("#")
    if not digits.isdigit():
        raise argparse.ArgumentTypeError(f"이슈 번호는 숫자여야 합니다: {value}")
    return int(digits)


# ---------------------------------------------------------------- the thread record

def find_record(ctx, issue):
    """{id, body, mark} of the first issue comment holding this channel's marker, or None."""
    for comment in ctx.gh.comments(issue):
        if comment.get("author_association") not in TRUSTED_AUTHORS:
            continue
        mark = parse_marker(comment.get("body"), expected_channel=ctx.chan)
        if mark is not None:
            return {"id": comment["id"], "body": comment["body"], "mark": mark}
    return None


def save_mark(ctx, record):
    """Rewrite the record's marker with its current fields."""
    body = replace_marker(record["body"], record["mark"])
    ctx.gh.edit_comment(record["id"], body)
    record["body"] = body


def permalink(ctx, ts):
    try:
        return ctx.call("chat.getPermalink", channel=ctx.chan, message_ts=ts).get("permalink", "")
    except Failure:
        return ""


def parent_text(ctx, issue, backlog):
    info = ctx.gh.issue(issue)
    who = ctx.account or ctx.gh.login()
    prefix = "[백로그] " if backlog else ""
    return f"{prefix}*#{issue} {_escape(info.get('title', ''))}*\n{info.get('url', '')}\n올린 사람: {who}"


def create_thread(ctx, issue, backlog=False):
    """Post the parent message and record it in an issue comment. When the record cannot
    be written, delete the message so the next run does not leave a second thread."""
    resp = ctx.call("chat.postMessage", channel=ctx.chan, text=parent_text(ctx, issue, backlog))
    ts = _field(resp, "ts", "chat.postMessage")
    link = permalink(ctx, ts)
    mark = {k: "" for k in MARKER_FIELDS}
    mark.update(channel=ctx.chan, ts=ts)
    body = marker_comment(mark, link)
    try:
        comment_id = ctx.gh.add_comment(issue, body)
    except Failure as e:
        try:
            ctx.call("chat.delete", channel=ctx.chan, ts=ts)
            done = "방금 올린 Slack 상위 메시지를 지웠습니다"
        except Failure:
            done = "방금 올린 Slack 상위 메시지도 지우지 못했으니 손으로 지워 주세요"
        raise Failure(f"쓰레드를 이슈 댓글에 기록하지 못해 {done}. ({e})")
    return {"id": comment_id, "body": body, "mark": mark, "link": link}


def ensure_thread(ctx, issue):
    record = find_record(ctx, issue)
    if record is None:
        record = create_thread(ctx, issue)
        print(f"Slack 쓰레드를 만들었습니다: {record['link'] or record['mark']['ts']}")
    return record


# ---------------------------------------------------------------- thread

def cmd_thread(ctx, args):
    record = find_record(ctx, args.issue)
    if record is not None:
        m = PERMALINK.search(record["body"])
        print(f"이미 쓰레드가 있습니다: {m.group(1) if m else record['mark']['ts']}")
        return OK
    record = create_thread(ctx, args.issue, backlog=args.backlog)
    if record["link"]:
        print(f"Slack 쓰레드를 만들었습니다: {record['link']}")
    else:
        print("Slack 쓰레드를 만들었습니다.")
    return OK


# ---------------------------------------------------------------- post

def page_attachments(page, page_hash):
    """[(name, bytes)] for the page's PNG (when Chrome made one) and standalone HTML, and
    the note snapshot left about them."""
    try:
        import snapshot
    except ImportError as e:
        raise Failure(f"화면을 찍는 scripts/snapshot.py를 불러오지 못했습니다: {e}")
    with tempfile.TemporaryDirectory(prefix=f"logbook-slack-{page_hash}-") as tmp:
        try:
            snap = snapshot.snapshot(page, tmp)
        except OSError as e:
            raise Failure(f"화면을 찍지 못했습니다: {e}")
        files = [p for p in (snap.get("png"), snap.get("html")) if p]
        return [(Path(p).name, _read_bytes(p, "화면 사본")) for p in files], snap.get("note") or ""


def upload(ctx, ts, message, attachments):
    """Upload each attachment, then share them all in the thread with the message."""
    entries = []
    for name, content in attachments:
        resp = ctx.call("files.getUploadURLExternal", filename=name, length=len(content))
        upload_bytes(_field(resp, "upload_url", "files.getUploadURLExternal"), content, name,
                     ctx.tok)
        entries.append({"id": _field(resp, "file_id", "files.getUploadURLExternal"),
                        "title": name})
    ctx.call("files.completeUploadExternal", files=entries, channel_id=ctx.chan,
             thread_ts=ts, initial_comment=message)


def reply(ctx, ts, message):
    ctx.call("chat.postMessage", channel=ctx.chan, thread_ts=ts, text=message)


def cmd_post(ctx, args):
    label = STAGES[args.stage]
    text = _read_bytes(args.text, "글 파일").decode("utf-8", "replace") if args.text else ""
    files = [(Path(p).name, _read_bytes(p, "첨부 파일")) for p in args.file]
    page_hash = ""
    if args.page:
        page_hash = hashlib.sha256(_read_bytes(args.page, "화면 파일")).hexdigest()[:12]

    record = ensure_thread(ctx, args.issue)
    ts = record["mark"]["ts"]
    message = f"*{label}*\n" + text
    page_changed = bool(page_hash) and record["mark"].get(args.stage) != page_hash
    if page_hash and not page_changed:
        message += "\n_화면은 지난 게시와 같습니다._"

    attachments = list(files)
    try:
        if page_changed:
            shots, note = page_attachments(args.page, page_hash)
            attachments = shots + attachments
            if note:
                message += "\n" + note
        if attachments:
            upload(ctx, ts, message, attachments)
        else:
            reply(ctx, ts, message)
    except Failure as e:
        if not attachments and not page_changed:
            raise
        # The attachments failed: keep the text in the thread and report the failure.
        reply(ctx, ts, f"{message}\n(첨부 실패: {e})")
        raise Failure(f"Slack 쓰레드에 {label} 글만 올리고 첨부는 실패했습니다: {e}")

    if page_changed:
        record["mark"][args.stage] = page_hash
        save_mark(ctx, record)
    print(f"Slack 쓰레드에 {label}{_object_particle(label)} 올렸습니다.")
    return OK


# ---------------------------------------------------------------- replies

def thread_messages(ctx, ts, oldest):
    """Every message conversations.replies returns after `oldest`, following the pages."""
    messages, cursor = [], None
    while True:
        resp = ctx.call("conversations.replies", channel=ctx.chan, ts=ts, oldest=oldest,
                        limit=200, cursor=cursor)
        messages.extend(resp.get("messages") or [])
        cursor = (resp.get("response_metadata") or {}).get("next_cursor")
        if not cursor:
            return messages


class Names:
    """Display names from users.info, asked once per user; the user ID when Slack has none."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.cache = {}

    def __call__(self, user):
        if not user:
            return "알 수 없음"
        if user not in self.cache:
            self.cache[user] = self._lookup(user)
        return self.cache[user]

    def _lookup(self, user):
        try:
            info = self.ctx.call("users.info", user=user).get("user") or {}
        except Failure:
            return user
        profile = info.get("profile") or {}
        return (profile.get("display_name") or profile.get("real_name")
                or info.get("real_name") or info.get("name") or user)


# Subtypes a person's reply can carry: also sent to the channel, or with a file attached.
HUMAN_SUBTYPES = ("thread_broadcast", "file_share")


def new_replies(messages, parent_ts, read, bot_user=""):
    """People's replies newer than `read`, oldest first: no parent, bots (logbook's own posts
    included) or system messages."""
    floor = _ts(read)
    picked = [m for m in messages
              if m.get("ts") and m["ts"] != parent_ts and not m.get("bot_id")
              and (not bot_user or m.get("user") != bot_user)
              and m.get("subtype", "") in ("",) + HUMAN_SUBTYPES and _ts(m["ts"]) > floor]
    unique = {m["ts"]: m for m in picked}
    return sorted(unique.values(), key=lambda m: _ts(m["ts"]))


def bot_user(ctx):
    """The bot's own user id, so its file posts never count as replies; "" when unknown."""
    try:
        return ctx.call("auth.test").get("user_id", "")
    except Failure:
        return ""


def cmd_replies(ctx, args):
    record = find_record(ctx, args.issue)
    if record is None:
        print("Slack 쓰레드가 아직 없습니다.")
        return OK
    ts = record["mark"]["ts"]
    read = record["mark"].get("read") or ts
    fresh = new_replies(thread_messages(ctx, ts, read), ts, read, bot_user(ctx))
    name = Names(ctx)
    for m in fresh:
        when = datetime.fromtimestamp(float(m["ts"])).strftime("%Y-%m-%d %H:%M")
        print(json.dumps({"user": name(m.get("user", "")), "time": when,
                          "text": m.get("text", ""), "ts": m["ts"]}, ensure_ascii=False))
    if not fresh:
        print("새 답글이 없습니다.")
        return OK
    record["mark"]["read"] = fresh[-1]["ts"]
    save_mark(ctx, record)
    print(f"새 답글 {len(fresh)}개를 읽었습니다.")
    return OK


# ---------------------------------------------------------------- entry point

def parser():
    p = argparse.ArgumentParser(prog="slack.sh",
                                description="Post an issue's logbook stages to its Slack thread.")
    sub = p.add_subparsers(dest="command", required=True)

    t = sub.add_parser("thread", help="post the issue's parent message unless it has a thread")
    t.add_argument("issue", type=_issue_number)
    t.add_argument("--backlog", action="store_true", help="mark the parent message as backlog")

    s = sub.add_parser("post", help="reply in the issue's thread, creating it when missing")
    s.add_argument("issue", type=_issue_number)
    s.add_argument("stage", choices=list(STAGES))
    s.add_argument("--text", metavar="FILE", help="UTF-8 text of the reply")
    s.add_argument("--page", metavar="HTML",
                   help="page attached as PNG and HTML when it changed (brief, debrief)")
    s.add_argument("--file", metavar="PATH", action="append", default=[],
                   help="file attached as it is; repeatable")

    r = sub.add_parser("replies", help="print the replies added since the last call")
    r.add_argument("issue", type=_issue_number)

    for each in (t, s, r):
        each.add_argument("--dir", default=".", help="the repository (default: cwd)")
    return p


COMMANDS = {"thread": cmd_thread, "post": cmd_post, "replies": cmd_replies}


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = parser()
    args = p.parse_args(argv)
    if args.command == "post" and args.page and args.stage not in PAGE_STAGES:
        p.error(f"--page는 {', '.join(PAGE_STAGES)} 단계에서만 씁니다")

    try:
        directory = str(Path(args.dir).resolve())
        chan = channel(directory)
        if chan is None:
            print("Slack 채널이 설정되지 않아 건너뜁니다.")
            return OFF
        tok = token()
        if not tok:
            print("LOGBOOK_SLACK_TOKEN이 없어 Slack 게시를 건너뜁니다.")
            return NO_TOKEN
        return COMMANDS[args.command](Context(chan, tok, directory), args)
    except Failure as e:
        # One line for the chat, even when gh or Slack answered with several.
        print(" ".join(str(e).split()))
        return FAILED
    except Exception as e:  # noqa: BLE001 - Slack must never stop the calling skill
        print(" ".join(f"Slack 게시 중 예상하지 못한 오류가 났습니다: {type(e).__name__}: {e}".split()))
        return FAILED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
