#!/usr/bin/env bash
# logbook tests: rulebook script, render-brief, plan-preview hook, debrief-gate hook, plugin files.
# Exit code 0 only when every check passes.
set -uo pipefail

umask 022
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
BLOCK_LINE='<!-- logbook:begin v1 -->'

ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; return 0; }
expect() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

# ---------------------------------------------------------------- rulebook
echo "== rulebook =="
R="$TMP/repo"
mkdir -p "$R/.claude"
git -C "$R" init -q -b main
git -C "$R" remote add origin git@github.com:acme/demo.git
printf '# Demo\n\nExisting rules stay.\n' > "$R/AGENTS.md"
chmod 644 "$R/AGENTS.md"
printf '{\n  "model": "opus"\n}\n' > "$R/.claude/settings.json"

out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then ok "rulebook: --apply exits 0"; else bad "rulebook: --apply exits 0" "$out"; fi
expect "rulebook: block inserted between markers" grep -qx "$BLOCK_LINE" "$R/AGENTS.md"
expect "rulebook: content outside the block kept" grep -q 'Existing rules stay.' "$R/AGENTS.md"
expect "rulebook: repo filled from origin remote" grep -q 'repo `acme/demo`' "$R/AGENTS.md"
expect "rulebook: gh account omitted when not given" bash -c "! grep -q 'gh 계정' '$R/AGENTS.md'"
expect "rulebook: CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' "$R/CLAUDE.md"
expect "rulebook: plansDirectory merged, existing keys kept" jq -e '.plansDirectory == "docs/plans" and .model == "opus"' "$R/.claude/settings.json"
expect "rulebook: .gitignore lists .logbook/" grep -qx '.logbook/' "$R/.gitignore"
expect "rulebook: docs/plans/ created" test -d "$R/docs/plans"
expect "rulebook: .logbook/config.json records repo and base" jq -e '.repo == "acme/demo" and .base == "main"' "$R/.logbook/config.json"
expect "rulebook: existing file keeps its mode (644)" test "$(mode_of "$R/AGENTS.md")" = 644
expect "rulebook: new files are readable by others" test "$(( 0$(mode_of "$R/CLAUDE.md") & 04 ))" -ne 0

snapshot() { cat "$R/AGENTS.md" "$R/CLAUDE.md" "$R/.claude/settings.json" "$R/.gitignore" "$R/.logbook/config.json" | shasum; }
before="$(snapshot)"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" 2>&1)"
after="$(snapshot)"
if [ "$before" = "$after" ] && printf '%s' "$out" | grep -q '변경 없음'; then
  ok "rulebook: second run changes nothing and says 변경 없음"
else
  bad "rulebook: second run changes nothing and says 변경 없음" "$out"
fi
expect "rulebook: still exactly one block" test "$(grep -c '^<!-- logbook:begin' "$R/AGENTS.md")" -eq 1
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" --account octo >/dev/null 2>&1
expect "rulebook: --account adds the gh account and refreshes the block" grep -q 'gh 계정 `octo`' "$R/AGENTS.md"
expect "rulebook: refresh keeps one block" test "$(grep -c '^<!-- logbook:begin' "$R/AGENTS.md")" -eq 1

C="$TMP/claude-existing"
mkdir -p "$C"
git -C "$C" init -q -b main
printf '# Local notes\n' > "$C/CLAUDE.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$C" --repo acme/c >/dev/null 2>&1
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$C" --repo acme/c >/dev/null 2>&1
expect "rulebook: existing CLAUDE.md keeps its text" grep -q '# Local notes' "$C/CLAUDE.md"
expect "rulebook: existing CLAUDE.md gets one @AGENTS.md line" test "$(grep -cx '@AGENTS.md' "$C/CLAUDE.md")" -eq 1

L="$TMP/symlinked"
mkdir -p "$L"
git -C "$L" init -q -b main
printf 'rules\n' > "$L/CLAUDE.md"
ln -s CLAUDE.md "$L/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$L" --repo acme/l >/dev/null 2>&1
expect "rulebook: AGENTS.md symlink survives" test -L "$L/AGENTS.md"
expect "rulebook: block lands in the symlink target" grep -qx "$BLOCK_LINE" "$L/CLAUDE.md"
expect "rulebook: no self-import when AGENTS.md points to CLAUDE.md" bash -c "! grep -qx '@AGENTS.md' '$L/CLAUDE.md'"

M="$TMP/broken-markers"
mkdir -p "$M"
git -C "$M" init -q -b main
printf '# A\n<!-- logbook:begin v1 -->\nold\n  <!-- logbook:end -->\nKEEP\n' > "$M/AGENTS.md"
cp "$M/AGENTS.md" "$TMP/broken-before"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$M" --repo acme/m 2>&1)"; rc=$?
if [ $rc -ne 0 ] && cmp -s "$M/AGENTS.md" "$TMP/broken-before"; then
  ok "rulebook: begin marker without end marker stops and leaves AGENTS.md untouched"
else
  bad "rulebook: begin marker without end marker stops and leaves AGENTS.md untouched" "$out"
fi

D="$TMP/dry"
mkdir -p "$D"
git -C "$D" init -q -b main
out="$("$ROOT/scripts/rulebook.sh" --dry-run --no-labels --dir "$D" --repo acme/dry 2>&1)"
if [ ! -e "$D/AGENTS.md" ] && [ ! -e "$D/CLAUDE.md" ] && [ ! -e "$D/.claude" ] && printf '%s' "$out" | grep -q 'planned'; then
  ok "rulebook: --dry-run lists changes and writes nothing"
else
  bad "rulebook: --dry-run lists changes and writes nothing" "$out"
fi

LBIN="$TMP/label-bin"
mkdir -p "$LBIN"
cat > "$LBIN/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "label list") printf 'Epic\nSTATUS:TODO\nstatus:done\n' ;;
  "label create") echo "$3" >> "$LABEL_LOG" ;;
  "auth token") echo faketoken ;;
esac
EOF
chmod +x "$LBIN/gh"
LB="$TMP/labels"
mkdir -p "$LB"
git -C "$LB" init -q -b main
LABEL_LOG="$TMP/labels.log" PATH="$LBIN:$PATH" "$ROOT/scripts/rulebook.sh" --apply --dir "$LB" --repo acme/labels >/dev/null 2>&1
created="$(sort "$TMP/labels.log" 2>/dev/null | tr '\n' ' ')"
if [ "$created" = "status:backlog status:in-progress " ]; then
  ok "rulebook: labels compared case-insensitively, only missing ones created"
else
  bad "rulebook: labels compared case-insensitively, only missing ones created" "created: $created"
fi

# ---------------------------------------------------------------- render-brief
echo "== render-brief =="
DOC="$ROOT/docs/plans/1-logbook-v0-1.md"
out="$("$ROOT/scripts/render-brief.sh" "$DOC" brief "$TMP/brief.html" 2>&1)"; rc=$?
printf '      %s\n' "$out"
if [ $rc -eq 0 ] && [ -s "$TMP/brief.html" ]; then ok "render-brief: plan doc brief block -> HTML"; else bad "render-brief: plan doc brief block -> HTML" "$out"; fi
slides="$(grep -c '<section class="slide"' "$TMP/brief.html")"
sections="$(awk '/^<!-- brief:begin -->$/ {f = 1; next} /^<!-- brief:end -->$/ {if (f) exit} /^```/ {fence = !fence} f && !fence && /^## / {c++} END {print c + 0}' "$DOC")"
printf '      ## sections in brief block: %s, slides rendered: %s\n' "$sections" "$slides"
expect "render-brief: one slide per ## section" test "$slides" -eq "$sections"
expect "render-brief: mermaid kept as pre.mermaid" grep -q '<pre class="mermaid">' "$TMP/brief.html"
expect "render-brief: tables rendered" grep -q '<table>' "$TMP/brief.html"
expect "render-brief: page has a title and a charset" bash -c "grep -q '<title>logbook v0.1 구축 브리핑</title>' '$TMP/brief.html' && grep -q '<meta charset=\"utf-8\">' '$TMP/brief.html'"
expect "render-brief: no template placeholders left" bash -c "! grep -q '{{' '$TMP/brief.html'"
out="$("$ROOT/scripts/render-brief.sh" "$DOC" debrief "$TMP/debrief.html" 2>&1)"; rc=$?
printf '      %s\n' "$out"
if [ $rc -eq 0 ]; then ok "render-brief: debrief block renders"; else bad "render-brief: debrief block renders" "$out"; fi
warn="$("$ROOT/scripts/render-brief.sh" "$DOC" brief "$TMP/brief2.html" 2>&1 >/dev/null)"
expect "render-brief: the plan doc has its flowchart and ERD statement (no warning)" test -z "$warn"
printf '# w\n\n<!-- brief:begin -->\n## a\n\nb\n<!-- brief:end -->\n' > "$TMP/nodiagram.md"
warn="$("$ROOT/scripts/render-brief.sh" "$TMP/nodiagram.md" brief "$TMP/nodiagram.html" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$warn" | grep -q 'flowchart' && printf '%s' "$warn" | grep -q 'ERD'; then
  ok "render-brief: warns when the flowchart and the ERD change are missing, still renders"
else
  bad "render-brief: warns when the flowchart and the ERD change are missing, still renders" "$warn"
fi
printf '# x\n\nno block here\n' > "$TMP/noblock.md"
if "$ROOT/scripts/render-brief.sh" "$TMP/noblock.md" brief "$TMP/noblock.html" >/dev/null 2>&1; then
  bad "render-brief: a doc without the block fails"
else
  ok "render-brief: a doc without the block fails"
fi

cat > "$TMP/edge.md" <<'EOF'
# Edge (#9)

<!-- brief:begin -->
## Links

[x](https://a"onmouseover="alert(1))

See https://github.com/acme/demo/pull/2에서 확인.

## Lists

1. first
   - detail
2. second

```text
## not a slide
```

## Drawing

```html
<div class="tiles"><div class="tile" onclick="alert(1)"><div class="num">4</div></div></div>
<script>alert(1)</script>
<scr<script>ipt>alert(2)</script>
<a href="javascript:alert(3)">x</a>
<a href="javascript: alert(5)">spaced</a>
<a href="java&#x09;script:alert(6)">encoded</a>
<svg viewBox="0 0 10 10"><script>alert(4)</script><rect width="10" height="10" style="fill: var(--accent)"/></svg>
```
<!-- brief:end -->
EOF
"$ROOT/scripts/render-brief.sh" "$TMP/edge.md" brief "$TMP/edge.html" >/dev/null 2>&1
expect "render-brief: a quote in a link URL cannot open an attribute" bash -c "! grep -q 'onmouseover=\"' '$TMP/edge.html'"
expect "render-brief: bare URL stops before attached Korean text" grep -q 'href="https://github.com/acme/demo/pull/2">https://github.com/acme/demo/pull/2</a>에서' "$TMP/edge.html"
expect "render-brief: sub-bullets nest instead of taking a number" grep -q '<li>first<ul class="md sub"><li>detail</li></ul></li><li>second</li>' "$TMP/edge.html"
expect "render-brief: ## inside a code fence does not split slides" test "$(grep -c '<section class="slide"' "$TMP/edge.html")" -eq 3
expect "render-brief: html blocks pass through as free-form drawings" grep -q '<div class="freeform"><div class="tiles">' "$TMP/edge.html"
drawing="$(sed -n '/<div class="freeform">/,/<\/section>/p' "$TMP/edge.html")"
expect "render-brief: scripts, handlers and script URLs are stripped from drawings" bash -c "! printf '%s' \"\$1\" | grep -qiE '<script|alert|onclick=|javascript:'" _ "$drawing"
expect "render-brief: harmless SVG survives sanitizing" bash -c "printf '%s' \"\$1\" | grep -q '<rect width=\"10\" height=\"10\" style=\"fill: var(--accent)\"/>'" _ "$drawing"

# ---------------------------------------------------------------- plan-preview hook
echo "== plan-preview hook =="
P="$TMP/proj"
mkdir -p "$P"
printf '# proj\n\n%s\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$P/AGENTS.md"
hook() { CLAUDE_PROJECT_DIR="$1" LOGBOOK_NO_OPEN=1 "$ROOT/hooks/plan-preview.sh"; }
pre_input() { jq -cn --arg plan "$1" --arg cwd "$P" '{hook_event_name: "PreToolUse", tool_name: "ExitPlanMode", tool_input: {plan: $plan}, cwd: $cwd}'; }

for engine in jq python; do
  force=""; [ "$engine" = python ] && force=1
  export LOGBOOK_FORCE_PYTHON="$force"
  res="$(pre_input $'# Plan\n\n1. do it\n' | hook "$P")"; rc=$?
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    ok "plan-preview [$engine]: plan without a brief block is denied"
  else
    bad "plan-preview [$engine]: plan without a brief block is denied" "$res"
  fi
  rm -f "$P/.logbook/briefs/plan-preview.html"
  res="$(pre_input "$(cat "$DOC")" | hook "$P")"; rc=$?
  if [ $rc -eq 0 ] && [ -z "$res" ] && head -1 "$P/.logbook/briefs/plan-preview.html" 2>/dev/null | grep -q '<!doctype html>'; then
    ok "plan-preview [$engine]: brief block renders a standalone preview and leaves the decision to the user"
  else
    bad "plan-preview [$engine]: brief block renders a standalone preview and leaves the decision to the user" "rc=$rc $res"
  fi
  res="$(jq -cn --arg cwd "$P" '{hook_event_name: "PostToolUse", tool_name: "ExitPlanMode", tool_input: {plan: "# p\n\nx"}, cwd: $cwd}' | hook "$P")"; rc=$?
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.hookSpecificOutput.additionalContext | test("/brief")' >/dev/null 2>&1; then
    ok "plan-preview [$engine]: approval adds a /brief reminder"
  else
    bad "plan-preview [$engine]: approval adds a /brief reminder" "$res"
  fi
done
unset LOGBOOK_FORCE_PYTHON

res="$(pre_input $'<!-- brief:begin -->\n## a\n\nb\n' | hook "$P")"
if printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | test("끝 표식"))' >/dev/null 2>&1; then
  ok "plan-preview: a block without its end marker is denied"
else
  bad "plan-preview: a block without its end marker is denied" "$res"
fi
res="$(pre_input $'<!-- brief:begin -->\n```mermaid\nflowchart LR\n  A --> B\n```\n> ERD 변화 없음: 없음\n<!-- brief:end -->\n' | hook "$P")"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.systemMessage | test("미리보기")' >/dev/null 2>&1; then
  ok "plan-preview: a render failure is reported, not swallowed"
else
  bad "plan-preview: a render failure is reported, not swallowed" "$res"
fi
res="$(pre_input $'<!-- brief:begin -->\n## 요약\n\n결론.\n<!-- brief:end -->\n' | hook "$P")"
if printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | test("주요 로직 흐름도") and test("ERD 변화"))' >/dev/null 2>&1; then
  ok "plan-preview: a briefing without the logic flowchart and the ERD change is denied"
else
  bad "plan-preview: a briefing without the logic flowchart and the ERD change is denied" "$res"
fi
res="$(pre_input $'<!-- brief:begin -->\n## 흐름\n\n결론.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n<!-- brief:end -->\n' | hook "$P")"
if printf '%s' "$res" | jq -e '(.hookSpecificOutput.permissionDecisionReason | test("ERD 변화")) and (.hookSpecificOutput.permissionDecisionReason | test("주요 로직") | not)' >/dev/null 2>&1; then
  ok "plan-preview: a flowchart alone still owes the ERD change"
else
  bad "plan-preview: a flowchart alone still owes the ERD change" "$res"
fi
res="$(pre_input $'<!-- brief:begin -->\n## 흐름\n\n결론.\n\n```mermaid\nsequenceDiagram\n  A->>B: call\n```\n\n> ERD 변화 없음: 데이터 모델을 건드리지 않는다\n<!-- brief:end -->\n' | hook "$P")"
expect "plan-preview: a sequence diagram plus an 'ERD 변화 없음' line passes" test -z "$res"
res="$(pre_input $'<!-- brief:begin -->\n## 흐름\n\n결론.\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\nerDiagram 은 아직 없다\n<!-- brief:end -->\n' | hook "$P")"
if printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("ERD 변화")' >/dev/null 2>&1; then
  ok "plan-preview: the word erDiagram outside a mermaid fence does not count"
else
  bad "plan-preview: the word erDiagram outside a mermaid fence does not count" "$res"
fi
cp "$DOC" "$TMP/plan-file.md"
rm -f "$P/.logbook/briefs/plan-preview.html"
res="$(jq -cn --arg f "$TMP/plan-file.md" --arg cwd "$P" '{hook_event_name: "PreToolUse", tool_input: {planFilePath: $f}, cwd: $cwd}' | hook "$P")"
expect "plan-preview: an empty plan falls back to planFilePath" bash -c "[ -z '$res' ] && [ -s '$P/.logbook/briefs/plan-preview.html' ]"
res="$(pre_input $'<!-- brief:skip -->\nfix a typo' | hook "$P")"; rc=$?
expect "plan-preview: brief:skip passes" test $rc -eq 0 -a -z "$res"
res="$(jq -cn --arg cwd "$P" '{hook_event_name: "PostToolUse", tool_input: {plan: "<!-- brief:skip -->\nfix"}, cwd: $cwd}' | hook "$P")"
expect "plan-preview: no /brief reminder after a skipped plan" test -z "$res"
res="$(jq -cn --arg cwd "$P" '{hook_event_name: "PreToolUse", agent_id: "a1", tool_input: {plan: "no block"}, cwd: $cwd}' | hook "$P")"
expect "plan-preview: subagent plans pass" test -z "$res"
N="$TMP/not-logbook"
mkdir -p "$N"
res="$(jq -cn --arg cwd "$N" '{hook_event_name: "PreToolUse", tool_input: {plan: "# x\n\n1. y"}, cwd: $cwd}' | hook "$N")"; rc=$?
expect "plan-preview: projects without logbook rules are left alone" test $rc -eq 0 -a -z "$res"

# ---------------------------------------------------------------- debrief-gate hook
echo "== debrief-gate hook =="
G="$TMP/gate"
BIN="$TMP/bin"
mkdir -p "$G" "$BIN"
git -C "$G" init -q -b main
printf '# gate\n\n%s\n트래커: repo `acme/demo` · 기본 브랜치 `main` · gh 계정 `octo`\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$G/AGENTS.md"
git -C "$G" add AGENTS.md
git -C "$G" -c user.email=t@example.com -c user.name=t commit -q -m init
git -C "$G" checkout -q -b feat/9-demo
cat > "$BIN/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth token") echo "$4" >> "${GH_LOG:-/dev/null}"; echo faketoken ;;
  "pr view")
    case "${FAKE_GH:-}" in
      nomarker) printf '{"url":"https://github.com/acme/demo/pull/9","state":"OPEN","body":"Closes #9"}\n' ;;
      marker) printf '{"url":"https://github.com/acme/demo/pull/9","state":"OPEN","body":"Closes #9\\n<!-- logbook:debrief -->"}\n' ;;
      merged) printf '{"url":"https://github.com/acme/demo/pull/9","state":"MERGED","body":"Closes #9"}\n' ;;
      *) echo "no pull requests found" >&2; exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/gh"
stop_input() { jq -cn --argjson active "$1" --arg cwd "${3:-$G}" --argjson bg "${2:-[]}" '{hook_event_name: "Stop", stop_hook_active: $active, cwd: $cwd, background_tasks: $bg}'; }
gate() { PATH="$BIN:$PATH" GH_LOG="$TMP/gh.log" FAKE_GH="$1" "$ROOT/hooks/debrief-gate.sh"; }

for engine in jq python; do
  force=""; [ "$engine" = python ] && force=1
  res="$(stop_input false | LOGBOOK_FORCE_PYTHON="$force" gate nomarker)"; rc=$?
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.decision == "block" and (.reason | test("/debrief"))' >/dev/null 2>&1; then
    ok "debrief-gate [$engine]: open PR without the marker blocks"
  else
    bad "debrief-gate [$engine]: open PR without the marker blocks" "rc=$rc $res"
  fi
  res="$(stop_input true | LOGBOOK_FORCE_PYTHON="$force" gate nomarker)"; rc=$?
  expect "debrief-gate [$engine]: stop_hook_active=true passes" test $rc -eq 0 -a -z "$res"
done
expect "debrief-gate: gh account comes from the AGENTS.md tracker line" grep -qx octo "$TMP/gh.log"
res="$(stop_input false '[{"id":"t1","type":"shell"}]' | gate nomarker)"; rc=$?
expect "debrief-gate: running background work passes" test $rc -eq 0 -a -z "$res"
res="$(stop_input false | gate fail)"; rc=$?
expect "debrief-gate: gh failure passes" test $rc -eq 0 -a -z "$res"
res="$(stop_input false | gate merged)"; rc=$?
expect "debrief-gate: merged PR passes" test $rc -eq 0 -a -z "$res"
git -C "$G" checkout -q main
res="$(stop_input false | gate nomarker)"; rc=$?
expect "debrief-gate: base branch passes" test $rc -eq 0 -a -z "$res"
git -C "$G" checkout -q feat/9-demo
H="$TMP/plain-repo"
mkdir -p "$H"
git -C "$H" init -q -b main
git -C "$H" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$H" checkout -q -b feat/1-x
res="$(stop_input false '[]' "$H" | gate nomarker)"; rc=$?
expect "debrief-gate: repositories without logbook rules pass" test $rc -eq 0 -a -z "$res"
res="$(stop_input false | gate marker)"; rc=$?
expect "debrief-gate: PR with the marker passes" test $rc -eq 0 -a -z "$res"
expect "debrief-gate: debriefed HEAD is cached" test -f "$G/.logbook/state/debrief-feat_9-demo"
res="$(stop_input false | gate nomarker)"
expect "debrief-gate: cached HEAD skips the gh call" test -z "$res"

# ---------------------------------------------------------------- plugin files
echo "== plugin files =="
expect "hooks.json is valid JSON" jq -e '.hooks.PreToolUse and .hooks.PostToolUse and .hooks.Stop' "$ROOT/hooks/hooks.json"
for skill in rulebook brief mission debrief; do
  f="$ROOT/skills/$skill/SKILL.md"
  if [ ! -f "$f" ]; then bad "skill $skill exists"; continue; fi
  lines="$(wc -l < "$f" | tr -d ' ')"
  shout="$(grep -cE '\b(MUST|CRITICAL|NEVER|ALWAYS)\b' "$f")"
  if [ "$lines" -le 150 ] && [ "$shout" -eq 0 ] && grep -q "^name: $skill\$" "$f"; then
    ok "skill $skill: $lines lines, no shouting, name matches"
  else
    bad "skill $skill: $lines lines, shouting=$shout"
  fi
done
expect "reviewer agent is read-only" grep -q '^tools: Read, Grep, Glob$' "$ROOT/agents/reviewer.md"
expect "reviewer agent runs on Sonnet at medium effort" bash -c "grep -qx 'model: sonnet' '$ROOT/agents/reviewer.md' && grep -qx 'effort: medium' '$ROOT/agents/reviewer.md'"
expect "diagram kit reference exists" test -s "$ROOT/templates/diagram-kit.md"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
