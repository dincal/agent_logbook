---
name: mission
description: Plan mode for /goal runs. Research, ask about every open choice that changes the user scenario, get the plan approved, get changed screens approved as mockups, then hand back a ready-to-run /goal prompt together with its briefing. Use when the user wants Claude to work unattended toward a goal, an issue or an epic.
argument-hint: "[goal | #issue | #epic]"
---

# mission

Prepare an unattended `/goal` run the way plan mode prepares an edit: read-only research, questions where the user scenario is open, an approved plan and approved screens, then a goal prompt. This skill does not implement anything.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## Steps

1. **Enter plan mode.** On Claude Code, call `EnterPlanMode` unless the session is already in plan mode. On harnesses without plan mode, stay read-only and ask for approval at step 3.
2. **Research and questions.** When given an issue, read its comments first: follow-up work deferred to it belongs in this plan. Follow steps 2 and 3 of `${CLAUDE_PLUGIN_ROOT}/skills/brief/SKILL.md`. An unattended run cannot ask, so settle every choice that changes the user scenario now.
3. **Plan.** Write the plan in the `${CLAUDE_PLUGIN_ROOT}/templates/plan.md` format, brief block included, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md` and `${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`. List the screens to mock up when the change has any, and put the draft goal prompt in its `## Goal` section. Submit it with `ExitPlanMode`; the logbook hook opens the briefing in the browser.
4. **After approval.**
   - Create or update the issue (`status:todo`) with gh, using the account on the AGENTS.md tracker line.
   - Move the plan file to `docs/plans/<issue>-<slug>.md`, create the work branch, commit the doc there and push.
   - When the plan has screens, run step 4 (screen mockup) of `/brief` now. The approved copy in `docs/designs/<issue>-<slug>/` is committed with the plan doc.
   - Render, publish and link the briefing (steps 7 and 8 of `/brief`).
5. **Goal prompt.** Fill `${CLAUDE_PLUGIN_ROOT}/templates/goal.md`.
   - Objective: the issue, the plan doc path and the branch.
   - Numbered done conditions. Each names the command or observation that proves it and says to show its output in the conversation; the /goal evaluator reads only the transcript and cannot open files.
   - Last condition: an open PR whose body has `Closes #<issue>`, the acceptance checklist with evidence, the debriefing link and `<!-- logbook:debrief -->`, plus a filled debrief block in the plan doc.
   - Constraints: no commits on the base branch; tests are not weakened or deleted; stop and explain before an unplanned schema change or data deletion; record deviations in the plan's decision log; update `docs/system/` in the same PR when the change alters what it describes; screens follow the approved copy, and a screen change without one stops the run with an explanation.
   - One line per turn listing the remaining condition numbers, and a turn cap (40 by default, 60 for large work).
   - Check the length with `wc -m`. The goal text stays within 4,000 characters, so detail belongs in the plan doc, not in the prompt.
6. **Output.** The briefing link, then a single code block that starts with `/goal `. Say that running it is the approval, and that it works best in a fresh session opened in the repository.

## Epics

- Write one goal per child issue, in dependency order. Each child gets its own branch, PR and debriefing.
- When the user wants the children run back to back, also give a shell loop that calls `claude -p "/goal …" --permission-mode auto` per child and pipes the output through `tee` into `~/.agent_shell_logs/<project>/`. Screens are mocked up and approved before the loop starts; headless runs cannot publish canvases.

## Codex

The same text works with Codex `/goal`. Codex lets the working model declare completion itself, so tie every condition to printed evidence.
