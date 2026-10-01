---
name: sync
description: Bring a project's documents in line with its document structure and with its code. When AGENTS.md has a document table and the docs follow it, rewrite the project docs that have fallen behind the code; otherwise ask the user how the project lays out its documents, write that table into AGENTS.md as a plain document rules paragraph, remove the traces of earlier agent tools (such as paperclip) and documents outside the chosen places, then write the project docs. The project docs (by default docs/system/overview.md, stack.md, flows.md and data-model.md) are published together as one HTML handbook. Use after /rulebook, when system-check reports stale docs, or when the user asks to sync the project docs.
argument-hint: "[full]"
---

# sync

Keep the project's documents where the project wants them and true to the code: a short map of the system as it is today, for a reader who will not read the code.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file.

## The document structure

AGENTS.md holds the project's document rules as a plain paragraph, written from `${CLAUDE_PLUGIN_ROOT}/templates/docs-rules.md`: a table of document kinds and their places, and the promise to update them in the same PR as the code. It belongs to the project, holds no logbook marker and no logbook command, and people without logbook follow it too.

| Kind | Default place |
|---|---|
| 지금 시스템 (the project docs below) | `docs/system/` |
| 변경 이력 (CHANGELOG: one line per notable PR, linking its issue and PR, by version or by date) | `CHANGELOG.md` |
| 사용 설명서 | `docs/manual/` |

The places in that table replace the defaults everywhere below and in the scripts: pass them as `system-check.sh --dir` and the folder argument of `render-system.sh`. A kind the project does not keep is left out of the table. Plan docs and approved mockup copies are working files, not project documents: they stay in the git-ignored `.logbook/plans/` and `.logbook/designs/` of the main checkout, so the table has no row for them.

## The project docs

The 지금 시스템 place (`docs/system/` by default) holds the files the structure names; by default up to four, written from `${CLAUDE_PLUGIN_ROOT}/templates/system/`:

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
- Each doc starts with `<!-- logbook:system sources="<git path patterns>" checked="<date>" -->` naming the code it describes and the day it was last compared with that code. data-model.md adds `tables="<n>"`, the number of tables the schema defines.
- When `system-check.sh` calls a doc stale but the doc still matches the code, set `checked` to today and commit; the commit clears the stale mark. Do not reword a doc only to clear it.
- The ERD shows every table in the database. List the tables from the schema's source of truth (ORM models or schema files, not the migration history). When there are many, split the ERD by domain into several sections so that each table appears at least once. When the project already generates an ERD (prisma-erd-generator, paracelsus, tbls and the like), start from its output.
- Without a database there is no data-model.md; overview.md says in one line where the data lives.
- Keep each doc short, about 150 lines; the ERD's completeness comes before that limit.

## What does not fit

List it yourself from `git ls-files` and the untracked files: files and folders of earlier agent tools, their rule sections in AGENTS.md and CLAUDE.md, their `.gitignore` lines, rule links such as GEMINI.md, and documents outside the document places. For each tool path you remove, `git grep` for tracked files that still point at it, leaving out CHANGELOG, which keeps history. Look for documents in `docs/`, in the folders that hold the places, and among the `*.md` files at the root; source, skill and template files are not documents. The places are the ones in the table, plus README, CHANGELOG, AGENTS.md, CLAUDE.md, LICENSE, CONTRIBUTING, SECURITY and CODE_OF_CONDUCT at the root.

Everything listed is removed, except code and configuration that point at a removed path; change those instead, then run the tests that cover them. Mark the documents that hold knowledge the code does not show, and move their essentials into the project docs before they go.

Plan docs and mockup copies that logbook before 0.9 committed (`docs/plans/`, `docs/designs/` or the places an older table named) are outside the places too. Copy them to `.logbook/plans/` and `.logbook/designs/` of the main checkout before removing them, add one CHANGELOG line per plan doc (its date, title, issue and PR) when the changelog lacks one, point links at them to the PR of each change, and replace their rows in the document table with the 변경 이력 row.

## Steps

1. **Set up first.** When the main checkout has no `.logbook/config.json` (`git rev-parse --git-common-dir` finds it from a worktree), stop and ask the user to run `/rulebook` first.
2. **Structure.** Read AGENTS.md's document table.
   - The table exists and the 지금 시스템 place holds docs that start with the `logbook:system` marker: the structure is in place. Go on with step 3.
   - Otherwise the structure is decided first (the structure path). Look at what the project already has (folders such as `docs/`, `documentation/`, `wiki/`, an ERD generator, a docs site) and ask, as the brief's questions: where each kind lives or whether the project keeps it at all, whether the changelog goes by version or by date (by date for an app that has no versions), and which files the 지금 시스템 docs consist of. Recommend the defaults; when the project already keeps a kind somewhere, offer keeping that place as well. Ask 1 to 4 questions at a time, with options.
3. **Scope.**
   - The structure path: set up the structure, clean up and write the project docs (the adoption path).
   - The 지금 시스템 docs are missing, or `$ARGUMENTS` is `full`: write all the docs.
   - Otherwise run `${CLAUDE_PLUGIN_ROOT}/scripts/system-check.sh --dir <system place>` and rewrite only the stale docs and the sections its warnings name. Fixing stale docs, one or several, needs no issue and no briefing: it ends in a PR without an issue that still gets a review. On every path, also check `git ls-files` for plan docs and mockup copies left by logbook before 0.9 (`docs/plans/`, `docs/designs/` or the places an older table names for them), and the document table for their rows. When something "What does not fit" lists turns up, show it as a cleanup table and ask once whether this PR removes it.
4. **Brief.** Follow `${CLAUDE_PLUGIN_ROOT}/skills/brief/SKILL.md`. The adoption path and a first write take the full briefing: the chosen structure, the cleanup table (path, what it is, action, reason) and the planned docs are the plan, and nothing is deleted before the user approves it. When the user stops the briefing, stop here too. A stale-doc fix skips it: ask what its step 3 would ask, cut a `docs/<slug>` branch from the base branch, and carry on with the steps below; step 10 opens a PR without an issue.
5. **Survey.** Send three parallel Explore agents on Sonnet, as subagents or a Workflow by `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md`: stack and runtime (manifests, build and deploy files, CI, infrastructure, outside services); flows (entry points and the flows that carry the business); data (the schema's source of truth, every table and relation, status fields).
6. **Write** the docs by the rules above. On the structure path, write the document rules paragraph into AGENTS.md from `templates/docs-rules.md` with the chosen places and changelog format, dropping the rows of kinds the project does not keep (create AGENTS.md when missing). Move rules that still hold from CLAUDE.md into AGENTS.md. On any path, CLAUDE.md ends up as the `@AGENTS.md` import; create it when missing.
7. **Clean up.** Delete tracked items with `git rm` on the work branch, so the PR is where they are reviewed. Move untracked leftovers to the Trash instead of deleting them. Remove a git worktree under a legacy folder only when it has no changes; otherwise ask.
8. **Check.** Nothing the user approved removing is left in `git ls-files`, `system-check.sh --dir <system place>` reports no stale doc and no warning, and the tests touched in step 7 pass. Read the handbook once as its reader would.
9. **Publish.** `${CLAUDE_PLUGIN_ROOT}/scripts/render-system.sh <system place> .logbook/system/handbook.html`. On Claude Code, publish it as an Artifact: when overview.md's header has a 핸드북 link, read that artifact and republish to the same URL; otherwise publish a new one and write its link into the header. Elsewhere, render with `--standalone` and the local path is the link.
10. **Finish.** Link the overview doc from README in one line; AGENTS.md gets no copy of the docs, since its table already points at them. Commit, open the PR with the cleanup table and, after a briefing, the plan's 주요 결정 in its body, and run `/debrief`.

## Called from other skills

`/debrief` follows the rules above for the sections a pull request changed, and republishes the handbook after merging.

## Language

Write in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
