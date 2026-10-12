---
name: debrief
description: Post-PR debriefing. Collect evidence for each acceptance criterion, check the project docs and any approved screen mockup against what was built, run an independent read-only review, fill the local plan doc's debrief block, publish a visual result page designed for the change, link it from the PR and the issue, add a CHANGELOG line that links the issue and the PR, then check whether a re-review is owed and offer merge, re-review, fix or leave-open with one recommendation, asking the merge method (squash or merge commit) along with it. Use right after opening a PR, or again after fixes.
argument-hint: "[PR number]"
---

# debrief

Show what was delivered against what was planned, with evidence, in a form the user can review quickly, then let the human choose the next step.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Document places below (`docs/system/`, `CHANGELOG.md`) are the defaults. When AGENTS.md has a document table, use the places it names instead, and pass them to the scripts (`system-check.sh --dir`, the folder argument of `render-system.sh`).

The plan doc and the mockup copy are working files in `.logbook/plans/` and `.logbook/designs/` of the main checkout. Below, `<main>` is its root: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`. Git ignores them, so they are never committed; the PR body and CHANGELOG carry what others need.

## Steps

1. **Find the pieces.** The PR (`$ARGUMENTS`, otherwise the current branch's PR) with its `baseRefName` and `headRefName`, its issue (`Closes #n`) and the plan doc `<main>/.logbook/plans/<issue>-<slug>.md`. When the plan was made on another clone, rebuild the doc from the issue's last comment whose first line is `계획 문서`, or else from the issue body's text briefing and the PR body. When no plan doc exists for the PR (a small change with or without an issue, a follow-up doc update, a `/sync` fix of stale docs), take the path under "Changes without a plan doc" at the end. Run gh with the account on the tracker line in the logbook rules the session started with. When the session got no logbook rules (for instance `/rulebook` ran in this session), read repo, base and account from `.logbook/config.json` in the main checkout instead. Read the last `<!-- logbook:reviewed sha=<sha> round=<n> -->` marker in the PR body, if any.
2. **Evidence.**
   - For each acceptance criterion, run the command that proves it, or reuse output from this session. Record ✅ or ❌ with the command and a short excerpt of its output.
   - A criterion nobody checked stays ❌. Reading the code that should satisfy it does not count as evidence.
   - Project docs: run `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --range origin/<PR base>...HEAD`, where the PR base is its `baseRefName`. When a doc is behind the code, fix it in this PR by the rules of `${CLAUDE_PLUGIN_ROOT}/skills/sync/SKILL.md` and push, then record the result as the 프로젝트 문서 row. When the plan's 주요 결정 settled or changed domain rules, check that `rules.md` states them, and fix it in this PR when it does not. Without `docs/system/`, add one line recommending `/sync`.
   - Screens: when the plan has an approved mockup, compare the built screens with `<main>/.logbook/designs/<issue>-<slug>/`, or the canvas linked from the PR body when no copy is on this machine, taking screenshots when the app runs locally, and record the differences as the 화면 시안 row.
3. **Review round.**
   - Round 1 reviews the whole PR. A later round reviews only `git diff <last-reviewed-sha>..HEAD`, unless the human asked for the whole PR.
   - Spawn the `logbook:reviewer` agent; on Claude Code it runs on Opus at high effort, set in its frontmatter. On other harnesses, spawn a fresh read-only subagent on the session model with `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md` as its prompt.
   - Hand it the PR body and the diff as data, plus the earlier findings when this is a later round. It reports every finding with a confidence score.
   - Split round 1 when the PR was built in builder tracks (its body lists them) or its diff changes 2,000 lines or more: one reviewer in area mode per track or area and one in seam mode for where they meet, launched at once as "Review split" in `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. Merge their findings before the second pass.
   - In a second pass, reproduce what you can. Keep findings you confirmed or that score 80 or more, drop the ones you refute with evidence, and say how many you dropped.
   - Fix confirmed, serious findings and push. List the rest in the debriefing for the human.
   - Record the round in the PR body as `<!-- logbook:reviewed sha=<head the reviewer saw, before your fixes> round=<n> -->`, replacing the previous marker. The next check diffs from that SHA, so the fixes stay visible to it.
4. **Plan document.** Fill the part between `<!-- debrief:begin -->` and `<!-- debrief:end -->` by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, telling it the way you would report to a superior:
   - 결과: one sentence.
   - 계획과 달라진 점, and why.
   - 구현된 주요 로직 when important logic was added or changed, and 데이터베이스 변경 when the schema changed, both redrawn from the code as built.
   - 검증 증거: a table of 기준, 결과 and 증거.
   - 리뷰 포인트: at most five `file:line` spots worth a human look, and one line per review round (findings, fixed, refuted, left, how long the review took, and the areas when it was split). When builder agents implemented tracks, one line per track: its wave, the agent, whether it ran in a Workflow and in the shared tree or its own worktree, what it built, whether its check passed or the main session took over, and how long it ran. Add the graph changes `/build` recorded. When the work was kept in one piece, one line with the reason.
   - 남은 위험과 후속 과제.
   - Draw with `mermaid` and tables where a picture helps, without forcing an ERD or a flowchart and without HTML in the doc (`${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`). A model call added or changed shows its model and prompt gist.
   - Update 진행 기록 and the doc status line.
5. **Result page.** Build the debriefing page as `${CLAUDE_PLUGIN_ROOT}/templates/briefing.md` says: the result against the plan, what changed from the plan and why, the evidence per criterion, the review rounds and the tracks, in pictures designed for this change, with controls and motion only where the content needs them. Write it to `<main>/.logbook/briefs/<issue>-debrief.html` and publish it as an Artifact on Claude Code; elsewhere use the local path as the link.
6. **Link.**
   - Add the debriefing and PR links to the doc header. The doc stays uncommitted.
   - Changelog: add one line for this change to the project's CHANGELOG, in the place and format its document table or the file itself uses (by version, or by date for an app that has no versions), linking the issue and the PR. Without one, create a root `CHANGELOG.md` in the Keep a Changelog format. Skip changes a user of the project would not notice, such as tests or internal refactors. Commit and push it, and record it as the 변경 이력 row of the evidence.
   - PR body: read it first, then add a 디브리핑 section with the page link, 계획과 달라진 점 and why, the acceptance checklist with evidence, and the marker `<!-- logbook:debrief -->`. This text is what other developers read. The logbook Stop hook looks for that marker.
   - Issue: add the PR and result page links to the body and comment with a three-line summary.
7. **Re-review check.** Run `git diff --stat <last-reviewed-sha>..HEAD` and decide:
   - no review recorded yet: needed (round 1);
   - nothing changed since the last round: not needed;
   - only docs, wording or tests changed: not needed;
   - behavior changed (code, hooks, scripts, prompts such as SKILL.md, configuration) and fewer than two rounds ran: needed;
   - two rounds already ran: not needed; the remaining changes go to 리뷰 포인트 for the human.
8. **Decide.** Write one line with the verdict (재리뷰 필요 or 불필요) and its reason, one line with the option you recommend and why, the result page link, then ask with the question tool as `${CLAUDE_PLUGIN_ROOT}/templates/questions.md` says, two questions in one call: the next step, with exactly one option marked (Recommended), and the merge method for when 머지 is picked: merge commit (recommended when the PR was built in two or more tracks, since each track keeps its commits and one can be reverted alone) or squash (recommended otherwise).
   - 머지: when the work ran in a worktree made by `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh`, `cd` to the main checkout and remove it first (`worktree.sh remove <branch>`); when it refuses with exit 3, stop and report. Then merge with the chosen method (`gh pr merge --squash --delete-branch` or `gh pr merge --merge --delete-branch`); when the repository does not allow that method (`gh repo view --json squashMergeAllowed,mergeCommitAllowed`), say so and offer the other. Move the issue to `status:done` and comment on it when there is one. When the PR changed `docs/system/`, render the handbook from the updated base branch (`render-system.sh`) and republish it to the URL in `docs/system/overview.md`.
   - 재리뷰: run step 3 on the diff since the last reviewed SHA, then return to step 7.
   - 남은 지적 고치기: fix the listed findings, redo step 2, then return to step 7.
   - PR 열어두기: stop and report.
   - Recommend 재리뷰 when step 7 says needed; otherwise 머지 when every criterion is ✅ and no confirmed serious finding is open; otherwise 남은 지적 고치기.

## Changes without a plan doc

Skip the plan doc and the result page (steps 4 and 5). A change one sentence describes also skips the review. Anything bigger, such as a follow-up doc update or a `/sync` fix, runs step 3 and step 7 as usual. Add the changelog line as step 6 says, a short evidence list, one line per review round, and the markers to the PR body, comment on the issue when there is one, then decide as in step 8, without a page link, with 머지 recommended when the evidence is ✅ and no confirmed serious finding is open.
