---
name: epic-finish
description: Put a finished epic on the default branch. Collects its child issues, merged PRs, dropped work and direct commits, merges the default branch in, writes what the work became with acceptance criteria drawn from them, opens the PR to the default branch and runs the full /debrief, where the human picks the merge. No briefing, since the development is done. Use when the user runs /epic-finish.
argument-hint: "[#issue]"
---

# epic-finish

Gather what an epic became and take it through the full debriefing to the default branch. The work is already built, so there is no briefing: the human reads the result and picks the merge in `/debrief`. How epics work is in `${CLAUDE_PLUGIN_ROOT}/templates/epic.md`.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Below, `<main>` is the root of the main checkout: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`.

Run gh with the account on the tracker line in the logbook rules the session started with: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without logbook rules in the session, read repo, base and account from `.logbook/config.json` in the main checkout. The base there is the default branch below.

## Steps

1. **Find the epic.** `$ARGUMENTS` names the parent; otherwise pick it from the checked-out branch as "Picking the target" in `templates/epic.md` says. Without an integration branch, say this is not an epic and stop. When an open PR already goes from it to the default branch, the run is past step 5: run `/debrief` instead.
2. **Collect.**
   - Fetch first. Child issues: `gh api --paginate repos/<repo>/issues/<parent>/sub_issues`, with the `에픽:` line of open issues as a fallback where linking failed.
   - PRs into the integration branch: `gh pr list --base <epic branch> --state all --limit 1000 --json number,title,state,headRefName,body,mergeCommit`.
   - Direct commits, as "Direct commits" in the guide says. When the integration branch holds nothing beyond the default branch, say there is nothing to put in and stop.
   - Sort the children into merged, dropped and still open. A child still open whose PR was merged, on the GitHub page for instance, counts as merged: close it with `--reason completed` and move it to `status:done`. Open ones are not touched here; `/debrief` shows them at the merge question.
   - Write the sorted list in the chat, one line each. This is a report, not a question.
3. **Merge the default branch in** as "Merging the default branch in" in the guide says, checked out in the main checkout or the worktree that holds the integration branch. Say so and stop when the full tests fail in a way you cannot fix.
4. **Write what it became.** Read the merged children's issues and PR bodies, then:
   - Fill the plan doc `<main>/.logbook/plans/<parent>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`: 요약, what the work became as features a user would recognize, the decisions the children recorded, the main logic flow and any schema change as built. Set its status line to 결과 보고. Rebuild it from the parent issue when it is not on this machine.
   - Write acceptance criteria from the epic's goal and the merged children's criteria, each naming the command or observation that proves it, the way `/brief` step 5 does. The human reads them in `/debrief`; do not ask for approval here.
   - Rewrite the parent's issue body with the same content, keeping `## 목표`, `## 범위`, `## 가설`, `## 합친 이슈` and `## 원래 요청`, with the text of someone else's issue under that last heading. Update its Slack thread's first message with `${CLAUDE_PLUGIN_ROOT}/scripts/slack.sh thread <parent> --text <file>`.
5. **Open the PR.** Push, then `gh pr create --base <default> --head <epic branch>` with `Closes #<parent>`. The body carries:
   - 요약 and what the work became;
   - a table of the merged children (issue, PR, one line of result);
   - the dropped children with why, the direct commits, and the children still open;
   - 주요 결정 from the children, with any 알린 우려;
   - the acceptance criteria.

   Then post `slack.sh post <parent> pr` to the thread and read new replies with `slack.sh replies <parent>`.
6. **Debrief.** Run `/debrief`. Its "Epics" section covers this PR: the full procedure, a review split by child, the merge question listing the children still open.

To drop the epic instead, the user asks in chat; "Dropping" in the guide says what happens.

## Language

Write the chat lines, the plan doc, the issue and the PR body by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
