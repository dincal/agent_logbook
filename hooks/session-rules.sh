#!/bin/sh
# logbook session-rules hook (SessionStart). Acts only in repositories set up with /rulebook.
# Adds the logbook working rules, with the tracker values from .logbook/config.json,
# to the session context, so a plugin update reaches every project without touching it.
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$PLUGIN_ROOT/hooks/lib.sh"
INPUT="$(cat)"

have_jq() { [ -z "${LOGBOOK_FORCE_PYTHON:-}" ] && command -v jq >/dev/null 2>&1; }

field() { # jq-filter python-expression-over-d
  if have_jq; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
  else
    printf '%s' "$INPUT" | python3 -c "import json,sys
d=json.load(sys.stdin); v=($2)
print('' if v is None else v)" 2>/dev/null
  fi
}

json_key() { # file key
  if have_jq; then
    jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null
  else
    python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print('' if v is None else v)" "$1" "$2" 2>/dev/null
  fi
}

project="$(field '.cwd // empty' 'd.get("cwd")')"
[ -n "$project" ] || project="${CLAUDE_PROJECT_DIR:-$PWD}"
# Outside git, the folder itself is both the working tree and the main checkout.
top="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)" || top="$project"
main="$(logbook_main_root "$project")" || main="$top"
logbook_enabled "$main" "$top" || exit 0

repo="" base="" account=""
config="$main/.logbook/config.json"
if [ -f "$config" ]; then
  repo="$(json_key "$config" repo)"
  base="$(json_key "$config" base)"
  account="$(json_key "$config" account)"
fi
# Before /rulebook migrates it, an old rule block carries the tracker line.
if logbook_old_block "$top"; then
  [ -n "$repo" ] || repo="$(sed -n '/^트래커:/s/.*repo `\([^`]*\)`.*/\1/p' "$top/AGENTS.md" | head -n 1)"
  [ -n "$base" ] || base="$(sed -n '/^트래커:/s/.*기본 브랜치 `\([^`]*\)`.*/\1/p' "$top/AGENTS.md" | head -n 1)"
  [ -n "$account" ] || account="$(sed -n '/^트래커:/s/.*gh 계정 `\([^`]*\)`.*/\1/p' "$top/AGENTS.md" | head -n 1)"
fi
[ -n "$base" ] || base="$(git -C "$top" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[ -n "$base" ] || base=main
[ -n "$repo" ] || repo="(GitHub 저장소 없음)"

version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" | head -n 1)"
note=""
if logbook_old_block "$top"; then
  note="AGENTS.md에 logbook 0.7 이전의 규칙 블록이 남아 있다. 이 규칙이 그 블록보다 우선한다. /rulebook을 실행하면 블록을 지우고 그 안의 문서 규칙을 AGENTS.md 문서 규칙 문단으로 옮긴다. 사람에게 한 번 알린다."
fi

python3 - "$PLUGIN_ROOT/templates/session-rules.md" "$version" "$repo" "$base" "$account" "$note" <<'EOF'
import json, sys
path, version, repo, base, account, note = sys.argv[1:7]
text = open(path, encoding="utf-8").read()
if not account:
    text = text.replace(" · gh 계정 `{account}`", "")
for key, value in (("version", version or "?"), ("repo", repo), ("base", base), ("account", account)):
    text = text.replace("{" + key + "}", value)
text = text.rstrip("\n") + "\n"
if note:
    text += "\n" + note + "\n"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}, ensure_ascii=False))
EOF
exit 0
