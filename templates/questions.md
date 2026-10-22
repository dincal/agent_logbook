# Questions

How logbook finds the decisions a change leaves open and asks the user about them. `/brief` follows all of it. `/discuss`, `/sync`, `/build`, `/debrief` and `/rulebook` follow "How to ask", and the logbook rules point here.

## Who decides

| Decision | Who | How |
|---|---|---|
| How the user works with the product: commands, steps, what they approve and when, what happens to their files and data | the user | ask, with options and a recommended one |
| Domain rules and behavior: what happens when, what is allowed and what is not, edge cases, which side wins a conflict | the user | draw it out of the user and never invent a rule; offer your best readings as options and always add an own-answer option |
| Technical choices with real trade-offs: storage, interface, consistency, cost, anything hard to reverse | the user | present the options with their trade-offs and a recommendation |
| What the request, the conversation, the code or the project docs already settle | you | decide, and say what settled it |
| Tuning values inside a settled mechanism that the user has no preference on (a limit, a timeout, a label) | you | pick a sensible default, mark it as adjustable, and list it with your own calls |

Wording, internal implementation and choices with one sensible answer are yours too. A short request raises the number of questions; it never lowers it.

## Find the open decisions

Before asking, list what the change must answer, so that nothing gets settled by accident.

1. Name what the change touches: data, people and roles, commands, screens, files, outside systems. Read `docs/system/` first, including `rules.md` when the project keeps one.
2. Go through four lenses for each of them and for each pair that meets:
   - **Structure**: how many, made of what, how one is told apart from another (does one order hold one item or many?).
   - **Behavior**: how it starts, changes and ends; two people or processes acting at once; failures and edge cases; what happens when two features combine (a cancelled booking that was already paid).
   - **Technique**: where it lives, through which interface, how consistent it must be, what it costs.
   - **Contract**: names, the exact set of values a field takes, what must be unique, what other code, tools or tests rely on.
3. Mark each item as settled (say by what), a tuning value (your default) or open. Only open items become questions.
4. When the request, the code and the docs disagree, do not pick one. Ask.

The lenses help you spot items; they are not a form to fill in. An item that fits none of them still counts.

## How to ask

- Use the question tool whenever the answers can be listed (AskUserQuestion on Claude Code): 1 to 4 questions per call, 2 to 4 options each, the recommended option first with "(Recommended)", and a header of a word or two. Where there is no question tool, write numbered options in prose.
- Put the context in the message before the call: the evidence, why the choice matters, and what each option leads to. The tool shows only short descriptions.
- A domain question carries an own-answer option ("다른 생각이 있다") among its options, so it lists at most three answers of yours. When the answers are too open to list, ask in prose.
- Ask in prose only when no options can be listed.
- When the tool fails or rejects the call, ask the same question in prose at once.
- Ask the questions that change the most first, and ask again in further rounds when answers open new choices.

## Independent check

`/brief` runs this after its question rounds and before it writes the plan doc, in plan mode too. A change that gets no briefing gets no check.

1. Spawn `logbook:checker` with every user message of the conversation verbatim, each question you asked with the user's exact answer, and the decision list split into the user's decisions, your own calls and tuning values. It cannot see the session, so paste them; never summarize them.
2. It returns at most eight items, each a decision it thinks was guessed or missed, with a question and options. Check them: drop the ones the conversation or the code does settle, and say how many you dropped and why.
3. Ask the rest as questions. Do not write an answer of your own into the plan instead.
4. Run it once more on what the answers changed, and only on that. What is still open after that goes to the user as it is; the check does not loop again.
5. When the checker cannot run, go through the lenses once more yourself and say in the briefing that the independent check did not run.

## Overlapping issues

`/brief` and `/discuss` run this before an issue is made or taken up, so the same work does not pile up in two issues. `/brief` runs it in step 1, before creating an issue or right after reading a given one, and when `/sync` calls it too; in plan mode it runs before the plan is written, since it only reads and asks. `/discuss` lists the overlaps in its summary and asks about them once the user picks an ending. Run gh with the account on the tracker line (the default login without one); below, that is the tracker account.

1. **Read.** List the open issues with `gh issue list --state open --limit 1000 --json number,title,labels,assignees,author`, leaving out the issue at hand, and read each candidate with `gh issue view <n> --comments`. Issue-less pull requests are not part of it.
2. **Judge.** Decide by meaning, not by shared words, which issues cover the same work, part of it, or work this change would undo. When none does, say so in one line and go on.
3. **Yours or someone else's.** An issue is yours when the tracker account is its only assignee, or when it has no assignee and that account opened it. Every other issue, a shared one included, is someone else's.
4. **Someone else's.** Ask nothing about it and change nothing on it. Plan one comment that mentions its assignees (its author when it has none), links the issue the work goes on in (the new one, or the one it continues with) and says in one line how the two overlap.
5. **Yours.** Ask one question per issue with the question tool as "How to ask" says: what overlaps, then the ways that fit the issue, your recommendation first. Any other way the user types into the free answer is followed as well.
   - A backlog or todo issue: merge it into the new issue, continue with it instead of a new issue, link the two, close it, or leave it.
   - An in-progress issue: link the two, close it, or leave it. Its plan is already approved, so nothing is merged into or out of it.
   - In `/discuss`, offer only what the picked ending allows. 바로 진행 leaves the questions to `/brief`. A backlog issue offers merging into it, linking, closing or leaving. 기존 이슈에 더하기 is continuing with that issue; the others may be merged into it, linked, closed or left. 남기지 않기 asks nothing. Each stays within what the issue's state allows above, so an in-progress issue is only linked, closed or left.
6. **Record.** `/brief` writes the decisions and the planned comments into the plan doc's 결정 기록 and the briefing's 주요 결정; `/discuss` asks them after the ending and says in the chat what it did. A plan picked up again after 나중에 하기 brings its decisions in the `계획 문서` comment: keep them, and ask only about issues that are new or changed since. After `/brief` switches to an issue to continue with, keep every decision made so far; the issue it came from and the issues already answered are not asked about again.
7. **Carry out at approval.** Continuing with an existing issue takes effect at once in `/brief` step 1: no new issue is made, and `/brief` works on that issue as if it had been given. Everything else waits. `/brief` acts when the briefing is approved, in plan mode and when `/sync` calls it as well; `/discuss` acts right after the ending is picked. On 나중에 하기 the decisions stay in the `계획 문서` comment with the rest of the plan; on 버리기 they are dropped. Just before acting, read each issue again, and ask once more about any issue whose state, assignees or text changed since the question.
   - Merge into the new issue (or into the issue `/brief` continues with, which is how a given issue at hand gives way to it when it is yours; a given issue that is someone else's only gets the planned comment): add its points with its link under `## 합친 이슈` in that issue's body, then `gh issue close <old> --duplicate-of <new>`; with a gh that lacks the flag, `--reason "not planned"` and a comment naming the new issue.
   - Link: a comment on each issue naming the other.
   - Close: `gh issue close <old> --reason "not planned"` with a comment saying why. Closing an in-progress issue keeps its branch and pull request; say so in that comment and in the chat.
   - A closed issue loses its `status:*` label. When it has a Slack thread, post `slack.sh post <old> close --outcome dropped --text <file>` saying where the work went; `slack.sh` posts nothing for an issue without one.
   - Then post the planned comments on the issues of others.
