#!/usr/bin/env bash
# Render docs/system/ into one HTML slide deck (the project handbook).
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "render-system: python3 not found" >&2
  exit 3
fi
exec python3 "$(cd "$(dirname "$0")" && pwd)/render_system.py" "$@"
