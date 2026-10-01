# Parallel work

How logbook launches work that runs side by side: implementation tracks (the builder agents) and research (Explore agents in `/brief`, `/discuss` and `/sync`). The rule for when implementation is split at all lives in the logbook rules the SessionStart hook adds ("구현은 이득이 있을 때만 나눈다"); this file covers how to launch it.

## Two ways to launch

| | Subagents | Workflow |
|---|---|---|
| What it is | The session calls the Agent tool once per track or area, in one message | The session runs one Workflow script (Claude Code's tool that spawns agents from a JavaScript script with `agent()`, `parallel()` and `pipeline()`) |
| Pick it when | The default. Two tracks or two research areas | The Workflow tool is available, and there are three or more tracks or areas, or the work is long enough that resuming after an interruption matters |
| What it adds | Nothing to set up | Each track returns a result in a fixed shape (schema), an interrupted run resumes with `resumeFromRunId`, and `/workflows` shows progress |

- Both run in the same working tree, so tracks never share files, and a track's check command covers only that track's files.
- When the Workflow tool is missing (Codex and other harnesses, an older Claude Code) or the user declines the run, launch subagents instead. Without subagents either, the session does the work itself.
- Say which one you picked: in the briefing's 일정과 검증 section for implementation, in one line of chat for research. The user can change it when approving the briefing.
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

## Implementation tracks as a Workflow

Commit the shared parts first, as the logbook rules say. Then one `parallel()` call runs every track; there is no stage after it, since the session merges and tests.

```js
export const meta = { name: 'logbook-tracks', description: 'Run independent implementation tracks for one plan' }
const TRACK = { type: 'object', properties: {
  files: { type: 'array', items: { type: 'string' } },
  check_output: { type: 'string' }, passed: { type: 'boolean' },
  not_done: { type: 'string' }, own_calls: { type: 'string' } },
  required: ['files', 'check_output', 'passed'] }
const results = await parallel(args.tracks.map(t => () =>
  agent(t.brief, { label: t.name, agentType: t.agent, model: t.model, effort: t.effort, schema: TRACK })))
return results.map((r, i) => ({ track: args.tracks[i].name, ...(r || { passed: false, not_done: 'agent failed' }) }))
```

- Pass the tracks as `args`: name, agent, model, effort, and a brief with the goal, the files it may change, the shared parts already built, the check command and the plan doc path.
- A track that did not pass is not handed out again; the session takes it over. After merging, the session runs the full tests and commits.
- The debriefing lists each track as usual: agent, what it built, whether its check passed, how long it ran, and that it ran in a Workflow.

## Research as a Workflow

One `parallel()` over the areas, each an Explore agent on Sonnet that returns findings with `file:line` evidence. Read yourself the files a conclusion rests on; the agents report, you check.
