#!/usr/bin/env bash
# Render the brief or debrief block of a logbook plan doc into an HTML slide deck.
set -euo pipefail

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "usage: render-brief.sh [--standalone] <plan-doc.md> <brief|debrief> <out.html>" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "render-brief: python3 not found" >&2
  exit 3
fi
exec python3 "$(cd "$(dirname "$0")" && pwd)/render_brief.py" "$@"
