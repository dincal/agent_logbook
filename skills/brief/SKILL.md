---
name: brief
description: Pre-implementation briefing for any change bigger than a one-sentence fix, as one issue or as an epic with one child issue per step. Research the code and sources, ask about every open choice that changes the user scenario, mock up changed screens and get them approved, write the plan doc in the git-ignored .logbook/plans/, render a slide briefing told the way one briefs a superior, link it from the GitHub issue, and wait for approval. Once approved, carry the plan through to its PR, or through every step of an epic to the epic PR. Use before editing code for a walk-in request, and right after a plan-mode plan is approved.
argument-hint: "[request | #issue | #epic]"
---

# brief

Turn a request into a plan the user approved, with a briefing they can review in two minutes, then carry it out. The user decides everything that changes how they will work; you decide the rest and say so. After approval the user only cares that what the briefing settled gets done.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Document places below (`docs/system/`, `CHANGELOG.md`) are the defaults. When AGENTS.md has a document table, use the places it names instead, and pass them to the scripts (`system-check.sh --dir`, the folder argument of `render-system.sh`).

Plan docs and mockup copies are working files, not project documents. They live in `.logbook/plans/` and `.logbook/designs/` of the main checkout, which git ignores, and are never committed. Below, `<main>` is the root of the main checkout: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`. Writing there keeps them when the worktree is removed. What others need from them goes to GitHub: the reasons to the PR body, the result to CHANGELOG.

## When to skip

A change that one sentence fully describes (a typo, a rename, a small config tweak) gets no briefing and no issue, and so does a follow-up doc update with no related branch or issue to ride on. Cut a `<type>/<slug>` branch from the base branch, implement, open a PR without an issue, and let `/debrief` finish it. When `$ARGUMENTS` names an issue, keep it: read its comments as step 1 says, use `<type>/<issue>-<slug>` and put `Closes #<issue>` in the PR body.

## Steps

1. **Issue and branch.**
   - Use the issue number in `$ARGUMENTS` when given. Otherwise create one labelled `status:todo` in the repo named on the tracker line in the logbook rules the session started with (the SessionStart hook adds them from `.logbook/config.json`). When the session got no logbook rules (for instance `/rulebook` ran in this session), read repo, base and account from `.logbook/config.json` in the main checkout instead.
   - An issue given in `status:backlog` (one `/discuss` left for later, for instance) moves to `status:todo`. A plan set aside with 나중에 하기 in step 9 is picked up again: start from the local plan doc `<main>/.logbook/plans/<issue>-<slug>.md`, or else from the issue's last comment whose first line is `계획 문서`, saving it as that doc. Check out its branch when it exists on this clone or the remote; otherwise cut it.
   - Read the given issue's comments too: follow-up work deferred to this issue, such as a doc update, is left there as a comment and belongs in this change.
   - Run gh with the account on that line: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without an account there, use the default login.
   - Slug: a short kebab-case summary. Branch: `<type>/<issue>-<slug>` (feat, fix, refactor, docs or chore), cut from the base branch.
   - Work in the main checkout and switch branches there; an epic gets no git worktree either. When something makes the main checkout unfit (uncommitted changes, a service running from it, another session working there), say what and ask before making a worktree with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add`; then do as the user picks: the worktree, the main checkout, or stop.
   - Work that splits into steps is planned as an epic (see Epics below): label the issue `epic` and use the branch `epic/<issue>-<slug>` instead. When research shows the split only later, relabel the issue and rename the branch then.
   - An `epic` issue already in `status:in-progress` was approved before: resume its run as "Stops and resuming" under Epics says, instead of these steps.
2. **Research.**
   - Start from `docs/system/` when it exists; it describes the system as it is. Note which of those docs the change will alter.
   - Code: research areas that do not depend on each other in parallel, with Explore subagents on Sonnet or a Workflow as `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. They read and report, you check their findings, and you read the files the change touches yourself.
   - Sources: search the web, or run `/deep-research`, when the change brings a new library, an external API or an unfamiliar pattern.
   - Keep evidence as `file:line` references and links.
3. **Questions.**
   - Ask about every choice the request leaves open that changes the user scenario: what a command does, the steps the user goes through, what they approve and when, what happens to their files and data. Do not settle such a choice yourself, even when you have a good default.
   - Skip trivial things: wording, internal implementation, choices with one sensible answer. Decide those yourself and list them in the briefing as your own calls.
   - When `$ARGUMENTS` or the issue carries a `/discuss` summary, its decisions are the user's own: list them under 주요 결정 with the alternatives set aside, and ask only about what it leaves open.
   - Ask 1 to 4 questions at a time, each with options and a recommended default, and ask again in further rounds when answers open new choices. Use the question tool, or numbered options in prose where there is none.
   - When an answer or instruction looks unreasonable against the evidence (it contradicts what research found, costs far more than it gains, carries a risk the user may not have seen, or works against their own stated goal), say so once before acting: the concern, the evidence, and a better option. If they keep it, follow it and list it under 주요 결정 as 알린 우려. Leave matters of taste and weak worries alone, and say plainly when nothing looked unreasonable.
4. **Screen mockup.** When the change adds a screen or visibly reshapes one:
   - On Claude Code with artifacts, draft a Design canvas, the same canvas `/design` makes: `Artifact` quickstart with intent `design`, then create one from the Design type. Draw one artboard per screen and state (default, empty, error), after reading the project's design tokens and components.
   - Elsewhere, write a static HTML mockup to `<main>/.logbook/designs/<issue>-<slug>/index.html` and open it in the browser.
   - Ask 승인 / 고쳐 달라 / 시안 없이 진행 / 중단 (중단 is handled as in step 9). On a change request, read the canvas again first (the user may have edited it), apply the feedback, republish to the same URL and ask again.
   - After approval, read the canvas back and save `project/canvas.json` and the `project/*.dc.html` artboards to `<main>/.logbook/designs/<issue>-<slug>/`. Implementation follows that copy.
5. **Plan document.**
   - Write `<main>/.logbook/plans/<issue>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`.
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
   - `${CLAUDE_PLUGIN_ROOT}/scripts/render-brief.sh <main>/.logbook/plans/<issue>-<slug>.md brief <main>/.logbook/briefs/<issue>-brief.html`
   - On Claude Code, publish that file as an Artifact and keep the link. Where publishing is unavailable, render with `--standalone` (it adds a doctype) and use the local file path as the link.
8. **Link.**
   - Put the briefing link in the doc header and in the issue body's link list. Read the body first; an edit replaces it whole.
   - Comment on the issue with a three-line summary, the briefing link and the 판단 필요 items.
   - Do not commit the plan doc.
9. **Approval.**
   - Called by `/sync`: ask "진행 / 수정 / 중단" and wait, then hand back to `/sync`, which carries out the approved plan itself under the "While carrying it out" rules below.
   - Walk-in request: ask "진행 / 수정 / 중단" and wait. Right after a plan-mode approval, the approval is already given.
   - On 중단, ask 나중에 하기 / 버리기. 나중에 하기 moves the issue to `status:backlog`, keeps the branch, and posts the whole plan doc as an issue comment whose first line is `계획 문서`, so `/brief #<issue>` picks it up again on any clone. 버리기 closes the issue as not planned (`gh issue close --reason "not planned"`) and deletes the branch, locally and on the remote where it was pushed. Then stop, and so does a calling `/sync`.
   - Once approved, move the issue to `status:in-progress` and carry the plan out to the end without asking for approval again: implement, open the PR with `Closes #<issue>` and run `/debrief`. The PR body carries what the plan doc cannot, since that stays local: 요약, 주요 결정 (the user's decisions with the alternatives set aside, any 알린 우려, your own calls), the mockup canvas link when step 4 ran, and the acceptance criteria. For an epic, do After approval and then Run under Epics.
   - Split the work into parallel builder tracks only where the logbook rule says it pays, launched as subagents or a Workflow, in the shared working tree or in worktrees, as `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. You decide this while implementing; it is not part of the briefing and not a question for the user.
   - While carrying it out: do not weaken or delete tests; stop and ask before a schema change or data deletion the plan does not cover; record anything decided differently from the plan, with the reason, in the plan doc's 결정 기록 and the PR body; update `docs/system/` in the same PR when the change alters what it describes.

## Epics

An epic is an issue labelled `epic` whose child issues are its steps. The human approves the epic briefing at the start and reads the epic debriefing at the end; in between, the session runs every step.

- **When.** Propose an epic when the work splits into steps that each deserve their own PR and review, and later steps build on what earlier ones deliver. The briefing's 단계 table shows the split, and approving the briefing approves it. Started from an existing `epic` issue, read it and its child issues, and create only the steps that are missing. When the user turns the split down, plan it as one issue again: drop the `epic` label, rename the branch back, and delete the remote `epic/...` branch if it was pushed.
- **Plan.** The epic doc `<main>/.logbook/plans/<epic>-<slug>.md` carries the 단계 section of `${CLAUDE_PLUGIN_ROOT}/templates/plan.md` (order, child issue, branch, the steps it waits for, what it delivers) and the epic's own completion conditions. Before approval the table names steps without numbers. Only the epic doc is rendered and published; step docs get no HTML.
- **After approval.**
  - Create the missing child issues in `status:todo`, each body holding its step's completion conditions, and write their numbers and branches into the table.
  - Write each step's doc `<main>/.logbook/plans/<child>-<slug>.md` with its own completion conditions, for whoever implements it. Step docs detail what the approved epic doc says and add no new decisions.
  - Put the 단계 table, with child issues and branches, the epic's completion conditions and its 주요 결정 in the epic issue body, push the epic branch, and move the epic issue to `status:in-progress`.
- **Run.** Take the steps in the order of the table, and do not end the turn between steps: stop only when a step cannot be merged or a question needs the user. Per step:
  - write "단계 n/N 시작: #<child> <title>" in one line, then fetch, bring the local epic branch up to its remote, merge the base branch into it when the base is ahead and push; stop on a conflict you cannot resolve;
  - reread the step doc and trust the docs and the code over what you remember from earlier steps, cut `<type>/<child>-<slug>` from the epic branch, move the child issue to `status:in-progress`, and implement;
  - open the PR against the epic branch with `Part of #<epic>` and the child issue number, and run `/debrief`, whose step path merges it into the epic branch or stops with the reason;
  - pull the epic branch, tick the step in the epic doc's 진행 기록 and in the epic issue's 단계 table, and write "단계 n/N 끝: <PR link>".
- **Side by side.** Steps that wait on no unmerged step and touch different files may be built at once, each by a builder in its own worktree cut from the epic branch, as "Epic steps side by side" in `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. You decide it while running the epic. Their PRs still open, go through `/debrief` and merge one at a time in table order, each followed by the tick and the 끝 line above. A step whose builder stops with a question is taken over by the session in its worktree.
- **Stops and resuming.** When a step stops, report the step, the reason and what would let it go on, then ask 고친 뒤 이어서 / 중단. To go on, in this session or in a new one started with `/brief #<epic>`:
  - read the epic doc's table and 진행 기록 (the epic issue's 단계 table when the doc is not on this machine), the child issues and the open PRs against the epic branch;
  - finish After approval first when child issues or step docs are missing; on another machine, rebuild the epic doc from the epic issue body and the step docs from the child issue bodies;
  - check `git worktree list`: a step branch held by a worktree under `.logbook/worktrees/` is resumed inside that worktree;
  - for the first step not ticked, reuse its branch and PR when they exist (fix, push, run `/debrief` again); a branch without a PR (a builder committed, then the run broke off) is checked, pushed and given its PR; otherwise start it as Run says; tick it as Run's last item says, then continue with Run;
  - the "While carrying it out" rules of step 9 apply throughout.
- **End.** After the last step, open the epic PR from the epic branch to the base branch with `Closes` for the epic and every child and a body like step 9's (요약, 주요 결정, completion conditions), and run `/debrief` on it. The human picks the merge there.
- The epic branch takes only merged step PRs, base-branch merges, and the doc and review fixes `/debrief` makes on the epic PR.
- Screens of every step are mocked up and approved in step 4, before the run starts.

## Plan mode

- Write the plan file itself in the plan.md format, brief block included. The logbook hook renders it in the browser when the approval screen appears, and denies a plan without a complete block.
- When the plan starts from an existing issue, read its comments before writing, as step 1 says.
- For a change that "When to skip" covers, put a `<!-- brief:skip -->` line in the plan instead. After approval, follow "When to skip" rather than the steps below; the plan file stays in `.logbook/plans/`, which git ignores.
- Plan mode is read-only, so step 4 cannot run there; list the screens to mock up in the plan. After approval and before editing code: do step 1 if the issue or branch does not exist yet, run step 4 when the plan has screens, move the plan file to `<main>/.logbook/plans/<issue>-<slug>.md` (in a worktree, plan mode saved it in the worktree's own `.logbook/plans/`), then do steps 7 and 8, and for an epic the After approval items under Epics.

## Language

Write the doc, the briefing, and the issue and PR text by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
