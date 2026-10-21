"""The thread, post and replies commands behind scripts/slack.sh.

Each issue gets one Slack thread, recorded by a hidden marker in an issue comment. A PR
opened without an issue gets one too, keyed by the PR number (kind=pr in the marker): it shows
two phases and takes only the close stage. `thread`
posts the parent message, `post` replies in the thread with a stage's text and attachments,
and `replies` hands out the replies people added since the last call. Messages go up as Block
Kit blocks (a header per stage, the progress line, the body, a small footer) with the same
words as plain text; a stage that moves the issue to another phase also redraws the progress
line on the first message. The settings, the stages and phases, and the GitHub and Slack calls
come from slack_config.py; the last stdout line is one line for the chat.
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
    BLOCK_CLOSED, BLOCK_STATUS, BLOCK_SUMMARY, CLOSED_NOTICE, FAILED, MARKER_FIELDS, NO_TOKEN,
    OFF, OK, OUTCOME_TITLES, OUTCOMES, PAGE_STAGES, PR_STAGES, REQUIRED_OUTCOME, STAGES,
    TRUSTED_AUTHORS, USAGE, Failure, GitHub, channel, is_closed, marker_comment, next_phase, parse_marker,
    progress_line, replace_marker, slack_call, stage_title, token, tracker, upload_bytes,
)

PERMALINK = re.compile(r"Slack 쓰레드: (\S+)")
# The first message's developer line, read back so a redraw keeps who posted the thread.
WHO = re.compile(r"올린 사람: (.*?) · 개발자용:")


class Refused(Exception):
    """Arguments a PR thread does not take; exits USAGE (2) before any Slack call."""


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


def _unescape(text):
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


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
        raise argparse.ArgumentTypeError(f"이슈나 PR 번호는 숫자여야 합니다: {value}")
    return int(digits)


def issue_kind(info):
    """"pr" when gh issue view answered for a pull request, "" for an issue."""
    return "pr" if re.search(r"/pull/\d+/?$", info.get("url") or "") else ""


def _developer_link(issue, info, kind):
    label = "GitHub PR" if kind == "pr" else "GitHub 이슈"
    return f"<{info.get('url', '')}|{label} #{issue}>"


# ---------------------------------------------------------------- Block Kit

SECTION_MAX = 3000  # characters in a section's text or a context element's
HEADER_MAX = 150    # characters in a header
BLOCKS_MAX = 50     # blocks in one message
DIVIDER = {"type": "divider"}
# Footer lines: a body line starting with DEV_PREFIX moves there, and so does ATTACH_NOTE,
# which the script adds itself whenever a page is attached.
DEV_PREFIX = "개발자용:"
ATTACH_NOTE = "첨부한 그림과 HTML 파일은 개발자용 자세한 설명입니다."
SAME_PAGE_NOTE = "화면은 지난 게시와 같습니다."


def _cut(text, limit):
    """`text`, cut to `limit` characters ending in "…" when it is longer."""
    return text if len(text) <= limit else text[:limit - 1] + "…"


def _header(text):
    return {"type": "header",
            "text": {"type": "plain_text", "text": _cut(text, HEADER_MAX), "emoji": True}}


def _context(text, block_id=None):
    block = {"type": "context", "elements": [{"type": "mrkdwn", "text": _cut(text, SECTION_MAX)}]}
    if block_id:
        block["block_id"] = block_id
    return block


def _section(text, block_id=None):
    block = {"type": "section", "text": {"type": "mrkdwn", "text": _cut(text, SECTION_MAX)}}
    if block_id:
        block["block_id"] = block_id
    return block


def _units(text, limit):
    """[(separator, piece)] of `text`: whole paragraphs (split on blank lines), and for a
    paragraph longer than `limit` its lines, a line longer than that cut by characters. The
    separator is what joined the piece to the one before it."""
    units = []
    for paragraph in re.split(r"\n\s*\n", text.strip()):
        if not paragraph.strip():
            continue
        if len(paragraph) <= limit:
            units.append(("\n\n", paragraph))
            continue
        sep = "\n\n"
        for line in paragraph.split("\n"):
            for i in range(0, max(len(line), 1), limit):
                units.append((sep, line[i:i + limit]))
                sep = ""
            sep = "\n"
    return units


def _body_sections(text, limit=SECTION_MAX):
    """The texts of the sections `text` fills, each at most `limit`; [] for an empty text."""
    sections = []
    for sep, piece in _units(text, limit):
        if sections and len(sections[-1]) + len(sep) + len(piece) <= limit:
            sections[-1] += sep + piece
        else:
            sections.append(piece)
    return sections


def _cap(sections, room):
    """At most `room` sections: the ones past it are merged into the last kept one, cut
    with "…" where they do not fit."""
    if len(sections) <= room:
        return sections
    return sections[:room - 1] + [_cut("\n\n".join(sections[room - 1:]), SECTION_MAX)]


def _reply_parts(body, notes):
    """(body without its footer lines, the footer lines): the body's developer lines and
    attachment line, then the notes, each once."""
    kept, footer = [], []
    for line in body.split("\n"):
        if line.strip().startswith(DEV_PREFIX) or line.strip() == ATTACH_NOTE:
            footer.append(line.strip())
        else:
            kept.append(line)
    footer = list(dict.fromkeys(n for n in footer + list(notes) if n))
    return "\n".join(kept), footer


def reply_blocks(stage, outcome, phase, body, notes, kind=""):
    """A stage's reply: the title header, the progress line (when the phase is known), a
    divider, the body as sections, and the footer lines under a divider."""
    kept, footer = _reply_parts(body, notes)
    head = [_header(stage_title(stage, outcome))]
    if progress_line(phase, kind):
        head.append(_context(progress_line(phase, kind)))
    head.append(DIVIDER)
    tail = [DIVIDER, _context("\n".join(footer))] if footer else []
    sections = _cap(_body_sections(kept), BLOCKS_MAX - len(head) - len(tail))
    return head + [_section(text) for text in sections] + tail


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


def parent_text(issue, info, who, summary, phase, kind=""):
    """The first message's plain text, the fallback notifications and search read."""
    prefix = "[백로그] " if phase == "later" else ""
    lines = [f"{prefix}*#{issue} {_escape(info.get('title', ''))}*"]
    if summary.strip():
        lines += [summary.strip(), ""]
    if progress_line(phase, kind):
        lines.append(progress_line(phase, kind))
    lines += [f"올린 사람: {_escape(who)}",
              f"개발자용: {_developer_link(issue, info, kind)}"]
    return "\n".join(lines)


def parent_blocks(issue, info, who, summary, phase, kind=""):
    """The thread's first message as blocks. Planners cannot open GitHub, so `summary` (the
    issue written out in plain words) carries the content and the issue link is a developer
    line. The summary and status blocks carry block_ids so a later run can find the summary
    again and redraw only the status; `phase` must be one progress_line knows for `kind`."""
    prefix = "[백로그] " if phase == "later" else ""
    status = progress_line(phase, kind)
    head = [_header(f"{prefix}#{issue} {info.get('title', '')}")]
    tail = [_context(status, BLOCK_STATUS)] if status else []
    if is_closed(phase):
        tail.append(_context(CLOSED_NOTICE, BLOCK_CLOSED))
    tail.append(_context(f"올린 사람: {_escape(who)} · "
                         f"개발자용: {_developer_link(issue, info, kind)}"))
    sections = _cap(_body_sections(summary), BLOCKS_MAX - len(head) - len(tail))
    return (head + [_section(text, f"{BLOCK_SUMMARY}{i}") for i, text in enumerate(sections)]
            + tail)


def parent_message(ctx, issue, summary, phase, who=None, kind="", info=None):
    """{text, blocks} of the first message, with the issue's current title and link; `info`
    is the gh issue view answer when the caller already has it."""
    info = info or ctx.gh.issue(issue)
    who = who or ctx.account or ctx.gh.login()
    return {"text": parent_text(issue, info, who, summary, phase, kind),
            "blocks": parent_blocks(issue, info, who, summary, phase, kind)}


def parent_parts(message):
    """(summary, who) of a first message posted as blocks, or None for one made before the
    blocks (it has no status block, so there is no summary to carry over)."""
    blocks = message.get("blocks") or []
    if not any(b.get("block_id") == BLOCK_STATUS for b in blocks):
        return None
    parts, who = [], None
    for b in blocks:
        block_id = b.get("block_id") or ""
        number = block_id[len(BLOCK_SUMMARY):]
        if block_id.startswith(BLOCK_SUMMARY) and number.isdigit():
            parts.append((int(number), (b.get("text") or {}).get("text", "")))
        for element in b.get("elements") or []:
            m = WHO.match(element.get("text") or "") if isinstance(element, dict) else None
            if m:
                who = _unescape(m.group(1))
    return "\n\n".join(text for _, text in sorted(parts)), who


def read_parent(ctx, ts):
    """The thread's first message as conversations.replies returns it."""
    resp = ctx.call("conversations.replies", channel=ctx.chan, ts=ts, limit=1)
    for m in resp.get("messages") or []:
        if m.get("ts") == ts:
            return m
    raise Failure("Slack 쓰레드 첫 메시지를 찾지 못했습니다")


def rewrite_parent(ctx, issue, ts, phase, kind=""):
    """Redraw the first message for `phase`, keeping its summary and who posted it; False
    when it was made before the blocks and is left as it is (`thread --text` converts it)."""
    parts = parent_parts(read_parent(ctx, ts))
    if parts is None:
        return False
    summary, who = parts
    ctx.call("chat.update", channel=ctx.chan, ts=ts,
             **parent_message(ctx, issue, summary, phase, who, kind))
    return True


def create_thread(ctx, issue, backlog=False, summary="", info=None):
    """Post the parent message and record it in an issue comment (a PR comment for a PR,
    which starts at 확인 and cannot be backlog). When the record cannot be written, delete
    the message so the next run does not leave a second thread."""
    info = info or ctx.gh.issue(issue)
    kind = issue_kind(info)
    if kind == "pr" and backlog:
        raise Refused(f"#{issue}은 PR이라 --backlog를 쓸 수 없습니다. PR 쓰레드는 백로그로 두지 않습니다")
    phase = "check" if kind == "pr" else ("later" if backlog else "plan")
    resp = ctx.call("chat.postMessage", channel=ctx.chan,
                    **parent_message(ctx, issue, summary, phase, kind=kind, info=info))
    ts = _field(resp, "ts", "chat.postMessage")
    link = permalink(ctx, ts)
    mark = {k: "" for k in MARKER_FIELDS}
    mark.update(channel=ctx.chan, ts=ts, phase=phase, shown=phase, kind=kind)
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


def thread_kind(ctx, issue):
    """(record or None, kind, gh issue view answer or None): the kind a marker records, or
    for a number without a thread the one gh issue view tells. No Slack call is made."""
    record = find_record(ctx, issue)
    if record is not None:
        return record, record["mark"].get("kind", ""), None
    info = ctx.gh.issue(issue)
    return None, issue_kind(info), info


# ---------------------------------------------------------------- thread

def cmd_thread(ctx, args):
    summary = _read_bytes(args.text, "글 파일").decode("utf-8", "replace") if args.text else ""
    record, kind, info = thread_kind(ctx, args.issue)
    if kind == "pr" and args.backlog:
        raise Refused(f"#{args.issue}은 PR이라 --backlog를 쓸 수 없습니다. PR 쓰레드는 백로그로 두지 않습니다")
    if record is not None:
        m = PERMALINK.search(record["body"])
        where = m.group(1) if m else record["mark"]["ts"]
        mark = record["mark"]
        if summary:
            # Rewrite the first message so a thread made before the summary or the blocks
            # existed gets them; a marker without a known phase gets the one drawn.
            start = "check" if kind == "pr" else ("later" if args.backlog else "plan")
            phase = (mark.get("phase") if progress_line(mark.get("phase", ""), kind)
                     else start)
            ctx.call("chat.update", channel=ctx.chan, ts=mark["ts"],
                     **parent_message(ctx, args.issue, summary, phase, kind=kind))
            if (mark.get("phase"), mark.get("shown")) != (phase, phase):
                mark.update(phase=phase, shown=phase)
                save_mark(ctx, record)
            print(f"쓰레드 첫 메시지를 이슈 내용으로 고쳤습니다: {where}")
        elif progress_line(mark.get("phase", ""), kind) and mark.get("shown") != mark["phase"]:
            # An earlier post could not redraw the first message (the last one, close, has no
            # later post to retry it), so this run does.
            redrawn = rewrite_parent(ctx, args.issue, mark["ts"], mark["phase"], kind)
            mark["shown"] = mark["phase"]
            save_mark(ctx, record)
            if redrawn:
                print(f"쓰레드 첫 메시지의 진행 표시를 고쳤습니다: {where}")
            else:
                print(f"쓰레드 첫 메시지가 옛 형식이라 그대로 두었습니다. --text로 다시 쓰면 바뀝니다: {where}")
        else:
            print(f"이미 쓰레드가 있습니다: {where}")
        return OK
    record = create_thread(ctx, args.issue, backlog=args.backlog, summary=summary, info=info)
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


def reply_message(stage, outcome, phase, body, notes, kind=""):
    """{text, blocks} of a stage's reply: the blocks for the thread, and the same words as
    plain text for notifications and search."""
    kept, footer = _reply_parts(body, notes)
    lines = [f"*{stage_title(stage, outcome)}*"] + ([kept.strip()] if kept.strip() else [])
    return {"text": "\n".join(lines + footer),
            "blocks": reply_blocks(stage, outcome, phase, body, notes, kind)}


def upload(ctx, ts, message, attachments):
    """Upload each attachment, then share them all in the thread with the message's blocks.
    When Slack refuses blocks on a file share, the message goes up on its own first and the
    files follow it; a failure after that carries posted=True."""
    entries = []
    for name, content in attachments:
        resp = ctx.call("files.getUploadURLExternal", filename=name, length=len(content))
        upload_bytes(_field(resp, "upload_url", "files.getUploadURLExternal"), content, name,
                     ctx.tok)
        entries.append({"id": _field(resp, "file_id", "files.getUploadURLExternal"),
                        "title": name})
    try:
        ctx.call("files.completeUploadExternal", files=entries, channel_id=ctx.chan,
                 thread_ts=ts, blocks=message["blocks"])
        return
    except Failure as e:
        if "invalid_blocks" not in str(e):
            raise
    reply(ctx, ts, message)
    try:
        ctx.call("files.completeUploadExternal", files=entries, channel_id=ctx.chan,
                 thread_ts=ts)
    except Failure as e:
        e.posted = True
        raise


def reply(ctx, ts, message):
    ctx.call("chat.postMessage", channel=ctx.chan, thread_ts=ts, text=message["text"],
             blocks=message["blocks"])


def _stage_name(stage, outcome):
    """The stage's title without its icon, as the chat line names it."""
    return OUTCOME_TITLES[outcome][1] if outcome in OUTCOME_TITLES else STAGES[stage]


def cmd_post(ctx, args):
    stage, outcome = args.stage, args.outcome or ""
    name = _stage_name(stage, outcome)
    text = _read_bytes(args.text, "글 파일").decode("utf-8", "replace") if args.text else ""
    files = [(Path(p).name, _read_bytes(p, "첨부 파일")) for p in args.file]
    page_hash = ""
    if args.page:
        page_hash = hashlib.sha256(_read_bytes(args.page, "화면 파일")).hexdigest()[:12]

    record, kind, info = thread_kind(ctx, args.issue)
    if kind == "pr" and stage not in PR_STAGES:
        raise Refused(f"#{args.issue}은 PR 쓰레드라 {', '.join(PR_STAGES)} 단계만 올릴 수 있습니다: {stage}")
    if record is None:
        record = create_thread(ctx, args.issue, info=info)
        print(f"Slack 쓰레드를 만들었습니다: {record['link'] or record['mark']['ts']}")
    mark = record["mark"]
    ts = mark["ts"]
    phase = next_phase(mark.get("phase", ""), stage, outcome)
    closed = [CLOSED_NOTICE] if stage == "close" or is_closed(phase) else []
    page_changed = bool(page_hash) and mark.get(stage) != page_hash
    notes = [SAME_PAGE_NOTE] if page_hash and not page_changed else []

    attachments, attach_error = list(files), None
    try:
        if page_changed:
            shots, snap_note = page_attachments(args.page, page_hash)
            attachments = shots + attachments
            notes += [ATTACH_NOTE] + ([_escape(snap_note)] if snap_note else [])
        message = reply_message(stage, outcome, phase, text, notes + closed, kind)
        if attachments:
            upload(ctx, ts, message, attachments)
        else:
            reply(ctx, ts, message)
    except Failure as e:
        if not attachments and not page_changed:
            raise
        # The attachments failed: keep the text in the thread and report the failure.
        attach_error = e
        if not getattr(e, "posted", False):
            kept = [n for n in notes if n != ATTACH_NOTE]
            reply(ctx, ts, reply_message(stage, outcome, phase, text,
                                         kept + [f"첨부 실패: {_escape(str(e))}"] + closed,
                                         kind))

    changed, problems = False, []
    if page_changed and attach_error is None:
        mark[stage] = page_hash
        changed = True
    if phase != mark.get("phase", ""):
        mark["phase"] = phase
        changed = True
    if phase != mark.get("shown", ""):
        try:
            rewrite_parent(ctx, args.issue, ts, phase, kind)
            # Recorded only once the first message shows it, so a failed rewrite is retried
            # by the next post or by `slack.sh thread <issue>`.
            mark["shown"] = phase
            changed = True
        except Failure as e:
            problems.append(f"첫 메시지 진행 표시를 고치지 못했습니다: {e}. "
                            f"slack.sh thread {args.issue}로 다시 고칠 수 있습니다")
    if changed:
        try:
            save_mark(ctx, record)
        except Failure as e:
            problems.append(f"이슈 댓글의 쓰레드 표시를 고치지 못했습니다: {e}")

    if attach_error is not None:
        raise Failure(" ".join([f"Slack 쓰레드에 {name} 글만 올리고 첨부는 실패했습니다: "
                                f"{attach_error}."] + problems))
    if problems:
        raise Failure("글은 올렸지만 " + " ".join(problems))
    print(f"Slack 쓰레드에 {name}{_object_particle(name)} 올렸습니다.")
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
                                description="Post an issue's (or an issue-less PR's) "
                                            "logbook stages to its Slack thread.")
    sub = p.add_subparsers(dest="command", required=True)

    t = sub.add_parser("thread", help="post the issue's parent message unless it has a thread")
    t.add_argument("issue", type=_issue_number)
    t.add_argument("--backlog", action="store_true", help="mark the parent message as backlog")
    t.add_argument("--text", metavar="FILE",
                   help="the issue written out in plain words; rewrites an existing first message")

    s = sub.add_parser("post", help="reply in the issue's thread, creating it when missing")
    s.add_argument("issue", type=_issue_number)
    s.add_argument("stage", choices=list(STAGES))
    s.add_argument("--text", metavar="FILE", help="UTF-8 text of the reply")
    s.add_argument("--outcome", choices=list(dict.fromkeys(v for vs in OUTCOMES.values()
                                                            for v in vs)),
                   help="how the stage ended: approve later|dropped, close merged|dropped (required)")
    s.add_argument("--page", metavar="HTML",
                   help="page attached as PNG and HTML when it changed (brief, debrief)")
    s.add_argument("--file", metavar="PATH", action="append", default=[],
                   help="file attached as it is; repeatable")

    r = sub.add_parser("replies", help="print the replies added since the last call")
    r.add_argument("issue", type=_issue_number)

    c = sub.add_parser("check", help="exit 0 when Slack posting is on, 10 or 11 when it is off, 12 on a setup error")

    for each in (t, s, r, c):
        each.add_argument("--dir", default=".", help="the repository (default: cwd)")
    return p


def cmd_check(ctx, args):
    """Reached only when the channel and the token are set; nothing is called."""
    print("Slack 게시가 켜져 있습니다.")
    return OK


COMMANDS = {"thread": cmd_thread, "post": cmd_post, "replies": cmd_replies, "check": cmd_check}


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = parser()
    args = p.parse_args(argv)
    if args.command == "post" and args.page and args.stage not in PAGE_STAGES:
        p.error(f"--page는 {', '.join(PAGE_STAGES)} 단계에서만 씁니다")
    if args.command == "post":
        allowed = OUTCOMES.get(args.stage, ())
        if args.outcome and not allowed:
            p.error(f"--outcome은 {', '.join(OUTCOMES)} 단계에서만 씁니다")
        if args.outcome and args.outcome not in allowed:
            p.error(f"{args.stage} 단계의 --outcome은 {'|'.join(allowed)} 중 하나입니다")
        if args.stage in REQUIRED_OUTCOME and not args.outcome:
            p.error(f"{args.stage} 단계에는 --outcome {'|'.join(allowed)}이 필요합니다")

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
    except Refused as e:
        print(" ".join(str(e).split()))
        return USAGE
    except Failure as e:
        # One line for the chat, even when gh or Slack answered with several.
        print(" ".join(str(e).split()))
        return FAILED
    except Exception as e:  # noqa: BLE001 - Slack must never stop the calling skill
        print(" ".join(f"Slack 게시 중 예상하지 못한 오류가 났습니다: {type(e).__name__}: {e}".split()))
        return FAILED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
