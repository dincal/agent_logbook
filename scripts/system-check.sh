#!/usr/bin/env bash
# Check that the project docs in docs/system/ still match the code they describe.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "system-check: python3 not found" >&2
  exit 3
fi
exec python3 "$(cd "$(dirname "$0")" && pwd)/system_check.py" "$@"
