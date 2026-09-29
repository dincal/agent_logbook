#!/usr/bin/env bash
# logbook tests: rulebook script, render-brief, plan-preview hook, debrief-gate hook,
# system-check, legacy-scan, render-system, plugin files.
# Exit code 0 only when every check passes.
set -uo pipefail

umask 022
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
BLOCK_LINE='<!-- logbook:begin v4 -->'

ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; return 0; }
expect() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
# True when tab-separated output $1 has a row whose first two fields are $2 and $3.
has_row() { printf '%s\n' "$1" | awk -F'\t' -v a="$2" -v b="$3" '$1 == a && $2 == b {f = 1} END {exit !f}'; }
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
expect "render-brief: no template placeholders left" bash -c "! grep -qE '\\{\\{[A-Z_]+\\}\\}' '$TMP/brief.html'"
out="$("$ROOT/scripts/render-brief.sh" "$DOC" debrief "$TMP/debrief.html" 2>&1)"; rc=$?
printf '      %s\n' "$out"
if [ $rc -eq 0 ]; then ok "render-brief: debrief block renders"; else bad "render-brief: debrief block renders" "$out"; fi
printf '# w\n\n<!-- brief:begin -->\n## a\n\nb\n<!-- brief:end -->\n' > "$TMP/nodiagram.md"
warn="$("$ROOT/scripts/render-brief.sh" "$TMP/nodiagram.md" brief "$TMP/nodiagram.html" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 0 ] && [ -z "$warn" ] && [ -s "$TMP/nodiagram.html" ]; then
  ok "render-brief: a block without a flowchart or an ERD renders with no warning"
else
  bad "render-brief: a block without a flowchart or an ERD renders with no warning" "rc=$rc $warn"
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

<!-- a marker comment is hidden by viewers and allowed -->

- **9** 지운 파일: 옛 문서 4개
- **5 / 5** 완료 조건: 명령 결과로 확인
- **11 → 4** 스킬

- **3** 숫자로 시작하는 항목
- 숫자가 없는 항목

`<Callout>` 같은 태그는 인라인 코드 안에서 글자로 남습니다.

```tsx
export const Box = () => <div className="box" />;
```

```mermaid
flowchart LR
  A["문의"] -->|"넣음"| M{{"`**claude-haiku-4-5**
  세 갈래로 나눠 달라`"}}
```
<!-- brief:end -->
EOF
"$ROOT/scripts/render-brief.sh" "$TMP/edge.md" brief "$TMP/edge.html" >/dev/null 2>&1
expect "render-brief: a quote in a link URL cannot open an attribute" bash -c "! grep -q 'onmouseover=\"' '$TMP/edge.html'"
expect "render-brief: bare URL stops before attached Korean text" grep -q 'href="https://github.com/acme/demo/pull/2">https://github.com/acme/demo/pull/2</a>에서' "$TMP/edge.html"
expect "render-brief: sub-bullets nest instead of taking a number" grep -q '<li>first<ul class="md sub"><li>detail</li></ul></li><li>second</li>' "$TMP/edge.html"
expect "render-brief: ## inside a code fence does not split slides" test "$(grep -c '<section class="slide"' "$TMP/edge.html")" -eq 3
expect "render-brief: a list of bold numbers becomes tiles" grep -q '<div class="tiles"><div class="tile"><div class="num">9</div><div class="what">지운 파일</div><div class="how">옛 문서 4개</div></div>' "$TMP/edge.html"
expect "render-brief: a slash or an arrow in a tile number is highlighted" bash -c "grep -q '5 <em>/</em> 5' '$TMP/edge.html' && grep -q '11 <em>→</em> 4' '$TMP/edge.html'"
expect "render-brief: a list that is not all bold numbers stays a list" grep -q '<li>숫자가 없는 항목</li>' "$TMP/edge.html"
expect "render-brief: tags in inline code and in other code blocks stay text" bash -c "grep -q '<code>&lt;Callout&gt;</code>' '$TMP/edge.html' && grep -q 'export const Box = () =&gt; &lt;div' '$TMP/edge.html'"
html_doc() { printf '# H\n\n<!-- brief:begin -->\n## 요약\n\n결론.\n\n%s\n<!-- brief:end -->\n' "$1" > "$TMP/html.md"; }
html_doc $'```html\n<div class="tiles"></div>\n```'
err="$("$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 4 ] && printf '%s' "$err" | grep -q '8줄 ```html' && printf '%s' "$err" | grep -q 'mermaid'; then
  ok "render-brief: an html block is refused (exit 4) with its line and what to use instead"
else
  bad "render-brief: an html block is refused (exit 4) with its line and what to use instead" "rc=$rc $err"
fi
html_doc '<div class="tiles">4</div>'
"$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
expect "render-brief: a raw tag in prose is refused" test $rc -eq 4
html_doc $'```mermaid\nflowchart LR\n  A["a<br/>b"] --> B\n```'
"$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
expect "render-brief: a <br> inside a mermaid label is refused" test $rc -eq 4
html_doc $'<!--\n여러 줄 주석 안의 <div>는 보이지 않습니다\n-->\n\n| 조각 | 설명 |\n|---|---|\n| 웹 | `<main>` 영역 |'
"$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
expect "render-brief: HTML comments and inline code in tables are allowed" test $rc -eq 0

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
rm -f "$P/.logbook/briefs/plan-preview.html"
res="$(pre_input $'<!-- brief:begin -->\n## 요약\n\n결론.\n<!-- brief:end -->\n' | hook "$P")"; rc=$?
if [ $rc -eq 0 ] && [ -z "$res" ] && [ -s "$P/.logbook/briefs/plan-preview.html" ]; then
  ok "plan-preview: a briefing without a flowchart or an ERD passes and gets a preview"
else
  bad "plan-preview: a briefing without a flowchart or an ERD passes and gets a preview" "rc=$rc $res"
fi
res="$(pre_input $'<!-- brief:begin -->\n## 요약\n\n결론.\n\n<div class="tiles">4</div>\n<!-- brief:end -->\n' | hook "$P")"
if printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | test("HTML") and test("6줄"))' >/dev/null 2>&1; then
  ok "plan-preview: a plan with HTML is sent back, naming the line"
else
  bad "plan-preview: a plan with HTML is sent back, naming the line" "$res"
fi
res="$(pre_input $'# Plan\n\n1. do it\n' | hook "$P")"
if printf '%s' "$res" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("요약과 요청") and (test("흐름 그림") | not)' >/dev/null 2>&1; then
  ok "plan-preview: the deny message lists the briefing's parts without demanding pictures"
else
  bad "plan-preview: the deny message lists the briefing's parts without demanding pictures" "$res"
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

# ---------------------------------------------------------------- system-check
echo "== system-check =="
S="$TMP/syscheck"
mkdir -p "$S/docs/system" "$S/src/api" "$S/db"
git -C "$S" init -q -b main
scommit() { git -C "$S" add -A && git -C "$S" -c user.email=t@example.com -c user.name=t commit -q -m "$1"; }
sc() { (cd "$S" && "$ROOT/scripts/system-check.sh" "$@"); }
printf 'def order():\n    return 0\n' > "$S/src/api/orders.py"
printf 'CREATE TABLE users (id int);\nCREATE TABLE orders (id int);\n' > "$S/db/schema.sql"
printf '.logbook/\n' > "$S/.gitignore"
cat > "$S/docs/system/flows.md" <<'EOF'
<!-- logbook:system sources="src/api/**" -->
# 주요 흐름

## 주문

주문을 받습니다. 기록은 `.logbook/state/`에 남습니다.

- 시작점: `src/api/orders.py`의 `order`
EOF
cat > "$S/docs/system/data-model.md" <<'EOF'
<!-- logbook:system sources="db/**" tables="2" -->
# 데이터 모델

## 전체 ERD

테이블 두 개입니다.

```mermaid
erDiagram
  USERS ||--o{ ORDERS : "주문한다"
  ORDERS {
    string status "대기"
  }
```
EOF
scommit init
out="$(sc)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '문서 2개, 뒤처진 문서 0, 경고 0'; then
  ok "system-check: docs committed with their code are in sync (an ignored local path is not a missing file)"
else
  bad "system-check: docs committed with their code are in sync (an ignored local path is not a missing file)" "$out"
fi
printf 'def order():\n    return 1\n' > "$S/src/api/orders.py"
out="$(sc)"
if has_row "$out" "뒤처짐" "flows.md" && has_row "$out" "정상" "data-model.md"; then ok "system-check: an uncommitted code change leaves only its doc behind"; else bad "system-check: an uncommitted code change leaves only its doc behind" "$out"; fi
scommit "code only"
out="$(sc)"
if has_row "$out" "뒤처짐" "flows.md"; then ok "system-check: a committed code change without a doc update is behind"; else bad "system-check: a committed code change without a doc update is behind" "$out"; fi
sc --strict >/dev/null; rc=$?
expect "system-check: --strict exits 1 when a doc is behind" test $rc -eq 1
printf '\n- 실패하면: 오류를 보여 줍니다.\n' >> "$S/docs/system/flows.md"
out="$(sc)"
if has_row "$out" "정상" "flows.md"; then ok "system-check: a doc being edited counts as updated"; else bad "system-check: a doc being edited counts as updated" "$out"; fi
scommit "doc update"
git -C "$S" checkout -q -b feat/1-x
printf 'def order():\n    return 2\n' > "$S/src/api/orders.py"
scommit "branch code"
out="$(sc --range main...HEAD)"
if has_row "$out" "뒤처짐" "flows.md"; then ok "system-check: --range flags code changed in the PR without its doc"; else bad "system-check: --range flags code changed in the PR without its doc" "$out"; fi
printf '\n- 쓰는 데이터: ORDERS\n' >> "$S/docs/system/flows.md"
scommit "branch doc"
out="$(sc --range main...HEAD)"
if has_row "$out" "정상" "flows.md"; then ok "system-check: --range accepts a PR that updates the doc too"; else bad "system-check: --range accepts a PR that updates the doc too" "$out"; fi
git -C "$S" checkout -q main && git -C "$S" merge -q --squash feat/1-x >/dev/null 2>&1 && scommit "squash"
out="$(sc)"
expect "system-check: nothing is behind after a squash merge" bash -c "printf '%s' \"\$1\" | grep -q '뒤처진 문서 0'" _ "$out"
printf '<!-- logbook:system sources="lib/**" -->\n# 한눈에\n\n## 한눈에 보기\n\n설명입니다. 설정은 `config/app.yml`에 있습니다.\n\n<div class="tiles">4</div>\n' > "$S/docs/system/overview.md"
printf '# 기술 스택\n\n## 구성\n\n서버 하나입니다.\n' > "$S/docs/system/stack.md"
sed -i.bak 's/tables="2"/tables="3"/' "$S/docs/system/data-model.md" && /bin/rm -f "$S/docs/system/data-model.md.bak"
out="$(sc)"
printf '%s\n' "$out" | sed 's/^/      /'
expect "system-check: warns about a path pattern that matches no file" bash -c "printf '%s' \"\$1\" | grep -q \"경로 패턴 'lib/\*\*'\"" _ "$out"
expect "system-check: warns about a file the doc names but the repo lacks" bash -c "printf '%s' \"\$1\" | grep -q '없는 파일을 가리킵니다: config/app.yml'" _ "$out"
expect "system-check: warns about a doc without its marker" bash -c "printf '%s' \"\$1\" | grep -q '첫 줄 주석'" _ "$out"
expect "system-check: a doc without its marker gets that one warning, not a second about sources" bash -c "! printf '%s' \"\$1\" | grep 'stack.md' | grep -q 'sources(이 문서가'" _ "$out"
expect "system-check: warns about HTML in a doc, naming the line" bash -c "printf '%s' \"\$1\" | grep -q 'HTML이 들어 있습니다(8줄'" _ "$out"
expect "system-check: warns when the ERD's table count differs from tables=" bash -c "printf '%s' \"\$1\" | grep -q 'ERD에 나온 테이블은 2개인데, 첫 줄 주석의 tables는 3'" _ "$out"
printf '<!-- logbook:system sources="" -->\n# 용어\n\n## 용어\n\n설명입니다.\n' > "$S/docs/system/glossary.md"
out="$(sc)"
if has_row "$out" "경고" "glossary.md" && printf '%s' "$out" | grep -q 'sources(이 문서가 설명하는 코드 경로)가 없어서'; then ok "system-check: warns about a marker without sources, which could never be checked"; else bad "system-check: warns about a marker without sources, which could never be checked" "$out"; fi
E="$TMP/syscheck-empty"
mkdir -p "$E"
git -C "$E" init -q -b main
out="$(cd "$E" && "$ROOT/scripts/system-check.sh")"; rc=$?
expect "system-check: without docs/system it points to /sync and exits 0" bash -c "[ $rc -eq 0 ] && printf '%s' \"\$1\" | grep -q '/sync'" _ "$out"
(cd "$E" && "$ROOT/scripts/system-check.sh" --strict >/dev/null); rc=$?
expect "system-check: without docs/system --strict exits 1" test $rc -eq 1

# ---------------------------------------------------------------- legacy-scan
echo "== legacy-scan =="
LG="$TMP/legacy"
mkdir -p "$LG/.agent-conventions" "$LG/.paperclip/state" "$LG/docs/flows" "$LG/docs/plans" "$LG/docs/system" "$LG/src"
git -C "$LG" init -q -b main
printf '# P\n\n## 1. 문서 맵 (Document Map)\n\n표\n\n## 빌드\n\nnpm run build\n' > "$LG/AGENTS.md"
ln -s AGENTS.md "$LG/CLAUDE.md"
ln -s AGENTS.md "$LG/GEMINI.md"
printf 'rules\n' > "$LG/.agent-conventions/diagram-convention.md"
printf '{}\n' > "$LG/.paperclip/state/run.json"
printf '# Paperclip local runtime artifacts\n.paperclip/\nnode_modules/\n' > "$LG/.gitignore"
printf 'erd\n' > "$LG/docs/erd.md"
printf 'flow\n' > "$LG/docs/flows/orders.md"
printf 'plan\n' > "$LG/docs/plans/3-orders.md"
printf 'map\n' > "$LG/docs/system/overview.md"
printf "export const out = '.paperclip/e2e';\n" > "$LG/src/config.ts"
printf 'notes\n' > "$LG/NOTES.md"
printf 'readme\n' > "$LG/README.md"
git -C "$LG" add -A && git -C "$LG" -c user.email=t@example.com -c user.name=t commit -q -m init
out="$("$ROOT/scripts/legacy-scan.sh" --dir "$LG")"
printf '%s\n' "$out" | sed 's/^/      /'
if has_row "$out" "옛 도구 파일" ".paperclip" && has_row "$out" "옛 도구 파일" ".agent-conventions"; then ok "legacy-scan: finds earlier tools' folders, ignored or tracked"; else bad "legacy-scan: finds earlier tools' folders, ignored or tracked" "$out"; fi
if has_row "$out" "옛 규칙" "AGENTS.md:3" && ! has_row "$out" "옛 규칙" "AGENTS.md:7"; then ok "legacy-scan: flags paperclip's rule sections and keeps the project's own"; else bad "legacy-scan: flags paperclip's rule sections and keeps the project's own" "$out"; fi
if has_row "$out" "옛 도구 언급" "src/config.ts"; then ok "legacy-scan: finds code that still points at paperclip paths"; else bad "legacy-scan: finds code that still points at paperclip paths" "$out"; fi
if has_row "$out" "옛 무시 목록" ".gitignore:1" && has_row "$out" "옛 무시 목록" ".gitignore:2" && ! has_row "$out" "옛 무시 목록" ".gitignore:3"; then ok "legacy-scan: flags only the old .gitignore lines"; else bad "legacy-scan: flags only the old .gitignore lines" "$out"; fi
if has_row "$out" "다른 규칙 링크" "GEMINI.md" && ! printf '%s' "$out" | grep -q 'CLAUDE.md'; then ok "legacy-scan: flags a GEMINI.md link but not the CLAUDE.md link"; else bad "legacy-scan: flags a GEMINI.md link but not the CLAUDE.md link" "$out"; fi
if has_row "$out" "자리 밖 문서" "docs/erd.md" && has_row "$out" "자리 밖 문서" "docs/flows/orders.md" && has_row "$out" "자리 밖 문서" "NOTES.md"; then ok "legacy-scan: flags documents outside logbook's places"; else bad "legacy-scan: flags documents outside logbook's places" "$out"; fi
expect "legacy-scan: leaves plans, project docs and README alone" bash -c "! printf '%s' \"\$1\" | grep -qE 'docs/plans/3-orders.md|docs/system/overview.md|README.md'" _ "$out"
CL="$TMP/legacy-clean"
mkdir -p "$CL/docs/plans" "$CL/docs/system"
git -C "$CL" init -q -b main
printf '# C\n\n%s\n## 작업 방식 (logbook)\n\n- **이슈부터 만든다.**\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$CL/AGENTS.md"
printf '@AGENTS.md\n' > "$CL/CLAUDE.md"
printf 'readme\n' > "$CL/README.md"
printf 'plan\n' > "$CL/docs/plans/1-start.md"
printf 'map\n' > "$CL/docs/system/overview.md"
git -C "$CL" add -A && git -C "$CL" -c user.email=t@example.com -c user.name=t commit -q -m init
out="$("$ROOT/scripts/legacy-scan.sh" --dir "$CL")"
expect "legacy-scan: prints nothing for a repository that fits logbook" test -z "$out"

# ---------------------------------------------------------------- render-system
echo "== render-system =="
SYS="$ROOT/docs/system"
out="$("$ROOT/scripts/render-system.sh" "$SYS" "$TMP/handbook.html" 2>&1)"; rc=$?
printf '      %s\n' "$out"
if [ $rc -eq 0 ] && [ -s "$TMP/handbook.html" ]; then ok "render-system: this repository's docs/system renders"; else bad "render-system: this repository's docs/system renders" "$out"; fi
sections="$(cat "$SYS"/*.md | awk '/^```/ {fence = !fence} !fence && /^## / {c++} END {print c + 0}')"
slides="$(grep -c '<section class="slide"' "$TMP/handbook.html")"
printf '      ## sections: %s, slides: %s\n' "$sections" "$slides"
expect "render-system: a contents slide plus one slide per ## section" test "$slides" -eq "$((sections + 1))"
expect "render-system: the page is titled after the project" grep -q '<title>logbook 프로젝트 문서</title>' "$TMP/handbook.html"
expect "render-system: the cover shows the commit it was rendered from" grep -q '기준: ' "$TMP/handbook.html"
expect "render-system: slide heads name the doc and the section" grep -q '기술 스택 · 구성과 기술 스택' "$TMP/handbook.html"
expect "render-system: no template placeholders left" bash -c "! grep -qE '\\{\\{[A-Z_]+\\}\\}' '$TMP/handbook.html'"
HS="$TMP/html-system"
mkdir -p "$HS"
printf '<!-- logbook:system sources="x" -->\n# 한눈에\n\n## 한눈에 보기\n\n요약.\n\n```svg\n<svg></svg>\n```\n' > "$HS/overview.md"
err="$("$ROOT/scripts/render-system.sh" "$HS" "$TMP/html-system.html" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 4 ] && printf '%s' "$err" | grep -q 'overview.md에 HTML이 있습니다'; then ok "render-system: a doc with HTML is refused (exit 4)"; else bad "render-system: a doc with HTML is refused (exit 4)" "rc=$rc $err"; fi

# ---------------------------------------------------------------- plugin files
echo "== plugin files =="
expect "hooks.json is valid JSON" jq -e '.hooks.PreToolUse and .hooks.PostToolUse and .hooks.Stop' "$ROOT/hooks/hooks.json"
for skill in rulebook brief mission debrief sync; do
  f="$ROOT/skills/$skill/SKILL.md"
  if [ ! -f "$f" ]; then bad "skill $skill exists"; continue; fi
  lines="$(wc -l < "$f" | tr -d ' ')"
  shout="$(grep -cE '\b(MUST|CRITICAL|NEVER|ALWAYS)\b' "$f")"
  if [ "$lines" -le 150 ] && [ "$shout" -eq 0 ] && grep -q "^name: $skill\$" "$f" && grep -q 'templates/writing.md' "$f"; then
    ok "skill $skill: $lines lines, no shouting, name matches, follows the writing guide"
  else
    bad "skill $skill: $lines lines, shouting=$shout, writing guide referenced: $(grep -c 'templates/writing.md' "$f")"
  fi
done
expect "reviewer agent is read-only" grep -q '^tools: Read, Grep, Glob$' "$ROOT/agents/reviewer.md"
expect "reviewer agent runs on Opus at high effort" bash -c "grep -qx 'model: opus' '$ROOT/agents/reviewer.md' && grep -qx 'effort: high' '$ROOT/agents/reviewer.md'"
for tier in "builder-fast sonnet medium" "builder inherit medium" "builder-deep inherit xhigh"; do
  set -- $tier
  expect "$1 agent runs on $2 at $3 effort and can edit" bash -c "f='$ROOT/agents/$1.md'; grep -qx 'name: $1' \"\$f\" && grep -qx 'model: $2' \"\$f\" && grep -qx 'effort: $3' \"\$f\" && grep -qx 'tools: Read, Grep, Glob, Edit, Write, Bash' \"\$f\""
  expect "$1 agent stays in its files, does not commit, and reports its check" bash -c "f='$ROOT/agents/$1.md'; grep -q 'Change only the files the brief lists' \"\$f\" && grep -q 'Do not commit' \"\$f\" && grep -q 'The check command and its output' \"\$f\""
done
expect "builder agents share one body" bash -c "cd '$ROOT/agents' && [ \"\$(sed '1,/^---\$/d' builder.md )\" = \"\$(sed '1,/^---\$/d' builder-fast.md )\" ] && [ \"\$(sed '1,/^---\$/d' builder.md )\" = \"\$(sed '1,/^---\$/d' builder-deep.md )\" ]"
expect "builder agents keep their check command to the track" grep -q 'Other tracks are editing the same working tree' "$ROOT/agents/builder.md"
expect "no worker agent" test ! -e "$ROOT/agents/worker.md"
expect "brief and sync send Explore on Sonnet" bash -c "grep -q 'Explore subagents.*model: sonnet' '$ROOT/skills/brief/SKILL.md' && grep -q 'Explore subagents (on Claude Code, pass \`model: sonnet\`)' '$ROOT/skills/sync/SKILL.md'"
expect "debrief names the reviewer's model and records builder tracks" bash -c "grep -q 'runs on Opus at high effort' '$ROOT/skills/debrief/SKILL.md' && grep -q 'When builder agents implemented tracks' '$ROOT/skills/debrief/SKILL.md'"
expect "brief flags an unreasonable answer once and records it" bash -c "grep -q 'looks unreasonable against the evidence' '$ROOT/skills/brief/SKILL.md' && grep -q '알린 우려' '$ROOT/skills/brief/SKILL.md'"
expect "diagram kit reference exists" test -s "$ROOT/templates/diagram-kit.md"
expect "reviewer agent checks docs/system against the code" grep -q 'docs/system/' "$ROOT/agents/reviewer.md"
W="$ROOT/templates/writing.md"
expect "writing guide sets the reader: a computer-science graduate new to the project" grep -q "computer-science bachelor's degree" "$W"
expect "writing guide carries the picture rules" bash -c "grep -q 'whatever a picture can show' '$W' && grep -q 'Do not force an ERD or a flowchart' '$W' && grep -q 'every table' '$W'"
expect "writing guide: markdown holds no HTML, and model calls show the model and the prompt" bash -c "grep -q 'Markdown files hold no HTML' '$W' && grep -q 'names the model and gives the gist of the prompt' '$W'"
K="$ROOT/templates/diagram-kit.md"
expect "diagram kit: pictures wherever they fit, no quota, no forced ERD" bash -c "grep -q 'no quota' '$K' && grep -q 'never go into an ERD' '$K' && grep -q 'every table' '$K'"
expect "diagram kit: markdown only, bold numbers become tiles, model calls get a hexagon and a table" bash -c "grep -q 'holds no HTML' '$K' && grep -q 'bold number' '$K' && grep -q '^## Model calls' '$K' && grep -q 'hexagon' '$K'"
md_files="$(cd "$ROOT" && ls templates/*.md templates/system/*.md docs/system/*.md docs/plans/*.md README.md CHANGELOG.md)"
html_hits="$(cd "$ROOT/scripts" && printf '%s\n' "$md_files" | python3 -c "
import sys, pathlib
from render_brief import html_in_markdown
root = pathlib.Path('$ROOT')
for name in sys.stdin.read().split():
    for number, snippet in html_in_markdown((root / name).read_text(encoding='utf-8')):
        print(f'{name}:{number} {snippet}')
")"
if [ -z "$html_hits" ]; then ok "templates and this repository's markdown carry no HTML"; else bad "templates and this repository's markdown carry no HTML" "$html_hits"; fi
expect "flows template has a model-call table" grep -q '| 모델 호출 | 모델(설정) |' "$ROOT/templates/system/flows.md"
expect "reviewer agent checks model calls and HTML in markdown" bash -c "grep -q 'LLM' '$ROOT/agents/reviewer.md' && grep -q 'hold no HTML' '$ROOT/agents/reviewer.md'"
B="$ROOT/templates/agents-block.md"
expect "rule block v4 asks whenever a choice changes the user scenario" bash -c "grep -qx '$BLOCK_LINE' '$B' && grep -q '흐름이 달라지는 부분은 묻는다' '$B' && grep -q '사소한 것은 묻지 않고' '$B'"
expect "rule block v4 sets the reader and the picture rules" bash -c "grep -q '컴퓨터공학 학부' '$B' && grep -q 'ERD와 흐름도는 억지로 그리지 않는다' '$B' && grep -q '모든 테이블' '$B'"
expect "rule block v4 points at docs/system, /sync and /design" bash -c "grep -q 'docs/system/' '$B' && grep -q '/sync' '$B' && grep -q '/design' '$B'"
expect "rule block v4 no longer demands a flowchart and an ERD in every briefing" bash -c "! grep -q 'ERD 변화(없으면' '$B'"
expect "rule block v4 keeps HTML out of markdown and details model calls" bash -c "grep -q 'md 파일에는 HTML을 넣지 않고' '$B' && grep -q 'AI 모델을 부르는 단계' '$B'"
expect "rule block v4 flags unreasonable decisions once and follows the user" bash -c "grep -q '비합리적인 결정은 알린다' '$B' && grep -q '그대로 가겠다고 하면 따르고' '$B' && grep -q '알린 우려' '$B'"
expect "rule block v4 splits implementation only when it pays, with three builder tiers" bash -c "grep -q '구현은 이득이 있을 때만 나눈다' '$B' && grep -q 'logbook:builder-fast' '$B' && grep -q 'logbook:builder\`' '$B' && grep -q 'logbook:builder-deep' '$B' && grep -q '세션이 이어받는다' '$B'"
expect "rule block v4 scopes a track's check command to its own files" grep -q '그 트랙의 파일만 검사하는 것으로 준다' "$B"
expect "this repository's AGENTS.md carries the current rule block" bash -c "diff <(sed -n '/^<!-- logbook:begin/,/^<!-- logbook:end/p' '$ROOT/AGENTS.md' | grep -v '^트래커') <(grep -v '^트래커' '$B')"
T="$ROOT/templates/plan.md"
expect "plan template records concerns raised about the user's decisions" grep -q '^알린 우려:' "$T"
expect "plan template: conditional slides for logic, database and screens, no ERD filler" bash -c "grep -q '^## 주요 로직 흐름 (주요 로직이' '$T' && grep -q '^## 데이터베이스 변경 (DB 스키마가' '$T' && grep -q '^## 화면 시안 (' '$T' && ! grep -q 'ERD 변화 없음' '$T'"
expect "goal template: approved screens and project docs" bash -c "grep -q 'docs/designs/' '$ROOT/templates/goal.md' && grep -q 'docs/system/' '$ROOT/templates/goal.md'"
for doc in overview stack flows data-model; do
  expect "system template $doc starts with its marker" bash -c "head -1 '$ROOT/templates/system/$doc.md' | grep -q '^<!-- logbook:system sources='"
done
expect "system template data-model declares the table count" bash -c "head -1 '$ROOT/templates/system/data-model.md' | grep -q 'tables='"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
