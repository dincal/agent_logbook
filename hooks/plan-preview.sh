#!/bin/sh
# logbook plan-preview hook for ExitPlanMode. Acts only in projects set up with /rulebook.
# PreToolUse: deny a plan without a complete brief block; otherwise render the briefing and open it.
# PostToolUse: remind the session to finish the /brief steps before editing code.
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INPUT="$(cat)"

have_jq() { [ -z "${LOGBOOK_FORCE_PYTHON:-}" ] && command -v jq >/dev/null 2>&1; }

# Evaluate the hook input with jq, or with a python expression over `d` when jq is unavailable.
field() {
  if have_jq; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
  else
    printf '%s' "$INPUT" | python3 -c "import json,sys
d=json.load(sys.stdin); v=($2)
print('' if v is None else v)" 2>/dev/null
  fi
}

# Print one hook response: deny <reason> | context <text> | message <text>.
respond() {
  if have_jq; then
    case "$1" in
      deny) jq -cn --arg v "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $v}}' ;;
      context) jq -cn --arg v "$2" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $v}}' ;;
      message) jq -cn --arg v "$2" '{systemMessage: $v}' ;;
    esac
  else
    python3 -c "import json,sys
k, v = sys.argv[1:3]
out = {
    'deny': {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'permissionDecisionReason': v}},
    'context': {'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': v}},
    'message': {'systemMessage': v},
}[k]
print(json.dumps(out, ensure_ascii=False))" "$1" "$2"
  fi
}

# True when $1 has a line that consists of the marker $2.
has_line() { printf '%s\n' "$1" | grep -qE "^[[:space:]]*$2[[:space:]]*\$"; }

[ -z "$(field '.agent_id // empty' 'd.get("agent_id")')" ] || exit 0

project="${CLAUDE_PROJECT_DIR:-}"
[ -n "$project" ] || project="$(field '.cwd // empty' 'd.get("cwd")')"
[ -n "$project" ] || project="$PWD"
root="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$project")"
if [ ! -f "$root/.logbook/config.json" ] && ! grep -q '^<!-- logbook:begin' "$root/AGENTS.md" 2>/dev/null; then
  exit 0
fi

plan="$(field '.tool_input.plan // .tool_response.plan // empty' '(d.get("tool_input") or {}).get("plan") or (d.get("tool_response") or {}).get("plan")')"
if [ -z "$plan" ]; then
  plan_file="$(field '.tool_input.planFilePath // .tool_response.filePath // empty' '(d.get("tool_input") or {}).get("planFilePath") or (d.get("tool_response") or {}).get("filePath")')"
  if [ -n "$plan_file" ] && [ -f "$plan_file" ]; then plan="$(cat "$plan_file")"; fi
fi
[ -n "$plan" ] || exit 0
has_line "$plan" '<!-- brief:skip -->' && exit 0

case "$(field '.hook_event_name // empty' 'd.get("hook_event_name")')" in
  PreToolUse)
    if ! has_line "$plan" '<!-- brief:begin -->'; then
      respond deny '플랜에 브리핑 블록이 없습니다. logbook의 templates/plan.md 형식대로 <!-- brief:begin -->과 <!-- brief:end --> 사이에 브리핑(요약과 요청, 배경, 하는 일, 주요 결정, 위험과 판단 필요, 일정과 검증)을 넣어 다시 제출하세요. 한 문장으로 설명되는 작은 수정이면 <!-- brief:skip --> 한 줄만 넣으면 됩니다.'
      exit 0
    fi
    if ! has_line "$plan" '<!-- brief:end -->'; then
      respond deny '브리핑 블록의 끝 표식(<!-- brief:end -->)이 없습니다. 블록을 닫고 다시 제출하세요.'
      exit 0
    fi
    out="$root/.logbook/briefs/plan-preview.html"
    tmp="$(mktemp "${TMPDIR:-/tmp}/logbook-plan.XXXXXX")" || exit 0
    printf '%s\n' "$plan" > "$tmp"
    if err="$("$PLUGIN_ROOT/scripts/render-brief.sh" "$tmp" brief "$out" 2>&1 >/dev/null)"; then
      # The local file opens without the Artifact skeleton, so give it a doctype.
      { printf '<!doctype html>\n'; cat "$out"; } > "$tmp" && cat "$tmp" > "$out"
      if [ -z "${LOGBOOK_NO_OPEN:-}" ]; then
        if [ "$(uname -s)" = Darwin ]; then
          open "$out" >/dev/null 2>&1 || true
        elif command -v xdg-open >/dev/null 2>&1; then
          xdg-open "$out" >/dev/null 2>&1 || true
        fi
      fi
    else
      respond message "logbook: 브리핑 미리보기를 만들지 못했습니다. ${err}"
    fi
    rm -f "$tmp"
    exit 0
    ;;
  PostToolUse)
    respond context '플랜이 승인됐습니다. 코드를 고치기 전에 /brief 절차를 마치세요. 이슈와 작업 브랜치가 없으면 만들고, 플랜 파일을 docs/plans/<이슈번호>-<slug>.md로 옮긴 뒤, 브리핑 HTML을 게시하고 이슈에 링크합니다. 화면을 새로 만들거나 크게 바꾸는 계획이면 코드를 고치기 전에 시안을 만들어 승인을 받습니다.'
    exit 0
    ;;
esac
exit 0
