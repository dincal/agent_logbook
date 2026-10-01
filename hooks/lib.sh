# Shared helpers for logbook hooks. POSIX sh; source it after setting nothing.

# Print the root of the main working tree for the repository that holds $1.
# In a linked worktree this is the original checkout, where the git-ignored
# .logbook/ folder lives. Prints nothing outside a git repository.
logbook_main_root() {
  common="$(CDPATH= cd -- "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  common="$(CDPATH= cd -- "$1" && CDPATH= cd -- "$common" 2>/dev/null && pwd -P)" || return 1
  case "$common" in
    */.git) dirname "$common" ;;
    *) git -C "$1" rev-parse --show-toplevel 2>/dev/null ;;
  esac
}

# True when $1 (a working tree) carries a rule block written by logbook before 0.7.
logbook_old_block() {
  grep -q '^<!-- logbook:begin' "$1/AGENTS.md" 2>/dev/null
}

# True when the repository uses logbook: the main root has .logbook/config.json,
# or the working tree $2 still has an old rule block that /rulebook has not migrated.
logbook_enabled() {
  [ -f "$1/.logbook/config.json" ] || logbook_old_block "$2"
}
