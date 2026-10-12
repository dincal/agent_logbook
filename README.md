# agent_logbook

`logbook`은 Claude Code를 우선으로 하는 개발 흐름 플러그인입니다. 에이전트가 코드와 자료를 조사해 계획을 세우고, 사람이 정할 결정(쓰는 방식, 도메인 규칙과 예외 상황, 득실이 있는 기술 선택)은 객관식으로 묻습니다. 사람은 구현 전 브리핑과 구현 후 결과 보고(디브리핑)만 검토합니다. 지금 시스템의 모습은 프로젝트 문서(`docs/system/`)로 남기고, 코드가 바뀔 때마다 맞춥니다.

- 사용설명서: [docs/manual/index.html](docs/manual/index.html)
- 이 저장소의 프로젝트 문서: [docs/system/overview.md](docs/system/overview.md)

## 설치

Claude Code:

```bash
claude plugin marketplace add dincal/agent_logbook
claude plugin install logbook@agent-logbook
```

- 설치 뒤 세션을 새로 열거나 `/reload-plugins`를 실행합니다.
- 저장소를 clone할 때마다 한 번 `/logbook:rulebook`을 실행해 logbook을 켭니다. 이 명령이 만드는 `.logbook/config.json`(git에서 제외)이 있는 저장소에만 hook이 작업 규칙을 넣습니다. 이어서 `/logbook:sync`를 실행하면 문서 구조를 정해 AGENTS.md에 문서 규칙 문단을 쓰고, 옛 문서를 정리하고, 프로젝트 문서를 씁니다.
- 새 버전으로 올릴 때는 `claude plugin marketplace update agent-logbook`과 `claude plugin update logbook@agent-logbook`을 실행합니다. 작업 규칙은 플러그인에서 세션마다 들어가므로 프로젝트에서 따로 할 일은 없습니다.
- 0.7 이전에 `/rulebook`으로 AGENTS.md에 규칙 블록을 넣은 프로젝트는 `/logbook:rulebook`을 한 번 더 실행합니다. 블록을 지우고, 그 안의 문서 규칙을 AGENTS.md의 일반 문단으로 옮깁니다.
- 0.9부터 계획 문서와 승인된 시안 사본은 저장소에 커밋하지 않고 원래 checkout의 `.logbook/plans/`, `.logbook/designs/`에 둡니다. 0.9 이전에 커밋된 `docs/plans/`, `docs/designs/`는 `/logbook:sync`가 로컬로 옮기고 CHANGELOG 한 줄씩으로 바꿔 정리합니다. AGENTS.md 문서 표의 "변경 기록", "승인된 화면 시안" 줄은 "변경 이력: `CHANGELOG.md`" 줄로 바꿉니다.
- 0.8 이전에 `/rulebook`을 실행한 프로젝트는 `/logbook:rulebook`을 한 번 더 실행하면 플랜 모드의 계획 파일이 git이 무시하는 `.logbook/plans`에 저장됩니다. 실행하기 전까지는 세션을 시작할 때 안내가 붙습니다.

Codex(기본 지원):

```bash
codex plugin marketplace add <이 저장소의 로컬 경로>
codex plugin add logbook@agent-logbook
```

Antigravity(agy):

```bash
agy plugin install <이 저장소의 로컬 경로>
```

OpenCode(안내만): `skills/` 아래 폴더를 각 하네스의 스킬 경로에 링크합니다. hook이 없으므로 `scripts/rulebook.sh --apply`로 logbook을 켠 뒤, `echo '{}' | hooks/session-rules.sh`가 출력하는 `additionalContext`의 규칙을 프로젝트 `AGENTS.md`에 직접 붙여 넣습니다. 이 경우에는 플러그인을 올릴 때마다 다시 붙여 넣어야 합니다.

## 명령(스킬)

| 명령 | 쓰는 때 | 하는 일 |
|---|---|---|
| `/logbook:rulebook` | clone마다 한 번 | logbook을 켜는 표시(`.logbook/config.json`), 이슈 라벨, 플랜 저장 위치(`.logbook/plans`) 준비. 0.7 이전의 규칙 블록은 문서 규칙 문단으로 옮김. 문서 구조가 없거나 기존 프로젝트면 `/sync`를 안내 |
| `/logbook:discuss` | 스펙을 정하기 전 | 코드와 웹을 읽기만 하며 아이디어를 토론. 선택지가 있는 질문은 질문 도구로 객관식으로 묻고, 끝에 `/brief`로 넘기기, backlog 이슈, 남기지 않기 중 선택 |
| `/logbook:brief` | 구현 전 | 조사하고, 네 관점(구조, 동작, 기술, 계약)으로 찾은 사람의 결정을 객관식으로 질문. 계획 전에 `logbook:checker`(Opus, high)가 짐작한 결정과 빠진 결정을 독립 점검. 화면 시안 승인, 트랙 그래프를 담은 계획 문서(로컬, 커밋하지 않음), 이슈마다 설계한 그림 브리핑 화면과 이슈 본문의 글 브리핑. 채팅에서 승인받으면 `/build`로 넘김. 큰 작업도 이슈 하나, PR 하나로 함 |
| `/logbook:build` | 브리핑 승인 직후(자동), 끊긴 작업을 이어 갈 때 | 계획 문서의 트랙 그래프대로 묶음 0의 공통 부분을 만든 뒤, 묶음마다 builder 트랙을 Workflow 하나로 동시에 실행. 위험한 트랙은 합치기 전에 리뷰하고, 트랙마다 커밋하며, 묶음마다 전체 테스트. 끝나면 PR과 `/debrief`. `/build #번호`로 이어 가고, `status:in-progress`가 아니거나 계획 문서가 이 기기에 없으면 멈춤 |
| `/logbook:debrief` | PR 직후 | 기준별 검증 증거, 프로젝트 문서와 코드 대조, 독립 리뷰(큰 PR은 영역별로 나눠서), 이슈마다 설계한 그림 결과 화면, 이슈와 PR을 링크한 CHANGELOG 한 줄. 다음 단계(머지·재리뷰·남은 지적 고치기·열어 두기)와 머지 방식(squash, merge commit)을 한 번에 질문 |
| `/logbook:sync` | 처음 도입할 때, 문서가 뒤처졌을 때 | 문서 구조가 없으면 물어서 정하고 AGENTS.md에 문서 규칙 문단을 씀. 옛 도구(paperclip 등)의 흔적과 자리 밖 문서 정리, 프로젝트 문서 작성과 동기화, 핸드북 게시. 도메인 규칙이 있는 프로젝트는 처음 쓸 때와 full일 때 업무 규칙 문서(`rules.md`) 초안을 코드에서 쓰고 규칙마다 객관식으로 확인 |

- hook(Claude Code가 특정 순간에 자동으로 실행하는 스크립트) 세 개가 함께 설치됩니다. 세션을 시작할 때마다 logbook 작업 규칙과 트래커 정보를 넣습니다(worktree에서도 원래 저장소의 설정을 읽습니다).
- 플랜을 제출하면 브리핑 블록이 없거나 HTML이 든 플랜을 되돌리고, 승인한 뒤에는 브리핑 화면을 만들어 채팅에서 한 번 더 승인받으라고 알립니다.
- 열린 PR에 디브리핑 표시(`<!-- logbook:debrief -->`)가 없으면 대화 종료를 한 번 막습니다.

## 문서를 두는 자리

문서를 어디에 둘지는 프로젝트가 정하고, AGENTS.md의 문서 규칙 문단(문서와 위치 표)에 적습니다. 이 문단은 logbook과 상관없는 프로젝트의 약속이라 logbook이 없는 사람도 따릅니다. logbook은 그 표의 위치를 읽고, 표가 없으면 아래 기본 위치를 씁니다.

| 기본 자리 | 담는 것 |
|---|---|
| `docs/system/` | 지금 시스템: 한눈에 보기, 기술 스택, 주요 흐름, 업무 규칙(도메인 규칙이 있을 때, `rules.md`), 데이터 모델(DB가 있을 때, 모든 테이블의 ERD) |
| `CHANGELOG.md` | 변경 이력: PR마다 한 줄, 이슈와 PR 링크, 버전별(버전이 없는 앱은 날짜별) |
| `docs/manual/` | 사용 설명서(있을 때) |

계획 문서(브리핑과 결과 보고의 원본)와 승인된 화면 시안의 사본은 작업용 문서라 저장소에 두지 않습니다. 원래 checkout(git worktree가 아닌 처음 clone한 폴더)의 `.logbook/plans/<이슈 번호>-<slug>.md`, `.logbook/designs/<이슈 번호>-<slug>/`에 두고, 결정 이유는 PR 본문에 남깁니다.

모든 문서는 컴퓨터공학 학부를 졸업했지만 이 프로젝트는 모르는 사람이 읽기 쉽게 씁니다. md 파일에는 HTML을 넣지 않고 그림은 mermaid로 그리며, AI 모델 호출은 모델과 프롬프트 요지를 그림에 적습니다. 기준은 [templates/writing.md](templates/writing.md)와 [templates/diagram-kit.md](templates/diagram-kit.md)에 있습니다.

## 개발

```bash
claude plugin validate .
bash tests/run.sh
scripts/system-check.sh
```

변경 이력은 [CHANGELOG.md](CHANGELOG.md)에 있고, 줄마다 이슈와 PR로 이어집니다. 결정 이유는 각 PR 본문에 있습니다.
