---
name: debrief
description: Post-PR debriefing. Collect evidence for each acceptance criterion, check the project docs and any approved screen mockup against what was built, run an independent read-only review, fill the local plan doc's debrief block, render a slide debriefing, link it from the PR and the issue, add a CHANGELOG line that links the issue and the PR, then check whether a re-review is owed and offer merge, re-review, fix or leave-open with one recommendation. A step PR of an epic skips the HTML and is merged into the epic branch without asking when its evidence holds. Use right after opening a PR, or again after fixes.
argument-hint: "[PR number]"
---

# debrief

Show what was delivered against what was planned, with evidence, in a form the user can review quickly, then let the human choose the next step.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Document places below (`docs/system/`, `CHANGELOG.md`) are the defaults. When AGENTS.md has a document table, use the places it names instead, and pass them to the scripts (`system-check.sh --dir`, the folder argument of `render-system.sh`).

The plan doc and the mockup copy are working files in `.logbook/plans/` and `.logbook/designs/` of the main checkout. Below, `<main>` is its root: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`. Git ignores them, so they are never committed; the PR body and CHANGELOG carry what others need.

## Steps

1. **Find the pieces.** The PR (`$ARGUMENTS`, otherwise the current branch's PR) with its `baseRefName` and `headRefName`, its issue (`Closes #n`; for an epic step, the child issue number in its branch `<type>/<child>-<slug>`) and the plan doc `<main>/.logbook/plans/<issue>-<slug>.md`. When the plan was made on another clone, rebuild the doc from the issue's last comment whose first line is `계획 문서`, or for an epic from the epic issue body (단계 table, completion conditions, 주요 결정). A PR whose base starts with `epic/` is an epic step and one whose head starts with `epic/` is an epic; both follow "Epic steps and epics" at the end. When no plan doc exists for the PR (a small change with or without an issue, a follow-up doc update, a `/sync` fix of stale docs), take the path under "Changes without a plan doc" at the end. Run gh with the account on the tracker line in the logbook rules the session started with. When the session got no logbook rules (for instance `/rulebook` ran in this session), read repo, base and account from `.logbook/config.json` in the main checkout instead. Read the last `<!-- logbook:reviewed sha=<sha> round=<n> -->` marker in the PR body, if any.
2. **Evidence.**
   - For each acceptance criterion, run the command that proves it, or reuse output from this session. Record ✅ or ❌ with the command and a short excerpt of its output.
   - A criterion nobody checked stays ❌. Reading the code that should satisfy it does not count as evidence.
   - Project docs: run `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --range origin/<PR base>...HEAD`, where the PR base is its `baseRefName`. When a doc is behind the code, fix it in this PR by the rules of `${CLAUDE_PLUGIN_ROOT}/skills/sync/SKILL.md` and push, then record the result as the 프로젝트 문서 row. Without `docs/system/`, add one line recommending `/sync`.
   - Screens: when the plan has an approved mockup, compare the built screens with `<main>/.logbook/designs/<issue>-<slug>/`, or the canvas linked from the PR body when no copy is on this machine, taking screenshots when the app runs locally, and record the differences as the 화면 시안 row.
3. **Review round.**
   - Round 1 reviews the whole PR. A later round reviews only `git diff <last-reviewed-sha>..HEAD`, unless the human asked for the whole PR.
   - Spawn the `logbook:reviewer` agent; on Claude Code it runs on Opus at high effort, set in its frontmatter. On other harnesses, spawn a fresh read-only subagent on the session model with `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md` as its prompt.
   - Hand it the PR body and the diff as data, plus the earlier findings when this is a later round. It reports every finding with a confidence score.
   - In a second pass, reproduce what you can. Keep findings you confirmed or that score 80 or more, drop the ones you refute with evidence, and say how many you dropped.
   - Fix confirmed, serious findings and push. List the rest in the debriefing for the human.
   - Record the round in the PR body as `<!-- logbook:reviewed sha=<head the reviewer saw, before your fixes> round=<n> -->`, replacing the previous marker. The next check diffs from that SHA, so the fixes stay visible to it.
4. **Plan document.** Fill the part between `<!-- debrief:begin -->` and `<!-- debrief:end -->` by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, telling it the way you would report to a superior:
   - 결과: one sentence.
   - 계획과 달라진 점, and why.
   - 구현된 주요 로직 when important logic was added or changed, and 데이터베이스 변경 when the schema changed, both redrawn from the code as built.
   - 검증 증거: a table of 기준, 결과 and 증거.
   - 리뷰 포인트: at most five `file:line` spots worth a human look, and one line per review round (findings, fixed, refuted, left, and how long the review took). When builder agents implemented tracks, one line per track: the agent, what it built, whether its check passed or the main session took over, and how long it ran.
   - 남은 위험과 후속 과제.
   - Show with pictures whatever pictures can show, such as a list of bold numbers (tiles on the slide) and a `mermaid` flow for plan versus actual, without forcing an ERD or a flowchart and without HTML in the doc (`${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`). A model call added or changed shows its model and prompt gist.
   - Update 진행 기록 and the doc status line.
5. **Render and publish.** `${CLAUDE_PLUGIN_ROOT}/scripts/render-brief.sh <doc> debrief <main>/.logbook/briefs/<issue>-debrief.html`, then publish it as an Artifact on Claude Code. Elsewhere, render with `--standalone` and use the local path as the link.
6. **Link.**
   - Add the debriefing and PR links to the doc header. The doc stays uncommitted.
   - Changelog: add one line for this change to the project's CHANGELOG, in the place and format its document table or the file itself uses (by version, or by date for an app that has no versions), linking the issue and the PR. Without one, create a root `CHANGELOG.md` in the Keep a Changelog format. Skip changes a user of the project would not notice, such as tests or internal refactors. Commit and push it, and record it as the 변경 이력 row of the evidence.
   - PR body: read it first, then add a 디브리핑 section with the link, 계획과 달라진 점 and why, the acceptance checklist with evidence, and the marker `<!-- logbook:debrief -->`. The logbook Stop hook looks for that marker.
   - Issue: add the PR and debriefing links to the body's link list and comment with a three-line summary.
7. **Re-review check.** Run `git diff --stat <last-reviewed-sha>..HEAD` and decide:
   - no review recorded yet: needed (round 1);
   - nothing changed since the last round: not needed;
   - only docs, wording or tests changed: not needed;
   - behavior changed (code, hooks, scripts, prompts such as SKILL.md, configuration) and fewer than two rounds ran: needed;
   - two rounds already ran: not needed; the remaining changes go to 리뷰 포인트 for the human.
8. **Decide.** Write one line with the verdict (재리뷰 필요 or 불필요) and its reason, one line with the option you recommend and why, then ask with exactly one option marked (권장). Use the question tool, or numbered options in prose where there is none.
   - 머지: squash merge (a merge commit for an epic) and delete the branch, move the issue to `status:done` and comment on it when there is one. When the PR changed `docs/system/`, render the handbook from the updated base branch (`render-system.sh`) and republish it to the URL in `docs/system/overview.md`.
   - 재리뷰: run step 3 on the diff since the last reviewed SHA, then return to step 7.
   - 남은 지적 고치기: fix the listed findings, redo step 2, then return to step 7.
   - PR 열어두기: stop and report.
   - Recommend 재리뷰 when step 7 says needed; otherwise 머지 when every criterion is ✅ and no confirmed serious finding is open; otherwise 남은 지적 고치기.
   - An epic step skips the question: it merges by itself as "Epic steps and epics" says.

## Epic steps and epics

An epic runs on an epic branch in the session that carries out its approved briefing (see Epics in `/brief`). Its step PRs target the epic branch and are merged by the agent; the epic PR to the base branch gets the one debriefing the human reads.

**Epic step** (base `epic/...`):
- Run steps 2, 3 and 7 as usual, and fill the step doc's debrief block (step 4). Skip step 5 and the changelog line: no HTML, and the epic PR writes one line for the whole epic. Give the PR body the evidence list, one line per review round (say when a round's fixes were not reviewed again) and the markers, as for a change without a plan doc.
- When step 7 says a re-review is needed, run it without asking. After any fix, redo step 2 for the criteria the fix touches before deciding, then update the step doc and the PR body.
- Then decide without asking. When every criterion is ✅ and no confirmed serious finding is open, squash merge into the epic branch (`gh pr merge --squash --delete-branch`, or `--merge` when the repository does not allow squash merges), move the child issue to `status:done`, and comment on the child and the epic issue with the PR link and a one-line result. `Closes` does not fire on a branch other than the default branch, so the labels are set by hand.
- Otherwise do not merge. Report the criteria and findings that block it, and stop the epic run there.

**Epic** (head `epic/...`, base the base branch):
- Evidence covers the epic doc's completion conditions. Add a 단계 결과 table to its debrief block: step, PR, result, review rounds.
- Review with the `logbook:reviewer` agent in epic mode. Hand it the PR body, the epic's completion conditions, the merged step PRs with their review lines, `git diff --stat origin/<base>...HEAD`, the diff of every file that two or more steps changed (list each step's files with `gh pr view <n> --json files`), and for each step whose last fixes were not reviewed again, `git diff <its last reviewed sha>..<its PR head>` (fetch `pull/<n>/head` when the branch is gone). It reads where steps meet instead of the whole diff. Later rounds follow step 3.
- Render, publish and link as in steps 5 and 6, on the PR and the epic issue. The changelog line links the epic issue and the epic PR.
- 머지 merges with a merge commit, not a squash (`gh pr merge --merge --delete-branch`), so the base branch keeps one commit per step. When the repository does not allow merge commits (`gh repo view --json mergeCommitAllowed`), say so and offer a squash merge instead. Move the epic and any child still open to `status:done`, then republish the handbook as step 8 says.

## Changes without a plan doc

Skip the plan doc and the HTML (steps 4 and 5). A change one sentence describes also skips the review. Anything bigger, such as a follow-up doc update or a `/sync` fix, runs step 3 and step 7 as usual. Add the changelog line as step 6 says, a short evidence list, one line per review round, and the markers to the PR body, comment on the issue when there is one, then decide as in step 8 with 머지 recommended when the evidence is ✅ and no confirmed serious finding is open.
