#!/usr/bin/env bash
# logbook tests: rulebook script, render-brief, plan-preview hook, debrief-gate hook,
# system-check, render-system, plugin files.
# Exit code 0 only when every check passes.
set -uo pipefail

umask 022
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
BLOCK_LINE='<!-- logbook:begin v8 -->'  # a rule block from logbook before 0.7

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
cp "$R/AGENTS.md" "$TMP/agents-before"
printf '{\n  "model": "opus"\n}\n' > "$R/.claude/settings.json"

out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" 2>&1)"; rc=$?
if [ $rc -eq 0 ]; then ok "rulebook: --apply exits 0"; else bad "rulebook: --apply exits 0" "$out"; fi
expect "rulebook: AGENTS.md without an old block is left alone" cmp -s "$R/AGENTS.md" "$TMP/agents-before"
expect "rulebook: no rule block is written" bash -c "! grep -q 'logbook:begin' '$R/AGENTS.md'"
expect "rulebook: CLAUDE.md imports AGENTS.md" grep -qx '@AGENTS.md' "$R/CLAUDE.md"
expect "rulebook: plansDirectory is the git-ignored .logbook/plans, existing keys kept" jq -e '.plansDirectory == ".logbook/plans" and .model == "opus"' "$R/.claude/settings.json"
expect "rulebook: .gitignore lists .logbook/" grep -qx '.logbook/' "$R/.gitignore"
expect "rulebook: no plans folder is created" test ! -e "$R/docs/plans"
expect "rulebook: .logbook/config.json records repo from origin and base" jq -e '.repo == "acme/demo" and .base == "main" and .account == ""' "$R/.logbook/config.json"
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
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" --account octo >/dev/null 2>&1
expect "rulebook: --account is recorded in .logbook/config.json, not in AGENTS.md" bash -c "jq -e '.account == \"octo\"' '$R/.logbook/config.json' >/dev/null && cmp -s '$R/AGENTS.md' '$TMP/agents-before'"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" 2>&1)"
expect "rulebook: a rerun without --account keeps the recorded account" bash -c "jq -e '.account == \"octo\" and .repo == \"acme/demo\"' '$R/.logbook/config.json' >/dev/null && printf '%s' \"\$1\" | grep -q '변경 없음'" _ "$out"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$R" --base trunk >/dev/null 2>&1
expect "rulebook: an option still replaces the recorded value" jq -e '.base == "trunk" and .account == "octo"' "$R/.logbook/config.json"

MG="$TMP/migrate"
mkdir -p "$MG"
git -C "$MG" init -q -b main
printf '# Old\n\nKeep before.\n\n<!-- logbook:begin v7 -->\n## 작업 방식 (logbook)\n\n- **이슈부터 만든다.**\n\n트래커: repo `acme/old` · 기본 브랜치 `main`\n<!-- logbook:end -->\n\nKeep after.\n' > "$MG/AGENTS.md"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$MG" --repo acme/old 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '^update *AGENTS.md'; then ok "rulebook: an old rule block is migrated"; else bad "rulebook: an old rule block is migrated" "$out"; fi
expect "rulebook: the old block and its markers are gone" bash -c "! grep -qE 'logbook:(begin|end)|작업 방식|트래커' '$MG/AGENTS.md'"
expect "rulebook: the document rules paragraph takes the block's place" bash -c "awk '/Keep before/ {a = NR} /^## 문서\$/ {b = NR} /Keep after/ {c = NR} END {exit !(a && b && c && a < b && b < c)}' '$MG/AGENTS.md'"
expect "rulebook: the paragraph lists the default places with no placeholders" bash -c "grep -q '\`docs/system/\`' '$MG/AGENTS.md' && grep -q '\`CHANGELOG.md\`' '$MG/AGENTS.md' && grep -q '\`docs/manual/\`' '$MG/AGENTS.md' && ! grep -qE 'docs/(plans|designs)' '$MG/AGENTS.md' && ! grep -q '{[a-z]*}' '$MG/AGENTS.md'"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$MG" --repo acme/old 2>&1)"
if printf '%s' "$out" | grep -q '변경 없음'; then ok "rulebook: a migrated project needs nothing on the next run"; else bad "rulebook: a migrated project needs nothing on the next run" "$out"; fi

PL="$TMP/plans-place"
mkdir -p "$PL/.claude"
git -C "$PL" init -q -b main
printf '{\n  "plansDirectory": "docs/plans"\n}\n' > "$PL/.claude/settings.json"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$PL" --repo acme/p >/dev/null 2>&1
expect "rulebook: a plansDirectory from before 0.8 moves to .logbook/plans" jq -e '.plansDirectory == ".logbook/plans"' "$PL/.claude/settings.json"
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$PL" --plans docs/plans 2>&1)"; rc=$?
expect "rulebook: --plans is no longer an option" test $rc -eq 2

NA="$TMP/no-agents"
mkdir -p "$NA"
git -C "$NA" init -q -b main
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$NA" --repo acme/na 2>&1)"
if [ ! -e "$NA/AGENTS.md" ] && [ ! -e "$NA/CLAUDE.md" ] && [ -f "$NA/.logbook/config.json" ]; then
  ok "rulebook: without AGENTS.md it writes only the setup and leaves the rules files to /sync"
else
  bad "rulebook: without AGENTS.md it writes only the setup and leaves the rules files to /sync" "$out"
fi

C="$TMP/claude-existing"
mkdir -p "$C"
git -C "$C" init -q -b main
printf '# Local notes\n' > "$C/CLAUDE.md"
printf '# C\n' > "$C/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$C" --repo acme/c >/dev/null 2>&1
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$C" --repo acme/c >/dev/null 2>&1
expect "rulebook: existing CLAUDE.md keeps its text" grep -q '# Local notes' "$C/CLAUDE.md"
expect "rulebook: existing CLAUDE.md gets one @AGENTS.md line" test "$(grep -cx '@AGENTS.md' "$C/CLAUDE.md")" -eq 1

L="$TMP/symlinked"
mkdir -p "$L"
git -C "$L" init -q -b main
printf 'rules\n\n%s\nold\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$L/CLAUDE.md"
ln -s CLAUDE.md "$L/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$L" --repo acme/l >/dev/null 2>&1
expect "rulebook: AGENTS.md symlink survives" test -L "$L/AGENTS.md"
expect "rulebook: the block in the symlink target is migrated" bash -c "grep -qx '## 문서' '$L/CLAUDE.md' && ! grep -q 'logbook:begin' '$L/CLAUDE.md' && grep -qx 'rules' '$L/CLAUDE.md'"
expect "rulebook: no self-import when AGENTS.md points to CLAUDE.md" bash -c "! grep -qx '@AGENTS.md' '$L/CLAUDE.md'"

TB="$TMP/two-blocks"
mkdir -p "$TB"
git -C "$TB" init -q -b main
printf '# T\n\n%s\none\n<!-- logbook:end -->\n\nmiddle\n\n%s\ntwo\n<!-- logbook:end -->\n' "$BLOCK_LINE" "$BLOCK_LINE" > "$TB/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$TB" --repo acme/tb >/dev/null 2>&1
out="$("$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$TB" --repo acme/tb 2>&1)"
if [ "$(grep -cx '## 문서' "$TB/AGENTS.md")" -eq 1 ] && ! grep -q 'logbook:begin' "$TB/AGENTS.md" && grep -qx 'middle' "$TB/AGENTS.md" && printf '%s' "$out" | grep -q '변경 없음'; then
  ok "rulebook: several old blocks become one paragraph in one run"
else
  bad "rulebook: several old blocks become one paragraph in one run" "$(cat "$TB/AGENTS.md")"
fi

WR="$TMP/wt-main"
mkdir -p "$WR"
git -C "$WR" init -q -b main
git -C "$WR" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$WR" worktree add -q "$TMP/wt-linked" -b feat/1-x
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$TMP/wt-linked" --repo acme/wt >/dev/null 2>&1
expect "rulebook: run in a worktree, it writes the config to the main checkout" bash -c "jq -e '.repo == \"acme/wt\"' '$WR/.logbook/config.json' >/dev/null && test ! -e '$TMP/wt-linked/.logbook/config.json'"
expect "rulebook: run in a worktree, the main checkout ignores .logbook/ without a tracked change" bash -c "[ -z \"\$(git -C '$WR' status --porcelain)\" ] && grep -qx '.logbook/' '$WR/.git/info/exclude'"

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
if [ ! -e "$D/.logbook" ] && [ ! -e "$D/.gitignore" ] && [ ! -e "$D/.claude" ] && printf '%s' "$out" | grep -q 'planned'; then
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
DOC="$ROOT/tests/fixtures/plan.md"
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
html_doc $'- 플랜 파일을 <path>에 두고 <label>을 붙인다\n- 이름은 <issue>-<slug>.md'
"$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
expect "render-brief: placeholders such as <path> and <label> are not HTML" test $rc -eq 0
html_doc $'- 플랜을 <label>에 둔다\n\n```tsx\n<label>x</label>\n```'
"$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
expect "render-brief: a closing tag inside a code block does not turn a placeholder into HTML" test $rc -eq 0
for tag in '<div>' '줄<br>바꿈' '</span>' '<a href="x">' '<path> 와 </path>' '<img/>'; do
  html_doc "본문 $tag 끝"
  "$ROOT/scripts/render-brief.sh" "$TMP/html.md" brief "$TMP/html.html" >/dev/null 2>&1; rc=$?
  expect "render-brief: $tag is still HTML" test $rc -eq 4
done
"$ROOT/scripts/render-brief.sh" "$DOC" brief "$TMP/plain.html" >/dev/null 2>&1
"$ROOT/scripts/render-brief.sh" --standalone "$DOC" brief "$TMP/standalone.html" >/dev/null 2>&1; rc=$?
expect "render-brief: --standalone adds a doctype, and the default leaves it to the Artifact" bash -c "[ $rc -eq 0 ] && head -1 '$TMP/standalone.html' | grep -qx '<!doctype html>' && ! grep -qi '<!doctype' '$TMP/plain.html'"

# ---------------------------------------------------------------- session-rules hook
echo "== session-rules hook =="
SR="$TMP/session"
mkdir -p "$SR"
git -C "$SR" init -q -b main
printf '# S\n' > "$SR/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$SR" --repo acme/session --account octo >/dev/null 2>&1
git -C "$SR" add -A && git -C "$SR" -c user.email=t@example.com -c user.name=t commit -q -m init
rules() { jq -cn --arg cwd "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}' | env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/session-rules.sh"; }
context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
VERSION="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"

for engine in jq python; do
  force=""; [ "$engine" = python ] && force=1
  res="$(LOGBOOK_FORCE_PYTHON="$force" rules "$SR")"; rc=$?
  ctx="$(context "$res")"
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1 \
     && printf '%s\n' "$ctx" | grep -qx "# logbook 작업 규칙 (플러그인 v$VERSION)"; then
    ok "session-rules [$engine]: a logbook repository gets the rules, headed by the plugin version"
  else
    bad "session-rules [$engine]: a logbook repository gets the rules, headed by the plugin version" "rc=$rc $res"
  fi
done
ctx="$(context "$(rules "$SR")")"
expect "session-rules: the tracker line comes from .logbook/config.json" bash -c "printf '%s' \"\$1\" | grep -qF 'repo \`acme/session\` · 라벨 \`status:backlog|todo|in-progress|done\`, \`epic\` · 기본 브랜치 \`main\` · gh 계정 \`octo\`'" _ "$ctx"
expect "session-rules: no placeholder is left" bash -c "! printf '%s' \"\$1\" | grep -qE '\\{(version|repo|base|account)\\}'" _ "$ctx"
expect "session-rules: the rules point at AGENTS.md's document rules" bash -c "printf '%s' \"\$1\" | grep -q '문서는 AGENTS.md의 문서 규칙을 따른다'" _ "$ctx"
size="$(printf '%s' "$ctx" | python3 -c 'import sys; print(len(sys.stdin.read()))')"
printf '      context: %s characters\n' "$size"
expect "session-rules: the context stays under Claude Code's 10,000-character hook limit" test "$size" -lt 10000
expect "session-rules: no migration note without an old block" bash -c "! printf '%s' \"\$1\" | grep -q '0.7 이전의 규칙 블록'" _ "$ctx"

git -C "$SR" worktree add -q "$TMP/session-wt" -b feat/1-wt
ctx_wt="$(context "$(rules "$TMP/session-wt")")"
expect "session-rules: a worktree finds the main checkout's config" bash -c "[ -n \"\$1\" ] && [ \"\$1\" = \"\$2\" ]" _ "$ctx_wt" "$ctx"
mkdir -p "$SR/sub/dir"
expect "session-rules: CDPATH does not change where the config is found" bash -c "[ \"\$1\" = \"\$2\" ]" _ "$(cd "$SR" && jq -cn --arg cwd "$SR" '{cwd: $cwd}' | CDPATH=.:/ env -u CLAUDE_PROJECT_DIR "$ROOT/hooks/session-rules.sh" | jq -r '.hookSpecificOutput.additionalContext')" "$ctx"
expect "session-rules: works from a subfolder" bash -c "[ \"\$1\" = \"\$2\" ]" _ "$(context "$(rules "$SR/sub/dir")")" "$ctx"

NL="$TMP/no-logbook"
mkdir -p "$NL"
git -C "$NL" init -q -b main
printf '# N\n' > "$NL/AGENTS.md"
res="$(rules "$NL")"; rc=$?
expect "session-rules: a repository without logbook gets nothing" test $rc -eq 0 -a -z "$res"
res="$(rules "$TMP")"; rc=$?
expect "session-rules: a folder outside git without .logbook/config.json gets nothing" test $rc -eq 0 -a -z "$res"
NGS="$TMP/not-git-session"
mkdir -p "$NGS"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$NGS" --repo acme/ngs >/dev/null 2>&1
expect "session-rules: a logbook folder outside git gets the rules" bash -c "printf '%s' \"\$1\" | grep -q '^트래커: repo .acme/ngs.'" _ "$(context "$(rules "$NGS")")"

OB="$TMP/old-block"
mkdir -p "$OB"
git -C "$OB" init -q -b main
printf '# O\n\n%s\n- old rules\n\n트래커: repo `acme/old` · 라벨 `x` · 기본 브랜치 `trunk` · gh 계정 `olduser`\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$OB/AGENTS.md"
ctx="$(context "$(rules "$OB")")"
expect "session-rules: an unmigrated project gets the rules with the tracker from its old block" bash -c "printf '%s' \"\$1\" | grep -qF 'repo \`acme/old\`' && printf '%s' \"\$1\" | grep -qF '기본 브랜치 \`trunk\` · gh 계정 \`olduser\`'" _ "$ctx"
expect "session-rules: an old block adds a note to run /rulebook" bash -c "printf '%s' \"\$1\" | grep -q '0.7 이전의 규칙 블록' && printf '%s' \"\$1\" | grep -q '/rulebook'" _ "$ctx"

OP="$TMP/old-plans"
mkdir -p "$OP/.claude"
git -C "$OP" init -q -b main
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$OP" --repo acme/op >/dev/null 2>&1
printf '{\n  "plansDirectory": "./.logbook/plans/"\n}\n' > "$OP/.claude/settings.json"
expect "session-rules: ./ and a trailing slash still count as .logbook/plans" bash -c "! printf '%s' \"\$1\" | grep -q '플랜 모드의 계획 파일'" _ "$(context "$(rules "$OP")")"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$OP" --repo acme/op >/dev/null 2>&1
expect "session-rules: no plans note when plansDirectory is .logbook/plans" bash -c "! printf '%s' \"\$1\" | grep -q '플랜 모드의 계획 파일'" _ "$(context "$(rules "$OP")")"
printf '{\n  "plansDirectory": "docs/plans"\n}\n' > "$OP/.claude/settings.json"
expect "session-rules: a plansDirectory from before 0.8 adds a note to rerun /rulebook" bash -c "printf '%s' \"\$1\" | grep -q '계획 파일을 \`docs/plans\`에 저장한다' && printf '%s' \"\$1\" | grep -q '/rulebook을 다시 실행하면'" _ "$(context "$(rules "$OP")")"

NAC="$TMP/no-account"
mkdir -p "$NAC"
git -C "$NAC" init -q -b main
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$NAC" --repo acme/na >/dev/null 2>&1
ctx="$(context "$(rules "$NAC")")"
expect "session-rules: without a gh account the tracker line leaves it out" bash -c "printf '%s' \"\$1\" | grep -qF '기본 브랜치 \`main\`' && ! printf '%s' \"\$1\" | grep -q 'gh 계정'" _ "$ctx"

# ---------------------------------------------------------------- plan-preview hook
echo "== plan-preview hook =="
P="$TMP/proj"
mkdir -p "$P"
git -C "$P" init -q -b main
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$P" --repo acme/proj >/dev/null 2>&1
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
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.hookSpecificOutput.additionalContext | test("/brief") and test("에픽") and test("PR")' >/dev/null 2>&1; then
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
res="$(jq -cn --arg cwd "$NL" '{hook_event_name: "PreToolUse", tool_input: {plan: "# x\n\n1. y"}, cwd: $cwd}' | hook "$NL")"; rc=$?
expect "plan-preview: a git repository without .logbook/config.json is left alone" test $rc -eq 0 -a -z "$res"
OP="$TMP/old-proj"
mkdir -p "$OP"
git -C "$OP" init -q -b main
printf '# old\n\n%s\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$OP/AGENTS.md"
res="$(jq -cn --arg cwd "$OP" '{hook_event_name: "PreToolUse", tool_input: {plan: "# x\n\n1. y"}, cwd: $cwd}' | hook "$OP")"
expect "plan-preview: an unmigrated project with an old block still gets the check" bash -c "printf '%s' \"\$1\" | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"' >/dev/null" _ "$res"
git -C "$P" add -A && git -C "$P" -c user.email=t@example.com -c user.name=t commit -q -m init
git -C "$P" worktree add -q "$TMP/proj-wt" -b feat/2-wt
res="$(jq -cn --arg cwd "$TMP/proj-wt" '{hook_event_name: "PreToolUse", tool_input: {plan: "# x\n\n1. y"}, cwd: $cwd}' | hook "$TMP/proj-wt")"
expect "plan-preview: a worktree uses the main checkout's config" bash -c "printf '%s' \"\$1\" | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"' >/dev/null" _ "$res"
NG="$TMP/not-git"
mkdir -p "$NG/.logbook"
printf '{"repo": "acme/ng", "base": "main", "account": ""}\n' > "$NG/.logbook/config.json"
res="$(jq -cn --arg cwd "$NG" '{hook_event_name: "PreToolUse", tool_input: {plan: "# x\n\n1. y"}, cwd: $cwd}' | hook "$NG")"
expect "plan-preview: a logbook folder outside git still gets the check" bash -c "printf '%s' \"\$1\" | jq -e '.hookSpecificOutput.permissionDecision == \"deny\"' >/dev/null" _ "$res"

# ---------------------------------------------------------------- debrief-gate hook
echo "== debrief-gate hook =="
G="$TMP/gate"
BIN="$TMP/bin"
mkdir -p "$G" "$BIN"
git -C "$G" init -q -b main
printf '# gate\n' > "$G/AGENTS.md"
"$ROOT/scripts/rulebook.sh" --apply --no-labels --dir "$G" --repo acme/demo --account octo >/dev/null 2>&1
git -C "$G" add -A
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

GATE_STATE="$G/.logbook/state/debrief-feat_9-demo"
for engine in jq python; do
  force=""; [ "$engine" = python ] && force=1
  rm -f "$GATE_STATE"
  res="$(stop_input false | LOGBOOK_FORCE_PYTHON="$force" gate nomarker)"; rc=$?
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.decision == "block" and (.reason | test("/debrief"))' >/dev/null 2>&1; then
    ok "debrief-gate [$engine]: open PR without the marker blocks"
  else
    bad "debrief-gate [$engine]: open PR without the marker blocks" "rc=$rc $res"
  fi
  res="$(stop_input true | LOGBOOK_FORCE_PYTHON="$force" gate nomarker)"; rc=$?
  expect "debrief-gate [$engine]: stop_hook_active=true passes" test $rc -eq 0 -a -z "$res"
done
expect "debrief-gate: gh account comes from .logbook/config.json" grep -qx octo "$TMP/gh.log"
res="$(stop_input false | gate nomarker)"; rc=$?
expect "debrief-gate: a later turn on the same HEAD passes" test $rc -eq 0 -a -z "$res"
git -C "$G" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m next
res="$(stop_input false | gate nomarker)"
expect "debrief-gate: a new commit blocks once more" bash -c "printf '%s' \"\$1\" | jq -e '.decision == \"block\"' >/dev/null" _ "$res"
rm -f "$GATE_STATE"
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
git -C "$G" worktree add -q "$TMP/gate-wt" -b feat/10-wt
: > "$TMP/gh.log"
res="$(stop_input false '[]' "$TMP/gate-wt" | gate nomarker)"
expect "debrief-gate: a worktree uses the main checkout's config" bash -c "printf '%s' \"\$1\" | jq -e '.decision == \"block\"' >/dev/null && grep -qx octo '$TMP/gh.log'" _ "$res"
OG="$TMP/old-gate"
mkdir -p "$OG"
git -C "$OG" init -q -b main
printf '# old\n\n%s\n트래커: repo `acme/old` · 기본 브랜치 `main` · gh 계정 `olduser`\n<!-- logbook:end -->\n' "$BLOCK_LINE" > "$OG/AGENTS.md"
git -C "$OG" add -A && git -C "$OG" -c user.email=t@example.com -c user.name=t commit -q -m init
git -C "$OG" checkout -q -b feat/2-old
: > "$TMP/gh.log"
res="$(stop_input false '[]' "$OG" | gate nomarker)"
expect "debrief-gate: an unmigrated project reads the account from its old block" bash -c "printf '%s' \"\$1\" | jq -e '.decision == \"block\"' >/dev/null && grep -qx olduser '$TMP/gh.log'" _ "$res"

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
expect "system-check: a stale doc points at the checked date" bash -c "printf '%s' \"\$1\" | grep -q 'checked 날짜를 오늘로 고쳐 커밋하세요'" _ "$out"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); l=p.read_text().split("\n",1); p.write_text(l[0].replace(" -->", " checked=\"2026-10-01\" -->",1)+"\n"+l[1])' "$S/docs/system/flows.md"
scommit "checked flows"
out="$(sc)"
if has_row "$out" "정상" "flows.md"; then ok "system-check: committing a new checked date clears a stale doc"; else bad "system-check: committing a new checked date clears a stale doc" "$out"; fi
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
"$ROOT/scripts/render-system.sh" --standalone "$SYS" "$TMP/handbook-standalone.html" >/dev/null 2>&1; rc=$?
expect "render-system: --standalone adds a doctype" bash -c "[ $rc -eq 0 ] && head -1 '$TMP/handbook-standalone.html' | grep -qx '<!doctype html>' && ! grep -qi '<!doctype' '$TMP/handbook.html'"
HS="$TMP/html-system"
mkdir -p "$HS"
printf '<!-- logbook:system sources="x" -->\n# 한눈에\n\n## 한눈에 보기\n\n요약.\n\n```svg\n<svg></svg>\n```\n' > "$HS/overview.md"
err="$("$ROOT/scripts/render-system.sh" "$HS" "$TMP/html-system.html" 2>&1 >/dev/null)"; rc=$?
if [ $rc -eq 4 ] && printf '%s' "$err" | grep -q 'overview.md에 HTML이 있습니다'; then ok "render-system: a doc with HTML is refused (exit 4)"; else bad "render-system: a doc with HTML is refused (exit 4)" "rc=$rc $err"; fi

# ---------------------------------------------------------------- plugin files
echo "== plugin files =="
expect "hooks.json is valid JSON with the four hooks" jq -e '.hooks.SessionStart and .hooks.PreToolUse and .hooks.PostToolUse and .hooks.Stop' "$ROOT/hooks/hooks.json"
expect "SessionStart runs on every source (no matcher)" jq -e '.hooks.SessionStart[0] | has("matcher") | not' "$ROOT/hooks/hooks.json"
for skill in rulebook discuss brief debrief sync; do
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
expect "brief and sync send Explore on Sonnet, as subagents or a Workflow" bash -c "grep -q 'Explore subagents on Sonnet or a Workflow' '$ROOT/skills/brief/SKILL.md' && grep -q 'Explore agents on Sonnet, as subagents or a Workflow' '$ROOT/skills/sync/SKILL.md'"
expect "debrief names the reviewer's model and records builder tracks" bash -c "grep -q 'runs on Opus at high effort' '$ROOT/skills/debrief/SKILL.md' && grep -q 'When builder agents implemented tracks' '$ROOT/skills/debrief/SKILL.md'"
expect "brief flags an unreasonable answer once and records it" bash -c "grep -q 'looks unreasonable against the evidence' '$ROOT/skills/brief/SKILL.md' && grep -q '알린 우려' '$ROOT/skills/brief/SKILL.md'"
D="$ROOT/skills/discuss/SKILL.md"
expect "discuss changes nothing until the user picks an ending" bash -c "grep -q 'Nothing in the project changes until the user picks an ending' '$D' && grep -q 'No file edits, no commits, no branches' '$D' && grep -q 'No issues, labels or comments' '$D' && grep -q 'no plan mode' '$D'"
expect "discuss leaves /debrief alone and cites issues as full links for /brief" bash -c "grep -q 'No \`/debrief\`, even when a Stop hook asks' '$D' && grep -q 'never as a bare' '$D' && grep -q 'without an account there, use the default login' '$D'"
expect "rule block has the agent load the discuss skill" grep -q '`/discuss` 스킬을 불러 그 절차대로 토론한다' "$ROOT/templates/session-rules.md"
expect "discuss researches read-only with Explore on Sonnet and the web" bash -c "grep -q 'Research actively, read-only' '$D' && grep -q 'Explore agents on Sonnet' '$D' && grep -q 'templates/parallel.md' '$D' && grep -q 'search the web' '$D'"
expect "discuss argues like a colleague and pushes back with evidence" bash -c "grep -q 'push back with confidence' '$D' && grep -q 'Do not argue for the sake of arguing' '$D' && grep -q 'strongest argument against' '$D'"
expect "discuss ends with a summary and three endings, one recommended" bash -c "grep -q '결론' '$D' && grep -q '합의한 것' '$D' && grep -q '남은 질문' '$D' && grep -q 'Recommend one of three endings' '$D' && grep -q '바로 진행' '$D' && grep -q 'backlog 이슈로 남기기' '$D' && grep -q '남기지 않기' '$D'"
expect "discuss keeps later ideas as status:backlog issues that /brief picks up" bash -c "grep -q 'labelled \`status:backlog\`' '$D' && grep -q '/logbook:brief #<issue>' '$D' && grep -q 'moves to \`status:todo\`' '$ROOT/skills/brief/SKILL.md'"
expect "brief takes a /discuss summary's decisions as the user's own" grep -q 'carries a `/discuss` summary, its decisions are the user' "$ROOT/skills/brief/SKILL.md"
expect "diagram kit reference exists" test -s "$ROOT/templates/diagram-kit.md"
expect "reviewer agent checks docs/system against the code" grep -q 'docs/system/' "$ROOT/agents/reviewer.md"
W="$ROOT/templates/writing.md"
expect "writing guide sets the reader: a computer-science graduate new to the project" grep -q "computer-science bachelor's degree" "$W"
expect "writing guide carries the picture rules" bash -c "grep -q 'whatever a picture can show' '$W' && grep -q 'Do not force an ERD or a flowchart' '$W' && grep -q 'every table' '$W'"
expect "writing guide: markdown holds no HTML, and model calls show the model and the prompt" bash -c "grep -q 'Markdown files hold no HTML' '$W' && grep -q 'names the model and gives the gist of the prompt' '$W'"
K="$ROOT/templates/diagram-kit.md"
expect "diagram kit: pictures wherever they fit, no quota, no forced ERD" bash -c "grep -q 'no quota' '$K' && grep -q 'never go into an ERD' '$K' && grep -q 'every table' '$K'"
expect "diagram kit: markdown only, bold numbers become tiles, model calls get a hexagon and a table" bash -c "grep -q 'holds no HTML' '$K' && grep -q 'bold number' '$K' && grep -q '^## Model calls' '$K' && grep -q 'hexagon' '$K'"
md_files="$(cd "$ROOT" && ls templates/*.md templates/system/*.md docs/system/*.md tests/fixtures/*.md README.md CHANGELOG.md)"
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
B="$ROOT/templates/session-rules.md"
expect "no rule block template; the rules come from session-rules.md" bash -c "test ! -e '$ROOT/templates/agents-block.md' && ! grep -q 'logbook:begin' '$B' && head -1 '$B' | grep -qF '(플러그인 v{version})'"
expect "rule block asks whenever a choice changes the user scenario" bash -c "grep -q '흐름이 달라지는 부분은 묻는다' '$B' && grep -q '사소한 것은 묻지 않고' '$B'"
expect "rule block sets the reader and the picture rules" bash -c "grep -q '컴퓨터공학 학부' '$B' && grep -q 'ERD와 흐름도는 억지로 그리지 않는다' '$B' && grep -q '모든 테이블' '$ROOT/templates/docs-rules.md'"
expect "rule block points at docs/system, /sync and /design" bash -c "grep -q 'docs/system/' '$B' && grep -q '/sync' '$B' && grep -q '/design' '$B'"
expect "rule block no longer demands a flowchart and an ERD in every briefing" bash -c "! grep -q 'ERD 변화(없으면' '$B'"
expect "rule block keeps HTML out of markdown and details model calls" bash -c "grep -q 'md 파일에는 HTML을 넣지 않고' '$B' && grep -q 'AI 모델을 부르는 단계' '$B'"
expect "rule block flags unreasonable decisions once and follows the user" bash -c "grep -q '비합리적인 결정은 알린다' '$B' && grep -q '그대로 가겠다고 하면 따르고' '$B' && grep -q '알린 우려' '$B'"
expect "rule block splits implementation only when it pays, with three builder tiers" bash -c "grep -q '구현은 이득이 있을 때만 나눈다' '$B' && grep -q 'logbook:builder-fast' '$B' && grep -q 'logbook:builder\`' '$B' && grep -q 'logbook:builder-deep' '$B' && grep -q '세션이 이어받는다' '$B'"
expect "rule block scopes a track's check command to its own files" grep -q '그 트랙의 파일만 검사하는 것으로 준다' "$B"
expect "rule block answers a request for an opinion with a discussion" bash -c "grep -q '의견을 묻는 말에는 토론으로 답한다' '$B' && grep -q '이슈와 브랜치를 만들지 않고' '$B' && grep -q '애매하면 어느 쪽인지 한 줄로 묻는다' '$B' && grep -q 'backlog 이슈로 남기기' '$B'"
expect "rule block creates issues only for work others need or that must be kept" bash -c "grep -q '이슈는 남길 일에만 만든다' '$B' && grep -q '다른 개발자가 알아야 하거나 꼭 남겨야 하는 작업' '$B' && ! grep -q '이슈부터 만든다' '$B'"
expect "rule block reports local-only work in chat and rides follow-up doc updates on related PRs" bash -c "grep -q '이슈, 브랜치, PR 없이 하고 채팅으로 보고한다' '$B' && grep -q 'docs/system/stack.md' '$B' && grep -q '관련 작업의 PR에 얹는다' '$B' && grep -q '그 이슈에 할 일을 댓글로 남기고' '$B' && grep -q '둘 다 없으면 이슈 없는 PR로 연다' '$B'"
expect "rule block asks when unsure and gives small changes a PR only" bash -c "grep -q '이슈로 만들지 애매하면 작업 전에 한 줄로 묻는다' '$B' && grep -q '이슈와 브리핑 HTML 없이 PR만 남긴다' '$B' && grep -q '<type>/<slug>' '$B'"
expect "brief, debrief and sync handle a PR without an issue" bash -c "grep -q 'open a PR without an issue' '$ROOT/skills/brief/SKILL.md' && grep -q 'deferred to this issue' '$ROOT/skills/brief/SKILL.md' && grep -q 'When no plan doc exists for the PR' '$ROOT/skills/debrief/SKILL.md' && grep -q 'a PR without an issue that still gets a review' '$ROOT/skills/sync/SKILL.md'"
expect "brief and plan mode read comments deferred to the issue" bash -c "grep -q 'deferred to this issue' '$ROOT/skills/brief/SKILL.md' && grep -q 'read its comments before writing' '$ROOT/skills/brief/SKILL.md'"
expect "a small change given an issue still closes it" grep -q 'put `Closes #<issue>` in the PR body' "$ROOT/skills/brief/SKILL.md"
expect "debrief reviews bigger changes without a plan doc and skips only the HTML" bash -c "grep -q '^## Changes without a plan doc' '$ROOT/skills/debrief/SKILL.md' && grep -q 'Anything bigger, such as a follow-up doc update or a \`/sync\` fix, runs step 3 and step 7' '$ROOT/skills/debrief/SKILL.md'"
expect "an approved brief:skip plan follows the skip path and stays in the git-ignored plans folder" grep -q 'the plan file stays in .\.logbook/plans/., which git ignores' "$ROOT/skills/brief/SKILL.md"
expect "this repository's AGENTS.md has no rule block and keeps the document table" bash -c "! grep -q 'logbook:begin' '$ROOT/AGENTS.md' && grep -qx '## 문서' '$ROOT/AGENTS.md' && grep -q '| 지금 시스템' '$ROOT/AGENTS.md'"
DR="$ROOT/templates/docs-rules.md"
expect "document rules paragraph: system, changelog and manual, no plan docs or mockups, no logbook marker and no logbook command" bash -c "for k in system changelog manual; do grep -q \"{\$k}\" '$DR' || exit 1; done; ! grep -qE '\\{(plans|designs)\\}' '$DR' && grep -q '이슈와 PR을 링크한다' '$DR' && grep -q '날짜별로' '$DR' && ! grep -qiE 'logbook|/sync|/brief|<!--' '$DR'"
expect "the rules defer document places to AGENTS.md's table" bash -c "grep -q '문서는 AGENTS.md의 문서 규칙을 따른다' '$B' && ! grep -q '문서는 정해진 자리에 둔다' '$B'"
expect "skills read the tracker line from the logbook rules, not from AGENTS.md" bash -c "! grep -rq 'AGENTS.md tracker line' '$ROOT/skills' && grep -q 'the tracker line in the logbook rules the session started with' '$ROOT/skills/brief/SKILL.md' && grep -q 'the tracker line in the logbook rules the session started with' '$ROOT/skills/debrief/SKILL.md' && grep -q 'the tracker line in the logbook rules the session started with' '$ROOT/skills/discuss/SKILL.md'"
expect "rulebook runs once per clone and writes no rule block" bash -c "grep -q 'once per clone' '$ROOT/skills/rulebook/SKILL.md' && grep -q 'A plugin update needs no rerun' '$ROOT/skills/rulebook/SKILL.md'"
expect "sync asks for the document structure when it is not in place" bash -c "grep -q '^2. \*\*Structure.\*\*' '$ROOT/skills/sync/SKILL.md' && grep -q 'templates/docs-rules.md' '$ROOT/skills/sync/SKILL.md' && ! grep -q 'rulebook.sh' '$ROOT/skills/sync/SKILL.md'"
T="$ROOT/templates/plan.md"
expect "plan template records concerns raised about the user's decisions" grep -q '^알린 우려:' "$T"
expect "plan template: conditional slides for logic, database and screens, no ERD filler" bash -c "grep -q '^## 주요 로직 흐름 (주요 로직이' '$T' && grep -q '^## 데이터베이스 변경 (DB 스키마가' '$T' && grep -q '^## 화면 시안 (' '$T' && ! grep -q 'ERD 변화 없음' '$T'"
P="$ROOT/templates/parallel.md"
expect "parallel guide: subagents by default, Workflow for three or more or long work, subagents as the fallback" bash -c "grep -q 'The default. Two tracks or two research areas' '$P' && grep -q 'three or more tracks or areas' '$P' && grep -q 'launch subagents instead' '$P'"
expect "parallel guide: Workflow agents keep the builder tiers and Explore on Sonnet" bash -c "grep -q \"agentType: 'logbook:builder-fast', model: 'sonnet', effort: 'medium'\" '$P' && grep -q \"agentType: 'logbook:builder-deep', effort: 'xhigh'\" '$P' && grep -q \"agentType: 'Explore', model: 'sonnet'\" '$P'"
expect "brief, discuss and sync launch parallel work by the guide" bash -c "for s in brief discuss sync; do grep -q 'templates/parallel.md' '$ROOT/skills/'\$s'/SKILL.md' || exit 1; done"
expect "rule block lets tracks and research run as subagents or a Workflow" bash -c "grep -q '서브에이전트나 Workflow' '$B' && grep -q 'Workflow를 쓸 수 없으면 서브에이전트로' '$B'"
expect "rule block runs an epic on an epic branch and merges steps only when the evidence holds" bash -c "grep -q '에픽은 에픽 브랜치에서' '$B' && grep -q 'epic/<번호>-<slug>' '$B' && grep -q '확인된 심각한 지적이 없을 때만 에이전트가 squash로 합친' '$B' && grep -q '일반 머지' '$B'"
DB="$ROOT/skills/debrief/SKILL.md"
expect "debrief: an epic step merges itself into the epic branch without HTML, or stops" bash -c "grep -q '^## Epic steps and epics' '$DB' && grep -q 'Skip step 5 and the changelog line: no HTML' '$DB' && grep -q 'gh pr merge --squash --delete-branch' '$DB' && grep -q 'stop the epic run there' '$DB'"
expect "debrief: an epic gets the epic review and a merge commit" bash -c "grep -q 'in epic mode' '$DB' && grep -q 'gh pr merge --merge --delete-branch' '$DB' && grep -q 'origin/<PR base>...HEAD' '$DB'"
expect "reviewer has an epic mode that reads where steps meet" bash -c "grep -q '^## Epic mode' '$ROOT/agents/reviewer.md' && grep -q 'where steps meet' '$ROOT/agents/reviewer.md'"
BR="$ROOT/skills/brief/SKILL.md"
expect "no /mission skill and no /goal template" bash -c "test ! -e '$ROOT/skills/mission' && test ! -e '$ROOT/templates/goal.md' && ! grep -q '^## Goal' '$ROOT/templates/plan.md'"
expect "skills, agents, hooks, templates and the rule block no longer mention /mission or /goal" bash -c "! grep -rnE '/mission|/goal|goal\\.md' '$ROOT/skills' '$ROOT/agents' '$ROOT/hooks' '$ROOT/templates' '$ROOT/scripts' '$ROOT/AGENTS.md' '$ROOT/README.md' '$ROOT/.claude-plugin' '$ROOT/docs/system' '$ROOT/docs/manual'"
expect "brief plans an epic: child issues, step docs without HTML, an epic branch" bash -c "grep -q '^## Epics' \"$BR\" && grep -q 'epic/<issue>-<slug>' \"$BR\" && grep -q 'Only the epic doc is rendered and published; step docs get no HTML' \"$BR\" && grep -q 'Create the missing child issues' \"$BR\""
expect "brief carries an approved plan through, and an epic through every step to the epic PR" bash -c "grep -q 'carry the plan out to the end without asking for approval again' \"$BR\" && grep -q 'do not end the turn between steps' \"$BR\" && grep -q 'open the epic PR from the epic branch' \"$BR\" && grep -q '고친 뒤 이어서 / 중단' \"$BR\" && grep -q 'Stops and resuming' \"$BR\" && grep -q 'do not weaken or delete tests' \"$BR\" && grep -q 'open the PR with \`Closes #<issue>\`' \"$BR\""
expect "rule block plans an epic with /brief and runs its steps without stopping" bash -c "grep -q '\`/brief\`가 \`epic\` 라벨 이슈와 단계 이슈로 계획하고' '$ROOT/templates/session-rules.md' && grep -q '단계 사이에서 멈추지 않고' '$ROOT/templates/session-rules.md'"
expect "plan template has the epic step table and results" bash -c "grep -q '^## 단계 (에픽일 때)' '$T' && grep -q '^## 단계 결과 (에픽일 때)' '$T' && grep -q 'origin/{PR의 base 브랜치}' '$T'"
for doc in overview stack flows data-model; do
  expect "system template $doc starts with its marker" bash -c "head -1 '$ROOT/templates/system/$doc.md' | grep -q '^<!-- logbook:system sources='"
done
expect "brief: 중단 asks 나중에 하기 or 버리기, and a set-aside branch is picked up again" bash -c "grep -q 'On 중단, ask 나중에 하기 / 버리기' '$ROOT/skills/brief/SKILL.md' && grep -q 'keeps the branch, and posts the whole plan doc as an issue comment' '$ROOT/skills/brief/SKILL.md' && grep -q 'not planned' '$ROOT/skills/brief/SKILL.md' && grep -q 'A plan set aside with 나중에 하기 in step 9 is picked up again' '$ROOT/skills/brief/SKILL.md'"
expect "sync: only the structure path cleans up without asking, root docs such as CONTRIBUTING stay, history is not grepped" bash -c "grep -q '^   - The structure path: set up the structure' '$ROOT/skills/sync/SKILL.md' && grep -q 'ask once whether this PR removes it' '$ROOT/skills/sync/SKILL.md' && grep -q 'CONTRIBUTING, SECURITY and CODE_OF_CONDUCT' '$ROOT/skills/sync/SKILL.md' && grep -q 'leaving out CHANGELOG, which keeps history' '$ROOT/skills/sync/SKILL.md'"
expect "sync: a stale doc that still matches gets a new checked date, not new wording" bash -c "grep -q 'set .checked. to today and commit' '$ROOT/skills/sync/SKILL.md'"
for f in "$ROOT"/templates/system/*.md; do
  expect "system template $(basename "$f") records when it was checked" bash -c "head -1 '$f' | grep -q 'checked='"
done
expect "no skill, hook, script or template runs legacy-scan or passes --plans" bash -c "! grep -rqE 'legacy-scan|legacy_scan|--plans' '$ROOT/skills' '$ROOT/hooks' '$ROOT/scripts' '$ROOT/templates' '$ROOT/agents'"
expect "system template data-model declares the table count" bash -c "head -1 '$ROOT/templates/system/data-model.md' | grep -q 'tables='"

# ---------------------------------------------------------------- local plan docs and CHANGELOG (0.9)
expect "this repository tracks no plan docs and no mockup copies" bash -c "cd '$ROOT' && test -z \"\$(git ls-files docs/plans docs/designs)\""
expect "only sync's migration rule still names docs/plans or docs/designs" bash -c "test \"\$(grep -rlE 'docs/(plans|designs)' '$ROOT/skills' '$ROOT/hooks' '$ROOT/scripts' '$ROOT/templates' '$ROOT/agents')\" = '$ROOT/skills/sync/SKILL.md' && grep -q 'Plan docs and mockup copies that logbook before 0.9 committed' '$ROOT/skills/sync/SKILL.md'"
expect "brief keeps the plan doc and the mockup copy in the main checkout's .logbook and never commits them" bash -c "grep -q '\`.logbook/plans/\` and \`.logbook/designs/\` of the main checkout' '$BR' && grep -q 'never committed' '$BR' && grep -q 'Write \`<main>/.logbook/plans/<issue>-<slug>.md\`' '$BR' && grep -q 'artboards to \`<main>/.logbook/designs/<issue>-<slug>/\`' '$BR' && grep -q 'render-brief.sh <main>/.logbook/plans/<issue>-<slug>.md brief <main>/.logbook/briefs/' '$BR' && grep -q 'render-brief.sh <doc> debrief <main>/.logbook/briefs/' '$DB' && grep -q 'Do not commit the plan doc' '$BR'"
expect "brief puts the reasons in the PR body" bash -c "grep -q 'The PR body carries what the plan doc cannot' '$BR' && grep -q '알린 우려, your own calls' '$BR' && grep -q 'in the plan doc.s 결정 기록 and the PR body' '$BR'"
expect "brief resumes a set-aside plan from the local doc or the 계획 문서 comment" bash -c "grep -q 'or else from the issue.s last comment whose first line is \`계획 문서\`' '$BR' && grep -q 'picks it up again on any clone' '$BR' && grep -q 'Check out its branch when it exists on this clone or the remote; otherwise cut it' '$BR'"
expect "brief keeps an epic's step table in the epic issue" bash -c "grep -q 'in the epic issue body, push the epic branch' '$BR' && grep -q 'rebuild the epic doc from the epic issue body and the step docs from the child issue bodies' '$BR' && grep -q 'a body like step 9.s (요약, 주요 결정, completion conditions)' '$BR'"
expect "debrief writes one CHANGELOG line linking the issue and the PR, once per epic" bash -c "grep -q 'Changelog: add one line for this change' '$DB' && grep -q 'linking the issue and the PR' '$DB' && grep -q 'Keep a Changelog' '$DB' && grep -q 'by date for an app that has no versions' '$DB' && grep -q 'The changelog line links the epic issue and the epic PR' '$DB' && grep -q 'The doc stays uncommitted' '$DB'"
expect "plan template keeps the doc local and has a 변경 이력 evidence row" bash -c "grep -q '커밋하지 않는다' '$T' && grep -q '^| 변경 이력 | ✅ |' '$T' && grep -q '.logbook/designs/{이슈번호}-{slug}/' '$T'"
expect "rules keep plan docs and mockups in .logbook and the history in CHANGELOG" bash -c "grep -q '.logbook/plans/<번호>-<slug>.md' '$B' && grep -q '.logbook/designs/<번호>-<slug>/' '$B' && grep -q 'CHANGELOG에 이슈와 PR을 링크한 한 줄' '$B' && grep -q '\`CHANGELOG.md\`(변경 이력)' '$B' && ! grep -qE 'docs/(plans|designs)' '$B'"
expect "sync's document table has a changelog row and asks version or date" bash -c "grep -q '| 변경 이력 (CHANGELOG' '$ROOT/skills/sync/SKILL.md' && grep -q 'whether the changelog goes by version or by date' '$ROOT/skills/sync/SKILL.md'"
expect "the approved-plan hook keeps the plan in .logbook/plans and commits no plan doc" bash -c "grep -q '원래 checkout의 .logbook/plans/<이슈번호>-<slug>.md로 옮긴 뒤' '$ROOT/hooks/plan-preview.sh' && grep -q '커밋하지 않습니다' '$ROOT/hooks/plan-preview.sh' && ! grep -qE '(계획 문서|문서)[^.]*커밋합니다' '$ROOT/hooks/plan-preview.sh'"
expect "sync looks for plan docs left by logbook before 0.9 on every run and puts 주요 결정 in its PR" bash -c "grep -q 'On every path, also check .git ls-files. for plan docs and mockup copies left by logbook before 0.9' '$ROOT/skills/sync/SKILL.md' && grep -q 'and the document table for their rows' '$ROOT/skills/sync/SKILL.md' && grep -q 'the plan.s 주요 결정 in its body' '$ROOT/skills/sync/SKILL.md'"
expect "system doc templates link decisions to PRs, not plan docs" bash -c "! grep -q '계획 문서 링크' '$ROOT/templates/system/overview.md' '$ROOT/templates/system/stack.md'"
expect "no skill or hook tells the agent to commit or push a plan doc" bash -c "test -z \"\$(grep -rniE '(commit|push)[a-z ]* (the|every) (plan|step|epic) doc|plan-doc updates' '$ROOT/skills' '$ROOT/hooks' '$ROOT/agents' '$ROOT/templates' | grep -viE 'do not commit')\""

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
