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
