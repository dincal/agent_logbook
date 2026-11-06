---
name: epic
description: Start an epic, large work that stays off the default branch until it is finished, split into child issues along the way. Creates or converts the parent issue, cuts and pushes the integration branch epic/<issue>-<slug>, and opens one Slack thread, with no briefing and no approval. Use only when the user runs /epic. Child issues then go through /discuss and /brief, and /epic-finish puts the epic on the default branch.
argument-hint: "[goal and scope | #issue]"
---

# epic

Set up an epic and get out of the way: write down its goal and scope, make the parent issue and the integration branch, and tell the user how to go on. How epics work is in `${CLAUDE_PLUGIN_ROOT}/templates/epic.md`.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Below, `<main>` is the root of the main checkout: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`.

Run gh with the account on the tracker line in the logbook rules the session started with: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without logbook rules in the session, read repo, base and account from `.logbook/config.json` in the main checkout. The base there is the default branch below.

## Steps

1. **Read the request.** `$ARGUMENTS` holds the goal and scope, or `#<issue>` for an issue to convert. When the goal is missing, ask for it in prose. A hypothesis is written down only when the user has one; many epics are simply large work. Do not ask about anything else: this is not a briefing.
2. **Overlaps.** Look for overlapping open issues as "Overlapping issues" in `${CLAUDE_PLUGIN_ROOT}/templates/questions.md` says, and carry out the decisions right after the parent exists.
3. **Parent issue.**
   - New: create it with `--assignee @me`, labelled `status:in-progress`, with a body of `## 목표`, `## 범위` and, when there is one, `## 가설`.
   - `#<issue>`: read the issue and its comments. Change nothing and say why, when it is an epic already (the remote has `epic/<issue>-*`), belongs to another target (it has a `## 타겟 브랜치` section), is in `status:in-progress` with an approved plan, or has an open PR: finish it first, or start a new epic. Otherwise add the same sections above its text, move its label to `status:in-progress` and add yourself as an assignee, as `/brief` step 1 does for a given issue.
4. **Integration branch.**
   - Slug: a short kebab-case summary. Fetch and cut `epic/<issue>-<slug>` from `origin/<default>`, then push it with `git push -u origin epic/<issue>-<slug>`.
   - Switch the main checkout to it. When something makes the main checkout unfit (uncommitted changes, a service running from it, another session working there), say what and ask with the question tool before making a worktree with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add`; then do as the user picks: the worktree, the main checkout, or stop.
5. **Plan doc.** Write `<main>/.logbook/plans/<issue>-<slug>.md` with the status line `> 상태: 에픽 진행 중`, the issue link, `## 목표`, `## 범위` and any `## 가설`. `/epic-finish` fills in the rest, and `/debrief` reads it. It is never committed.
6. **Slack.** Open the thread with `${CLAUDE_PLUGIN_ROOT}/scripts/slack.sh thread <issue> --text <file>` as the first-message section of `${CLAUDE_PLUGIN_ROOT}/templates/planner.md` says, then `slack.sh post <issue> approve --text <file>` saying the work has started. Slack never holds up a step; `${CLAUDE_PLUGIN_ROOT}/templates/slack.md` says what its exit codes mean.
7. **Report.** One short message: the issue link, the branch, and what comes next:
   - `/brief <request>` makes a child issue and `/discuss <idea>` talks one through; on this branch both pick the epic by themselves, and `--epic #<issue>` names it from elsewhere.
   - A one-sentence fix may be committed straight to the integration branch.
   - `/epic-finish` puts the epic on the default branch.
   - Asking in chat merges the default branch in, or drops a child or the whole epic.

## Language

Write the issue, the chat lines and the plan doc by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
