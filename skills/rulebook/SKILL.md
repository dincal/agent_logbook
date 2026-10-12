---
name: rulebook
description: Turn logbook on in the current repository, once per clone, namely the local marker .logbook/config.json, the tracker labels and plansDirectory. The working rules are not copied into the project; the plugin's SessionStart hook adds them to every session, so a plugin update needs no rerun. In a project set up by logbook before 0.7, it also replaces the old AGENTS.md rule block with a plain document rules paragraph. In a new or existing project it then points to /sync, which sets up the document structure and writes the project docs.
argument-hint: "[owner/repo]"
disable-model-invocation: true
---

# rulebook

Set up this repository so every session follows the logbook flow: an issue for work others need to know about, a briefing before implementation, a debriefing after the PR, and a question wherever a decision is the user's to make.

The rules themselves live in the plugin (`${CLAUDE_PLUGIN_ROOT}/templates/session-rules.md`). The SessionStart hook adds them, with this repository's tracker values, to every session whose repository has `.logbook/config.json`, including sessions in a git worktree of it. Run this skill once per clone: in a new project, in an existing one, and after cloning a repository that already uses logbook, since the marker is git-ignored and does not travel with a clone. A plugin update needs no rerun.

## What changes

`${CLAUDE_PLUGIN_ROOT}/scripts/rulebook.sh` does the writing and is idempotent. On harnesses without that variable, the script lives in the plugin's `scripts/` folder, two levels above this file.

- `.logbook/config.json`: repo, base branch and gh account. The hooks read it, and its presence is what turns logbook on. Run from a git worktree, it is written to the main checkout, where the hooks look. A value not passed as an option keeps what the existing file holds.
- `.gitignore`: adds `.logbook/` (the marker, previews, hook state).
- GitHub labels: `status:backlog`, `status:todo`, `status:in-progress`, `status:done`.
- `plansDirectory` in `.claude/settings.json`: `.logbook/plans`, so plan-mode plans land where git ignores them. `/brief` keeps an approved plan in the main checkout's `.logbook/plans/` too, under its issue number; a plan made in a git worktree is moved there.
- `CLAUDE.md`: adds an `@AGENTS.md` import when AGENTS.md exists, so Claude Code reads the project's rules even in sessions that skip AGENTS.md.
- `AGENTS.md`: touched only when it still holds a rule block from logbook before 0.7 (`<!-- logbook:begin` to `<!-- logbook:end -->`). The block is replaced, in place, by the document rules paragraph from `${CLAUDE_PLUGIN_ROOT}/templates/docs-rules.md`: the table of document places and the promise to update them with the code. That paragraph belongs to the project, not to logbook; logbook never rewrites it. Everything outside the block stays as it is.

## Steps

1. Check the preconditions: a git repository, a GitHub `origin` remote, and `gh auth status`. Without GitHub, continue with `--no-labels` and say that issue tracking is unavailable.
2. Resolve the values.
   - Repo: `$ARGUMENTS` when given, otherwise the `origin` remote.
   - Base branch: the remote default branch, otherwise `main`.
   - gh account: when `gh auth status` lists several accounts, pick the one whose name matches the repo owner. If none matches, ask which account owns the repository, with the accounts as options.
3. Run `rulebook.sh --dry-run --repo <repo> --base <base> [--account <account>]` and show the planned changes. Ask for approval before writing, with the question tool as `${CLAUDE_PLUGIN_ROOT}/templates/questions.md` says.
4. Run the same command with `--apply` and report every line it prints. A second run prints `변경 없음`.
5. When files the repository tracks changed (anything but `.logbook/` and labels), commit them on a work branch with the next change, not directly on the base branch. A fresh clone of a logbook repository usually changes nothing tracked.
6. Next step:
   - AGENTS.md has no document table, or the project docs are missing: tell the user to run `/sync` next. It asks how the project wants its documents laid out, writes the document rules paragraph and the project docs, cleans up documents outside those places, and its PR carries this skill's changes as well.
   - First setup: say that the rules arrive from the next session on (a new session or `/clear`), since this session started without them. A migrated block: the session already had the rules through the old block; say that the document rules stayed in AGENTS.md as a plain paragraph the project owns.

## Notes

- To change the rules for every project, change `templates/session-rules.md` in the plugin and release it. Projects need nothing.
- When the project already keeps agent rules in another file that AGENTS.md does not import, point that out and ask with the question tool before adding a second source of rules.
- Harnesses without hooks (Antigravity, OpenCode) do not get the rules this way; the README says how to add them by hand.
- Report to the user by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language.
