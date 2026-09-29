#!/bin/sh
# logbook debrief-gate hook (Stop). Acts only in projects set up with /rulebook.
# Blocks once when the current branch's open PR has no debriefing marker.
# Any infrastructure problem (no git, no gh, timeout) lets the turn end.
set -u

INPUT="$(cat)"

have_jq() { [ -z "${LOGBOOK_FORCE_PYTHON:-}" ] && command -v jq >/dev/null 2>&1; }

field() { # jq-filter python-expression-over-d
  if have_jq; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
  else
    printf '%s' "$INPUT" | python3 -c "import json,sys
d=json.load(sys.stdin); v=($2)
print('' if v is None else (str(v).lower() if isinstance(v, bool) else v))" 2>/dev/null
  fi
}

json_key() { # json-text key
  if have_jq; then
    printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$1" | python3 -c "import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print('' if v is None else v)" "$2" 2>/dev/null
  fi
}

run_timeout() { # seconds command...
  secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
  else "$@"
  fi
}

[ "$(field '.stop_hook_active // false' 'd.get("stop_hook_active", False)')" = "true" ] && exit 0
bg="$(field '(.background_tasks // []) | length' 'len(d.get("background_tasks") or [])')"
[ -n "$bg" ] && [ "$bg" != "0" ] && exit 0

cwd="$(field '.cwd // empty' 'd.get("cwd")')"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || exit 0
root="$(git rev-parse --show-toplevel)"

agents_md="$root/AGENTS.md"
if [ ! -f "$root/.logbook/config.json" ] && ! grep -q '^<!-- logbook:begin' "$agents_md" 2>/dev/null; then
  exit 0
fi

base="" account=""
if [ -f "$root/.logbook/config.json" ]; then
  config="$(cat "$root/.logbook/config.json")"
  base="$(json_key "$config" base)"
  account="$(json_key "$config" account)"
fi
# Fresh clones have no local config; the committed tracker line carries the same values.
if [ -f "$agents_md" ]; then
  [ -n "$base" ] || base="$(sed -n 's/.*기본 브랜치 `\([^`]*\)`.*/\1/p' "$agents_md" | head -n 1)"
  [ -n "$account" ] || account="$(sed -n 's/.*gh 계정 `\([^`]*\)`.*/\1/p' "$agents_md" | head -n 1)"
fi
[ -n "$base" ] || base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[ -n "$base" ] || base=main
[ "$branch" = "$base" ] && exit 0

head="$(git rev-parse HEAD 2>/dev/null)" || exit 0
state_file="$root/.logbook/state/debrief-$(printf '%s' "$branch" | tr '/ ' '__')"
[ -f "$state_file" ] && [ "$(cat "$state_file")" = "$head" ] && exit 0

command -v gh >/dev/null 2>&1 || exit 0
token=""
[ -n "$account" ] && token="$(gh auth token --user "$account" 2>/dev/null || true)"
if [ -n "$token" ]; then
  pr="$(run_timeout 10 env GH_TOKEN="$token" gh pr view --json url,body,state 2>/dev/null)" || exit 0
else
  pr="$(run_timeout 10 gh pr view --json url,body,state 2>/dev/null)" || exit 0
fi
[ "$(json_key "$pr" state)" = "OPEN" ] || exit 0

case "$(json_key "$pr" body)" in
  *'<!-- logbook:debrief -->'*)
    mkdir -p "$(dirname "$state_file")" && printf '%s\n' "$head" > "$state_file"
    exit 0
    ;;
esac

url="$(json_key "$pr" url)"
reason="PR ${url}에 디브리핑이 없습니다. /debrief를 실행해 수용 기준별 증거를 PR 본문에 남기세요. 계획 문서가 있는 PR은 결과 HTML도 PR과 이슈에 붙입니다(에픽 단계 PR은 HTML 없이 PR 본문에만 남깁니다)."
if have_jq; then
  jq -cn --arg r "$reason" '{decision: "block", reason: $r}'
else
  python3 -c "import json,sys; print(json.dumps({'decision': 'block', 'reason': sys.argv[1]}, ensure_ascii=False))" "$reason"
fi
exit 0
