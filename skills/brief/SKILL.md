---
name: brief
description: Pre-implementation briefing for any change bigger than a one-sentence fix, always as one issue. Research the code and sources, find every decision the change leaves open and ask the user about the ones that are theirs as multiple choice, run an independent check for guessed decisions, mock up changed screens, write the plan doc with a track graph in the git-ignored .logbook/plans/, put a text briefing in the issue body, publish a visual briefing page designed for the issue, and ask for approval in the chat. Once approved, hand the plan to /build. Use before editing code for a walk-in request, and right after a plan-mode plan is approved.
argument-hint: "[request | #issue]"
---

# brief

Turn a request into a plan the user approved, then hand it to `/build`. The user decides everything that is theirs to decide; you decide the rest and say so.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Document places below (`docs/system/`, `CHANGELOG.md`) are the defaults. When AGENTS.md has a document table, use the places it names instead, and pass them to the scripts (`system-check.sh --dir`, the folder argument of `render-system.sh`).

Plan docs and mockup copies are working files, not project documents. They live in `.logbook/plans/` and `.logbook/designs/` of the main checkout, which git ignores, and are never committed. Below, `<main>` is the root of the main checkout: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`. Writing there keeps them when the worktree is removed. What others need from them goes to GitHub: the text briefing to the issue body, the reasons to the PR body, the result to CHANGELOG.

## When to skip

A change that one sentence fully describes (a typo, a rename, a small config tweak) gets no briefing and no issue, and so does a follow-up doc update with no related branch or issue to ride on. Cut a `<type>/<slug>` branch from the base branch, implement, open a PR without an issue, and let `/debrief` finish it, which also keeps the Slack record (a PR thread) for the issue-less PR. When `$ARGUMENTS` names an issue, keep it: read its comments as step 1 says, use `<type>/<issue>-<slug>` and put `Closes #<issue>` in the PR body.

## Steps

1. **Issue and branch.**
   - Use the issue number in `$ARGUMENTS` when given. Otherwise create one labelled `status:todo` and assigned to yourself (`--assignee @me`) in the repo named on the tracker line in the logbook rules the session started with (the SessionStart hook adds them from `.logbook/config.json`). When the session got no logbook rules (for instance `/rulebook` ran in this session), read repo, base and account from `.logbook/config.json` in the main checkout instead.
   - An issue given in `status:backlog` (one `/discuss` left for later, for instance) moves to `status:todo`. A plan set aside with 나중에 하기 in step 9 is picked up again: start from the local plan doc `<main>/.logbook/plans/<issue>-<slug>.md`, or else from the issue's last comment whose first line is `계획 문서`, saving it as that doc. Check out its branch when it exists on this clone or the remote; otherwise cut it.
   - An issue already in `status:in-progress` was approved before: hand it to `/build #<issue>` instead of these steps.
   - A given issue gets you as an assignee too (`gh issue edit <issue> --add-assignee @me`). When someone else is already assigned, ask with the question tool whether to add yourself beside them, replace them with yourself (`--remove-assignee <login>` alongside), or leave the assignees as they are.
   - Read the given issue's comments too: follow-up work deferred to this issue, such as a doc update, is left there as a comment and belongs in this change.
   - Run gh with the account on that line: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without an account there, use the default login.
   - Slug: a short kebab-case summary. Branch: `<type>/<issue>-<slug>` (feat, fix, refactor, docs or chore), cut from the base branch.
   - One request is one issue and one PR, however large, and even when it mixes unrelated features. Large work is split into tracks inside it (step 5), never into child issues.
   - After creating the issue, open its Slack thread with `${CLAUDE_PLUGIN_ROOT}/scripts/slack.sh thread <issue> --text <file>`, the issue written out in plain words for people who cannot open GitHub. Every Slack post and reply check below follows `${CLAUDE_PLUGIN_ROOT}/templates/slack.md`, written by `${CLAUDE_PLUGIN_ROOT}/templates/planner.md`; Slack never holds up a step.
   - Work in the main checkout and switch branches there. When something makes the main checkout unfit (uncommitted changes, a service running from it, another session working there), say what and ask with the question tool before making a worktree with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add`; then do as the user picks: the worktree, the main checkout, or stop.
2. **Research.**
   - Start from `docs/system/` when it exists; it describes the system as it is, and `rules.md` there holds the domain rules users settled before. Note which of those docs the change will alter.
   - Code: research areas that do not depend on each other in parallel, with Explore subagents on Sonnet or a Workflow as `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md` says. They read and report, you check their findings, and you read the files the change touches yourself.
   - Sources: search the web, or run `/deep-research`, when the change brings a new library, an external API or an unfamiliar pattern.
   - Keep evidence as `file:line` references and links.
3. **Questions.** Follow `${CLAUDE_PLUGIN_ROOT}/templates/questions.md`.
   - List the open decisions with its four lenses (structure, behavior, technique, contract) over everything the change touches. Ask about every one that is the user's: how they work with the product, domain rules and edge cases, technical choices with real trade-offs. Decide what is already settled and the tuning values yourself, and list them in the briefing as your own calls.
   - When `$ARGUMENTS` or the issue carries a `/discuss` summary, its decisions are the user's own: list them under 주요 결정 with the alternatives set aside, and ask only about what it leaves open.
   - Ask with the question tool as its "How to ask" says, in rounds, until no open decision is left. When the request, the code and the docs disagree, ask instead of picking one.
   - When an answer or instruction looks unreasonable against the evidence (it contradicts what research found, costs far more than it gains, carries a risk the user may not have seen, or works against their own stated goal), say so once before acting: the concern, the evidence, and a better option. If they keep it, follow it and list it under 주요 결정 as 알린 우려. Leave matters of taste and weak worries alone, and say plainly when nothing looked unreasonable.
   - Then run the independent check with `logbook:checker` as its "Independent check" says, and ask about what it finds before writing the plan.
4. **Screen mockup.** When the change adds a screen or visibly reshapes one:
   - On Claude Code with artifacts, draft a Design canvas, the same canvas `/design` makes: `Artifact` quickstart with intent `design`, then create one from the Design type. Draw one artboard per screen and state (default, empty, error), after reading the project's design tokens and components.
   - Elsewhere, write a static HTML mockup to `<main>/.logbook/designs/<issue>-<slug>/index.html` and open it in the browser.
   - Before asking, post the draft to the thread: when `slack.sh check` exits 0, save the draft artboards to a new temporary folder (the design folder holds the approved copy only), then `slack.sh post <issue> mockup` with a PNG per artboard, and read new replies with `slack.sh replies <issue>`, as `templates/slack.md` says.
   - Ask 승인 / 고쳐 달라 / 시안 없이 진행 / 중단 with the question tool (중단 is handled as in step 9). On a change request, read the canvas again first (the user may have edited it), apply the feedback, republish to the same URL, post the mockup again and ask again.
   - After approval, read the canvas back and save `project/canvas.json` and the `project/*.dc.html` artboards to `<main>/.logbook/designs/<issue>-<slug>/`. Implementation follows that copy, and the briefing page shows the approved screens. Post the approval to the thread with `slack.sh post <issue> design` (text only).
5. **Plan document.**
   - Write `<main>/.logbook/plans/<issue>-<slug>.md` from `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`, by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`.
   - The part between `<!-- brief:begin -->` and `<!-- brief:end -->` is the text briefing that goes into the issue body and the approval message. Conclusion and request first: 요약, 배경, what you will do, 주요 결정, 위험과 판단 필요, 일정과 검증. Add 주요 로직 흐름 when important logic is added or changed, 데이터베이스 변경 when the schema changes, and 화면 시안 when step 4 ran. Each section opens with one sentence that states its conclusion.
   - 주요 결정 separates what the user decided, with the alternatives they rejected, from your own calls; your calls that change behavior or cost come first.
   - Close with `> 판단 필요: 없음`, or at most two items only the human can decide: irreversible choices, product direction, scope.
   - Every acceptance criterion names the command or observation that proves it. When the change alters what `docs/system/` describes, name those docs and add a criterion proved by `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --range <base>...HEAD`. When it settles or changes a domain rule, name `rules.md`; when the project has none and this change settles its first domain rule, the change creates it from `${CLAUDE_PLUGIN_ROOT}/templates/system/rules.md`.
   - Under `## 상세`, write the track graph by the "Track graph" section of `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md`: the parts, who builds each one, which wait for which, which are risky. Keep waves large: the shared parts first, then one wave with everything else, unless the session truly has to review and merge something before later tracks can start. It is not a question for the user and stays off the briefing page. Other details that do not fit go under `## 상세` too.
6. **Pictures.** Follow `${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`:
   - The plan doc holds no HTML: draw with `mermaid` and compare with tables.
   - When the change adds or alters a call to an LLM or another AI model, its picture names the model and gives the gist of the prompt: what goes in, what the model is asked, what comes back.
   - Never force an ERD or a flowchart. Always include the main logic flow the change adds or alters, and an ERD of any database schema change.
7. **Briefing page.** Build the page as `${CLAUDE_PLUGIN_ROOT}/templates/briefing.md` says: designed for this issue, pictures over text, controls and motion only where the content needs them, the approved screens inside it when step 4 ran. On Claude Code, publish it as an Artifact and keep the link; where publishing is unavailable, use the local file path as the link.
8. **Link.**
   - Put the page link in the plan doc header.
   - Rewrite the issue body as the text briefing from the brief block (요약, what changes, 주요 결정, risks, acceptance criteria) with the page link. Read the body first, since an edit replaces it whole: when someone else wrote it, keep their text under `## 원래 요청` at the end.
   - Comment on the issue with a three-line summary, the page link and the 판단 필요 items.
   - Post the briefing to the thread: `slack.sh post <issue> brief --text <planner briefing> --page <main>/.logbook/briefs/<issue>-brief.html`. The text is the planner briefing `templates/planner.md` describes: user stories in plain words, no developer terms.
   - Do not commit the plan doc.
9. **Approval.**
   - First read the thread's new replies with `slack.sh replies <issue>` and handle them as `templates/slack.md` says: tell the user, and ask before any reply changes the plan.
   - Ask in the chat as `${CLAUDE_PLUGIN_ROOT}/templates/briefing.md` says: one sentence of summary, your calls that change behavior or cost, the risks and 판단 필요, the number of acceptance criteria and the page link, then "진행 / 수정 / 중단" with the question tool.
   - Called by `/sync`: ask the same and hand back to `/sync`, which carries out the approved plan itself. Leave the issue's label to `/sync` and do not invoke `/build`, so that a rerun of `/sync` briefs again instead of handing its plan to `/build`.
   - On 수정, change the plan, rewrite the issue body's text briefing, republish the page to the same URL and ask again.
   - Post the outcome to the thread with `slack.sh post <issue> approve` (브리핑이 승인되어 개발을 시작합니다; with `--outcome later` on 나중에 하기), or only `slack.sh post <issue> close --outcome dropped` on 버리기.
   - On 중단, ask 나중에 하기 / 버리기 with the question tool. 나중에 하기 moves the issue to `status:backlog`, keeps the branch, and posts the whole plan doc as an issue comment whose first line is `계획 문서`, so `/brief #<issue>` picks it up again on any clone. 버리기 closes the issue as not planned (`gh issue close --reason "not planned"`) and deletes the branch, locally and on the remote where it was pushed. Then stop, and so does a calling `/sync`.
   - Otherwise, once approved, move the issue to `status:in-progress` and invoke `/build #<issue>` without asking for approval again. The briefing page stays as approved; later changes to the plan appear in the debriefing.

## Plan mode

- Run steps 2 and 3 in plan mode, the independent check included, then write the plan file itself in the plan.md format, brief block and track graph included. The logbook hook denies a plan without a complete block or with HTML in it.
- When the plan starts from an existing issue, read its comments before writing, as step 1 says.
- For a change that "When to skip" covers, put a `<!-- brief:skip -->` line in the plan instead. After approval, follow "When to skip" rather than the steps below; the plan file stays in `.logbook/plans/`, which git ignores.
- Plan mode is read-only, so steps 4, 7 and 8 wait for the plan's approval. After it and before editing code: do step 1 if the issue or branch does not exist yet, run step 4 when the plan has screens, move the plan file to `<main>/.logbook/plans/<issue>-<slug>.md` (in a worktree, plan mode saved it in the worktree's own `.logbook/plans/`), do steps 7 and 8, then ask for approval once more in the chat as step 9 says. On 진행, move the issue to `status:in-progress` and invoke `/build #<issue>`.

## Language

Write the doc, the page, the chat messages, and the issue and PR text by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
