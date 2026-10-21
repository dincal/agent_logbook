#!/usr/bin/env bash
# Post an issue's logbook stages to its Slack thread, and snapshot briefing pages.
# The logic lives in slack.py and snapshot.py; slack_config.py holds what they share.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: slack.sh thread <issue> [--backlog] [--dir DIR]
       slack.sh post <issue> <stage> [--text FILE] [--page HTML] [--file PATH]... [--dir DIR]
       slack.sh replies <issue> [--dir DIR]
       slack.sh snapshot <page.html> <out-dir>

thread    Post the issue's parent message unless the issue already has a thread, and record
          the thread in an issue comment.
post      Reply in the issue's thread, creating the thread first when it has none. Stages:
          design, brief, approve, wave, check, pr, debrief, close, feedback. With --page
          (brief and debrief only), attach a PNG and a standalone HTML copy of the page when
          the page differs from the one last posted for this stage; otherwise post the text
          alone. Each --file is attached as it is.
replies   Print the replies people added since the last call, one JSON object per line
          ({"user", "time", "text", "ts"}), oldest first, and record how far it read.
snapshot  Write <out-dir>/<name>.png (full page height, Google Chrome headless) and
          <out-dir>/<name>.html (doctype, UTF-8, local resources inlined).

The channel comes from the line "- Slack 채널: `<ID>`" in AGENTS.md, else from
LOGBOOK_SLACK_CHANNEL (a default for every project); the token from
LOGBOOK_SLACK_TOKEN, the repo and gh account from .logbook/config.json.
Exit codes: 0 posted, 10 off (no channel line), 11 skipped (no token),
12 failed (Slack, GitHub or Chrome). The last line of stdout is one line for the chat.
EOF
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "slack: python3 not found" >&2
  exit 12
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  thread|post|replies) exec python3 "$HERE/slack.py" "$@" ;;
  snapshot) shift; exec python3 "$HERE/snapshot.py" "$@" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
