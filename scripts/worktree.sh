#!/usr/bin/env bash
# Create and remove the git worktrees logbook uses for parallel work.
# They live in the main checkout's git-ignored .logbook/worktrees/, one folder per branch,
# so they never show up as sibling folders and the plan docs stay where the hooks look.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: worktree.sh add BRANCH [BASE] [--dir DIR]
       worktree.sh remove BRANCH [--delete-branch] [--dir DIR]
       worktree.sh path BRANCH [--dir DIR]

add     Creates <main>/.logbook/worktrees/<BRANCH with / as -> on BRANCH, cutting BRANCH
        from BASE when it does not exist yet, and links the main checkout's git-ignored
        .env and .env.* files into it. Prints the worktree path on the last line.
        An existing worktree for BRANCH is reused.
remove  Removes that worktree. Refuses (exit 3) when it has uncommitted changes other
        than the linked env files. The branch is kept unless --delete-branch is given,
        which deletes it only when `git branch -d` allows it (merged into the main
        checkout's HEAD, or into its upstream); otherwise it is kept and the exit is 4.
path    Prints the worktree path for BRANCH.
EOF
}

CMD="${1:-}"; [ $# -gt 0 ] && shift
BRANCH="" BASE="" DIR="" DELETE_BRANCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:?--dir needs a value}"; shift ;;
    --delete-branch) DELETE_BRANCH=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "worktree: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) if [ -z "$BRANCH" ]; then BRANCH="$1"; elif [ -z "$BASE" ]; then BASE="$1"; else usage >&2; exit 2; fi ;;
  esac
  shift
done
case "$CMD" in add|remove|path) ;; -h|--help) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac
[ -n "$BRANCH" ] || { usage >&2; exit 2; }

DIR="${DIR:-$(pwd)}"
# The main checkout is the folder above the shared .git, also when called from a worktree.
common="$(CDPATH= cd -- "$DIR" && git rev-parse --git-common-dir)"
common="$(CDPATH= cd -- "$DIR" && CDPATH= cd -- "$common" && pwd -P)"
case "$common" in
  */.git) MAIN="$(dirname "$common")" ;;
  *) echo "worktree: $DIR has no .git folder to find the main checkout from" >&2; exit 1 ;;
esac
WT="$MAIN/.logbook/worktrees/${BRANCH//\//-}"

# True when $1 in the worktree is a link this script made to the main checkout's env file.
linked_env() {
  [ -L "$WT/$1" ] && [ "$(readlink "$WT/$1")" = "$MAIN/$1" ]
}

case "$CMD" in
  path)
    echo "$WT"
    ;;

  add)
    if [ -e "$WT/.git" ]; then
      echo "worktree: reusing $WT"
    else
      # Keep the worktrees out of the main checkout's status even before /rulebook ran.
      if ! git -C "$MAIN" check-ignore -q .logbook/worktrees; then
        echo ".logbook/" >> "$common/info/exclude"
        echo "worktree: added .logbook/ to $common/info/exclude"
      fi
      mkdir -p "$MAIN/.logbook/worktrees"
      if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        # An existing branch is checked out as it is; say so, since BASE is not applied.
        [ -z "$BASE" ] || echo "worktree: $BRANCH already exists; using it as it is, not cutting it from $BASE"
        BASE=""
        git -C "$MAIN" worktree add -q "$WT" "$BRANCH"
      elif git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        git -C "$MAIN" worktree add -q --track -b "$BRANCH" "$WT" "origin/$BRANCH"
        BASE="origin/$BRANCH"
      else
        [ -n "$BASE" ] || { echo "worktree: $BRANCH does not exist; give the base to cut it from" >&2; exit 2; }
        git -C "$MAIN" worktree add -q -b "$BRANCH" "$WT" "$BASE"
      fi
      echo "worktree: created $WT on $BRANCH${BASE:+ from $BASE}"
    fi
    for f in "$MAIN"/.env "$MAIN"/.env.*; do
      [ -f "$f" ] || continue
      name="$(basename "$f")"
      git -C "$MAIN" check-ignore -q "$name" || continue
      [ -e "$WT/$name" ] || [ -L "$WT/$name" ] && continue
      ln -s "$f" "$WT/$name"
      echo "worktree: linked $name"
    done
    echo "$WT"
    ;;

  remove)
    if [ ! -e "$WT/.git" ]; then
      # A folder deleted by hand stays registered and keeps its branch locked until pruned.
      git -C "$MAIN" worktree prune
      echo "worktree: no worktree at $WT"
    else
      # Capture first: a failing git status inside a process substitution would go unnoticed.
      status="$(git -C "$WT" status --porcelain --untracked-files=all)"
      dirty=""
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line:3}"
        case "$line" in "?? "*) linked_env "$path" && continue ;; esac
        dirty="$dirty$line"$'\n'
      done <<< "$status"
      if [ -n "$dirty" ]; then
        echo "worktree: $WT has uncommitted changes; not removed" >&2
        printf '%s' "$dirty" >&2
        exit 3
      fi
      # Only the linked env files can be left untracked here, so --force removes nothing else.
      git -C "$MAIN" worktree remove --force "$WT"
      echo "worktree: removed $WT"
    fi
    if [ "$DELETE_BRANCH" != 1 ]; then
      echo "worktree: branch $BRANCH kept"
    elif ! git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      echo "worktree: branch $BRANCH is already gone"
    elif git -C "$MAIN" branch -q -d "$BRANCH" 2>/dev/null; then
      echo "worktree: deleted branch $BRANCH"
    else
      # -d refused: the branch holds commits not merged yet. Forcing it would lose them.
      echo "worktree: $BRANCH is not merged; kept. Stop and report it; do not force-delete it" >&2
      exit 4
    fi
    ;;
esac
