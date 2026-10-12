# Parallel work

How logbook launches work that runs side by side: implementation tracks of `/build` (the builder agents), research (Explore agents in `/brief`, `/discuss` and `/sync`) and a split review (reviewer agents in `/debrief`). The rule for splitting lives in the logbook rules the SessionStart hook adds ("독립 트랙은 나눠서 동시에 만든다"): two or more independent, sizeable tracks are split by default. `/brief` plans the tracks in the plan doc's track graph, and `/build` launches them as this file says.

The user is not asked about tracks, and the briefing page does not show the graph. Splitting is the default; when the work stays in one piece, the graph says why in one line.

## Track graph

`/brief` writes it under `### 트랙 그래프` in the plan doc's `## 상세`, after the questions are settled, as a mermaid flowchart and a table with one row per track: 묶음 (wave), 트랙, 맡을 에이전트, 바꿀 파일, 기다리는 트랙, 위험, 확인 명령.

- Keep waves few and large. A wave is the unit the session reviews, merges and tests, so a wave boundary goes only where the session really has to review and merge earlier results before later tracks can start. The default is two waves: wave 0 with the shared parts (types, interfaces, configuration) that the session builds and commits, then one wave with every other track at once.
- Work that can be built from the plan doc alone, docs and tests included, goes into the same wave as the code it describes. A further wave needs one line in the graph saying why that review cannot wait until the wave is merged; a wave with a single track usually means the split is wrong.
- Tracks of one wave share no files.
- Pick the agent by the Models table below. Work that is design-heavy, a few steps long, or may need a question to the user stays with the session.
- 위험 is 예 when the track has tricky logic, a contract other tracks rely on, or many edge cases. Such a track is reviewed before its wave is merged; it is no reason for a wave of its own.
- `/build` follows the graph. After each wave it merges the tracks and runs the full test suite. A track marked 위험 is reviewed before it is merged: `logbook:reviewer` in area mode, given the plan's acceptance criteria in place of a PR body, the track's diff and the diff stat; confirmed serious findings are fixed before the next wave starts.
- When reality differs from the graph (an unexpected shared file, a track that turns out tiny), change it and record what changed and why in the plan doc's 결정 기록 and the PR body.

## Two ways to launch

| | Subagents | Workflow |
|---|---|---|
| What it is | The session calls the Agent tool once per track or area, in one message | The session runs one Workflow script (Claude Code's tool that spawns agents from a JavaScript script with `agent()`, `parallel()` and `pipeline()`) |
| Pick it when | Research or a split review with one or two areas, and any harness without the Workflow tool | Every `/build` wave that holds builder tracks, however many, and research or a split review with three or more areas or reviewers, when the Workflow tool is available |
| What it adds | Nothing to set up | Each track returns a result in a fixed shape (schema), an interrupted run resumes with `resumeFromRunId`, and `/workflows` shows progress |

- Either way, each track runs in the shared working tree or in a git worktree of its own; see Where tracks run.
- When the Workflow tool is missing (Codex and other harnesses, an older Claude Code) or the user declines the run, launch subagents instead. Without subagents either, the session does the work itself.
- Say in one line of chat what you launched and where it runs, when you launch it.
- This skill's instructions are the user's opt-in for the Workflow tool. Keep a run within the Workflow size setting (under 10 agents by default); launch only as many agents as there are tracks or areas.

## Models

Each agent runs on the model its task calls for, the same tiers either way.

| Task | Subagent | Workflow `agent()` options |
|---|---|---|
| Routine but large track | `logbook:builder-fast` | `agentType: 'logbook:builder-fast', model: 'sonnet', effort: 'medium'` |
| Feature with a clear scope | `logbook:builder` | `agentType: 'logbook:builder', effort: 'medium'` (session model) |
| Tricky algorithm, concurrency, many edge cases | `logbook:builder-deep` | `agentType: 'logbook:builder-deep', effort: 'xhigh'` (session model) |
| Research of one area | `Explore` with `model: sonnet` | `agentType: 'Explore', model: 'sonnet'` |

Write the model and effort into the script even though the agent definitions carry them, so the script alone shows what ran where.

## Where tracks run

| | Shared working tree | A worktree per track |
|---|---|---|
| Pick it when | Checking a track's own files is enough | A track needs the whole build or test suite |
| Check command | Covers only that track's files, since other tracks are editing the same tree | The full tests, run inside the worktree |
| Commits | The builder does not commit; the session reviews the diff and commits | The builder commits on its own branch, never pushes; the session merges that branch |
| Cost | None | Setting up each worktree: env files, dependencies |

- Make the worktree with the plugin's `scripts/worktree.sh add <branch> <base>` (the plugin root is the folder above this file's `templates/`): it puts it in `<main>/.logbook/worktrees/<branch with / turned into ->` (`worktree.sh path <branch>` prints it), cuts the branch from the base you name (the work branch after the shared parts are committed), links the main checkout's git-ignored `.env` files, and prints the path. Install dependencies there as `docs/system/stack.md` says before handing it out.
- Brief the builder with that path as where it works. Track branches are named `<work branch>-<track>`. A branch that already exists is checked out as it is, not cut again from the base, so pick a fresh track name for a second run.
- Do not use Claude Code's `isolation: 'worktree'` on the Agent tool or `agent()`: it cuts the worktree from the default branch, so the shared parts and earlier waves are missing.
- Run `worktree.sh` from the main checkout, not from inside the worktree it removes. Merge a track's branch into the work branch, then `worktree.sh remove <branch> --delete-branch`. `remove` refuses with exit 3 when uncommitted changes are left, and `--delete-branch` with exit 4 when the branch holds commits not merged yet; then stop, report the path and do not force it.
- A track the session takes over keeps its worktree until it is merged, then goes the same way.
- Some tools (jest, for one) may also scan `.logbook/worktrees/`; when one does, exclude that folder in the project's tool settings.

## Implementation tracks as a Workflow

Commit the shared parts first, as the logbook rules say. Then `/build` runs one Workflow per wave: one `parallel()` call over that wave's builder tracks. The session merges, reviews the tracks marked 위험 and runs the full tests between waves, since those steps can need a judgment or a question to the user, which agents inside a Workflow cannot ask.

```js
export const meta = { name: 'logbook-tracks', description: 'Run independent implementation tracks for one plan' }
const TRACK = { type: 'object', properties: {
  files: { type: 'array', items: { type: 'string' } },
  branch: { type: 'string' }, commit: { type: 'string' },
  check_output: { type: 'string' }, passed: { type: 'boolean' },
  not_done: { type: 'string' }, own_calls: { type: 'string' } },
  required: ['files', 'check_output', 'passed'] }
const results = await parallel(args.tracks.map(t => () =>
  agent(t.brief, { label: t.name, agentType: t.agent, model: t.model, effort: t.effort, schema: TRACK })))
return results.map((r, i) => ({ track: args.tracks[i].name, ...(r || { passed: false, not_done: 'agent failed' }) }))
```

- Pass the tracks as `args`: name, agent, model, effort, and a brief with the goal, the files it may change, the shared parts already built, the check command, the plan doc path and, for a track in its own worktree, that path.
- A track that did not pass is not handed out again; the session takes it over. After merging, the session runs the full tests and commits.
- The debriefing lists each track as usual: agent, what it built, whether its check passed, how long it ran, that it ran in a Workflow, and whether it had its own worktree.

## Research as a Workflow

One `parallel()` over the areas, each an Explore agent on Sonnet that returns findings with `file:line` evidence. Read yourself the files a conclusion rests on; the agents report, you check.

## Review split

`/debrief` splits round 1 of a review when the PR was built in builder tracks (its body lists them), or when its diff changes 2,000 lines or more (`git diff --shortstat`, leaving out lock files and generated files). Smaller PRs and later rounds keep one reviewer.

- Areas: one per track, by the files each track changed; files no track changed (the session's own edits, docs, glue after merging) form one more area. Without tracks, split by top-level folder or module so that each area is a few hundred to about 1,500 lines. Merge small areas so the reviewers, the seam one included, stay within the Workflow size setting.
- Area reviewer: `logbook:reviewer` in area mode, given the PR body, the full diff stat and the diff of its area's files. It may read any other file from the checkout.
- Seam reviewer: `logbook:reviewer` in seam mode, given the PR body, the full diff stat, the area list with its files, the diff of the shared parts (the commit made before the tracks, or files that several areas use) and the diff of every file two or more areas changed.
- Launch them as the table under Two ways to launch says: subagents for two, a Workflow for three or more. In a Workflow, each reviewer is `agent()` with `agentType: 'logbook:reviewer', model: 'opus', effort: 'high'`, the values its frontmatter carries.
- The session merges their findings, drops duplicates, and filters them as `/debrief` step 3 says. The PR body's review line names the areas.
