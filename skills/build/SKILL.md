---
name: build
description: Carry out a plan that /brief got approved, by the track graph in its plan doc. Build the shared parts, run each wave's builder tracks at once as a Workflow, review risky tracks before merging, run the full tests after every wave, then open the PR and run /debrief. Resume a run that broke off with /build #issue. Invoked by /brief after approval; use it directly to resume.
argument-hint: "[#issue]"
---

# build

Turn an approved plan into a pull request without asking for approval again. The plan doc and its track graph say what to build and who builds each part; the user is asked only when the run cannot go on.

Paths below use `${CLAUDE_PLUGIN_ROOT}`. On harnesses that do not substitute it, the plugin root is two levels above this file. Below, `<main>` is the root of the main checkout: the current repository root, or from a git worktree the folder above `git rev-parse --git-common-dir`. Plan docs live in `<main>/.logbook/plans/`, which git ignores, and are never committed.

## Start

1. **Find the plan.** The issue is `$ARGUMENTS`, or else the number in the current branch `<type>/<issue>-<slug>`.
   - Only an approved plan runs: the issue must be in `status:in-progress`. In `status:todo` or `status:backlog`, say the plan is not approved and point to `/brief #<issue>`, then stop.
   - Read `<main>/.logbook/plans/<issue>-<slug>.md` and set its status line to 구현 중. Without it on this machine, say the plan was made on another machine: go on there, or move the issue back to `status:todo` and plan again here with `/brief #<issue>`. Then stop.
   - Run gh with the account on the tracker line in the logbook rules the session started with: `GH_TOKEN="$(gh auth token --user <account>)" gh ...`. Without logbook rules in the session, read repo, base and account from `.logbook/config.json` in the main checkout.
2. **Branch.** When the issue's branch is already checked out in a worktree (the user picked one in `/brief`), work there. Otherwise check it out in the main checkout, cut from the base branch when it does not exist yet. When something makes the main checkout unfit (uncommitted changes, a service running from it, another session working there), say what and ask with the question tool before making a worktree with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh add`. Uncommitted files of this issue's interrupted wave are no such reason; step 3 takes them over.
3. **Where it stands.** When the branch already has an open PR, the run is past Finish: run `/debrief` instead. Otherwise read the plan doc's 진행 기록 and compare it with the branch: waves ticked there are done. Work left by an interrupted wave is taken over before going on: uncommitted files of its shared-tree tracks (match them with the graph's file lists and finish and check them; the wave's merge step below reviews the risky ones and commits them one track at a time), and track worktrees under `.logbook/worktrees/` from `git worktree list` (merge what they committed, take over the rest). A plan doc without a track graph (one made before 0.12) runs as one wave that you build yourself. Say in one line which wave the run starts from.

## Run the graph

Follow `### 트랙 그래프` under the plan doc's `## 상세` and the "Track graph" section of `${CLAUDE_PLUGIN_ROOT}/templates/parallel.md`. Do not end the turn between waves; stop only when a wave cannot be finished or a question needs the user.

Every wave, wave 0 included, goes through these steps. Wave 0 holds the shared parts, which you build yourself.

- **Each wave.**
  - Write "묶음 n/N 시작: <tracks>" in one line of chat.
  - Launch the wave's builder tracks at once as a Workflow, however many there are, each with the agent the graph names and the model and effort the Models table of the parallel guide gives that agent, in the shared working tree or in worktrees as the parallel guide says. Brief each builder with the goal, the files it may change, the shared parts already built, the check command, the plan doc path, and its worktree path when it has one. When the wave holds more tracks than the Workflow size setting allows, run them as several Workflows one after another; it is still one wave. Without the Workflow tool, launch them as subagents in one message. Tracks the graph gives to the session, you build yourself.
  - A track that fails its check or stops with a question is not handed out again; take it over.
  - Before merging a track marked 위험, spawn `logbook:reviewer` in area mode with the plan's acceptance criteria in place of a PR body, the track's diff and the diff stat. Fix confirmed serious findings first.
  - Merge the tracks with one commit per track, so that each track can be reverted alone: commit a shared-tree track's files under a message naming the track, and merge a worktree track's branch. Remove the track worktrees and branches from the main checkout with `worktree.sh remove <branch> --delete-branch` (on exit 3 or 4, stop and report the path). Then run the project's full tests and commit any fix.
  - Tick the wave in the plan doc's 진행 기록 and write "묶음 n/N 끝: <result>".
  - Share it in the issue's Slack thread as `${CLAUDE_PLUGIN_ROOT}/templates/slack.md` says, in the plain words of `${CLAUDE_PLUGIN_ROOT}/templates/planner.md`: a feedback summary when the user gave instructions since the last post, and `${CLAUDE_PLUGIN_ROOT}/scripts/slack.sh post <issue> check --file <path>...` when screenshots or e2e test results exist for a person to look at. Then read new replies with `slack.sh replies <issue>` and handle them as that guide says; a reply that would change the plan is the user's call. Do not post `wave` per wave; Finish posts it once. Slack never holds up a wave.
- **When reality differs from the graph** (an unexpected shared file, a track that turns out tiny, a new dependency), change the graph and record what changed and why in the plan doc's 결정 기록; it goes into the PR body later.
- **While building:** do not weaken or delete tests. Stop and ask before a schema change or data deletion the plan does not cover. Record anything decided differently from the plan, with the reason, in the plan doc's 결정 기록 and the PR body. Update `docs/system/` in the same PR when the change alters what it describes, and `rules.md` when a domain rule was settled or changed.
- **When a wave stops** (full tests failing in a way you cannot fix, a question for the user, a conflict you cannot resolve): report the wave, the reason and what would let it go on, and ask 고친 뒤 이어서 / 중단 with the question tool, as `${CLAUDE_PLUGIN_ROOT}/templates/questions.md` says. On 중단, leave the plan doc, the branch and its commits as they are, keep the issue in `status:in-progress`, and stop; `/build #<issue>` picks it up later.

## Finish

- Post `slack.sh post <issue> wave` (개발 끝) once, with what was built and the test result in plain words, unless the thread already has it from this run. Then read new replies with `slack.sh replies <issue>` and handle them before opening the PR.
- Push the branch and open the PR with `Closes #<issue>`, then post `slack.sh post <issue> pr` to the thread. The PR body carries what the plan doc cannot, since that stays local: 요약, 주요 결정 (the user's decisions with the alternatives set aside, any 알린 우려, your own calls), the mockup canvas link when there is one, the acceptance criteria, one line per track (wave, agent, files, whether it ran in a Workflow and in its own worktree) or why the work stayed in one piece, and the graph changes with their reasons.
- Run `/debrief`.

## Language

Write chat lines, plan doc entries and the PR body by `${CLAUDE_PLUGIN_ROOT}/templates/writing.md`, in the project's language (Korean unless AGENTS.md says otherwise). Keep code identifiers, commands and paths as they are.
