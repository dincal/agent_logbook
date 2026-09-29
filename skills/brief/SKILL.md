---
name: brief
description: Pre-implementation briefing for any change bigger than a one-sentence fix. Research the code and sources, ask about every open choice that changes the user scenario, mock up changed screens and get them approved, write docs/plans/<issue>-<slug>.md, render a slide briefing told the way one briefs a superior, link it from the GitHub issue, and wait for approval. Use before editing code for a walk-in request, and right after a plan-mode plan is approved.
argument-hint: "[request or #issue]"
---

# brief

Turn a request into a plan the user approved, with a briefing they can review in two minutes. The user decides everything that changes how they will work; you decide the rest and say so.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## When to skip

A change that one sentence fully describes (a typo, a rename, a small config tweak) gets no briefing. Create or reuse the issue and a branch, implement, open the PR, and let `/debrief` add the short evidence list.

## Steps

1. **Issue and branch.**
   - Use the issue number in `$ARGUMENTS` when given. Otherwise create one labelled `status:todo` in the repo named on the AGENTS.md tracker line.
   - Run gh with the account on that line: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without an account there, use the default login.
   - Slug: a short kebab-case summary. Branch: `<type>/<issue>-<slug>` (feat, fix, refactor, docs or chore), cut from the base branch.
2. **Research.**
   - Start from `docs/system/` when it exists; it describes the system as it is. Note which of those docs the change will alter.
   - Code: send parallel Explore subagents to areas that do not depend on each other (on Claude Code, pass `model: sonnet`: they read and report, and you check their findings), and read the files the change touches yourself.
   - Sources: search the web, or run `/deep-research`, when the change brings a new library, an external API or an unfamiliar pattern.
   - Keep evidence as `file:line` references and links.
3. **Questions.**
   - Ask about every choice the request leaves open that changes the user scenario: what a command does, the steps the user goes through, what they approve and when, what happens to their files and data. Do not settle such a choice yourself, even when you have a good default.
   - Skip trivial things: wording, internal implementation, choices with one sensible answer. Decide those yourself and list them in the briefing as your own calls.
   - Ask 1 to 4 questions at a time, each with options and a recommended default, and ask again in further rounds when answers open new choices. Use the question tool, or numbered options in prose where there is none.
   - When an answer or instruction looks unreasonable against the evidence (it contradicts what research found, costs far more than it gains, carries a risk the user may not have seen, or works against their own stated goal), say so once before acting: the concern, the evidence, and a better option. If they keep it, follow it and list it under 주요 결정 as 알린 우려. Leave matters of taste and weak worries alone, and say plainly when nothing looked unreasonable.
4. **Screen mockup.** When the change adds a screen or visibly reshapes one:
   - On Claude Code with artifacts, draft a Design canvas, the same canvas `/design` makes: `Artifact` quickstart with intent `design`, then create one from the Design type. Draw one artboard per screen and state (default, empty, error), after reading the project's design tokens and components.
   - Elsewhere, write a static HTML mockup to `docs/designs/<issue>-<slug>/index.html` and open it in the browser.
   - Ask 승인 / 고쳐 달라 / 시안 없이 진행 / 중단. On a change request, read the canvas again first (the user may have edited it), apply the feedback, republish to the same URL and ask again.
   - After approval, read the canvas back and save `project/canvas.json` and the `project/*.dc.html` artboards to `docs/designs/<issue>-<slug>/`. Implementation follows that copy.
5. **Plan document.**
   - Write `docs/plans/<issue>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`.
   - The part between `<!-- brief:begin -->` and `<!-- brief:end -->` becomes the slides. Tell it the way you would brief a superior, conclusion and request first: 요약, 배경, what you will do (as many slides as it needs), 주요 결정, 위험과 판단 필요, 일정과 검증, in 5 to 9 slides. Add 주요 로직 흐름 when important logic is added or changed, 데이터베이스 변경 when the schema changes, and 화면 시안 when step 4 ran.
   - The first paragraph of each section is that slide's headline: one sentence that states the conclusion.
   - 주요 결정 separates what the user decided, with the alternatives they rejected, from your own calls.
   - Close with `> 판단 필요: 없음`, or at most two items only the human can decide: irreversible choices, product direction, scope.
   - Every acceptance criterion names the command or observation that proves it. When the change alters what `docs/system/` describes, name those docs and add a criterion proved by `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --range <base>...HEAD`.
   - Details that do not fit the slides go under `## 상세`.
6. **Pictures.** Follow `${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`:
   - Show with a picture whatever content a picture can show. The plan doc holds no HTML: draw with `mermaid`, write numbers as a list of bold numbers (the slides show them as tiles), and compare with tables. No quota either way.
   - When the change adds or alters a call to an LLM or another AI model, its picture names the model and gives the gist of the prompt: what goes in, what the model is asked, what comes back.
   - Never force an ERD or a flowchart. An ERD holds database tables only; a flowchart shows logic that matters to the reader.
   - Always include the main logic flow the change adds or alters, and an ERD of any database schema change.
7. **Render and publish.**
   - `${CLAUDE_PLUGIN_ROOT}/scripts/render-brief.sh docs/plans/<issue>-<slug>.md brief .logbook/briefs/<issue>-brief.html`
   - On Claude Code, publish that file as an Artifact and keep the link. Where publishing is unavailable, use the local file path as the link.
8. **Link.**
   - Put the briefing link and the doc link in the doc header and in the issue body's link list. Read the body first; an edit replaces it whole.
   - Comment on the issue with a three-line summary, the briefing link and the 판단 필요 items.
   - Commit the plan doc on the work branch and push it.
9. **Approval.**
   - Walk-in request: ask "진행 / 수정 / 중단" and wait. Once approved, move the issue to `status:in-progress` and implement, splitting the work into parallel builder tracks only where the AGENTS.md rule says it pays.
   - Right after a plan-mode approval: move the issue to `status:in-progress` and implement.
   - Called by `/mission`: stop after step 8 and hand back. Do not implement, and leave the issue in `status:todo`; the `/goal` run moves it.
   - Called by `/sync`: ask as for a walk-in request, then hand back to `/sync`, which carries out the approved plan.

## Plan mode

- Write the plan file itself in the plan.md format, brief block included. The logbook hook renders it in the browser when the approval screen appears, and denies a plan without a complete block.
- For a one-sentence change, put a `<!-- brief:skip -->` line in the plan instead.
- Plan mode is read-only, so step 4 cannot run there; list the screens to mock up in the plan. After approval and before editing code: do step 1 if the issue or branch does not exist yet, run step 4 when the plan has screens, move the plan file to `docs/plans/<issue>-<slug>.md`, then do steps 7 and 8.

## Language

Write the doc, the briefing, and the issue and PR text by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
