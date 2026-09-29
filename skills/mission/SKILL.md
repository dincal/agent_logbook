---
name: mission
description: Plan mode for /goal runs. Research, ask about every open choice that changes the user scenario, get the plan approved, get changed screens approved as mockups, then hand back a ready-to-run /goal prompt together with its briefing. Use when the user wants Claude to work unattended toward a goal, an issue or an epic; an epic runs step by step on an epic branch in one session.
argument-hint: "[goal | #issue | #epic]"
---

# mission

Prepare an unattended `/goal` run the way plan mode prepares an edit: read-only research, questions where the user scenario is open, an approved plan and approved screens, then a goal prompt. This skill does not implement anything.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## Steps

1. **Enter plan mode.** On Claude Code, call `EnterPlanMode` unless the session is already in plan mode. On harnesses without plan mode, stay read-only and ask for approval at step 3.
2. **Research and questions.** When given an issue, read its comments first: follow-up work deferred to it belongs in this plan. Follow steps 2 and 3 of `${CLAUDE_PLUGIN_ROOT}/skills/brief/SKILL.md`, launching research as `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. An unattended run cannot ask, so settle every choice that changes the user scenario now.
3. **Plan.** Write the plan in the `${CLAUDE_PLUGIN_ROOT}/templates/plan.md` format, brief block included, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md` and `${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`. List the screens to mock up when the change has any, and put the draft goal prompt in its `## Goal` section. Submit it with `ExitPlanMode`; the logbook hook opens the briefing in the browser.
4. **After approval.**
   - Create or update the issue (`status:todo`) with gh, using the account on the AGENTS.md tracker line.
   - Move the plan file to `docs/plans/<issue>-<slug>.md`, create the work branch (the epic branch for an epic, see below), commit the doc there and push.
   - When the plan has screens, run step 4 (screen mockup) of `/brief` now. The approved copy in `docs/designs/<issue>-<slug>/` is committed with the plan doc.
   - Render, publish and link the briefing (steps 7 and 8 of `/brief`).
5. **Goal prompt.** Fill the first form of `${CLAUDE_PLUGIN_ROOT}/templates/goal.md`; an epic uses its second form (see Epics).
   - Objective: the issue, the plan doc path and the branch.
   - Numbered done conditions. Each names the command or observation that proves it and says to show its output in the conversation; the /goal evaluator reads only the transcript and cannot open files.
   - Last condition: an open PR whose body has `Closes #<issue>`, the acceptance checklist with evidence, the debriefing link and `<!-- logbook:debrief -->`, plus a filled debrief block in the plan doc.
   - Constraints: no commits on the base branch; when the plan splits implementation into tracks, launch them as `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says; tests are not weakened or deleted; stop and explain before an unplanned schema change or data deletion; record deviations in the plan's decision log; update `docs/system/` in the same PR when the change alters what it describes; screens follow the approved copy, and a screen change without one stops the run with an explanation.
   - One line per turn listing the remaining condition numbers, and a turn cap (40 by default, 60 for large work).
   - Check the length with `wc -m`. The goal text stays within 4,000 characters, so detail belongs in the plan doc, not in the prompt.
6. **Output.** The briefing link, then a single code block that starts with `/goal `. Say that running it is the approval, and that it works best in a fresh session opened in the repository.

## Epics

An epic is an issue labelled `epic` whose child issues are its steps. One `/goal` session runs the whole epic, step after step, on an epic branch; the human approves the epic briefing at the start and reads the epic debriefing at the end.

- **Plan.** The epic doc `docs/plans/<epic>-<slug>.md` carries the 단계 section of `${CLAUDE_PLUGIN_ROOT}/templates/plan.md` (order, child issue, branch, the steps it waits for, what it delivers) and the epic's own completion conditions. Each step also gets `docs/plans/<child>-<slug>.md` with its own completion conditions, written for the agent that implements it. Write the step docs after approval, once the child issues exist; they detail what the approved epic doc already says and add no new decisions. Only the epic doc is rendered and published; step docs get no HTML. In plan mode the table names steps without numbers; after approval create the missing child issues in `status:todo` and write their numbers and branches into the table before committing.
- **Branches.** After approval, create `epic/<epic>-<slug>` from the base branch, commit every plan doc there and push it. Each step branch `<type>/<child>-<slug>` is cut from the latest epic branch, and its PR targets the epic branch.
- **Goal.** Write one goal for the whole epic from the epic part of `${CLAUDE_PLUGIN_ROOT}/templates/goal.md`, with the steps in the order of the 단계 table. Per step it:
  - fetches, brings the local epic branch up to its remote, merges the base branch into it when the base is ahead, and stops on a conflict it cannot resolve;
  - implements the step from its plan doc, opens the PR against the epic branch with `Part of #<epic>` and the child issue number (the step branch is `<type>/<child>-<slug>`), and runs `/debrief`, whose step path merges the PR into the epic branch or stops the run with the reason.
- After the last step it opens the epic PR from the epic branch to the base branch with `Closes` for the epic and every child, and runs `/debrief` on it. The run ends there; the human picks the merge.
- Done conditions: each step merged into the epic branch with its child issue in `status:done` (`gh pr list --base epic/<epic>-<slug> --state merged`), and the epic PR open with the debriefing link and `<!-- logbook:debrief -->`, plus a filled debrief block in the epic doc.
- Constraints add: commit to the epic branch only through merged step PRs, base-branch merges, plan-doc updates and the doc and review fixes `/debrief` makes on the epic PR; stop at the first step that cannot be merged.
- Screens of every step are mocked up and approved before the run starts.

## Codex

The same text works with Codex `/goal`. Codex lets the working model declare completion itself, so tie every condition to printed evidence.
