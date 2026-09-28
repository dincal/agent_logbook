#!/usr/bin/env bash
# Install or update logbook's working rules in a project. Idempotent: a second run changes nothing.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: rulebook.sh (--dry-run | --apply) [--dir DIR] [--repo OWNER/NAME] [--base BRANCH]
                   [--account GH_USER] [--no-labels]

Writes the logbook rule block into AGENTS.md, an @AGENTS.md import into CLAUDE.md,
plansDirectory into .claude/settings.json, .logbook/ into .gitignore, docs/plans/,
.logbook/config.json, and the tracker labels on GitHub.
EOF
}

MODE="" DIR="" REPO="" BASE="" ACCOUNT="" LABELS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry ;;
    --apply) MODE=apply ;;
    --dir) DIR="${2:?--dir needs a value}"; shift ;;
    --repo) REPO="${2:?--repo needs a value}"; shift ;;
    --base) BASE="${2:?--base needs a value}"; shift ;;
    --account) ACCOUNT="${2:?--account needs a value}"; shift ;;
    --no-labels) LABELS=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "rulebook: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$MODE" ] || { usage >&2; exit 2; }

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$PLUGIN_ROOT/templates/agents-block.md"
DIR="${DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$DIR"

if [ -z "$REPO" ]; then
  origin="$(git remote get-url origin 2>/dev/null || true)"
  REPO="$(printf '%s' "$origin" | sed -E 's#^(ssh://)?(git@|https://)[^/:]+[:/]##; s#\.git$##')"
fi
if [ -z "$BASE" ]; then
  BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  BASE="${BASE:-main}"
fi

CHANGES=0
note() { printf '%-10s %s\n' "$1" "$2"; }

# Write $2 to $1 when it differs from the current content. Runs in the main shell so CHANGES counts.
write_if_changed() {
  local path="$1" tmp action
  tmp="$(mktemp)"
  printf '%s' "$2" > "$tmp"
  if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
    note unchanged "$path"
    rm -f "$tmp"
    return 0
  fi
  action=update
  [ -e "$path" ] || action=create
  CHANGES=$((CHANGES + 1))
  if [ "$MODE" = apply ]; then
    mkdir -p "$(dirname "$path")"
    cat "$tmp" > "$path"
  fi
  rm -f "$tmp"
  note "$action" "$path"
}

render_block() {
  local block
  block="$(cat "$TEMPLATE")"
  block="${block//\{repo\}/${REPO:-owner/repo}}"
  block="${block//\{base\}/$BASE}"
  if [ -n "$ACCOUNT" ]; then
    block="${block//\{account\}/$ACCOUNT}"
  else
    block="${block// · gh 계정 \`\{account\}\`/}"
  fi
  printf '%s' "$block"
}

upsert_agents_block() {
  local file=AGENTS.md block new="" before="" after="" state=0 line
  block="$(render_block)"
  if [ -f "$file" ] && grep -q '^<!-- logbook:begin' "$file"; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$state" in
        0) case "$line" in "<!-- logbook:begin"*) state=1 ;; *) before+="$line"$'\n' ;; esac ;;
        1) case "$line" in "<!-- logbook:end -->"*) state=2 ;; esac ;;
        2) after+="$line"$'\n' ;;
      esac
    done < "$file"
    if [ "$state" != 2 ]; then
      echo "rulebook: $file has '<!-- logbook:begin' but no '<!-- logbook:end -->' line; fix the markers and rerun" >&2
      exit 1
    fi
    new="${before}${block}"$'\n'"${after}"
  elif [ -f "$file" ]; then
    new="$(cat "$file")"$'\n\n'"${block}"$'\n'
  else
    new="# ${REPO##*/}"$'\n\n'"${block}"$'\n'
  fi
  write_if_changed "$file" "$new"
}

ensure_claude_import() {
  local file=CLAUDE.md target
  if [ -L AGENTS.md ]; then
    case "$(readlink AGENTS.md)" in
      CLAUDE.md|./CLAUDE.md) note unchanged "$file (AGENTS.md is a symlink to it)"; return 0 ;;
    esac
  fi
  if [ -L "$file" ]; then
    target="$(readlink "$file")"
    case "$target" in
      AGENTS.md|./AGENTS.md) note unchanged "$file (symlink to AGENTS.md)" ;;
      *) note skipped "$file (symlink to $target; add @AGENTS.md there by hand)" ;;
    esac
    return 0
  fi
  if [ -f "$file" ]; then
    if grep -qE '^@(\./)?AGENTS\.md[[:space:]]*$' "$file"; then
      note unchanged "$file"
      return 0
    fi
    write_if_changed "$file" "$(cat "$file")"$'\n\n'"@AGENTS.md"$'\n'
  else
    write_if_changed "$file" "@AGENTS.md"$'\n'
  fi
}

json_set_plans_dir() {
  if command -v jq >/dev/null 2>&1; then
    jq '.plansDirectory = "docs/plans"' "$1"
  else
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["plansDirectory"]="docs/plans"; print(json.dumps(d, indent=2, ensure_ascii=False))' "$1"
  fi
}

json_has_plans_dir() {
  if command -v jq >/dev/null 2>&1; then
    jq -e '.plansDirectory == "docs/plans"' "$1" >/dev/null 2>&1
  else
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("plansDirectory")=="docs/plans" else 1)' "$1" 2>/dev/null
  fi
}

ensure_plans_setting() {
  local file=.claude/settings.json new
  if [ -f "$file" ]; then
    if json_has_plans_dir "$file"; then
      note unchanged "$file"
      return 0
    fi
    new="$(json_set_plans_dir "$file")" || { echo "rulebook: cannot parse $file" >&2; exit 1; }
    write_if_changed "$file" "$new"$'\n'
  else
    write_if_changed "$file" $'{\n  "plansDirectory": "docs/plans"\n}\n'
  fi
}

ensure_gitignore() {
  local file=.gitignore
  if [ -f "$file" ] && grep -qxF '.logbook/' "$file"; then
    note unchanged "$file"
    return 0
  fi
  if [ -s "$file" ]; then
    write_if_changed "$file" "$(cat "$file")"$'\n'".logbook/"$'\n'
  else
    write_if_changed "$file" ".logbook/"$'\n'
  fi
}

ensure_plans_dir() {
  if [ -d docs/plans ] && [ -n "$(ls -A docs/plans 2>/dev/null)" ]; then
    note unchanged "docs/plans/"
    return 0
  fi
  write_if_changed docs/plans/.gitkeep ""
}

config_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg repo "$REPO" --arg base "$BASE" --arg account "$ACCOUNT" '{repo: $repo, base: $base, account: $account}'
  else
    python3 -c 'import json,sys; print(json.dumps({"repo": sys.argv[1], "base": sys.argv[2], "account": sys.argv[3]}, indent=2))' "$REPO" "$BASE" "$ACCOUNT"
  fi
}

write_config() {
  write_if_changed .logbook/config.json "$(config_json)"$'\n'
}

gh_run() {
  if [ -n "${LOGBOOK_GH_TOKEN:-}" ]; then GH_TOKEN="$LOGBOOK_GH_TOKEN" gh "$@"; else gh "$@"; fi
}

ensure_labels() {
  local existing name color desc
  if [ "$LABELS" = 0 ]; then note skipped "labels (--no-labels)"; return 0; fi
  if ! command -v gh >/dev/null 2>&1; then note skipped "labels (gh not found)"; return 0; fi
  if [ -z "$REPO" ]; then note skipped "labels (no GitHub remote)"; return 0; fi
  if [ -n "$ACCOUNT" ]; then LOGBOOK_GH_TOKEN="$(gh auth token --user "$ACCOUNT" 2>/dev/null || true)"; fi
  if ! existing="$(gh_run label list --repo "$REPO" --limit 200 --json name --jq '.[].name' 2>/dev/null)"; then
    note skipped "labels (gh could not list labels for $REPO)"
    return 0
  fi
  while IFS='|' read -r name color desc; do
    if printf '%s\n' "$existing" | grep -qixF "$name"; then
      note unchanged "label $name"
      continue
    fi
    if [ "$MODE" = apply ] && ! gh_run label create "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null 2>&1; then
      note failed "label $name"
      continue
    fi
    CHANGES=$((CHANGES + 1))
    note create "label $name"
  done <<'EOF'
status:backlog|C9CED6|Not started
status:todo|BFD4F2|Briefed, waiting for approval
status:in-progress|F9D38C|Being implemented
status:done|A7E3B5|Merged
epic|3E4B9E|Epic / Large initiative
EOF
}

echo "logbook rulebook ($MODE): dir=$DIR repo=${REPO:-none} base=$BASE account=${ACCOUNT:-default}"
upsert_agents_block
ensure_claude_import
ensure_plans_setting
ensure_gitignore
ensure_plans_dir
write_config
ensure_labels

if [ "$CHANGES" -eq 0 ]; then
  echo "변경 없음 (no changes)"
elif [ "$MODE" = dry ]; then
  echo "$CHANGES change(s) planned; run with --apply to write them"
else
  echo "$CHANGES change(s) applied"
fi
