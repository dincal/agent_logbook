# agent_logbook

`logbook`은 Claude Code를 우선으로 하는 개발 흐름 플러그인입니다. 에이전트가 코드와 자료를 조사해 스펙을 정하고, 사람은 구현 전 브리핑과 구현 후 디브리핑 두 번만 검토합니다. 요청이 애매하면 구현 전에 되묻습니다.

사용설명서: [docs/manual/index.html](docs/manual/index.html)

## 설치

Claude Code:

```bash
claude plugin marketplace add dincal/agent_logbook
claude plugin install logbook@agent-logbook
```

- 설치 뒤 세션을 새로 열거나 `/reload-plugins`를 실행합니다.
- 프로젝트마다 한 번 `/logbook:rulebook`을 실행해 규칙을 설치합니다.

Codex(기본 지원):

```bash
codex plugin marketplace add <이 저장소의 로컬 경로>
codex plugin add logbook@agent-logbook
```

Antigravity·OpenCode(안내만): `skills/` 아래 폴더를 각 하네스의 스킬 경로에 링크하고, `scripts/rulebook.sh --apply`로 프로젝트 `AGENTS.md`에 규칙 블록을 넣습니다.

## 스킬

| 스킬 | 쓰는 때 | 하는 일 |
|---|---|---|
| `/logbook:rulebook` | 프로젝트당 한 번 | AGENTS.md 규칙 블록, CLAUDE.md import, 이슈 라벨, 플랜 폴더 설치 |
| `/logbook:brief` | 구현 전 | 조사, 애매한 점 질문, 결정, 상세 문서와 브리핑 HTML, 이슈 링크 |
| `/logbook:mission` | `/goal`을 맡길 때 | 플랜 모드처럼 계획을 승인받고 바로 실행할 `/goal` 문장 출력 |
| `/logbook:debrief` | PR 직후 | 기준별 검증 증거, 독립 리뷰, 디브리핑 HTML, 재리뷰 판정과 머지·재리뷰 선택지 |

- hook 두 종이 함께 설치됩니다. 플랜 승인 화면에서 브리핑을 브라우저로 엽니다(`LOGBOOK_NO_OPEN=1`이면 열지 않음).
- 열린 PR에 디브리핑 표식(`<!-- logbook:debrief -->`)이 없으면 턴 종료를 한 번 막습니다.

## 개발

```bash
claude plugin validate .
bash tests/run.sh
```

설계와 결정 기록은 [docs/plans/](docs/plans/)에 있습니다.
