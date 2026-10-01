# agent_logbook

`logbook`은 Claude Code를 우선으로 하는 개발 흐름 플러그인입니다. 에이전트가 코드와 자료를 조사해 계획을 세우고, 사용 흐름이 달라지는 선택은 사람에게 묻습니다. 사람은 구현 전 브리핑과 구현 후 결과 보고(디브리핑)만 검토합니다. 지금 시스템의 모습은 프로젝트 문서(`docs/system/`)로 남기고, 코드가 바뀔 때마다 맞춥니다.

- 사용설명서: [docs/manual/index.html](docs/manual/index.html)
- 이 저장소의 프로젝트 문서: [docs/system/overview.md](docs/system/overview.md)

## 설치

Claude Code:

```bash
claude plugin marketplace add dincal/agent_logbook
claude plugin install logbook@agent-logbook
```

- 설치 뒤 세션을 새로 열거나 `/reload-plugins`를 실행합니다.
- 프로젝트마다 한 번 `/logbook:rulebook`을 실행해 규칙을 설치합니다. 이미 개발 중인 프로젝트라면 이어서 `/logbook:sync`를 실행해 옛 문서를 정리하고 프로젝트 문서를 씁니다.
- 새 버전으로 올릴 때는 `claude plugin marketplace update agent-logbook`과 `claude plugin update logbook@agent-logbook`을 실행합니다.

Codex(기본 지원):

```bash
codex plugin marketplace add <이 저장소의 로컬 경로>
codex plugin add logbook@agent-logbook
```

Antigravity·OpenCode(안내만): `skills/` 아래 폴더를 각 하네스의 스킬 경로에 링크하고, `scripts/rulebook.sh --apply`로 프로젝트 `AGENTS.md`에 규칙 블록을 넣습니다.

## 명령(스킬)

| 명령 | 쓰는 때 | 하는 일 |
|---|---|---|
| `/logbook:rulebook` | 프로젝트당 한 번 | AGENTS.md 규칙 블록, CLAUDE.md import, 이슈 라벨, 플랜 폴더 설치. 기존 프로젝트면 `/sync`를 안내 |
| `/logbook:discuss` | 스펙을 정하기 전 | 코드와 웹을 읽기만 하며 아이디어를 토론. 끝에 `/brief`로 넘기기, backlog 이슈, 남기지 않기 중 선택 |
| `/logbook:brief` | 구현 전 | 조사, 흐름이 달라지는 선택 질문, 화면 시안 승인, 상세 문서와 브리핑 슬라이드, 이슈 링크. 여러 단계로 나뉘는 작업은 에픽 이슈와 단계 이슈로 계획. 승인 뒤에는 PR과 디브리핑까지, 에픽이면 모든 단계를 에픽 브랜치에 합치고 에픽 PR까지 진행 |
| `/logbook:debrief` | PR 직후 | 기준별 검증 증거, 프로젝트 문서와 코드 대조, 독립 리뷰, 결과 보고 슬라이드, 머지·재리뷰 선택지. 에픽 단계 PR은 슬라이드 없이 조건을 채우면 에픽 브랜치에 스스로 머지 |
| `/logbook:sync` | 기존 프로젝트 도입, 문서가 뒤처졌을 때 | 옛 도구(paperclip 등)의 흔적과 자리 밖 문서 정리, 프로젝트 문서 작성과 동기화, 핸드북 게시 |

- hook(Claude Code가 특정 순간에 자동으로 실행하는 스크립트) 두 개가 함께 설치됩니다. 플랜 승인 화면에서 브리핑을 브라우저로 엽니다(`LOGBOOK_NO_OPEN=1`이면 열지 않음).
- 열린 PR에 디브리핑 표시(`<!-- logbook:debrief -->`)가 없으면 대화 종료를 한 번 막습니다.

## 문서를 두는 자리

| 자리 | 담는 것 |
|---|---|
| `docs/plans/<이슈 번호>-<slug>.md` | 변경마다 하나씩 쓰는 계획과 보고 |
| `docs/system/` | 지금 시스템: 한눈에 보기, 기술 스택, 주요 흐름, 데이터 모델(DB가 있을 때, 모든 테이블의 ERD) |
| `docs/designs/<이슈 번호>-<slug>/` | 승인된 화면 시안의 사본 |
| `docs/manual/` | 사용 설명서(있을 때) |

모든 문서는 컴퓨터공학 학부를 졸업했지만 이 프로젝트는 모르는 사람이 읽기 쉽게 씁니다. md 파일에는 HTML을 넣지 않고 그림은 mermaid로 그리며, AI 모델 호출은 모델과 프롬프트 요지를 그림에 적습니다. 기준은 [templates/writing.md](templates/writing.md)와 [templates/diagram-kit.md](templates/diagram-kit.md)에 있습니다.

## 개발

```bash
claude plugin validate .
bash tests/run.sh
scripts/system-check.sh
```

설계와 결정 기록은 [docs/plans/](docs/plans/)에 있습니다.
