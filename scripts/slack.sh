#!/usr/bin/env bash
# Post an issue's logbook stages to its Slack thread, and snapshot briefing pages.
# The logic lives in slack.py and snapshot.py; slack_config.py holds what they share.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: slack.sh thread <issue|pr> [--backlog] [--text FILE] [--dir DIR]
       slack.sh post <issue|pr> <stage> [--outcome VALUE] [--text FILE] [--page HTML] [--file PATH]... [--dir DIR]
       slack.sh replies <issue|pr> [--dir DIR]
       slack.sh check [--dir DIR]
       slack.sh snapshot <page.html> <out-dir>

thread    Post the issue's parent message unless the issue already has a thread, and record
          the thread in an issue comment. --text is the issue written out in plain words for
          people who cannot open GitHub; given for an existing thread, it rewrites the first
          message. Without --text on an existing thread, it redraws a first message whose
          progress line a failed post left behind.
post      Reply in the issue's thread as Slack blocks, creating the thread first when it has
          none. Stages: mockup, design, brief, approve, wave, check, pr, debrief, close,
          feedback. close takes --outcome merged|dropped, which it requires; approve takes
          --outcome later|dropped when the briefing was not approved. With --page
          (brief and debrief only), attach a PNG and a standalone HTML copy of the page when
          the page differs from the one last posted for this stage; otherwise post the text
          alone. Each --file is attached as it is.
replies   Print the replies people added since the last call, one JSON object per line
          ({"user", "time", "text", "ts"}), oldest first, and record how far it read.
check     Exit 0 when posting is on, 10 or 11 when it is off, 12 on a setup error;
          it calls no Slack API.
snapshot  Write <out-dir>/<name>.png (full page height, Google Chrome headless) and
          <out-dir>/<name>.html (doctype, UTF-8, local resources inlined).

A PR number (a PR opened without an issue) gets a PR thread: progress 확인 → 반영, only
close is accepted, and any other stage or --backlog exits 2 without calling Slack.

The channel comes from the line "- Slack 채널: `<ID>`" in AGENTS.md, else from
LOGBOOK_SLACK_CHANNEL (a default for every project); the token from
LOGBOOK_SLACK_TOKEN, the repo and gh account from .logbook/config.json.
Exit codes: 0 posted, 2 wrong arguments, 10 off (no channel line and no LOGBOOK_SLACK_CHANNEL),
11 skipped (no token), 12 failed (Slack, GitHub or Chrome, or a channel name in
LOGBOOK_SLACK_CHANNEL instead of an ID). The last line of stdout is one line for the chat.
EOF
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "slack: python3 not found" >&2
  exit 12
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  thread|post|replies|check) exec python3 "$HERE/slack.py" "$@" ;;
  snapshot) shift; exec python3 "$HERE/snapshot.py" "$@" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
