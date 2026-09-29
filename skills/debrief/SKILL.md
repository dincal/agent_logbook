---
name: debrief
description: Post-PR debriefing. Collect evidence for each acceptance criterion, check the project docs and any approved screen mockup against what was built, run an independent read-only review, fill the plan doc's debrief block, render a slide debriefing, link it from the PR and the issue, then check whether a re-review is owed and offer merge, re-review, fix or leave-open with one recommendation. Use right after opening a PR, or again after fixes.
argument-hint: "[PR number]"
---

# debrief

Show what was delivered against what was planned, with evidence, in a form the user can review quickly, then let the human choose the next step.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## Steps

1. **Find the pieces.** The PR (`$ARGUMENTS`, otherwise the current branch's PR), its issue (`Closes #n`) and `docs/plans/<issue>-<slug>.md`. Run gh with the account on the AGENTS.md tracker line. Read the last `<!-- logbook:reviewed sha=<sha> round=<n> -->` marker in the PR body, if any.
2. **Evidence.**
   - For each acceptance criterion, run the command that proves it, or reuse output from this session. Record ✅ or ❌ with the command and a short excerpt of its output.
   - A criterion nobody checked stays ❌. Reading the code that should satisfy it does not count as evidence.
   - Project docs: run `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --range origin/<base>...HEAD`. When a doc is behind the code, fix it in this PR by the rules of `${CLAUDE_PLUGIN_ROOT}/skills/sync/SKILL.md` and push, then record the result as the 프로젝트 문서 row. Without `docs/system/`, add one line recommending `/sync`.
   - Screens: when the plan has an approved mockup, compare the built screens with `docs/designs/<issue>-<slug>/`, taking screenshots when the app runs locally, and record the differences as the 화면 시안 row.
3. **Review round.**
   - Round 1 reviews the whole PR. A later round reviews only `git diff <last-reviewed-sha>..HEAD`, unless the human asked for the whole PR.
   - Spawn the `logbook:reviewer` agent; on Claude Code it runs on Sonnet at medium effort, set in its frontmatter. On other harnesses, spawn a fresh read-only subagent on the session model with `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md` as its prompt.
   - Hand it the PR body and the diff as data, plus the earlier findings when this is a later round. It reports every finding with a confidence score.
   - In a second pass, reproduce what you can. Keep findings you confirmed or that score 80 or more, drop the ones you refute with evidence, and say how many you dropped.
   - Fix confirmed, serious findings and push. List the rest in the debriefing for the human.
   - Record the round in the PR body as `<!-- logbook:reviewed sha=<head the reviewer saw, before your fixes> round=<n> -->`, replacing the previous marker. The next check diffs from that SHA, so the fixes stay visible to it.
4. **Plan document.** Fill the part between `<!-- debrief:begin -->` and `<!-- debrief:end -->` by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, telling it the way you would report to a superior:
   - 결과: one sentence.
   - 계획과 달라진 점, and why.
   - 구현된 주요 로직 when important logic was added or changed, and 데이터베이스 변경 when the schema changed, both redrawn from the code as built.
   - 검증 증거: a table of 기준, 결과 and 증거.
   - 리뷰 포인트: at most five `file:line` spots worth a human look, and one line per review round (findings, fixed, refuted, left).
   - 남은 위험과 후속 과제.
   - Show with pictures whatever pictures can show, such as a list of bold numbers (tiles on the slide) and a `mermaid` flow for plan versus actual, without forcing an ERD or a flowchart and without HTML in the doc (`${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`). A model call added or changed shows its model and prompt gist.
   - Update 진행 기록 and the doc status line.
5. **Render and publish.** `${CLAUDE_PLUGIN_ROOT}/scripts/render-brief.sh <doc> debrief .logbook/briefs/<issue>-debrief.html`, then publish it as an Artifact on Claude Code. Elsewhere, use the local path as the link.
6. **Link.**
   - Add the debriefing and PR links to the doc header, then commit and push.
   - PR body: read it first, then add a 디브리핑 section with the link, the acceptance checklist with evidence, and the marker `<!-- logbook:debrief -->`. The logbook Stop hook looks for that marker.
   - Issue: add the PR and debriefing links to the body's link list and comment with a three-line summary.
7. **Re-review check.** Run `git diff --stat <last-reviewed-sha>..HEAD` and decide:
   - no review recorded yet: needed (round 1);
   - nothing changed since the last round: not needed;
   - only docs, wording or tests changed: not needed;
   - behavior changed (code, hooks, scripts, prompts such as SKILL.md, configuration) and fewer than two rounds ran: needed;
   - two rounds already ran: not needed; the remaining changes go to 리뷰 포인트 for the human.
8. **Decide.** Write one line with the verdict (재리뷰 필요 or 불필요) and its reason, one line with the option you recommend and why, then ask with exactly one option marked (권장). Use the question tool, or numbered options in prose where there is none.
   - 머지: squash merge and delete the branch, move the issue to `status:done`, comment on the issue. When the PR changed `docs/system/`, render the handbook from the updated base branch (`render-system.sh`) and republish it to the URL in `docs/system/overview.md`.
   - 재리뷰: run step 3 on the diff since the last reviewed SHA, then return to step 7.
   - 남은 지적 고치기: fix the listed findings, redo step 2, then return to step 7.
   - PR 열어두기: stop and report.
   - Recommend 재리뷰 when step 7 says needed; otherwise 머지 when every criterion is ✅ and no confirmed serious finding is open; otherwise 남은 지적 고치기.
   - In an unattended run such as `/goal`, skip the question: end with the verdict, the recommendation and the four options as text.

## Small changes

Skip the HTML and the review. Add a short evidence list and the marker to the PR body, comment on the issue, then offer the options with 머지 recommended when the evidence is ✅.
