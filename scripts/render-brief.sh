#!/usr/bin/env bash
# Render the brief or debrief block of a logbook plan doc into a CTO-style HTML deck.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: render-brief.sh <plan-doc.md> <brief|debrief> <out.html>" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "render-brief: python3 not found" >&2
  exit 3
fi
exec python3 "$(cd "$(dirname "$0")" && pwd)/render_brief.py" "$@"
