# Writing guide

Everything logbook writes follows this guide: briefing and debriefing slides, plan documents, the project docs in `docs/system/`, issue and PR text and comments, `/goal` prompts, and commit messages.

## The reader

Write for someone with a computer-science bachelor's degree who does not know this project, its history, or the tools around it.

- They know programming, data structures, databases and ERDs, HTTP and APIs, and git (branches, commits, pull requests, merges).
- They do not know the project's internal names, the agent tools (Claude Code, logbook, hooks, Artifacts, plan mode, git worktrees, `/goal`), or shorthand invented along the way.
- The text should read smoothly for them in one pass, without looking anything up.

## Rules

1. Lead with the conclusion, then give the reason. The first sentence of a section says what the reader should take away.
2. Say one thing per sentence. Write complete sentences with their particles and endings. Do not stack nouns, and do not end Korean sentences in nouns or clipped endings (~함, ~임, ~필요).
3. Explain a term that belongs to this project or to its tools the first time it appears, in a short parenthesis. Common computer-science terms need no explanation.
4. Keep internal shorthand out of sentences: write "완료 조건 1", "코드보다 뒤처진 문서", "경로 패턴" rather than `AC-1`, `stale`, `glob`. A table may use a short label when its header explains it.
5. Keep commands, paths and identifiers in code format, and let the sentence say what they do.
6. Use tables and lists to line items up, not to replace explanation. A bullet that states a fact is a full sentence.
7. Prefer plain, everyday words to jargon and to literal translations from English. Avoid physical verbs for abstract things (무너지다, 드러나다, 착지하다), phrases that announce what comes next (살펴보겠습니다, 분명히 하자면), feelings supplied for the reader (놀랍게도, 안타깝게도), emphasis that overstates (이것이 핵심입니다), and frequent em dashes.
8. Show with a picture whatever a picture can show, by `templates/diagram-kit.md`. Markdown files hold no HTML, so they read well in any markdown viewer: draw with `mermaid`, tables and lists, and let the slide renderer add the HTML. Do not force an ERD or a flowchart: an ERD holds database tables only, and a flowchart shows logic that matters to the reader. Briefings and debriefings always include the main logic flow and any database schema change. The ERD in the project docs (`docs/system/data-model.md`) covers every table in the database.
9. Explain the important points of a flow in detail, above all every call to an LLM or another AI model. Its picture names the model and gives the gist of the prompt: what goes in, what the model is asked to do, and what comes back. The text adds the setting that picks the model, where the prompt lives, how the answer is checked, and what happens when the call fails or returns something unusable.
10. Write in the project's language, Korean unless AGENTS.md says otherwise. Briefings and debriefings address the person who approves, in a polite report tone (~합니다, ~하겠습니다).
11. Before publishing, read the text once as that reader. Rewrite any sentence you had to read twice and any term they would have to look up.

## Examples

| Hard to read | Reads smoothly |
|---|---|
| AC-3 stale 0 확인 필요 | 완료 조건 3: 코드보다 뒤처진 문서가 없는지 `system-check.sh`로 확인합니다. |
| 비용 추정 토큰 함수 오류 시 재시도 | 비용을 추정하는 함수에서 오류가 나면 한 번 더 시도합니다. |
| sources glob 미매칭 시 warn | 문서 첫 줄에 적은 경로 패턴이 어떤 파일과도 맞지 않으면 경고합니다. |
| 플랜 모드에서 Artifact 게시 불가 | 플랜 모드(코드를 고치기 전에 계획만 세우는 읽기 전용 모드)에서는 Artifact(claude.ai에 올리는 비공개 웹 페이지)를 게시할 수 없습니다. |
| 결국 핵심은 원문 대조다 | 원문과 대조하면 틀린 인용이 걸립니다. |
