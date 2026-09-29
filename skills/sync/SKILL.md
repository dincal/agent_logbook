---
name: sync
description: Bring a project's documents in line with logbook and with its code. In an existing project, remove the traces of earlier agent tools (such as paperclip) and every document outside logbook's places, then write the project docs; in a logbook project, rewrite the project docs that have fallen behind the code. The project docs are docs/system/overview.md, stack.md, flows.md and data-model.md, published together as one HTML handbook. Use after /rulebook on an existing project, when system-check reports stale docs, or when the user asks to sync the project docs.
argument-hint: "[full]"
---

# sync

Keep the project's documents where logbook expects them and true to the code: a short map of the system as it is today, for a reader who will not read the code.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## The project docs

`docs/system/` holds up to four files, written from `${CLAUDE_PLUGIN_ROOT}/templates/system/`:

| File | What it covers |
|---|---|
| `overview.md` | what the system does and for whom, a system map (users, the system, outside systems), hard-to-reverse choices and risks, a glossary when needed |
| `stack.md` | the building blocks and the technology each uses, deployment and runtime, development tools |
| `flows.md` | the 3 to 7 flows that carry the business, one section each |
| `data-model.md` | only when there is a database: an ERD with every table, what each table means, status changes |

- Write by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md` and draw by `${CLAUDE_PLUGIN_ROOT}/templates/diagram-kit.md`. Each `##` section becomes one handbook slide, and its first paragraph is one sentence that states the conclusion.
- Only facts the code confirms. Old documents are hints: keep a claim only after checking it in the code. Mark what the code cannot tell (product intent, quality goals) as `확인 필요` and ask.
- The docs hold no HTML, so they read well in any markdown viewer: pictures are `mermaid` diagrams, tables and lists.
- Each call to an LLM or another AI model is a point to explain in detail: the flow's picture names the model and gives the gist of the prompt (what goes in, what the model is asked, what comes back), and a table under it adds the setting that picks the model, where the prompt lives, how the answer is checked and what happens on failure. stack.md lists the models.
- Code references appear only on a flow's `시작점` line and in the model-call table, as a file path plus a function, class or setting name, without line numbers.
- Each doc starts with `<!-- logbook:system sources="<git path patterns>" -->` naming the code it describes. data-model.md adds `tables="<n>"`, the number of tables the schema defines.
- The ERD shows every table in the database. List the tables from the schema's source of truth (ORM models or schema files, not the migration history). When there are many, split the ERD by domain into several sections so that each table appears at least once. When the project already generates an ERD (prisma-erd-generator, paracelsus, tbls and the like), start from its output.
- Without a database there is no data-model.md; overview.md says in one line where the data lives.
- Keep each doc short, about 150 lines; the ERD's completeness comes before that limit.

## What does not fit logbook

`${CLAUDE_PLUGIN_ROOT}/scripts/legacy-scan.sh` lists it, one line per item: files and folders of earlier agent tools, their rule sections in AGENTS.md and CLAUDE.md, tracked files that mention them, their `.gitignore` lines, rule links such as GEMINI.md, and documents outside logbook's places. Those places are `docs/plans/<issue>-<slug>.md`, `docs/system/`, `docs/designs/` and `docs/manual/`, plus README, CHANGELOG, AGENTS.md and CLAUDE.md at the root.

Everything it lists is removed, except code and configuration that point at a removed path; change those instead, then run the tests that cover them. Mark the documents that hold knowledge the code does not show, and move their essentials into the project docs before they go.

## Steps

1. **Rules first.** When AGENTS.md has no logbook block (`<!-- logbook:begin`), stop and ask the user to run `/rulebook` first.
2. **Scope.**
   - `legacy-scan.sh` prints something: clean up and write the project docs (the adoption path).
   - `docs/system/` is missing, or `$ARGUMENTS` is `full`: write all the docs.
   - Otherwise run `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh` and rewrite only the stale docs and the sections its warnings name. Fixing stale docs, one or several, needs no issue and no briefing: it ends in a PR without an issue that still gets a review.
3. **Brief.** Follow `${CLAUDE_PLUGIN_ROOT}/skills/brief/SKILL.md`. The adoption path and a first write take the full briefing: the cleanup table (path, what it is, action, reason) and the planned docs are the plan, and nothing is deleted before the user approves it. A stale-doc fix skips it: ask what its step 3 would ask, cut a `docs/<slug>` branch from the base branch, and carry on with the steps below; step 9 opens a PR without an issue.
4. **Survey.** Send three parallel Explore subagents (on Claude Code, pass `model: sonnet`): stack and runtime (manifests, build and deploy files, CI, infrastructure, outside services); flows (entry points and the flows that carry the business); data (the schema's source of truth, every table and relation, status fields).
5. **Write** the docs by the rules above. Move rules that still hold from CLAUDE.md into AGENTS.md, and leave CLAUDE.md as the `@AGENTS.md` import.
6. **Clean up.** Delete tracked items with `git rm` on the work branch, so the PR is where they are reviewed. Move untracked leftovers to the Trash instead of deleting them. Remove a git worktree under a legacy folder only when it has no changes; otherwise ask.
7. **Check.** `legacy-scan.sh` prints nothing, `system-check.sh` reports no stale doc and no warning, and the tests touched in step 6 pass. Read the handbook once as its reader would.
8. **Publish.** `${CLAUDE_PLUGIN_ROOT}/scripts/render-system.sh docs/system .logbook/system/handbook.html`. On Claude Code, publish it as an Artifact: when overview.md's header has a 핸드북 link, read that artifact and republish to the same URL; otherwise publish a new one and write its link into the header. Elsewhere, the local path is the link.
9. **Finish.** Link `docs/system/overview.md` from README in one line; AGENTS.md gets no copy, since every session loads it. Commit, open the PR with the cleanup table in its body, and run `/debrief`.

## Called from other skills

`/debrief` follows the rules above for the sections a pull request changed, and republishes the handbook after merging.

## Language

Write in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
