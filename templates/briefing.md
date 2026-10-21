# Briefing pages

How `/brief` and `/debrief` show a plan and its result to the person who approves it. The text goes to the chat and to the issue or PR body; the page explains the change with pictures.

## What goes where

| Place | What it holds |
|---|---|
| Chat, when asking for approval or a merge | One sentence of summary, your own calls that change behavior or cost, the risks and 판단 필요, the number of acceptance criteria, the page link, then the question |
| Issue body (`/brief`) or PR body (`/debrief`) | The text briefing in markdown: summary, what changes, 주요 결정, risks, acceptance criteria, links. Other developers read it there, since they cannot open a private page |
| Plan doc | The full record that `/build` and `/debrief` read |
| The page | Pictures that let the approver grasp the change without reading the text |

## Design each page for its issue

There is no template. Read the change and pick the pictures that explain it best: a before-and-after of a flow, the work laid out on a timeline, a decision tree for a new rule, a state diagram, an ERD of the changed tables, the approved screen mockups, a small mock of a command's output. Two issues rarely need the same page.

- Keep text short: a headline per section that states its point, labels and short captions. Paragraphs belong in the chat and the issue body.
- A static picture is the default. Use buttons, toggles or motion only when the content cannot be shown without them; a page full of controls or animation reads as decoration.
- Draw with HTML, CSS or inline SVG built from the page's own color tokens, or with mermaid where it fits. Show a model call with its model, effort and the gist of its prompt (what goes in, what it is asked, what comes back), as `templates/diagram-kit.md` says.
- Every briefing page has the conclusion and the request, what changes, the main logic flow, the decisions split into the user's and yours, the risks and 판단 필요, and the acceptance criteria. Add the database change when the schema changes and the mockups when screens change.
- Show your own calls that change behavior or cost as pictures as large as the user's decisions; gather only the trivial ones into a short list.
- When screens change, put the approved mockup in the page: show the saved artboards themselves, not only a link to the canvas.
- A debriefing page shows the result against the plan: what was built, what changed from the plan and why, the evidence per criterion, the review rounds and the tracks.

## Build and publish

- On Claude Code, follow the artifact-design guidance (load the `artifact-design` skill), write the page to `<main>/.logbook/briefs/<issue>-brief.html` or `<issue>-debrief.html`, and publish it as an Artifact without runtime capabilities. Where publishing is unavailable (`claude -p`, no claude.ai login, other harnesses), write the same file as a complete HTML document with a doctype and a UTF-8 charset, open it in the browser, and use its path as the link. The Artifact viewer draws mermaid by itself; a local file loads mermaid from a pinned CDN version, or draws its pictures without it.
- Look at the page once before publishing when the session offers a way, fix what the look shows, then publish.
- Write in the project's language by `templates/writing.md`.
- The issue's Slack thread gets the page as a PNG and a standalone HTML file, under a plain-language text for planners, as `templates/slack.md` and `templates/planner.md` say.
- A briefing page records what was approved. Republish it to the same URL only before approval; after approval, changes to the plan appear on the debriefing page under 계획과 달라진 점.
