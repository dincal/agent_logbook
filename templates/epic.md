# Epics

How logbook runs large work that stays off the default branch until it is finished. `/epic` starts an epic, `/discuss` and `/brief` work inside it, `/epic-finish` puts it on the default branch, and dropping needs no command.

An epic is a parent issue plus an integration branch `epic/<parent>-<slug>`, the long-lived branch its child issues merge into. It may test a hypothesis or simply be a large piece of work. It exists only when the user runs `/epic`; every other request stays one issue and one PR. There is no `epic` label: an issue is a parent when the remote has a branch `epic/<issue>-*`. Below, the default branch is the tracker's base branch.

## Picking the target

The target is the branch an issue is cut from and its PR goes to. `/discuss` and `/brief` take the first of these that applies and say in one line which they picked:

1. `--base <branch>`. The default branch means an ordinary issue, whatever branch is checked out. `--base epic/<n>-*` means the same as `--epic #<n>`. Any other branch must exist on the remote; otherwise stop and say so.
2. `--epic #<n>`. Find the branch with `git ls-remote --heads origin "epic/<n>-*"`. When there is none, the issue is not an epic: say so and stop.
3. The `## 타겟 브랜치` section of an issue given by number. A given issue without that section but with a parent (`gh api repos/<repo>/issues/<issue>/parent --jq .number`) that has an epic branch is a child of that epic.
4. The checked-out branch: `epic/<n>-*`, or a branch `<type>/<issue>-<slug>` whose issue has a `## 타겟 브랜치` section naming an epic branch. `/sync` skips this one, since its documents belong to the default branch.
5. The tracker's base branch, as before.

An issue with a target other than an epic branch and the default branch follows the ordinary flow in full. Only its branch base and PR target differ, its issue is closed by `/debrief`, and the handbook is not published.

An issue in `status:in-progress`, or with a branch or PR already, stays on the target it started on; say so instead of moving it. A flag that changes a planned issue's target rewrites its section and moves or removes its sub-issue link (`gh api --method DELETE repos/<repo>/issues/<parent>/sub_issue -F sub_issue_id=<id>`). When a recorded target is no longer on the remote, say so and ask which target to use.

## Recording the target

An issue with any target other than the default branch, whether new or given, carries this section in its body before work starts, and a child also carries its parent. `/brief` and `/build` read it, so the target survives a new session and another machine; `/debrief` goes by the PR's own branches. Every rewrite of the issue body keeps it.

```markdown
## 타겟 브랜치

`epic/12-pivot`

에픽: #12
```

Create a child with `gh issue create --parent <parent>`. Link a given issue with `gh api --method POST repos/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<id>`, where `<id>` comes from `gh api repos/<repo>/issues/<issue> --jq .id`. When a gh too old for `--parent` refuses, create the issue without it and link it with that call. When linking fails (an old gh, a host without sub-issues), keep the body section and say so in one line.

## A child issue

A child goes through the usual skills with these differences.

| Step | Child issue |
|---|---|
| Branch | `<type>/<issue>-<slug>`, always cut from the fetched integration branch, never stacked on another child |
| `/brief` questions and independent check | As usual. The overlap check leaves out its parent and the other children of its epic. Its plan names no project docs and no `system-check.sh` criterion |
| `/brief` approval | The text briefing in the issue body and the chat, with no briefing page (steps 7 and the page link of steps 8 and 9 are skipped) |
| `/build` | As usual, without updating `docs/system/`. The PR goes to the integration branch with `Closes #<issue>` and `Part of #<parent>`; GitHub ignores `Closes` there, and `/debrief` uses it to find the issue |
| `/debrief` evidence and review | As usual, without the project docs row |
| `/debrief` result | No result page, no CHANGELOG line, no `docs/system/` update and no handbook. Those wait for `/epic-finish` |
| Merge | The user picks it. `/debrief` then closes the issue itself. Merging says the change may go to the default branch: nothing takes a merged child out later |
| Slack | See "Slack" below |

## Merging the default branch in

Only when the user asks and during `/epic-finish`. Fetch, check out the integration branch, bring it up to its remote with `git pull --ff-only`, `git merge origin/<default>` (never rebase, so merged PRs keep their commits), run the project's full tests and push. When a conflict cannot be resolved, report it and ask 고친 뒤 이어서 / 중단 with the question tool.

## Direct commits

A change one sentence describes is committed straight to the integration branch and pushed, with no issue, PR or review. Anything bigger is a child issue. List them with `git log --first-parent --no-merges origin/<default>..origin/<epic branch>`, leaving out each merged PR's `mergeCommit`. `/epic-finish` lists them for the final review.

## Dropping

The user can drop a child or a whole epic at any moment by asking in chat, whatever step is running; there is no command. Dropping removes work for good, so show the list once and act on that one answer.

1. **Collect.** Fetch first.
   - A child: its issue, open PR, branch and any worktree.
   - An epic: the parent, every open child with the same (`gh api --paginate repos/<repo>/issues/<parent>/sub_issues`, and open issues whose body has the `에픽:` line where linking failed), every open PR into the integration branch (`gh pr list --base <epic branch> --state open --limit 1000`), the integration branch and any open PR from it to the default branch.
   - Merged children stay closed and untouched. An open child whose PR was merged, on the GitHub page for instance, counts as merged: close it with `--reason completed` instead of listing it. For an epic, count them in the list: their code goes with the integration branch and stays reachable through their closed PRs.
2. **Mark.** On each branch, its uncommitted changes (`git status --porcelain` where it is checked out) and its unmerged commits (`git rev-list --count origin/<target>..<branch>`, using `origin/<branch>` when it is only on the remote, and the larger number when both exist).
   - Someone else's issue or branch, as "Overlapping issues" in `templates/questions.md` tells them apart, is not touched. Plan one comment mentioning its assignees that says what is being dropped, and for an epic that its integration branch is going away, so any PR of theirs needs a new target. A parent that is someone else's is not dropped: report that and stop.
3. **Confirm once.** Show the list with the marks and ask with the question tool: 지우기 / 그만두기. Any other answer the user types is followed. Ask nothing further.
4. **Remove, in this order.**
   - Close open PRs first (`gh pr close <pr> --comment <why>`), so that deleting a base branch retargets nothing.
   - Close issues with `gh issue close <issue> --reason "not planned" --comment <why>` and take off their `status:*` labels. Use the reason the user gave, or say none was given.
   - Post the planned comments.
   - When the main checkout is on a branch going away, switch it to the integration branch for a child or the default branch for an epic (`git switch --discard-changes <branch>`, since the user saw the mark). Untracked files stay in that folder: name them in the report.
   - Delete each branch with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh remove <branch> --delete-branch --discard`, adding `--outside` for a worktree outside `.logbook/worktrees/`, then `git push origin --delete <branch>` when it is on the remote.
   - The worktree this session runs in goes last, after the report, as `/debrief` does.
5. **Report** what went, and post to Slack as below.

`--discard` is for this path only. Everywhere else the exit codes 3 and 4 of `worktree.sh` stop the run. Run it from the main checkout. When it still fails (a locked worktree, a branch git will not delete), leave that branch on the remote too, report its message and go on with the rest; never remove it by other means.

## Slack

An epic has one thread, the parent's; a child never opens its own. Post a child's news with `${CLAUDE_PLUGIN_ROOT}/scripts/slack.sh post <parent> part --text <file> [--file <path>...]`, the first line naming the child (`#13 ...`), in the plain words of `templates/planner.md`:

- a child's screen mockup before it is approved, with its PNGs;
- a merged child: what it now does, plus the direct commits made since the previous child merged;
- a dropped child: that it was dropped and why.

A child never calls `slack.sh` with its own number, since that would open a thread: every other post the usual steps name for it (`design`, `brief`, `approve`, `wave`, `check`, `pr`, `debrief`, `close`, `feedback`) is skipped, and instructions the user gave go into its next `part` post.

Read `slack.sh replies <parent>` where the usual steps read replies, and answer a question from the thread with `slack.sh post <parent> feedback`. Say which child each reply is about. A change of direction for a child other than the current one becomes a comment on that child's issue. The parent's own thread gets `pr`, `debrief` and `close` from `/epic-finish` and `/debrief`, or `close --outcome dropped` when the epic is dropped.
