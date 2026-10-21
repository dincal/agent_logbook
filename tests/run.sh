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
  "label list") printf 'Status:Backlog\nSTATUS:TODO\nstatus:done\n' ;;
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
if [ "$created" = "status:in-progress " ]; then
  ok "rulebook: labels compared case-insensitively, only missing status labels created, no epic label"
else
  bad "rulebook: labels compared case-insensitively, only missing status labels created, no epic label" "created: $created"
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
rules() { jq -cn --arg cwd "$1" '{hook_event_name: "SessionStart", source: "startup", cwd: $cwd}' | env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT "$ROOT/hooks/session-rules.sh"; }
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
expect "session-rules: the tracker line comes from .logbook/config.json" bash -c "printf '%s' \"\$1\" | grep -qF 'repo \`acme/session\` · 라벨 \`status:backlog|todo|in-progress|done\` · 기본 브랜치 \`main\` · gh 계정 \`octo\`'" _ "$ctx"
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
  if [ $rc -eq 0 ] && [ -z "$res" ] && [ ! -e "$P/.logbook/briefs/plan-preview.html" ]; then
    ok "plan-preview [$engine]: a valid brief block passes silently and writes no preview"
  else
    bad "plan-preview [$engine]: a valid brief block passes silently and writes no preview" "rc=$rc $res"
  fi
  res="$(jq -cn --arg cwd "$P" '{hook_event_name: "PostToolUse", tool_name: "ExitPlanMode", tool_input: {plan: "# p\n\nx"}, cwd: $cwd}' | hook "$P")"; rc=$?
  if [ $rc -eq 0 ] && printf '%s' "$res" | jq -e '.hookSpecificOutput.additionalContext | test("/brief") and test("templates/briefing.md") and test("질문 도구") and test("한 번 더") and test("/build") and test("PR") and (test("에픽") | not)' >/dev/null 2>&1; then
    ok "plan-preview [$engine]: approval reminds the /brief steps, the briefing page, one more approval and /build"
  else
    bad "plan-preview [$engine]: approval reminds the /brief steps, the briefing page, one more approval and /build" "$res"
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
if [ $rc -eq 0 ] && [ -z "$res" ] && [ ! -e "$P/.logbook/briefs/plan-preview.html" ]; then
  ok "plan-preview: a block the check cannot render as slides passes, since only markers and HTML are checked"
else
  bad "plan-preview: a block the check cannot render as slides passes, since only markers and HTML are checked" "rc=$rc $res"
fi
res="$(pre_input $'<!-- brief:begin -->\n## 요약\n\n결론.\n<!-- brief:end -->\n' | hook "$P")"; rc=$?
if [ $rc -eq 0 ] && [ -z "$res" ] && [ ! -e "$P/.logbook/briefs/plan-preview.html" ]; then
  ok "plan-preview: a briefing without a flowchart or an ERD passes and writes no preview"
else
  bad "plan-preview: a briefing without a flowchart or an ERD passes and writes no preview" "rc=$rc $res"
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
printf '# P\n\n<!-- brief:begin -->\n## 요약\n\n결론.\n\n<div>x</div>\n<!-- brief:end -->\n' > "$TMP/plan-file.md"
res="$(jq -cn --arg f "$TMP/plan-file.md" --arg cwd "$P" '{hook_event_name: "PreToolUse", tool_input: {planFilePath: $f}, cwd: $cwd}' | hook "$P")"
cp "$DOC" "$TMP/plan-file-ok.md"
res_ok="$(jq -cn --arg f "$TMP/plan-file-ok.md" --arg cwd "$P" '{hook_event_name: "PreToolUse", tool_input: {planFilePath: $f}, cwd: $cwd}' | hook "$P")"
expect "plan-preview: an empty plan falls back to planFilePath" bash -c "printf '%s' \"\$1\" | jq -e '.hookSpecificOutput.permissionDecision == \"deny\" and (.hookSpecificOutput.permissionDecisionReason | test(\"HTML\"))' >/dev/null && [ -z \"\$2\" ] && [ ! -e '$P/.logbook/briefs/plan-preview.html' ]" _ "$res" "$res_ok"
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

# ---------------------------------------------------------------- worktree script
echo "== worktree script =="
W="$TMP/wtrepo"
mkdir -p "$W"
git -C "$W" init -q -b main
printf '.env\n.env.local\n' > "$W/.gitignore"
printf 'example\n' > "$W/.env.example"
git -C "$W" add -A
git -C "$W" -c user.email=t@example.com -c user.name=t commit -q -m init
git -C "$W" switch -q -c feat/5-shared
git -C "$W" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m shared
git -C "$W" switch -q main
printf 'SECRET=1\n' > "$W/.env"
printf 'LOCAL=1\n' > "$W/.env.local"
WS="$ROOT/scripts/worktree.sh"
out="$("$WS" add feat/6-a feat/5-shared --dir "$W" 2>&1)"; rc=$?
WP="$W/.logbook/worktrees/feat-6-a"
if [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "$(cd "$W" && pwd -P)/.logbook/worktrees/feat-6-a" ]; then ok "worktree: add prints the path under the main checkout's .logbook/worktrees"; else bad "worktree: add prints the path under the main checkout's .logbook/worktrees" "$out"; fi
expect "worktree: add cuts the branch from the given base, not the default branch" bash -c "[ \"\$(git -C '$WP' rev-parse HEAD)\" = \"\$(git -C '$W' rev-parse feat/5-shared)\" ] && [ \"\$(git -C '$WP' branch --show-current)\" = feat/6-a ]"
expect "worktree: add links the git-ignored env files and leaves tracked ones alone" bash -c "[ -L '$WP/.env' ] && [ -L '$WP/.env.local' ] && [ ! -L '$WP/.env.example' ] && grep -q SECRET '$WP/.env'"
expect "worktree: the main checkout's status stays clean" bash -c "[ -z \"\$(git -C '$W' status --porcelain)\" ]"
out="$("$WS" add feat/6-a --dir "$WP" 2>&1)"
expect "worktree: add from inside a worktree reuses the existing one" bash -c "printf '%s' \"\$1\" | grep -q 'reusing' && [ \"\$(git -C '$W' worktree list | wc -l | tr -d ' ')\" = 2 ]" _ "$out"
printf 'x\n' > "$WP/new.txt"
"$WS" remove feat/6-a --dir "$W" >/dev/null 2>&1; rc=$?
expect "worktree: remove refuses with exit 3 while there are uncommitted changes" bash -c "[ $rc -eq 3 ] && [ -e '$WP/new.txt' ]"
git -C "$WP" add new.txt && git -C "$WP" -c user.email=t@example.com -c user.name=t commit -q -m track
out="$("$WS" remove feat/6-a --dir "$W" 2>&1)"; rc=$?
expect "worktree: remove deletes a clean worktree with its env links and keeps the branch" bash -c "[ $rc -eq 0 ] && [ ! -e '$WP' ] && git -C '$W' show-ref --verify --quiet refs/heads/feat/6-a && [ -f '$W/.env' ]"
out="$("$WS" add feat/7-b --dir "$W" 2>&1)"; rc=$?
expect "worktree: add of a new branch without a base fails with exit 2" bash -c "[ $rc -eq 2 ]"
out="$("$WS" add feat/6-a main --dir "$W" 2>&1)"
expect "worktree: add of an existing branch says the base is not applied" bash -c "printf '%s' \"\$1\" | grep -q 'already exists; using it as it is, not cutting it from main'" _ "$out"
"$WS" remove feat/6-a --dir "$W" --delete-branch >/dev/null 2>&1; rc=$?
expect "worktree: remove --delete-branch keeps an unmerged branch and exits 4" bash -c "[ $rc -eq 4 ] && git -C '$W' show-ref --verify --quiet refs/heads/feat/6-a"
git -C "$W" -c user.email=t@example.com -c user.name=t merge -q --no-edit feat/6-a
out="$("$WS" remove feat/6-a --dir "$W" --delete-branch 2>&1)"; rc=$?
expect "worktree: remove --delete-branch deletes a merged branch" bash -c "[ $rc -eq 0 ] && ! git -C '$W' show-ref --verify --quiet refs/heads/feat/6-a"
out="$("$WS" remove feat/6-a --dir "$W" --delete-branch 2>&1)"
expect "worktree: remove --delete-branch on a branch already gone says so" bash -c "printf '%s' \"\$1\" | grep -q 'is already gone'" _ "$out"
"$WS" add feat/9-d main --dir "$W" >/dev/null 2>&1
/bin/rm -rf "$W/.logbook/worktrees/feat-9-d"
"$WS" remove feat/9-d --dir "$W" --delete-branch >/dev/null 2>&1; rc=$?
expect "worktree: remove prunes a worktree folder deleted by hand so its branch can go" bash -c "[ $rc -eq 0 ] && ! git -C '$W' worktree list | grep -q feat-9-d && ! git -C '$W' show-ref --verify --quiet refs/heads/feat/9-d"
W2="$TMP/wtrepo-noignore"
mkdir -p "$W2"
git -C "$W2" init -q -b main
git -C "$W2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
"$WS" add fix/8-c main --dir "$W2" >/dev/null 2>&1
expect "worktree: a repository that does not ignore .logbook/ yet gets it in .git/info/exclude" bash -c "grep -qx '.logbook/' '$W2/.git/info/exclude' && [ -z \"\$(git -C '$W2' status --porcelain)\" ]"

# ---------------------------------------------------------------- plugin files
echo "== plugin files =="
expect "hooks.json is valid JSON with the four hooks" jq -e '.hooks.SessionStart and .hooks.PreToolUse and .hooks.PostToolUse and .hooks.Stop' "$ROOT/hooks/hooks.json"
expect "SessionStart runs on every source (no matcher)" jq -e '.hooks.SessionStart[0] | has("matcher") | not' "$ROOT/hooks/hooks.json"
for skill in rulebook discuss brief build debrief sync; do
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
for tier in "builder-fast sonnet medium" "builder inherit medium" "builder-deep inherit high"; do
  set -- $tier
  expect "$1 agent runs on $2 at $3 effort and can edit" bash -c "f='$ROOT/agents/$1.md'; grep -qx 'name: $1' \"\$f\" && grep -qx 'model: $2' \"\$f\" && grep -qx 'effort: $3' \"\$f\" && grep -qx 'tools: Read, Grep, Glob, Edit, Write, Bash' \"\$f\""
  expect "$1 agent stays in its files, does not commit, and reports its check" bash -c "f='$ROOT/agents/$1.md'; grep -q 'Change only the files the brief lists' \"\$f\" && grep -q 'Do not commit' \"\$f\" && grep -q 'The check command and its output' \"\$f\""
done
expect "builder agents share one body" bash -c "cd '$ROOT/agents' && [ \"\$(sed '1,/^---\$/d' builder.md )\" = \"\$(sed '1,/^---\$/d' builder-fast.md )\" ] && [ \"\$(sed '1,/^---\$/d' builder.md )\" = \"\$(sed '1,/^---\$/d' builder-deep.md )\" ]"
expect "builder agents keep their check command to the track in the shared tree and commit only in their own worktree" bash -c "for f in '$ROOT'/agents/builder*.md; do grep -q 'other tracks are editing the same working tree' \"\$f\" && grep -q 'In a worktree of your own: work only inside that path' \"\$f\" && grep -q 'commit your work on the worktree.s branch. Do not push' \"\$f\" || exit 1; done"
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
expect "rule block asks about every decision that is the user's, with the question tool and the questions guide" bash -c "grep -q '^- \*\*사용자가 정할 것은 묻는다.\*\*' '$B' && grep -q '도메인 규칙과 예외 상황, 득실이 있는 기술 선택' '$B' && grep -q '사용자가 신경 쓰지 않을 조정값은 정한 뒤 그렇게 표시한다' '$B' && grep -q '서로 다르면 고르지 않고 묻는다' '$B' && grep -q '질문 도구(Claude Code의 AskUserQuestion)' '$B' && grep -q '{plugin_root}/templates/questions.md' '$B'"
expect "rule block: the question rule comes first" bash -c "grep -m1 '^- \*\*' '$B' | grep -q '사용자가 정할 것은 묻는다'"
expect "rule block sets the reader and the picture rules" bash -c "grep -q '컴퓨터공학 학부' '$B' && grep -q 'ERD와 흐름도는 억지로 그리지 않' '$B' && grep -q '모든 테이블' '$ROOT/templates/docs-rules.md'"
expect "rule block points at docs/system, /sync and /design" bash -c "grep -q 'docs/system/' '$B' && grep -q '/sync' '$B' && grep -q '/design' '$B'"
expect "rule block no longer demands a flowchart and an ERD in every briefing" bash -c "! grep -q 'ERD 변화(없으면' '$B'"
expect "rule block keeps HTML out of markdown and details model calls" bash -c "grep -q 'md 파일에는 HTML을 넣지 않고' '$B' && grep -q 'AI 모델을 부르는 단계' '$B'"
expect "rule block flags unreasonable decisions once and follows the user" bash -c "grep -q '비합리적인 결정은 알린다' '$B' && grep -q '그대로 가겠다고 하면 따르고' '$B' && grep -q '알린 우려' '$B'"
expect "rule block splits independent tracks by default, with three builder tiers" bash -c "grep -q '독립 트랙은 나눠서 동시에 만든다' '$B' && grep -q '둘 이상이면 나누는 것이 기본이다' '$B' && grep -q '나누지 않을 때는 그래프에 그 이유를 한 줄 적는다' '$B' && grep -q 'logbook:builder-fast' '$B' && grep -q 'logbook:builder\`' '$B' && grep -q 'logbook:builder-deep' '$B' && grep -q '세션이 이어받는다' '$B'"
expect "rule block plans tracks in the track graph and runs each wave as a Workflow, with full tests and risky tracks reviewed" bash -c "grep -q '계획 문서 \`## 상세\`의 트랙 그래프' '$B' && grep -q '\`/build\`가 그대로 따른다' '$B' && grep -q '\`/build\`는 builder 트랙이 있는 묶음마다 트랙 수와 상관없이 Workflow로 돌리고(Workflow 크기 설정을 넘으면 여러 번에 나눠 차례로)' '$B' && grep -q '묶음을 합칠 때마다 전체 테스트를 돌리고' '$B' && grep -q '그래프에 위험으로 표시한 트랙(까다로운 로직, 다른 트랙이 기대는 계약, 예외가 많은 수정)은 합치기 전에 리뷰어가 본다' '$B'"
expect "rule block scopes a shared-tree track's check command to its own files" grep -q '같은 폴더의 트랙은 다른 트랙이 쓰는 중이라 확인 명령을 그 트랙의 파일로 좁히고 커밋하지 않는다' "$B"
expect "rule block answers a request for an opinion with a discussion" bash -c "grep -q '의견을 묻는 말에는 토론으로 답한다' '$B' && grep -q '이슈와 브랜치를 만들지 않고' '$B' && grep -q '애매하면 어느 쪽인지 질문 도구로 묻는다' '$B' && grep -q 'backlog 이슈로 남기기' '$B'"
expect "rule block creates issues only for work others need or that must be kept" bash -c "grep -q '이슈는 남길 일에만 만든다' '$B' && grep -q '다른 개발자가 알아야 하거나 꼭 남겨야 하는 작업' '$B' && ! grep -q '이슈부터 만든다' '$B'"
expect "rule block reports local-only work in chat and rides follow-up doc updates on related PRs" bash -c "grep -q '이슈, 브랜치, PR 없이 하고 채팅으로 보고한다' '$B' && grep -q 'docs/system/stack.md' '$B' && grep -q '관련 작업의 PR에 얹는다' '$B' && grep -q '그 이슈에 할 일을 댓글로 남기고' '$B' && grep -q '둘 다 없으면 이슈 없는 PR로 연다' '$B'"
expect "rule block asks when unsure and gives small changes a PR only" bash -c "grep -q '이슈로 만들지 애매하면 작업 전에 질문 도구로 묻는다' '$B' && grep -q '이슈와 브리핑 화면 없이 PR만 남긴다' '$B' && grep -q '<type>/<slug>' '$B'"
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
expect "parallel guide: subagents for one or two research areas, a Workflow for every /build wave, three or more areas and every split review, subagents as the fallback" bash -c "grep -q 'Research with one or two areas' '$P' && grep -q 'Every \`/build\` wave that holds builder tracks, however many' '$P' && grep -q 'and every split review, when the Workflow tool is available' '$P' && grep -q 'launch subagents instead' '$P'"
expect "parallel guide: Workflow agents keep the builder tiers and Explore on Sonnet" bash -c "grep -q \"agentType: 'logbook:builder-fast', model: 'sonnet', effort: 'medium'\" '$P' && grep -q \"agentType: 'logbook:builder-deep', effort: 'high'\" '$P' && grep -q \"agentType: 'Explore', model: 'sonnet'\" '$P'"
expect "brief, discuss and sync launch parallel work by the guide" bash -c "for s in brief discuss sync; do grep -q 'templates/parallel.md' '$ROOT/skills/'\$s'/SKILL.md' || exit 1; done"
expect "rule block lets tracks and research run as subagents or a Workflow" bash -c "grep -q '서브에이전트나 Workflow' '$B' && grep -q 'Workflow를 쓸 수 없으면 서브에이전트로' '$B'"
expect "rule block: one request is one issue and one PR, split into tracks inside" bash -c "grep -q '^- \*\*요청 하나는 이슈 하나.\*\*' '$B' && grep -q '하위 이슈나 단계로 나누지 않고 이슈 하나, PR 하나로 하며' '$B' && grep -q '관련 없는 기능이 섞인 요청도 마찬가지다' '$B'"
expect "rule block asks the merge method along with the merge" grep -q '머지를 고르면 squash와 merge commit 중에서도 고르게 한다' "$B"
expect "rule block mentions no epic" bash -c "! grep -qiE 'epic|에픽' '$B'"
DB="$ROOT/skills/debrief/SKILL.md"
expect "debrief: one question call asks the next step and the merge method, and merges with the chosen gh flag" bash -c "grep -q 'two questions in one call: the next step' '$DB' && grep -q 'exactly one option marked (Recommended)' '$DB' && grep -q 'the merge method for when 머지 is picked: merge commit' '$DB' && grep -q 'gh pr merge --squash --delete-branch' '$DB' && grep -q 'gh pr merge --merge --delete-branch' '$DB' && grep -q 'squashMergeAllowed,mergeCommitAllowed' '$DB'"
expect "debrief: the result page follows the briefing guide and is written to .logbook/briefs, with no slide renderer" bash -c "grep -q 'templates/briefing.md' '$DB' && grep -q '<main>/.logbook/briefs/<issue>-debrief.html' '$DB' && grep -q 'origin/<PR base>...HEAD' '$DB' && ! grep -q 'render-brief' '$DB'"
expect "debrief mentions no epic" bash -c "! grep -qiE 'epic|에픽' '$DB'"
expect "reviewer has no epic mode and reviews a risky /build track in area mode" bash -c "! grep -qiE 'epic|에픽' '$ROOT/agents/reviewer.md' && grep -q '\`/build\` also uses area mode for a risky track before merging it' '$ROOT/agents/reviewer.md'"
BR="$ROOT/skills/brief/SKILL.md"
expect "no /mission skill and no /goal template" bash -c "test ! -e '$ROOT/skills/mission' && test ! -e '$ROOT/templates/goal.md' && ! grep -q '^## Goal' '$ROOT/templates/plan.md'"
expect "skills, agents, hooks, templates and the rule block no longer mention /mission or /goal" bash -c "! grep -rnE '/mission|/goal|goal\\.md' '$ROOT/skills' '$ROOT/agents' '$ROOT/hooks' '$ROOT/templates' '$ROOT/scripts' '$ROOT/AGENTS.md' '$ROOT/README.md' '$ROOT/.claude-plugin' '$ROOT/docs/system' '$ROOT/docs/manual'"
expect "brief finds decisions with the questions guide and its four lenses, and runs logbook:checker before the plan" bash -c "grep -q 'templates/questions.md' \"$BR\" && grep -q 'four lenses (structure, behavior, technique, contract)' \"$BR\" && grep -q 'independent check with \`logbook:checker\`' \"$BR\" && grep -q 'with the question tool' \"$BR\""
expect "brief writes the track graph under 상세 and keeps it off the briefing page" bash -c "grep -q 'write the track graph by the \"Track graph\" section' \"$BR\" && grep -q 'stays off the briefing page' \"$BR\""
expect "brief builds the page by the briefing guide and puts the text briefing in the issue body under a kept 원래 요청" bash -c "grep -q 'templates/briefing.md' \"$BR\" && grep -q 'Rewrite the issue body as the text briefing' \"$BR\" && grep -q '## 원래 요청' \"$BR\" && ! grep -q 'render-brief' \"$BR\""
expect "brief hands an approved plan to /build, and plan mode asks for approval once more" bash -c "grep -q 'invoke \`/build #<issue>\` without asking for approval again' \"$BR\" && grep -q 'hand it to \`/build #<issue>\` instead of these steps' \"$BR\" && grep -q 'ask for approval once more in the chat as step 9 says' \"$BR\" && grep -q 'do not invoke \`/build\`' \"$BR\""
expect "brief mentions no epic and no child issues but tracks" bash -c "! grep -qiE 'epic|에픽' \"$BR\" && grep -q 'never into child issues' \"$BR\""
BU="$ROOT/skills/build/SKILL.md"
expect "build runs only an approved plan and stops without a plan doc" bash -c "grep -q 'the issue must be in \`status:in-progress\`' '$BU' && grep -q 'say the plan is not approved and point to \`/brief #<issue>\`, then stop' '$BU' && grep -q 'Without it on this machine, say the plan was made on another machine' '$BU' && grep -q 'Then stop.' '$BU'"
expect "build resumes with /build #issue, and an open PR goes on to /debrief" bash -c "grep -q 'argument-hint: \"\[#issue\]\"' '$BU' && grep -q 'When the branch already has an open PR, the run is past Finish: run \`/debrief\` instead' '$BU' && grep -q \"read the plan doc's 진행 기록\" '$BU' && grep -q '\`/build #<issue>\` picks it up later' '$BU'"
expect "build runs each wave as a Workflow and reviews risky tracks in area mode before merging" bash -c "grep -q 'as a Workflow, however many there are' '$BU' && grep -q 'run them as several Workflows one after another; it is still one wave' '$BU' && grep -q 'Without the Workflow tool, launch them as subagents' '$BU' && grep -q 'Before merging a track marked 위험, spawn \`logbook:reviewer\` in area mode' '$BU' && grep -q 'templates/parallel.md' '$BU'"
expect "build makes one commit per track and runs the full tests after every wave" bash -c "grep -q 'one commit per track' '$BU' && grep -q 'Every wave, wave 0 included' '$BU' && grep -q \"run the project's full tests\" '$BU' && grep -q 'Tick the wave' '$BU'"
expect "build keeps tests intact, asks 고친 뒤 이어서 / 중단 when a wave stops, and opens the PR with Closes #issue" bash -c "grep -q 'do not weaken or delete tests' '$BU' && grep -q '고친 뒤 이어서 / 중단 with the question tool' '$BU' && grep -q 'open the PR with \`Closes #<issue>\`' '$BU' && grep -q 'Run \`/debrief\`.' '$BU' && grep -q 'Do not end the turn between waves' '$BU'"
expect "rule block hands an approved plan from /brief to /build and asks once more after plan mode" bash -c "grep -q '승인하면 \`/brief\`가 \`/build\`로 넘기고' '$ROOT/templates/session-rules.md' && grep -q '플랜 모드에서는 플랜을 승인한 뒤 화면을 만들어 채팅에서 한 번 더 승인받고' '$ROOT/templates/session-rules.md' && grep -q 'logbook:checker' '$ROOT/templates/session-rules.md'"
expect "plan template has a track graph with its table and no step sections" bash -c "grep -q '^### 트랙 그래프' '$T' && grep -qF '| 묶음 | 트랙 | 맡을 에이전트 | 바꿀 파일 | 기다리는 트랙 | 위험 | 확인 명령 |' '$T' && ! grep -q '^## 단계' '$T' && ! grep -qiE 'epic|에픽' '$T' && grep -q 'origin/{PR의 base 브랜치}' '$T'"
for doc in overview stack flows rules data-model; do
  expect "system template $doc starts with its marker" bash -c "head -1 '$ROOT/templates/system/$doc.md' | grep -q '^<!-- logbook:system sources='"
done
expect "brief: 중단 asks 나중에 하기 or 버리기, and a set-aside branch is picked up again" bash -c "grep -q 'On 중단, ask 나중에 하기 / 버리기' '$ROOT/skills/brief/SKILL.md' && grep -q 'keeps the branch, and posts the whole plan doc as an issue comment' '$ROOT/skills/brief/SKILL.md' && grep -q 'not planned' '$ROOT/skills/brief/SKILL.md' && grep -q 'A plan set aside with 나중에 하기 in step 9 is picked up again' '$ROOT/skills/brief/SKILL.md'"
expect "sync: only the structure path cleans up without asking, root docs such as CONTRIBUTING stay, history is not grepped" bash -c "grep -q '^   - The structure path: set up the structure' '$ROOT/skills/sync/SKILL.md' && grep -q 'ask once, with the question tool, whether this PR removes it' '$ROOT/skills/sync/SKILL.md' && grep -q 'CONTRIBUTING, SECURITY and CODE_OF_CONDUCT' '$ROOT/skills/sync/SKILL.md' && grep -q 'leaving out CHANGELOG, which keeps history' '$ROOT/skills/sync/SKILL.md'"
expect "sync drafts rules.md on the structure path and a full write only, confirming each rule" bash -c "grep -q 'Write it on the structure path and on a full write only; a stale-doc fix updates an existing \`rules.md\` and never creates one' '$ROOT/skills/sync/SKILL.md' && grep -q '확인 필요' '$ROOT/skills/sync/SKILL.md'"
expect "sync: a stale doc that still matches gets a new checked date, not new wording" bash -c "grep -q 'set .checked. to today and commit' '$ROOT/skills/sync/SKILL.md'"
for f in "$ROOT"/templates/system/*.md; do
  expect "system template $(basename "$f") records when it was checked" bash -c "head -1 '$f' | grep -q 'checked='"
done
expect "no skill, hook, script or template runs legacy-scan or passes --plans" bash -c "! grep -rqE 'legacy-scan|legacy_scan|--plans' '$ROOT/skills' '$ROOT/hooks' '$ROOT/scripts' '$ROOT/templates' '$ROOT/agents'"
expect "system template data-model declares the table count" bash -c "head -1 '$ROOT/templates/system/data-model.md' | grep -q 'tables='"

# ---------------------------------------------------------------- local plan docs and CHANGELOG (0.9)
expect "this repository tracks no plan docs and no mockup copies" bash -c "cd '$ROOT' && test -z \"\$(git ls-files docs/plans docs/designs)\""
expect "only sync's migration rule still names docs/plans or docs/designs" bash -c "test \"\$(grep -rlE 'docs/(plans|designs)' '$ROOT/skills' '$ROOT/hooks' '$ROOT/scripts' '$ROOT/templates' '$ROOT/agents')\" = '$ROOT/skills/sync/SKILL.md' && grep -q 'Plan docs and mockup copies that logbook before 0.9 committed' '$ROOT/skills/sync/SKILL.md'"
expect "brief keeps the plan doc and the mockup copy in the main checkout's .logbook and never commits them" bash -c "grep -q '\`.logbook/plans/\` and \`.logbook/designs/\` of the main checkout' '$BR' && grep -q 'never committed' '$BR' && grep -q 'Write \`<main>/.logbook/plans/<issue>-<slug>.md\`' '$BR' && grep -q 'artboards to \`<main>/.logbook/designs/<issue>-<slug>/\`' '$BR' && grep -q 'Do not commit the plan doc' '$BR'"
expect "no skill renders a briefing or a debriefing with the slide renderer" bash -c "! grep -rq 'render-brief' '$ROOT/skills'"
expect "build puts the reasons in the PR body" bash -c "grep -q 'The PR body carries what the plan doc cannot' '$BU' && grep -q '알린 우려, your own calls' '$BU' && grep -q \"in the plan doc's 결정 기록 and the PR body\" '$BU'"
expect "brief resumes a set-aside plan from the local doc or the 계획 문서 comment" bash -c "grep -q 'or else from the issue.s last comment whose first line is \`계획 문서\`' '$BR' && grep -q 'picks it up again on any clone' '$BR' && grep -q 'Check out its branch when it exists on this clone or the remote; otherwise cut it' '$BR'"
expect "brief: a plan made on another clone is rebuilt from the issue, and /debrief falls back to the issue body" bash -c "grep -q 'or else from the issue.s last comment whose first line is \`계획 문서\`' '$BR' && grep -q \"or else from the issue body's text briefing and the PR body\" '$DB'"
expect "debrief writes one CHANGELOG line linking the issue and the PR" bash -c "grep -q 'Changelog: add one line for this change' '$DB' && grep -q 'linking the issue and the PR' '$DB' && grep -q 'Keep a Changelog' '$DB' && grep -q 'by date for an app that has no versions' '$DB' && grep -q 'The doc stays uncommitted' '$DB'"
expect "plan template keeps the doc local and has a 변경 이력 evidence row" bash -c "grep -q '커밋하지 않는다' '$T' && grep -q '^| 변경 이력 | ✅ |' '$T' && grep -q '.logbook/designs/{이슈번호}-{slug}/' '$T'"
expect "rules keep plan docs and mockups in .logbook and the history in CHANGELOG" bash -c "grep -q '.logbook/plans/<번호>-<slug>.md' '$B' && grep -q '.logbook/designs/<번호>-<slug>/' '$B' && grep -q 'CHANGELOG에 이슈와 PR을 링크한 한 줄' '$B' && grep -q '\`CHANGELOG.md\`(변경 이력)' '$B' && ! grep -qE 'docs/(plans|designs)' '$B'"
expect "sync's document table has a changelog row and asks version or date" bash -c "grep -q '| 변경 이력 (CHANGELOG' '$ROOT/skills/sync/SKILL.md' && grep -q 'whether the changelog goes by version or by date' '$ROOT/skills/sync/SKILL.md'"
expect "the approved-plan hook keeps the plan in .logbook/plans and commits no plan doc" bash -c "grep -q '원래 checkout의 .logbook/plans/<이슈번호>-<slug>.md로 옮긴 뒤' '$ROOT/hooks/plan-preview.sh' && grep -q '커밋하지 않습니다' '$ROOT/hooks/plan-preview.sh' && ! grep -qE '(계획 문서|문서)[^.]*커밋합니다' '$ROOT/hooks/plan-preview.sh'"
expect "sync looks for plan docs left by logbook before 0.9 on every run and puts 주요 결정 in its PR" bash -c "grep -q 'On every path, also check .git ls-files. for plan docs and mockup copies left by logbook before 0.9' '$ROOT/skills/sync/SKILL.md' && grep -q 'and the document table for their rows' '$ROOT/skills/sync/SKILL.md' && grep -q 'the plan.s 주요 결정 in its body' '$ROOT/skills/sync/SKILL.md'"
expect "system doc templates link decisions to PRs, not plan docs" bash -c "! grep -q '계획 문서 링크' '$ROOT/templates/system/overview.md' '$ROOT/templates/system/stack.md'"
expect "no skill or hook tells the agent to commit or push a plan doc" bash -c "test -z \"\$(grep -rniE '(commit|push)[a-z ]* (the|every) (plan|step|epic) doc|plan-doc updates' '$ROOT/skills' '$ROOT/hooks' '$ROOT/agents' '$ROOT/templates' | grep -viE 'do not commit')\""

# ---------------------------------------------------------------- worktrees (0.10)
expect "rules: work happens in the main checkout, and an unfit checkout is asked about" bash -c "grep -q '작업 폴더는 원래 checkout이다' '$B' && grep -q 'git worktree(한 저장소를 여러 폴더에 동시에 checkout하는 git 기능)를 만들기 전에 이유를 들어 묻고' '$B' && grep -q '사람이 worktree를 쓰라고 하면 따른다' '$B'"
expect "rules: /brief plans the tracks in the graph without asking or showing them on the page, and changes are recorded" bash -c "grep -q '사람에게 묻지 않고 브리핑 화면에도 넣지 않는다' '$B' && grep -q '구현 중에 그래프를 바꾸면 이유를 계획 문서의 결정 기록과 PR 본문에 남긴다' '$B' && ! grep -q '브리핑이나 채팅에 적는다' '$B'"
expect "rules: worktree tracks come from worktree.sh, not Claude Code's isolation, and are removed after merging" bash -c "grep -q '{plugin_root}/scripts/worktree.sh' '$B' && grep -q 'isolation: worktree.는 기본 브랜치에서 worktree를 만들어' '$B' && grep -q '합친 트랙의 worktree와 트랙 브랜치는 원래 checkout에서 .worktree.sh remove <브랜치> --delete-branch.로 바로 지운다' '$B' && grep -q '강제로 지우지 않고 멈춰 경로를 보고한다' '$B' && grep -q '세션이 이어받은 트랙도 합친 뒤 같이 지운다' '$B'"
expect "rules: shared parts first, then one large wave; more waves only where a review must come first" bash -c "grep -q '공통 부분(타입, 인터페이스, 설정)을 먼저 만들어 커밋하고, 나머지 트랙은 모두 한 묶음으로' '$B' && grep -q '묶음은 세션이 리뷰하고 합치는 단위라 크게 잡는다' '$B' && grep -q '앞 결과를 세션이 리뷰하고 합쳐야만 뒤 트랙을 시작할 수 있을 때만 묶음을 더 나누고' '$B' && grep -q '계획 문서만 보고 만들 수 있는 문서와 테스트도 같은 묶음에 넣는다' '$B' && ! grep -q '서로 기다리지 않는 단계' '$B'"
expect "parallel guide and brief keep waves few and large" bash -c "grep -q 'Keep waves few and large' '$P' && grep -q 'The default is two waves' '$P' && grep -q 'docs and tests included, goes into the same wave' '$P' && grep -q 'it is no reason for a wave of its own' '$P' && grep -q 'Keep waves large: the shared parts first, then one wave with everything else' '$ROOT/skills/brief/SKILL.md'"
expect "session-rules hook fills in the plugin root with a path to worktree.sh that exists" bash -c "p=\$(printf '%s' \"\$1\" | grep -o '[^\`]*/scripts/worktree.sh' | head -1) && [ -x \"\$p\" ] && ! printf '%s' \"\$1\" | grep -q '{plugin_root}'" _ "$ctx"
expect "parallel guide: tracks run in the shared tree or a worktree, and the user is not asked about them" bash -c "grep -q '## Where tracks run' '$P' && grep -q 'The user is not asked about tracks, and the briefing page does not show the graph' '$P' && grep -q 'scripts/worktree.sh add <branch> <base>' '$P' && grep -q \"Do not use Claude Code's .isolation: 'worktree'.\" '$P' && ! grep -q \"briefing's 일정과 검증\" '$P'"
expect "parallel guide: a Track graph section, a Workflow per wave, risky tracks reviewed, splitting by default" bash -c "grep -q '^## Track graph' '$P' && grep -q '### 트랙 그래프' '$P' && grep -q '묶음 (wave), 트랙, 맡을 에이전트, 바꿀 파일, 기다리는 트랙, 위험, 확인 명령' '$P' && grep -q '\`/build\` runs each wave as a Workflow' '$P' && grep -q 'several Workflows in a row when the wave holds more tracks than the Workflow size setting allows' '$P' && grep -q 'A track marked 위험 is reviewed before it is merged' '$P' && grep -q 'Splitting is the default' '$P' && ! grep -qiE 'epic|에픽' '$P'"
expect "parallel guide: a review split by area with a seam reviewer for tracked or large PRs" bash -c "grep -q '^## Review split' '$P' && grep -q 'built in builder tracks (its body lists them), or when its diff changes 2,000 lines or more' '$P' && grep -q 'in area mode' '$P' && grep -q 'in seam mode' '$P'"
expect "debrief splits round 1 for tracked or large PRs, and the reviewer has area and seam modes" bash -c "grep -q 'Split round 1 when the PR was built in builder tracks (its body lists them) or its diff changes 2,000 lines or more' '$DB' && grep -q '^## Area mode' '$ROOT/agents/reviewer.md' && grep -q '^## Seam mode' '$ROOT/agents/reviewer.md' && grep -q '영역이 만나는 지점을 보는 리뷰어를 하나 더 둔다' '$B'"
expect "brief: main checkout by default, asks before a worktree, large work split into tracks, not child issues" bash -c "grep -q 'say what and ask with the question tool before making a worktree' '$BR' && grep -q 'It is not a question for the user and stays off the briefing page' '$BR' && ! grep -q '일정과 검증 names the tracks' '$BR' && grep -q 'Large work is split into tracks inside it (step 5), never into child issues' '$BR' && grep -q 'One request is one issue and one PR' '$BR'"
expect "no prompt or doc still runs steps side by side" bash -c "for d in '$ROOT/agents' '$ROOT/skills' '$ROOT/templates' '$ROOT/docs/system' '$ROOT/docs/manual' '$ROOT/README.md'; do test -e \"\$d\" || exit 1; done && ! grep -rnE 'beside other steps|Epic steps side by side|병렬 단계|서로 기다리지 않는 (에픽 )?단계|이득이 있을 때만' '$ROOT/agents' '$ROOT/skills' '$ROOT/templates' '$ROOT/docs/system' '$ROOT/docs/manual' '$ROOT/README.md'"
expect "split review covers files outside the tracks, and the PR body lists the tracks" bash -c "grep -q 'files no track changed' '$P' && grep -q 'one line per track (wave, agent, files' '$BU' && grep -q 'Split round 1 when the PR was built in builder tracks' '$DB'"
expect "debrief: an asked-for worktree is removed before the merge" bash -c "! grep -q 'when the epic branch has moved since this step was cut' '$DB' && ! grep -q 'A step built in a worktree' '$DB' && grep -q 'when the work ran in a worktree made by' '$DB'"

# ---------------------------------------------------------------- questions, briefing pages, /build, no epics (0.12)
Q="$ROOT/templates/questions.md"
expect "questions guide: who decides, and the four lenses" bash -c "grep -q '^## Who decides' '$Q' && grep -q '\*\*Structure\*\*' '$Q' && grep -q '\*\*Behavior\*\*' '$Q' && grep -q '\*\*Technique\*\*' '$Q' && grep -q '\*\*Contract\*\*' '$Q' && grep -q 'When the request, the code and the docs disagree, do not pick one. Ask.' '$Q'"
expect "questions guide: ask with the question tool, the recommended option first, prose as the fallback" bash -c "grep -q '^## How to ask' '$Q' && grep -q 'Use the question tool whenever the answers can be listed (AskUserQuestion on Claude Code)' '$Q' && grep -q '(Recommended)' '$Q' && grep -q 'ask the same question in prose at once' '$Q' && grep -q '다른 생각이 있다' '$Q'"
expect "questions guide: the independent check spawns logbook:checker with the dialogue verbatim and runs once more at most" bash -c "grep -q '^## Independent check' '$Q' && grep -q 'Spawn \`logbook:checker\`' '$Q' && grep -q 'never summarize them' '$Q' && grep -q 'the check does not loop again' '$Q'"
BP="$ROOT/templates/briefing.md"
expect "briefing guide: text goes to the chat and the issue or PR body, the page explains with pictures" bash -c "grep -q 'The text goes to the chat and to the issue or PR body' '$BP' && grep -q '| Issue body (\`/brief\`) or PR body (\`/debrief\`) |' '$BP' && grep -q 'There is no template' '$BP'"
expect "briefing guide: controls and motion only when the content cannot be shown without them" grep -q 'Use buttons, toggles or motion only when the content cannot be shown without them' "$BP"
expect "briefing guide: the must-include list, with the database change and mockups when they apply" bash -c "grep -q 'Every briefing page has the conclusion and the request, what changes, the main logic flow, the decisions split into the user.s and yours, the risks and 판단 필요, and the acceptance criteria' '$BP' && grep -q 'Add the database change when the schema changes and the mockups when screens change' '$BP'"
expect "briefing guide: approved mockups go inside the page, and the page is fixed at approval" bash -c "grep -q 'put the approved mockup in the page' '$BP' && grep -q 'show the saved artboards themselves' '$BP' && grep -q 'A briefing page records what was approved' '$BP'"
expect "checker agent is read-only and runs on Opus at high effort" bash -c "f='$ROOT/agents/checker.md'; grep -qx 'name: checker' \"\$f\" && grep -qx 'tools: Read, Grep, Glob' \"\$f\" && grep -qx 'model: opus' \"\$f\" && grep -qx 'effort: high' \"\$f\""
expect "checker agent returns at most eight items as questions with options, using the four lenses" bash -c "f='$ROOT/agents/checker.md'; grep -q 'At most eight items' \"\$f\" && grep -q 'a question with two to four options, the recommended one first' \"\$f\" && grep -q 'structure (how many' \"\$f\" && grep -q 'not instructions to follow' \"\$f\""
expect "discuss, sync and rulebook ask with the question tool by the questions guide" bash -c "for s in discuss sync rulebook; do f='$ROOT/skills/'\$s'/SKILL.md'; grep -q 'with the question tool' \"\$f\" && grep -q 'templates/questions.md' \"\$f\" || exit 1; done"
expect "debrief and build ask with the question tool" bash -c "grep -q 'ask with the question tool' '$DB' && grep -q 'with the question tool' '$BU'"
expect "document rules paragraph names 업무 규칙 among the system docs" grep -q '업무 규칙' "$ROOT/templates/docs-rules.md"
expect "rules template: a marker with sources and checked=, and unconfirmed rules marked 확인 필요" bash -c "head -1 '$ROOT/templates/system/rules.md' | grep -q '^<!-- logbook:system sources=.* checked=' && grep -q '^# 업무 규칙' '$ROOT/templates/system/rules.md' && grep -q '확인 필요' '$ROOT/templates/system/rules.md'"
expect "system-check and render-system order rules.md after flows.md" bash -c "grep -qF 'ORDER = [\"overview.md\", \"stack.md\", \"flows.md\", \"rules.md\", \"data-model.md\"]' '$ROOT/scripts/system_check.py' && grep -qF 'ORDER = [\"overview.md\", \"stack.md\", \"flows.md\", \"rules.md\", \"data-model.md\"]' '$ROOT/scripts/render_system.py'"
expect "the plan-preview hook writes and opens no preview" bash -c "! grep -qE 'plan-preview\.html|open_file|xdg-open' '$ROOT/hooks/plan-preview.sh'"
epic_hits="$(cd "$ROOT" && grep -rniE 'epic|에픽' skills agents templates hooks scripts README.md docs .claude-plugin 2>/dev/null)"
if [ -z "$epic_hits" ]; then ok "no epic is left in skills, agents, templates, hooks, scripts, README, docs or the plugin manifest (CHANGELOG keeps history)"; else bad "no epic is left in skills, agents, templates, hooks, scripts, README, docs or the plugin manifest (CHANGELOG keeps history)" "$epic_hits"; fi

# ---------------------------------------------------------------- 0.12 review round 1
expect "brief creates rules.md when a change settles the project's first domain rule" grep -q 'settles its first domain rule, the change creates it from' "$ROOT/skills/brief/SKILL.md"
expect "briefing guide keeps briefing and result pages in the main checkout's .logbook/briefs" bash -c "grep -q '<main>/.logbook/briefs/<issue>-brief.html' '$ROOT/templates/briefing.md' && grep -q '<issue>-debrief.html' '$ROOT/templates/briefing.md'"
v_plugin="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
v_market="$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")"
v_log="$(sed -n 's/^## \[\([0-9.]*\)\].*/\1/p' "$ROOT/CHANGELOG.md" | head -1)"
if [ -n "$v_plugin" ] && [ "$v_plugin" = "$v_market" ] && [ "$v_plugin" = "$v_log" ]; then ok "plugin.json, marketplace.json and the top CHANGELOG entry share one version ($v_plugin)"; else bad "plugin.json, marketplace.json and the top CHANGELOG entry share one version" "plugin=$v_plugin market=$v_market changelog=$v_log"; fi
BP="$TMP/brokenplugin"
mkdir -p "$BP/hooks" "$BP/scripts" "$BP/.claude-plugin"
cp "$ROOT/hooks/"*.sh "$BP/hooks/"
cp "$ROOT/.claude-plugin/plugin.json" "$BP/.claude-plugin/"
printf '#!/bin/sh\necho "render-brief: python3 not found" >&2\nexit 3\n' > "$BP/scripts/render-brief.sh"
chmod +x "$BP/scripts/render-brief.sh" "$BP/hooks/"*.sh
PROJ="$TMP/proj"
res="$(jq -cn --arg plan $'<!-- brief:begin -->\n## 요약\n\n결론.\n<!-- brief:end -->\n' --arg cwd "$PROJ" '{hook_event_name: "PreToolUse", tool_name: "ExitPlanMode", tool_input: {plan: $plan}, cwd: $cwd}' | CLAUDE_PLUGIN_ROOT="$BP" CLAUDE_PROJECT_DIR="$PROJ" LOGBOOK_NO_OPEN=1 "$BP/hooks/plan-preview.sh")"
if printf '%s' "$res" | jq -e '.systemMessage | test("HTML 검사를 하지 못했습니다")' >/dev/null 2>&1; then ok "plan-preview: a check that cannot run says so instead of passing silently"; else bad "plan-preview: a check that cannot run says so instead of passing silently" "$res"; fi
expect "plan-mode reminder and brief move the issue to in-progress before /build" bash -c "grep -q '진행이면 이슈를 status:in-progress로 옮기고 /build로 넘겨' '$ROOT/hooks/plan-preview.sh' && grep -q 'On 진행, move the issue to .status:in-progress. and invoke ./build #<issue>.' '$ROOT/skills/brief/SKILL.md'"
expect "build takes over an interrupted shared-tree wave and runs a pre-0.12 plan as one wave" bash -c "grep -q 'Uncommitted files of this issue.s interrupted wave are no such reason' '$ROOT/skills/build/SKILL.md' && grep -q 'A plan doc without a track graph (one made before 0.12) runs as one wave' '$ROOT/skills/build/SKILL.md'"
expect "brief rewrites the issue body's text briefing on 수정" grep -q "On 수정, change the plan, rewrite the issue body's text briefing" "$ROOT/skills/brief/SKILL.md"

# ---------------------------------------------------------------- slack (0.13)
echo "== slack =="
SL="$TMP/slack"
SBIN="$SL/bin"
GH_STATE="$SL/gh"
SLOG="$SL/api.log"
SREPLIES="$SL/replies.json"
SPAGE="$ROOT/tests/fixtures/slack-page/page.html"
mkdir -p "$SBIN" "$GH_STATE"
: > "$SLOG"

# Fake Slack Web API on a free local port; killed on exit with the rest of the temp files.
SLACK_PID=""
SFLAKY="$SL/flaky-upload"
# Settings the fake server reads on every request (FAKE_SLACK_FAIL, FAKE_SLACK_INVALID_BLOCKS).
SSET="$SL/settings.json"
FAKE_SLACK_REPLIES="$SREPLIES" FAKE_SLACK_UPLOAD_5XX="$SFLAKY" FAKE_SLACK_SETTINGS="$SSET" python3 "$ROOT/tests/fixtures/slack_api.py" "$SL/port" "$SLOG" &
SLACK_PID=$!
trap 'kill $SLACK_PID 2>/dev/null; wait $SLACK_PID 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 50); do [ -s "$SL/port" ] && break; sleep 0.1; done
SPORT="$(cat "$SL/port" 2>/dev/null)"
[ -n "$SPORT" ] && ok "slack: fake Slack API is listening" || bad "slack: fake Slack API is listening"

# Fake gh: issues and comments of acme/app kept as JSON files in $GH_STATE.
cat > "$SL/fake_gh.py" <<'EOF'
import json, os, sys
state = os.environ["GH_STATE"]
args = sys.argv[1:]
with open(os.path.join(state, "calls.log"), "a", encoding="utf-8") as f:
    f.write(json.dumps(args, ensure_ascii=False) + "\n")

def comments_file(number):
    return os.path.join(state, f"comments-{number}.json")

def load(number):
    try:
        with open(comments_file(number), encoding="utf-8") as f:
            return json.load(f)
    except OSError:
        return []

def save(number, items):
    with open(comments_file(number), "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False)

def body_of(args):
    for i, a in enumerate(args):
        if a == "-f" and args[i + 1].startswith("body="):
            return args[i + 1][len("body="):]
    sys.exit("fake gh: no body")

if args[:2] == ["auth", "token"]:
    print("gho_faketoken")
elif args[:2] == ["issue", "view"]:
    n = args[2]
    print(json.dumps({"title": f"데모 이슈 {n}", "url": f"https://github.com/acme/app/issues/{n}", "state": "OPEN"}))
elif args[:1] == ["api"] and args[1:2] == ["user"]:
    print("octo")
elif args[:2] == ["api", "--paginate"]:
    n = args[2].split("/")[-2]
    for c in load(n):
        print(json.dumps({"id": c["id"], "body": c["body"], "author_association": c.get("author_association", "OWNER")}, ensure_ascii=False))
elif args[:3] == ["api", "-X", "POST"]:
    if os.environ.get("FAKE_GH_FAIL_COMMENT") == "1":
        sys.stderr.write("HTTP 403: fake failure\n")
        sys.exit(1)
    n = args[3].split("/")[-2]
    items = load(n)
    counter = os.path.join(state, "next-id")
    new_id = int(open(counter).read()) if os.path.exists(counter) else 9001
    open(counter, "w").write(str(new_id + 1))
    items.append({"id": new_id, "body": body_of(args)})
    save(n, items)
    print(new_id)
elif args[:3] == ["api", "-X", "PATCH"]:
    cid = int(args[3].split("/")[-1])
    for f in os.listdir(state):
        if not f.startswith("comments-"):
            continue
        n = f[len("comments-"):-len(".json")]
        items = load(n)
        for c in items:
            if c["id"] == cid:
                c["body"] = body_of(args)
                save(n, items)
                print(cid)
                sys.exit(0)
    sys.stderr.write("HTTP 404: no such comment\n")
    sys.exit(1)
else:
    sys.stderr.write(f"fake gh: unexpected {args}\n")
    sys.exit(1)
EOF
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$SL/fake_gh.py" > "$SBIN/gh"
chmod +x "$SBIN/gh"

# A repo with the channel line, and one without.
SR="$SL/repo"
SR0="$SL/repo-off"
for d in "$SR" "$SR0"; do
  mkdir -p "$d/.logbook"
  git -C "$d" init -q -b main
  printf '{"repo": "acme/app", "base": "main", "account": "dev"}\n' > "$d/.logbook/config.json"
done
printf '# App\n\n- Slack 채널: `C0TEST`\n' > "$SR/AGENTS.md"
printf '# App\n\nNo Slack here.\n' > "$SR0/AGENTS.md"

# Run slack.sh in $SL_DIR (default $SR). SL_TOKEN overrides the token (empty = none);
# SL_CHROME=real leaves Chrome discovery to the script, otherwise Chrome is missing.
# SL_CHANNEL sets the LOGBOOK_SLACK_CHANNEL default; otherwise the caller's value is dropped.
slack() {
  local dir="${SL_DIR:-$SR}" chrome=(LOGBOOK_CHROME=/nonexistent) chan=(-u LOGBOOK_SLACK_CHANNEL)
  [ "${SL_CHROME:-}" = real ] && chrome=(-u LOGBOOK_CHROME)
  [ -n "${SL_CHANNEL:-}" ] && chan=(LOGBOOK_SLACK_CHANNEL="$SL_CHANNEL")
  (cd "$dir" && env "${chan[@]}" env "${chrome[@]}" PATH="$SBIN:$PATH" GH_STATE="$GH_STATE" \
    LOGBOOK_SLACK_API="http://127.0.0.1:$SPORT" LOGBOOK_SLACK_TOKEN="${SL_TOKEN-xoxb-test}" \
    "$ROOT/scripts/slack.sh" "$@" --dir "$dir")
}
# Query the API log: slog <python expression over L, the list of logged requests> [args...].
# The expression sees A (the extra args), SC (slack_config) and these helpers:
# B(e) the request's blocks, T(b) a block's text, H(e) the header text (None without one),
# ALL(e) text and every block's text, BID(e, id) the text of the block with that block_id,
# RP(ts) the chat.postMessage replies in thread ts, UP(ts) the chat.update calls of ts,
# PARENT(ts) the chat.postMessage that made the parent ts.
slog() { python3 -c '
import json, sys
sys.path.insert(0, sys.argv[3]); import slack_config as SC
L = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
A = sys.argv[4:]
def B(e):
    try: b = json.loads(e["params"].get("blocks") or "[]")
    except ValueError: return []
    return b if isinstance(b, list) else []
def T(b):
    t = b.get("text"); parts = [t.get("text", "")] if isinstance(t, dict) else []
    parts += [el.get("text", "") for el in b.get("elements") or [] if isinstance(el, dict) and isinstance(el.get("text"), str)]
    return "\n".join(parts)
def H(e):
    b = B(e)
    return T(b[0]) if b and b[0].get("type") == "header" else None
def ALL(e): return "\n".join([e["params"].get("text", "")] + [T(b) for b in B(e)])
def BID(e, i): return next((T(b) for b in B(e) if b.get("block_id") == i), None)
def RP(ts): return [e for e in L if e["method"] == "chat.postMessage" and e["params"].get("thread_ts") == ts]
def UP(ts): return [e for e in L if e["method"] == "chat.update" and e["params"].get("ts") == ts]
def PARENT(ts): return next((e for e in L if e["method"] == "chat.postMessage" and e.get("ts") == ts), {"params": {}})
r = eval(sys.argv[2])
print(r if isinstance(r, str) else json.dumps(r, ensure_ascii=False))' "$SLOG" "$1" "$ROOT/scripts" "${@:2}"; }
# Turn fake server settings on for one command: sfake <json object> <command...>.
sfake() { printf '%s' "$1" > "$SSET"; shift; "$@"; local rc=$?; rm -f "$SSET"; return $rc; }
posts() { slog '[e for e in L if e["method"] == "chat.postMessage"]'; }
# The marker fields of issue $1's comments as JSON ({} when there is none).
smark() { python3 -c '
import json, re, sys
try: items = json.load(open(sys.argv[1]))
except OSError: items = []
for c in items:
    m = re.search(r"<!-- logbook:slack ([^>]*?) -->", c["body"])
    if m and "C0TEST" in m.group(1):
        print(json.dumps(dict(p.split("=", 1) for p in m.group(1).split() if "=" in p))); break
else: print("{}")' "$GH_STATE/comments-$1.json"; }
mfield() { smark "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$2"; }

# 1. no channel line
: > "$SLOG"
out="$(SL_DIR="$SR0" slack post 1 approve 2>&1)"; rc=$?
if [ $rc -eq 10 ] && [ ! -s "$SLOG" ]; then ok "slack: without the channel line it exits 10 and calls no Slack API"; else bad "slack: without the channel line it exits 10 and calls no Slack API" "rc=$rc $out"; fi

# 1b. LOGBOOK_SLACK_CHANNEL is the default where AGENTS.md has no line; the line wins over it
: > "$SLOG"
out="$(SL_DIR="$SR0" SL_CHANNEL=CENV slack thread 9 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[e["params"]["channel"] for e in L if e["method"] == "chat.postMessage"]')" = '["CENV"]' ]; then ok "slack: without the line, LOGBOOK_SLACK_CHANNEL picks the channel"; else bad "slack: without the line, LOGBOOK_SLACK_CHANNEL picks the channel" "rc=$rc $out $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(SL_CHANNEL=CENV slack thread 8 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[e["params"]["channel"] for e in L if e["method"] == "chat.postMessage"]')" = '["C0TEST"]' ]; then ok "slack: the AGENTS.md line wins over LOGBOOK_SLACK_CHANNEL"; else bad "slack: the AGENTS.md line wins over LOGBOOK_SLACK_CHANNEL" "rc=$rc $out $(cat "$SLOG")"; fi

# check: on with a channel and a token, off without the channel; a channel name is refused
out="$(slack check 2>&1)"; rc=$?; out0="$(SL_DIR="$SR0" slack check 2>&1)"; rc0=$?; outn="$(SL_DIR="$SR0" SL_CHANNEL='#dev' slack check 2>&1)"; rcn=$?
if [ $rc -eq 0 ] && [ $rc0 -eq 10 ] && [ $rcn -eq 12 ]; then ok "slack: check exits 0 when on, 10 without a channel, 12 for a channel name instead of an ID"; else bad "slack: check exits 0 when on, 10 without a channel, 12 for a channel name instead of an ID" "rc=$rc rc0=$rc0 rcn=$rcn $out $out0 $outn"; fi

# 2. no token
: > "$SLOG"
out="$(SL_TOKEN= slack post 1 approve 2>&1)"; rc=$?
if [ $rc -eq 11 ] && [ ! -s "$SLOG" ] && [ -n "$(printf '%s' "$out" | tail -1)" ]; then ok "slack: without a token it says one line and exits 11"; else bad "slack: without a token it says one line and exits 11" "rc=$rc $out"; fi

# 3. thread, then replies in the same thread
: > "$SLOG"
out="$(slack thread 1 2>&1)"; rc=$?
P1="$(slog '[e["ts"] for e in L if e["method"] == "chat.postMessage"][0]' 2>/dev/null)"
if [ $rc -eq 0 ] && slog '[e for e in L if e["method"] == "chat.postMessage"]' | python3 -c 'import json,sys; p=json.load(sys.stdin); sys.exit(not (len(p) == 1 and "thread_ts" not in p[0]["params"] and p[0]["params"].get("channel") == "C0TEST"))'; then
  ok "slack: thread posts one parent message to the channel"
else
  bad "slack: thread posts one parent message to the channel" "rc=$rc $out $(cat "$SLOG")"
fi
if [ -n "$P1" ] && [ "$(mfield 1 channel)" = C0TEST ] && [ "$(mfield 1 ts)" = "$P1" ]; then ok "slack: thread records the channel and parent ts in an issue comment"; else bad "slack: thread records the channel and parent ts in an issue comment" "$(cat "$GH_STATE/comments-1.json" 2>&1)"; fi
: > "$SLOG"
out="$(slack thread 1 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(posts)" = "[]" ]; then ok "slack: a second thread call posts nothing"; else bad "slack: a second thread call posts nothing" "rc=$rc $out $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 1 approve 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ -n "$P1" ] && [ "$(slog '[e["params"].get("thread_ts") for e in L if e["method"] == "chat.postMessage"]')" = "[\"$P1\"]" ]; then ok "slack: post approve replies with thread_ts = the parent ts"; else bad "slack: post approve replies with thread_ts = the parent ts" "rc=$rc $out $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 2 approve 2>&1)"; rc=$?
P2="$(mfield 2 ts)"
if [ $rc -eq 0 ] && [ -n "$P2" ] && [ "$(slog '[e["params"].get("thread_ts") for e in L if e["method"] == "chat.postMessage"]')" = "[null, \"$P2\"]" ]; then ok "slack: post on an issue without a thread makes the thread first"; else bad "slack: post on an issue without a thread makes the thread first" "rc=$rc $out $(cat "$SLOG")"; fi

# 4. a failed comment deletes the parent
: > "$SLOG"
out="$(FAKE_GH_FAIL_COMMENT=1 slack thread 3 2>&1)"; rc=$?
P3="$(slog '([e["ts"] for e in L if e["method"] == "chat.postMessage"] or [""])[0]')"
if [ $rc -eq 12 ] && [ -n "$P3" ] && [ "$(slog '[(e["params"].get("channel"), e["params"].get("ts")) for e in L if e["method"] == "chat.delete"]')" = "[[\"C0TEST\", \"$P3\"]]" ] && [ "$(smark 3)" = "{}" ]; then ok "slack: when the issue comment fails, the parent is deleted and it exits 12"; else bad "slack: when the issue comment fails, the parent is deleted and it exits 12" "rc=$rc $out $(cat "$SLOG")"; fi

# 5. pages: upload once, then text alone while the page is the same
HASH="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest()[:12])' "$SPAGE")"
: > "$SLOG"
out="$(slack post 4 brief --page "$SPAGE" 2>&1)"; rc=$?
P4="$(mfield 4 ts)"
names="$(slog '[e["params"].get("filename", "").rsplit(".", 1)[-1] for e in L if e["method"] == "files.getUploadURLExternal"]')"
if [ "$names" = '["html"]' ] && [ "$(slog 'len([e for e in L if e["method"] == "upload"])')" = 1 ]; then ok "slack: post brief --page without Chrome uploads the HTML copy only"; else bad "slack: post brief --page without Chrome uploads the HTML copy only" "rc=$rc $out $(cat "$SLOG")"; fi
if [ -n "$P4" ] && [ "$(slog '[(e["params"].get("channel_id"), e["params"].get("thread_ts")) for e in L if e["method"] == "files.completeUploadExternal"]')" = "[[\"C0TEST\", \"$P4\"]]" ]; then ok "slack: the upload completes in the issue's thread"; else bad "slack: the upload completes in the issue's thread" "$(cat "$SLOG")"; fi
if [ "$(slog '[(H(e), "initial_comment" in e["params"]) for e in L if e["method"] == "files.completeUploadExternal"] == [(SC.stage_title("brief"), False)]')" = true ]; then ok "slack: the attached post shares the blocks with the files and no initial_comment"; else bad "slack: the attached post shares the blocks with the files and no initial_comment" "$(cat "$SLOG")"; fi
if [ -n "$P4" ] && [ "$(slog 'len(RP(A[0]))' "$P4")" = 0 ]; then ok "slack: an attached post with accepted blocks is one message (no separate text reply)"; else bad "slack: an attached post with accepted blocks is one message (no separate text reply)" "$(cat "$SLOG")"; fi
if [ "$(mfield 4 brief)" = "$HASH" ]; then ok "slack: the marker records brief=<12 hex of the page's sha256>"; else bad "slack: the marker records brief=<12 hex of the page's sha256>" "$(smark 4) want $HASH"; fi
: > "$SLOG"
out="$(slack post 4 brief --page "$SPAGE" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog 'len([e for e in L if e["method"] == "chat.postMessage"])')" = 1 ] && [ "$(slog 'len([e for e in L if e["method"].startswith("files.") or e["method"] == "upload"])')" = 0 ]; then ok "slack: posting the same page again posts text alone"; else bad "slack: posting the same page again posts text alone" "rc=$rc $out $(cat "$SLOG")"; fi
printf '[{"id": 8001, "body": "<!-- logbook:slack channel=COTHER ts=1600000000.000001 -->"}]' > "$GH_STATE/comments-5.json"
: > "$SLOG"
out="$(slack post 5 approve 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[(e["params"].get("channel"), e["params"].get("thread_ts")) for e in L if e["method"] == "chat.postMessage"][0]')" = '["C0TEST", null]' ] && [ "$(slog '[e for e in L if "1600000000.000001" in json.dumps(e) or "COTHER" in json.dumps(e)]')" = "[]" ]; then ok "slack: a marker naming another channel is ignored and a new thread is made"; else bad "slack: a marker naming another channel is ignored and a new thread is made" "rc=$rc $out $(cat "$SLOG")"; fi
printf '[{"id": 8002, "author_association": "NONE", "body": "<!-- logbook:slack channel=C0TEST ts=1600000000.000002 -->"}]' > "$GH_STATE/comments-6.json"
: > "$SLOG"
out="$(slack post 6 approve 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[e["params"].get("thread_ts") for e in L if e["method"] == "chat.postMessage"][0]')" = "null" ] && [ "$(slog '[e for e in L if "1600000000.000002" in json.dumps(e)]')" = "[]" ]; then ok "slack: a marker left by someone without write access is ignored"; else bad "slack: a marker left by someone without write access is ignored" "rc=$rc $out $(cat "$SLOG")"; fi
# The standalone copy inlines only files inside the page's folder or repository.
OUTP="$SL/outside"; mkdir -p "$OUTP/page"
cp "$ROOT/tests/fixtures/slack-page/img.png" "$OUTP/secret.png"
printf '<p>x</p><img src="../secret.png"><img src="%s">\n' "$OUTP/secret.png" > "$OUTP/page/page.html"
LOGBOOK_CHROME=/nonexistent "$ROOT/scripts/slack.sh" snapshot "$OUTP/page/page.html" "$OUTP/out" >/dev/null 2>&1
if [ -f "$OUTP/out/page.html" ] && ! grep -q 'data:image' "$OUTP/out/page.html"; then ok "slack: snapshot does not inline files outside the page's folder or repository"; else bad "slack: snapshot does not inline files outside the page's folder or repository" "$(head -c 300 "$OUTP/out/page.html" 2>&1)"; fi

# 6. snapshot with a real Chrome
# The standalone HTML copy needs no Chrome, so it is checked on every machine.
SNAP0="$SL/snap0"
LOGBOOK_CHROME=/nonexistent "$ROOT/scripts/slack.sh" snapshot "$SPAGE" "$SNAP0" >/dev/null 2>&1
if head -c 15 "$SNAP0/page.html" 2>/dev/null | grep -qi '^<!doctype html>' && grep -qi 'charset="\{0,1\}utf-8' "$SNAP0/page.html" && ! grep -q 'src="img.png"' "$SNAP0/page.html" && grep -q 'data:image/png;base64,' "$SNAP0/page.html"; then ok "slack: snapshot HTML has a doctype and UTF-8, and the image is inlined"; else bad "slack: snapshot HTML has a doctype and UTF-8, and the image is inlined" "$(head -c 400 "$SNAP0/page.html" 2>&1)"; fi
MPAGE="$SL/mermaid/page.html"; mkdir -p "$SL/mermaid"
printf '<p>그림</p>\n<pre class="mermaid">\nflowchart LR\n  A --> B\n</pre>\n' > "$MPAGE"
LOGBOOK_CHROME=/nonexistent "$ROOT/scripts/slack.sh" snapshot "$MPAGE" "$SL/mermaid/out" >/dev/null 2>&1
if grep -q 'cdn.jsdelivr.net/npm/mermaid@11.4.1/' "$SL/mermaid/out/page.html" 2>/dev/null; then ok "slack: snapshot HTML of a page with mermaid loads the pinned mermaid"; else bad "slack: snapshot HTML of a page with mermaid loads the pinned mermaid" "$(cat "$SL/mermaid/out/page.html" 2>&1 | head -5)"; fi

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "$(command -v google-chrome 2>/dev/null)" "$(command -v chromium 2>/dev/null)" "$(command -v chromium-browser 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { CHROME="$c"; break; }
done
if [ -z "$CHROME" ]; then
  ok "slack: snapshot skipped (no Chrome on this machine)"
else
  SNAP="$SL/snap"
  out="$(env -u LOGBOOK_CHROME "$ROOT/scripts/slack.sh" snapshot "$SPAGE" "$SNAP" 2>&1)"; rc=$?
  height="$(python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print(struct.unpack(">I", d[20:24])[0] if d[:8] == b"\x89PNG\r\n\x1a\n" else 0)' "$SNAP/page.png" 2>/dev/null)"
  # The fixture is about 2.5k px tall: taller than the 1000 px window, shorter than the 4000 px fallback.
  if [ $rc -eq 0 ] && [ "${height:-0}" -gt 2400 ] && [ "${height:-0}" -lt 4000 ]; then ok "slack: snapshot PNG has the full page height ($height px)"; else bad "slack: snapshot PNG has the full page height" "rc=$rc height=$height $out"; fi
  : > "$SLOG"
  out="$(SL_CHROME=real slack post 6 brief --page "$SPAGE" 2>&1)"; rc=$?
  names="$(slog 'sorted(e["params"].get("filename", "").rsplit(".", 1)[-1] for e in L if e["method"] == "files.getUploadURLExternal")')"
  if [ $rc -eq 0 ] && [ "$names" = '["html", "png"]' ]; then ok "slack: post brief --page with Chrome uploads the PNG and the HTML"; else bad "slack: post brief --page with Chrome uploads the PNG and the HTML" "rc=$rc $out $(cat "$SLOG")"; fi
fi

# 7. the other stages, --file, and bad arguments
printf '테스트용 본문 문장입니다.\n' > "$SL/text.md"
printf 'e2e: 3 passed\n' > "$SL/e2e.log"
slack thread 7 >/dev/null 2>&1
P7="$(mfield 7 ts)"
# Each stage replies with its title in a header block and the body in a section block and in text.
for stage in mockup design wave check pr feedback; do
  title="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import slack_config; print(slack_config.stage_title(sys.argv[2]))' "$ROOT/scripts" "$stage")"
  : > "$SLOG"
  out="$(slack post 7 "$stage" --text "$SL/text.md" 2>&1)"; rc=$?
  said="$(slog '[(H(e), any(b.get("type") == "section" and "테스트용 본문 문장입니다" in T(b) for b in B(e)), "테스트용 본문 문장입니다" in e["params"].get("text", "")) for e in RP(A[0])] == [(A[1], True, True)]' "$P7" "$title")"
  if [ $rc -eq 0 ] && [ -n "$P7" ] && [ "$said" = true ]; then ok "slack: post $stage replies in the thread with the header $title and the text"; else bad "slack: post $stage replies in the thread with the header $title and the text" "rc=$rc $out $(cat "$SLOG")"; fi
done

# Block shape: header, progress line, divider, the body, and the developer line in the footer.
slack thread 21 >/dev/null 2>&1
P21="$(mfield 21 ts)"
printf '기획자가 읽을 본문입니다.\n\n개발자용: <https://x|PR>\n' > "$SL/dev.md"
: > "$SLOG"
out="$(slack post 21 brief --text "$SL/dev.md" 2>&1)"; rc=$?
said="$(slog '[(lambda b: [x.get("type") for x in b[:3]] == ["header", "context", "divider"] and SC.progress_line("plan") in T(b[1]) and b[-1].get("type") == "context" and "개발자용: <https://x|PR>" in T(b[-1]) and not any("개발자용" in T(x) for x in b if x.get("type") == "section") and any("기획자가 읽을 본문" in T(x) for x in b if x.get("type") == "section"))(B(e)) for e in RP(A[0])] == [True]' "$P21")"
if [ $rc -eq 0 ] && [ -n "$P21" ] && [ "$said" = true ]; then ok "slack: a reply is header, progress line, divider, body sections, and the 개발자용 line in the last context block"; else bad "slack: a reply is header, progress line, divider, body sections, and the 개발자용 line in the last context block" "rc=$rc $out $(cat "$SLOG")"; fi

# A body longer than one section block is split into several, each within 3000 characters.
python3 -c 'import sys; open(sys.argv[1], "w").write("\n\n".join(["가" * 1200] * 3 + ["나" * 4000]) + "\n")' "$SL/long.md"
: > "$SLOG"
out="$(slack post 21 wave --text "$SL/long.md" 2>&1)"; rc=$?
said="$(slog '[(lambda secs: len(secs) >= 3 and all(len(x) <= 3000 for x in secs) and "".join("".join(secs).split()) == "".join(open(A[1], encoding="utf-8").read().split()))([T(b) for b in B(e) if b.get("type") == "section"]) for e in RP(A[0])] == [True]' "$P21" "$SL/long.md")"
if [ $rc -eq 0 ] && [ "$said" = true ]; then ok "slack: a body over 3000 characters is split into section blocks of 3000 at most"; else bad "slack: a body over 3000 characters is split into section blocks of 3000 at most" "rc=$rc $out $(slog '[[len(T(b)) for b in B(e) if b.get("type") == "section"] for e in L if e["method"] == "chat.postMessage"]')"; fi

# --outcome: other titles for a briefing left for later and a dropped issue; close needs one
slack thread 22 >/dev/null 2>&1
P22="$(mfield 22 ts)"
: > "$SLOG"
out="$(slack post 22 approve --outcome later --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[H(e) for e in RP(A[0])] == ["⏸ 나중에 하기"]' "$P22")" = true ] && [ "$(mfield 22 phase)" = later ]; then ok "slack: approve --outcome later replies under ⏸ 나중에 하기 and records phase=later"; else bad "slack: approve --outcome later replies under ⏸ 나중에 하기 and records phase=later" "rc=$rc $out $(smark 22) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 22 close 2>&1)"; rc=$?
if [ $rc -eq 2 ] && [ ! -s "$SLOG" ]; then ok "slack: close without --outcome exits 2 and calls no Slack API"; else bad "slack: close without --outcome exits 2 and calls no Slack API" "rc=$rc $out"; fi
out="$(slack post 22 approve --outcome merged 2>&1)"; rc=$?
if [ $rc -eq 2 ] && [ ! -s "$SLOG" ]; then ok "slack: approve --outcome merged exits 2"; else bad "slack: approve --outcome merged exits 2" "rc=$rc $out"; fi
out="$(slack post 22 wave --outcome later 2>&1)"; rc=$?
if [ $rc -eq 2 ] && [ ! -s "$SLOG" ]; then ok "slack: --outcome on a stage that takes none exits 2"; else bad "slack: --outcome on a stage that takes none exits 2" "rc=$rc $out"; fi
slack thread 23 >/dev/null 2>&1
P23="$(mfield 23 ts)"
: > "$SLOG"
out="$(slack post 23 close --outcome dropped --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[H(e) for e in RP(A[0])] == ["⏸ 중단"]' "$P23")" = true ]; then ok "slack: close --outcome dropped replies under ⏸ 중단"; else bad "slack: close --outcome dropped replies under ⏸ 중단" "rc=$rc $out $(cat "$SLOG")"; fi
if [ "$(mfield 23 phase)" = dropped ] && [ "$(slog '[(SC.SPECIAL_PHASES["dropped"] in (BID(e, SC.BLOCK_STATUS) or ""), SC.CLOSED_NOTICE in (BID(e, SC.BLOCK_CLOSED) or "")) for e in UP(A[0])] == [(True, True)]' "$P23")" = true ]; then ok "slack: a dropped issue's first message reads 중단했습니다 with the closed notice"; else bad "slack: a dropped issue's first message reads 중단했습니다 with the closed notice" "$(smark 23) $(cat "$SLOG")"; fi

# Attachments Slack refuses the blocks of: the blocks go up as a message, then the files alone.
slack thread 24 >/dev/null 2>&1
P24="$(mfield 24 ts)"
: > "$SLOG"
out="$(sfake '{"FAKE_SLACK_INVALID_BLOCKS": "1"}' slack post 24 brief --page "$SPAGE" 2>&1)"; rc=$?
said="$(slog '[(e["method"], bool(B(e)), e["params"].get("thread_ts")) for e in L if e["method"] in ("chat.postMessage", "files.completeUploadExternal")] == [("files.completeUploadExternal", True, A[0]), ("chat.postMessage", True, A[0]), ("files.completeUploadExternal", False, A[0])]' "$P24")"
if [ $rc -eq 0 ] && [ -n "$P24" ] && [ "$said" = true ]; then ok "slack: on invalid_blocks the blocks are posted in the thread, then the files are shared without blocks"; else bad "slack: on invalid_blocks the blocks are posted in the thread, then the files are shared without blocks" "rc=$rc $out $(cat "$SLOG")"; fi
: > "$SLOG"
slack post 7 check --file "$SL/e2e.log" >/dev/null 2>&1
if [ "$(slog '[e["params"].get("filename") for e in L if e["method"] == "files.getUploadURLExternal"]')" = '["e2e.log"]' ] && [ "$(slog '[e["params"]["bytes"] for e in L if e["method"] == "upload"]')" = "[$(wc -c < "$SL/e2e.log" | tr -d ' ')]" ] && [ "$(slog '[e["params"].get("thread_ts") for e in L if e["method"] == "files.completeUploadExternal"]')" = "[\"$P7\"]" ]; then ok "slack: post check --file uploads the file as it is into the thread"; else bad "slack: post check --file uploads the file as it is into the thread" "$(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 7 nosuchstage 2>&1)"; rc=$?
if [ $rc -eq 2 ] && [ ! -s "$SLOG" ]; then ok "slack: an unknown stage exits 2"; else bad "slack: an unknown stage exits 2" "rc=$rc $out"; fi
out="$(slack post 7 approve --page "$SPAGE" 2>&1)"; rc=$?
if [ $rc -eq 2 ] && [ ! -s "$SLOG" ]; then ok "slack: --page on approve exits 2"; else bad "slack: --page on approve exits 2" "rc=$rc $out"; fi

# A 504 from the upload host is tried once more and the post still goes through.
: > "$SLOG"; : > "$SFLAKY"
out="$(slack post 7 check --text "$SL/text.md" --file "$SL/e2e.log" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog 'len([e for e in L if e["method"] == "upload-504"])')" = 1 ] && [ "$(slog 'len([e for e in L if e["method"] == "upload"])')" = 1 ] && [ "$(slog 'len([e for e in L if e["method"] == "files.completeUploadExternal"])')" = 1 ]; then ok "slack: an upload that gets 504 once is retried and attached"; else bad "slack: an upload that gets 504 once is retried and attached" "rc=$rc $out $(cat "$SLOG")"; fi
rm -f "$SFLAKY"

# thread --text writes the issue out in plain words; on an existing thread it rewrites the first message
printf '회원이 비밀번호를 스스로 다시 만들 수 있게 합니다.\n' > "$SL/summary.md"
: > "$SLOG"
out="$(slack thread 11 --text "$SL/summary.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '(lambda e: "스스로 다시 만들" in ALL(e) and bool(B(e)) and "개발자용: <" in T(B(e)[-1]))([e for e in L if e["method"] == "chat.postMessage"][0])')" = true ]; then ok "slack: thread --text puts the plain-words issue in the first message, the GitHub link last"; else bad "slack: thread --text puts the plain-words issue in the first message, the GitHub link last" "rc=$rc $out $(cat "$SLOG")"; fi
P11="$(mfield 11 ts)"
printf '이슈 내용을 고쳐 쓴 요약입니다.\n' > "$SL/summary2.md"
: > "$SLOG"
out="$(slack thread 11 --text "$SL/summary2.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(posts)" = "[]" ] && [ "$(slog '[e["params"]["ts"] for e in L if e["method"] == "chat.update" and "고쳐 쓴 요약" in ALL(e)]')" = "[\"$P11\"]" ]; then ok "slack: thread --text on an existing thread rewrites its first message"; else bad "slack: thread --text on an existing thread rewrites its first message" "rc=$rc $out $(cat "$SLOG")"; fi
# A phase change redraws the first message with the summary and the poster it already had.
slack thread 29 --text "$SL/summary.md" >/dev/null 2>&1
P29="$(mfield 29 ts)"
: > "$SLOG"
printf '{"repo": "acme/app", "base": "main", "account": "teammate"}\n' >| "$SR/.logbook/config.json"
out="$(slack post 29 approve --text "$SL/text.md" 2>&1)"; rc=$?
printf '{"repo": "acme/app", "base": "main", "account": "dev"}\n' >| "$SR/.logbook/config.json"
if [ $rc -eq 0 ] && [ "$(slog '[("스스로 다시 만들" in (BID(e, SC.BLOCK_SUMMARY + "0") or "")) and "올린 사람: dev" in "".join(T(b) for b in B(e)) for e in UP(A[0])] == [True]' "$P29")" = true ]; then ok "slack: redrawing the first message keeps its plain-words summary and its poster"; else bad "slack: redrawing the first message keeps its plain-words summary and its poster" "rc=$rc $out $(cat "$SLOG")"; fi

# The first message shows the phase and is rewritten only when the phase moves forward.
: > "$SLOG"
slack thread 25 >/dev/null 2>&1
P25="$(mfield 25 ts)"
if [ -n "$P25" ] && [ "$(mfield 25 phase)" = plan ] && [ "$(slog '(BID(PARENT(A[0]), SC.BLOCK_STATUS) or "") == SC.progress_line("plan")' "$P25")" = true ]; then ok "slack: a new thread records phase=plan and its first message has the logbook_status progress line"; else bad "slack: a new thread records phase=plan and its first message has the logbook_status progress line" "$(smark 25) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 25 approve --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(mfield 25 phase)" = build ] && [ "$(slog '[("*만들기* ●" in (BID(e, SC.BLOCK_STATUS) or "")) for e in UP(A[0])] == [True]' "$P25")" = true ]; then ok "slack: post approve rewrites the first message to *만들기* ● and records phase=build"; else bad "slack: post approve rewrites the first message to *만들기* ● and records phase=build" "rc=$rc $out $(smark 25) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 25 wave --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog 'len([e for e in L if e["method"] == "chat.update"])')" = 0 ] && [ "$(mfield 25 phase)" = build ]; then ok "slack: a post that keeps the phase does not touch the first message"; else bad "slack: a post that keeps the phase does not touch the first message" "rc=$rc $out $(cat "$SLOG")"; fi
slack post 25 pr --text "$SL/text.md" >/dev/null 2>&1
: > "$SLOG"
out="$(slack post 25 check --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(mfield 25 phase)" = check ] && [ "$(slog 'len([e for e in L if e["method"] == "chat.update"])')" = 0 ]; then ok "slack: check after pr keeps phase=check (the phase never moves back)"; else bad "slack: check after pr keeps phase=check (the phase never moves back)" "rc=$rc $out $(smark 25) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 25 close --outcome merged --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(mfield 25 phase)" = done ] && [ "$(slog '[SC.CLOSED_NOTICE in (BID(e, SC.BLOCK_CLOSED) or "") for e in UP(A[0])] == [True] and [H(e) for e in RP(A[0])] == [SC.stage_title("close")]' "$P25")" = true ]; then ok "slack: close --outcome merged records phase=done and adds the closed notice to the first message"; else bad "slack: close --outcome merged records phase=done and adds the closed notice to the first message" "rc=$rc $out $(smark 25) $(cat "$SLOG")"; fi
if [ "$(slog '[(lambda b: bool(b) and b[-1].get("type") == "context" and SC.CLOSED_NOTICE in T(b[-1]))(B(e)) for e in RP(A[0])] == [True]' "$P25")" = true ]; then ok "slack: the close reply ends with the closed notice"; else bad "slack: the close reply ends with the closed notice" "$(cat "$SLOG")"; fi

# A backlog thread is marked [백로그] until a stage takes it up again.
: > "$SLOG"
slack thread 26 --backlog >/dev/null 2>&1
P26="$(mfield 26 ts)"
if [ -n "$P26" ] && [ "$(mfield 26 phase)" = later ] && [ "$(slog '(H(PARENT(A[0])) or "").startswith("[백로그] ")' "$P26")" = true ]; then ok "slack: thread --backlog heads the first message with [백로그] and records phase=later"; else bad "slack: thread --backlog heads the first message with [백로그] and records phase=later" "$(smark 26) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 26 brief --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(mfield 26 phase)" = plan ] && [ "$(slog '[(not (H(e) or "[백로그] ").startswith("[백로그] ") and "#26" in (H(e) or "")) for e in UP(A[0])] == [True]' "$P26")" = true ]; then ok "slack: a brief on a backlog thread drops [백로그] from the header and records phase=plan"; else bad "slack: a brief on a backlog thread drops [백로그] from the header and records phase=plan" "rc=$rc $out $(smark 26) $(cat "$SLOG")"; fi

# A failed rewrite of the first message exits 12 and leaves shown at the old phase, so
# `thread` (with no later post, as after close) redraws it without posting again.
slack thread 27 >/dev/null 2>&1
P27="$(mfield 27 ts)"
: > "$SLOG"
out="$(sfake '{"FAKE_SLACK_FAIL": "chat.update"}' slack post 27 approve --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 12 ] && printf '%s' "$out" | tail -1 | grep -q '첫 메시지' && printf '%s' "$out" | tail -1 | grep -q 'slack.sh thread 27' && [ "$(mfield 27 phase)" = build ] && [ "$(mfield 27 shown)" = plan ] && [ "$(slog 'len(RP(A[0]))' "$P27")" = 1 ]; then ok "slack: when chat.update fails the reply stays, it exits 12 naming 첫 메시지 and the retry, and shown keeps the old phase"; else bad "slack: when chat.update fails the reply stays, it exits 12 naming 첫 메시지 and the retry, and shown keeps the old phase" "rc=$rc $out $(smark 27) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack thread 27 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(mfield 27 shown)" = build ] && [ "$(slog 'len(UP(A[0]))' "$P27")" = 1 ] && [ "$(posts)" = "[]" ]; then ok "slack: thread redraws a first message a failed post left behind, without posting"; else bad "slack: thread redraws a first message a failed post left behind, without posting" "rc=$rc $out $(smark 27) $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack post 27 wave --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog 'len(UP(A[0]))' "$P27")" = 0 ]; then ok "slack: once shown matches the phase, the next post leaves the first message alone"; else bad "slack: once shown matches the phase, the next post leaves the first message alone" "rc=$rc $out $(smark 27) $(cat "$SLOG")"; fi

# thread without --text on an old first message a post could not redraw leaves it and says so.
printf '[{"id": 8030, "body": "<!-- logbook:slack channel=C0TEST ts=1600000000.000030 phase=build -->"}]' > "$GH_STATE/comments-30.json"
printf '[{"ts": "1600000000.000030", "user": "U0BOT", "text": "*#30 옛 첫 메시지*"}]' > "$SREPLIES"
: > "$SLOG"
out="$(slack thread 30 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | tail -1 | grep -q '옛 형식' && [ "$(slog 'len([e for e in L if e["method"] == "chat.update"])')" = 0 ] && [ "$(mfield 30 shown)" = build ]; then ok "slack: thread leaves an old first message as it is and says so"; else bad "slack: thread leaves an old first message as it is and says so" "rc=$rc $out $(smark 30) $(cat "$SLOG")"; fi

# A thread made before phases existed: its first message has no summary blocks and is left alone.
printf '[{"id": 8028, "body": "<!-- logbook:slack channel=C0TEST ts=1600000000.000028 -->"}]' > "$GH_STATE/comments-28.json"
printf '[{"ts": "1600000000.000028", "user": "U0BOT", "text": "*#28 옛 첫 메시지*"}]' > "$SREPLIES"
: > "$SLOG"
out="$(slack post 28 approve --text "$SL/text.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog 'len([e for e in L if e["method"] == "chat.update"])')" = 0 ]; then ok "slack: a first message in the old format (no summary blocks) is not rewritten"; else bad "slack: a first message in the old format (no summary blocks) is not rewritten" "rc=$rc $out $(cat "$SLOG")"; fi
: > "$SLOG"
out="$(slack thread 28 --text "$SL/summary.md" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(slog '[any((b.get("block_id") or "").startswith(SC.BLOCK_SUMMARY) and "스스로 다시 만들" in T(b) for b in B(e)) for e in UP("1600000000.000028")] == [True]')" = true ]; then ok "slack: thread --text rewrites an old first message with blocks"; else bad "slack: thread --text rewrites an old first message with blocks" "rc=$rc $out $(cat "$SLOG")"; fi
rm -f "$SREPLIES"

# 8. replies
slack thread 8 >/dev/null 2>&1
P8="$(mfield 8 ts)"
python3 - "$SREPLIES" "$P8" <<'EOF'
import json, sys
path, parent = sys.argv[1], sys.argv[2]
json.dump([
    {"ts": parent, "user": "U0PARENT", "text": "parent", "bot_id": "B0LOGBOOK"},
    {"ts": "1700000050.000001", "bot_id": "B0OTHER", "text": "봇 메시지"},
    {"ts": "1700000100.000001", "user": "U1", "text": "첫 답글입니다"},
    {"ts": "1700000150.000001", "user": "U0BOT", "text": "logbook이 올린 첨부 메시지"},
    {"ts": "1700000160.000001", "user": "U3", "subtype": "channel_join", "text": "채널에 들어옴"},
    {"ts": "1700000200.000001", "user": "U2", "text": "둘째 답글입니다"},
    {"ts": "1700000250.000001", "user": "U3", "subtype": "thread_broadcast", "text": "채널에도 보낸 답글입니다"},
], open(path, "w"), ensure_ascii=False)
EOF
jsonlines() { python3 -c '
import json, sys
for line in sys.stdin:
    try: o = json.loads(line)
    except ValueError: continue
    if isinstance(o, dict): print(json.dumps([o.get("user"), o.get("text"), o.get("ts")], ensure_ascii=False))'; }
out="$(slack replies 8 2>&1)"; rc=$?
got="$(printf '%s\n' "$out" | jsonlines)"
want="$(printf '%s\n%s\n%s' '["Name-U1", "첫 답글입니다", "1700000100.000001"]' '["Name-U2", "둘째 답글입니다", "1700000200.000001"]' '["Name-U3", "채널에도 보낸 답글입니다", "1700000250.000001"]')"
if [ $rc -eq 0 ] && [ "$got" = "$want" ]; then ok "slack: replies prints the people's replies oldest first (broadcast ones too), without the parent, bots, logbook's own posts and system messages"; else bad "slack: replies prints the people's replies oldest first (broadcast ones too), without the parent, bots, logbook's own posts and system messages" "rc=$rc $out"; fi
if [ "$(mfield 8 read)" = 1700000250.000001 ]; then ok "slack: replies records read=<newest ts> in the marker"; else bad "slack: replies records read=<newest ts> in the marker" "$(smark 8)"; fi
out="$(slack replies 8 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ -z "$(printf '%s\n' "$out" | jsonlines)" ]; then ok "slack: a second replies call prints no reply"; else bad "slack: a second replies call prints no reply" "rc=$rc $out"; fi
rm -f "$SREPLIES"

# 9. rulebook --slack-channel
R9="$SL/rulebook"
mkdir -p "$R9"
git -C "$R9" init -q -b main
git -C "$R9" remote add origin git@github.com:acme/app.git
printf '# App\n\nExisting rules stay.\n' > "$R9/AGENTS.md"
chan_lines() { grep -c '^- Slack 채널: ' "$R9/AGENTS.md"; }
out="$("$ROOT/scripts/rulebook.sh" --apply --dir "$R9" --no-labels --slack-channel C0123ABCD 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ "$(chan_lines)" = 1 ] && grep -qxF -e '- Slack 채널: `C0123ABCD`' "$R9/AGENTS.md" && grep -q 'Existing rules stay.' "$R9/AGENTS.md"; then ok "rulebook: --slack-channel writes one channel line into AGENTS.md"; else bad "rulebook: --slack-channel writes one channel line into AGENTS.md" "rc=$rc $out"; fi
cp "$R9/AGENTS.md" "$SL/agents9"
"$ROOT/scripts/rulebook.sh" --apply --dir "$R9" --no-labels --slack-channel C0123ABCD >/dev/null 2>&1
expect "rulebook: the same --slack-channel again changes nothing" bash -c "cmp -s '$R9/AGENTS.md' '$SL/agents9' && grep -qxF -e '- Slack 채널: \`C0123ABCD\`' '$R9/AGENTS.md'"
"$ROOT/scripts/rulebook.sh" --apply --dir "$R9" --no-labels --slack-channel C0999ZZZZ >/dev/null 2>&1
if [ "$(chan_lines)" = 1 ] && grep -qxF -e '- Slack 채널: `C0999ZZZZ`' "$R9/AGENTS.md"; then ok "rulebook: another --slack-channel replaces the line"; else bad "rulebook: another --slack-channel replaces the line" "$(cat "$R9/AGENTS.md")"; fi
"$ROOT/scripts/rulebook.sh" --apply --dir "$R9" --no-labels --slack-channel bad-id >/dev/null 2>&1; rc=$?
if [ $rc -eq 2 ] && grep -qxF -e '- Slack 채널: `C0999ZZZZ`' "$R9/AGENTS.md"; then ok "rulebook: --slack-channel bad-id exits 2"; else bad "rulebook: --slack-channel bad-id exits 2" "rc=$rc"; fi

# The stage titles planners read, written out so a changed table shows up here.
expect "slack: the stage titles are the planner words with their icons" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import slack_config as c; want = {"mockup": "🎨 시안", "design": "✅ 시안 승인", "brief": "📋 브리핑", "approve": "✅ 개발 시작", "wave": "🔨 개발 끝", "check": "🔍 확인할 결과", "pr": "👀 마지막 확인", "debrief": "📦 완성 보고", "close": "🚀 반영 완료", "feedback": "💬 피드백 반영"}; sys.exit(0 if {s: c.stage_title(s) for s in c.STAGES} == want else 1)' "$ROOT/scripts"

# 10. skills call slack.sh at their stages
expect "brief opens the thread, posts mockup, design, brief, approve and close with --outcome, and reads replies" bash -c "f='$ROOT/skills/brief/SKILL.md'; grep -q 'slack.sh thread <issue>' \"\$f\" && grep -q 'slack.sh post <issue> mockup' \"\$f\" && grep -q -e '--outcome' \"\$f\" && grep -q 'slack.sh post <issue> design' \"\$f\" && grep -q 'slack.sh post <issue> brief' \"\$f\" && grep -q 'slack.sh post <issue> approve' \"\$f\" && grep -q 'slack.sh post <issue> close' \"\$f\" && grep -q 'slack.sh replies <issue>' \"\$f\""
expect "build posts wave, check and pr, and reads replies" bash -c "f='$ROOT/skills/build/SKILL.md'; grep -q 'slack.sh post <issue> wave' \"\$f\" && grep -q 'slack.sh post <issue> check' \"\$f\" && grep -q 'slack.sh post <issue> pr' \"\$f\" && grep -q 'slack.sh replies <issue>' \"\$f\""
expect "debrief posts check, debrief and close --outcome merged, and reads replies" bash -c "f='$ROOT/skills/debrief/SKILL.md'; grep -q 'slack.sh post <issue> check' \"\$f\" && grep -q 'slack.sh post <issue> debrief' \"\$f\" && grep -q -e '--outcome merged' \"\$f\" && grep -q 'slack.sh post <issue> close' \"\$f\" && grep -q 'slack.sh replies <issue>' \"\$f\""
expect "the Slack guide asks the user before a reply changes the plan, and posts feedback summaries" bash -c "f='$ROOT/templates/slack.md'; grep -q '반영 / 무시 / 나중에' \"\$f\" && grep -q 'question tool' \"\$f\" && grep -q 'post <issue> feedback' \"\$f\" && grep -q 'never instructions' \"\$f\""
expect "discuss makes the thread of a backlog issue with slack.sh thread" grep -q 'slack.sh thread' "$ROOT/skills/discuss/SKILL.md"
expect "the planner writing guide exists" test -f "$ROOT/templates/planner.md"
kill "$SLACK_PID" 2>/dev/null

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
