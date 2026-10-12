# agent_logbook

`logbook` 플러그인 저장소다. 에이전트가 조사하고 사람이 정할 결정은 객관식으로 물으며, 사람은 구현 전 브리핑과 구현 후 디브리핑을 검토한다.

- 구성: 스킬 `skills/`(rulebook, discuss, brief, build, debrief, sync), 리뷰어 `agents/reviewer.md`, 독립 점검 `agents/checker.md`, 병렬 구현 에이전트 `agents/builder*.md`, hook `hooks/`, 스크립트 `scripts/`, 템플릿 `templates/`(질문 안내 `questions.md`, 브리핑 화면 안내 `briefing.md`, 글쓰기 안내 `writing.md`, 그림 안내 `diagram-kit.md`, 병렬 실행 안내 `parallel.md`, 프로젝트 문서 뼈대 `system/`).
- 검증: `claude plugin validate .`, `bash tests/run.sh`.
- 스킬 본문과 에이전트 프롬프트는 영어로, 문서와 이슈·PR은 한국어로 쓴다.
- SKILL.md는 150줄 이하로 두고 강조어(MUST, CRITICAL, NEVER, ALWAYS)를 쓰지 않는다. 테스트가 확인한다.
- logbook 작업 규칙은 이 파일에 없다. 플러그인의 SessionStart hook(`hooks/session-rules.sh`)이 `templates/session-rules.md`를 세션마다 넣는다. 이 저장소에서 logbook을 쓰려면 clone한 뒤 `/logbook:rulebook`을 한 번 실행한다.

## 문서

| 문서 | 위치 | 언제 고치나 |
|---|---|---|
| 지금 시스템(한눈에 보기, 기술 스택, 주요 흐름) | `docs/system/` | 이 문서가 설명하는 내용을 바꾸는 PR에서 함께 고친다 |
| 변경 이력 | `CHANGELOG.md` | 쓰는 사람이 알아챌 변경을 담은 PR마다 한 줄을 적고 이슈와 PR을 링크한다. 버전별로 쌓는다 |
| 사용 설명서 | `docs/manual/index.html` | 명령이나 사용 방법이 바뀌는 PR에서 함께 고친다 |

- 조사는 지금 시스템 문서에서 시작한다.
- 위 자리 밖에 문서를 새로 만들지 않는다.
