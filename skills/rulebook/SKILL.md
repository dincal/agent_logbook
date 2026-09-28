---
name: rulebook
description: Install or refresh logbook's working rules in the current repository, namely the AGENTS.md rule block, a CLAUDE.md import, the tracker labels and the plans folder. Run once per project, or again after the rules change. On an existing project it then points to /sync, which cleans up earlier tools' traces and writes the project docs.
argument-hint: "[owner/repo]"
disable-model-invocation: true
---

# rulebook

Set up this repository so every development request follows the logbook flow: an issue first, a briefing before implementation, a debriefing after the PR, and a question wherever an open choice changes the user scenario.

## What changes

`${CLAUDE_PLUGIN_ROOT}/scripts/rulebook.sh` does the writing and is idempotent. On harnesses without that variable, the script lives in the plugin's `scripts/` folder, two levels above this file.

- `AGENTS.md`: inserts or refreshes the block between `<!-- logbook:begin` and `<!-- logbook:end -->`. Everything outside the markers stays as it is.
- `CLAUDE.md`: adds an `@AGENTS.md` import, so Claude Code reads the rules even in sessions that skip AGENTS.md.
- `.claude/settings.json`: sets `plansDirectory` to `docs/plans`, so plan-mode plans land in the repository.
- `.gitignore`: adds `.logbook/` (previews, hook state, local config).
- `docs/plans/`: created when missing.
- `.logbook/config.json`: repo, base branch and gh account, read by the hooks.
- GitHub labels: `status:backlog`, `status:todo`, `status:in-progress`, `status:done`, `epic`.

## Steps

1. Check the preconditions: a git repository, a GitHub `origin` remote, and `gh auth status`. Without GitHub, continue with `--no-labels` and say that issue tracking is unavailable.
2. Resolve the values.
   - Repo: `$ARGUMENTS` when given, otherwise the `origin` remote.
   - Base branch: the remote default branch, otherwise `main`.
   - gh account: when `gh auth status` lists several accounts, pick the one whose name matches the repo owner. If none matches, ask which account owns the repository.
3. Run `rulebook.sh --dry-run --repo <repo> --base <base> [--account <account>]` and show the planned changes. Ask for approval before writing (question tool, or numbered options in prose where there is none).
4. Run the same command with `--apply` and report every line it prints. A second run prints `변경 없음`.
5. Commit the changes on a work branch with the next change, not directly on the base branch.
6. Existing project: run `${CLAUDE_PLUGIN_ROOT}/scripts/legacy-scan.sh`. When it prints anything (traces of earlier agent tools such as paperclip, or documents outside logbook's places), or when `docs/system/` is missing, tell the user to run `/sync` next. `/sync` cleans those up and writes the project docs, and its PR carries this skill's changes as well.

## Notes

- The block text comes from `templates/agents-block.md`. Change the template to change the rules for every project, then rerun this skill in each project.
- When the project already keeps agent rules in another file that AGENTS.md does not import, point that out and ask before adding a second source of rules.
- Report to the user by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language.
