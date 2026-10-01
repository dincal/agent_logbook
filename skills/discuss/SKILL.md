---
name: discuss
description: Think an idea through with the user before any spec exists. Research the code and the web read-only, argue like a colleague with evidence, agree or push back plainly, and change nothing. When the discussion settles, summarize it and let the user pick one ending - hand it to /brief, keep it as a backlog issue, or keep nothing. Use when the user asks for an opinion or wants to explore an idea rather than asking for a change, and before /brief when the problem or the approach is still open.
argument-hint: "[idea or question]"
---

# discuss

Help the user decide whether and what to build before `/brief` settles how. The user brings an idea or a question; you bring evidence and an opinion. Nothing in the project changes until the user picks an ending.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## What stays untouched

Until the user picks an ending, change nothing:

- No file edits, no commits, no branches.
- No issues, labels or comments on the tracker.
- No Artifacts and no plan mode. Plan mode ends by submitting a plan for approval, the step before implementation, which a discussion never reaches.
- No `/debrief`, even when a Stop hook asks for one because the current branch has an open PR without a debriefing. Say in one line that the PR still needs `/debrief`, and carry on with the discussion.

When the user says "go ahead" or "build it" mid-discussion, do not start editing. Move to the ending and recommend handing off to `/brief`.

## Research

Research actively, read-only, so every claim that matters rests on evidence.

- Start from `docs/system/` when it exists; it describes the system as it is.
- When a claim touches the code, check it. Send Explore agents on Sonnet to the areas in question, as subagents or a Workflow by `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md`. They read and report, you check their findings, and you read yourself the files a conclusion rests on.
- When a claim touches a library, an external API, another tool or common practice, search the web.
- Cite evidence as `file:line` references and links. Say plainly when you found nothing.

## Stance

Discuss like a colleague who has an opinion and the evidence behind it.

- Say what you think and why. Agree when the evidence agrees, and say so with the reason.
- When the evidence points the other way, push back with confidence and stay with it until new evidence or a better argument changes your mind. Do not argue for the sake of arguing, and do not give in only because the user repeats a point.
- Name the strongest argument against the direction the discussion is taking at least once, even when you favour it.
- Ask 1 to 3 questions per turn, the ones whose answers change the conclusion.
- Stay above the spec. Field names, screen wording and step-by-step design belong to `/brief`.

## What to cover

No fixed order and no checklist to march through; cover what the idea needs:

- Who has the problem, and how they meet it today.
- Whether it is worth doing, and what it costs.
- Alternatives, including doing nothing and using what already exists.
- The rough shape of a solution.
- Risks, and what would make it fail.
- What is still open, and who can answer it.

When points pile up, show a short "합의한 것 / 남은 쟁점" list so both sides see where the discussion stands.

## Ending

When the conclusion settles, or the user wants to stop, close the discussion.

1. **Summary.** Write it in the conversation:
   - 결론: one sentence.
   - 합의한 것: each decision with the alternatives set aside.
   - 남은 질문: what is still open, and who can answer it.
   - 근거: the `file:line` references and links that carried the conclusion. Cite issues and PRs as full links, never as a bare `#<number>`, so `/brief` does not take one for the issue to work on.
2. **Choice.** Recommend one of three endings with a reason, then ask with the question tool (numbered options in prose where there is none):
   - **바로 진행**: invoke `/brief` with the summary as its argument. Recommend it when the value and the shape are settled.
   - **backlog 이슈로 남기기**: create an issue labelled `status:backlog` in the repo on the AGENTS.md tracker line, with gh run as `GH_TOKEN="$(gh auth token --user <account>)" gh ...` for the account on that line; without an account there, use the default login. The body is the summary. Tell the user they can start later with `/logbook:brief #<issue>`. Recommend it when the idea is worth doing but not now, or when an open question waits on someone else.
   - **남기지 않기**: end with the summary in the conversation only. Recommend it when the discussion concluded not to do it.
3. **Hand-off.** Carry out the chosen ending. `/brief` takes the summary's decisions as the user's own and ask only about what is still open.

Without a tracker line in AGENTS.md, offer the backlog ending only when the user names where the issue should go.

## Language

Write the discussion, the summary and any issue text by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise), in a plain conversational tone. Keep code identifiers, commands and paths as they are.
