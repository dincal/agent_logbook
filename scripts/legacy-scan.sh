#!/usr/bin/env bash
# List traces of earlier agent tools and documents outside logbook's layout.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "legacy-scan: python3 not found" >&2
  exit 3
fi
exec python3 "$(cd "$(dirname "$0")" && pwd)/legacy_scan.py" "$@"
