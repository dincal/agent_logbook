---
name: brief
description: Pre-implementation briefing for any change bigger than a one-sentence fix. Research the code and sources, ask only about genuinely ambiguous intent, decide the spec, write docs/plans/<issue>-<slug>.md, render a CTO-style briefing HTML, link it from the GitHub issue, and wait for approval. Use before editing code for a walk-in request, and right after a plan-mode plan is approved.
argument-hint: "[request or #issue]"
---

# brief

Turn a request into a decided plan and a briefing a CTO can review in two minutes. You make the technical decisions; the human approves the start.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## When to skip

A change that one sentence fully describes (a typo, a rename, a small config tweak) gets no briefing. Create or reuse the issue and a branch, implement, open the PR, and let `/debrief` add the short evidence list.

## Steps

1. **Issue and branch.**
   - Use the issue number in `$ARGUMENTS` when given. Otherwise create one labelled `status:todo` in the repo named on the AGENTS.md tracker line.
   - Run gh with the account on that line: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without an account there, use the default login.
   - Slug: a short kebab-case summary. Branch: `<type>/<issue>-<slug>` (feat, fix, refactor, docs or chore), cut from the base branch.
2. **Research.**
   - Code: send parallel Explore subagents to areas that do not depend on each other, and read the files the change touches yourself.
   - Sources: search the web, or run `/deep-research`, when the change brings a new library, an external API or an unfamiliar pattern.
   - Keep evidence as `file:line` references and links.
3. **Ambiguity.**
   - Ask only when the request reads more than one way, the readings lead to different results, and research could not settle it.
   - Ask 1 to 3 questions at once, each with options and a recommended default. Use the question tool, or numbered options in prose where there is none.
   - Decide technical choices yourself and record them as assumptions (가정).
4. **Plan document.**
   - Write `docs/plans/<issue>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`.
   - The part between `<!-- brief:begin -->` and `<!-- brief:end -->` becomes the slides: 6 to 8 `##` sections covering 요약, 왜, 주요 로직 흐름, 데이터 모델 변화, 주요 결정, 리스크와 판단 필요, 실행과 검증.
   - The first paragraph of each section is that slide's headline: one sentence that states the conclusion.
   - Each decision names the rejected alternative and the reason. Mark agent-made choices as 가정.
   - Close with `> 판단 필요: 없음`, or at most two items only the human can decide: irreversible choices, product direction, scope.
   - Every acceptance criterion names the command or observation that proves it.
   - Details that do not fit the slides go under `## 상세`.
5. **Diagrams.** Two pictures are required; give the other slides one picture each where it helps (`${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`):
   - 주요 로직 흐름: a Mermaid flowchart or sequence diagram of the main logic the change adds or alters, in domain steps and decisions rather than function names.
   - 데이터 모델 변화: a Mermaid `erDiagram` of only the entities and relations the change adds or alters, with the changed columns. When the data model does not change, the single line `> ERD 변화 없음: <reason>` instead.
   - Other slides: free-form fenced `html` or `svg` blocks such as number tiles, before and after tracks, comparisons, cards, or an SVG drawn for this change.
   - The plan-mode hook denies a plan missing either required picture, and the renderer warns about it.
6. **Render and publish.**
   - `${CLAUDE_PLUGIN_ROOT}/scripts/render-brief.sh docs/plans/<issue>-<slug>.md brief .logbook/briefs/<issue>-brief.html`
   - On Claude Code, publish that file as an Artifact and keep the link. Where publishing is unavailable, use the local file path as the link.
7. **Link.**
   - Put the briefing link and the doc link in the doc header and in the issue body's link list. Read the body first; an edit replaces it whole.
   - Comment on the issue with a three-line summary, the briefing link and the 판단 필요 items.
   - Commit the plan doc on the work branch and push it.
8. **Approval.**
   - Walk-in request: ask "진행 / 수정 / 중단" and wait. Once approved, move the issue to `status:in-progress` and implement.
   - Right after a plan-mode approval: move the issue to `status:in-progress` and implement.
   - Called by `/mission`: stop after step 7 and hand back to `/mission`. Do not implement, and leave the issue in `status:todo`; the `/goal` run moves it.

## Plan mode

- Write the plan file itself in the plan.md format, brief block included. The logbook hook renders it in the browser when the approval screen appears, and denies a plan without a complete block.
- For a one-sentence change, put a `<!-- brief:skip -->` line in the plan instead.
- After approval and before editing code: do step 1 if the issue or branch does not exist yet, move the plan file to `docs/plans/<issue>-<slug>.md`, then do steps 6 and 7.

## Language

Write the doc, the briefing, and the issue and PR text in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
