# 변경 이력

## [0.16.0] - 2026-10-21

이슈 [#39](https://github.com/dincal/agent_logbook/issues/39)

이슈 없이 여는 PR도 Slack에 PR마다 쓰레드를 하나 만들어 무엇을 바꾸는지와 반영 완료를 남깁니다.

### 추가

- 이슈 없는 PR(`Closes #n`이 없는 PR)은 `/debrief` 시작에 자기 Slack 쓰레드를 엽니다. 쓰레드 표시는 PR 댓글에 남습니다.
- PR 쓰레드에는 첫 메시지와 반영 완료 두 글만 올라오고, 피드백은 반영 완료 글에 한두 줄로 들어갑니다.
- PR 쓰레드의 진행 줄은 `확인 → 반영` 두 칸입니다.

### 바뀜

- `slack.sh`는 PR 쓰레드에 `close`가 아닌 단계나 `--backlog`를 올리면 Slack을 부르지 않고 종료 코드 2로 거부합니다.

## [0.15.0] - 2026-10-21

PR [#38](https://github.com/dincal/agent_logbook/pull/38)

### 추가

- logbook이 만드는 이슈(`/brief`의 이슈, `/discuss`의 backlog 이슈)에 트래커 줄의 gh 계정을 담당자(assignee)로 붙입니다. `/brief #<번호>`로 이어받는 이슈에도 더하고, 다른 사람이 이미 담당자이면 함께 두기, 바꾸기, 그대로 두기 중에서 묻습니다.

## [0.14.0] - 2026-10-21

이슈 [#36](https://github.com/dincal/agent_logbook/issues/36) · PR [#37](https://github.com/dincal/agent_logbook/pull/37)

Slack 쓰레드의 글을 Block Kit으로 바꿔 단계마다 아이콘을 붙인 큰 제목이 보이게 하고, 첫 메시지와 각 글에 진행 단계(계획 → 만들기 → 확인 → 반영)를, 끝난 쓰레드에는 답글이 전달되지 않는다는 안내를 붙였습니다.

### 바뀜

- 단계 이름을 기획자 말로 바꿨습니다: 개발 시작(브리핑 승인), 개발 끝(묶음 끝, 마지막 묶음 뒤 한 번만), 마지막 확인(PR), 완성 보고(디브리핑), 반영 완료(머지와 닫힘), 피드백 반영(피드백 요약).
- `개발자용:` 줄, 첨부 설명, 첨부 실패 안내는 작은 회색 꼬리말로 내려갑니다.
- `slack.sh post <이슈> close`는 `--outcome merged|dropped`를 반드시 받고, `approve`는 중단할 때 `--outcome later|dropped`를 받습니다.

### 추가

- 시안을 승인 전에 먼저 올리는 `mockup` 단계(🎨 시안)를 추가했습니다. `design`(✅ 시안 승인)은 글만 올립니다.
- 첫 메시지 고치기가 실패하면 `slack.sh thread <이슈>`로 글을 다시 올리지 않고 고칠 수 있습니다. 이 변경 전에 만든 쓰레드는 `slack.sh thread <이슈> --text`로 새 형식이 됩니다.

## [0.13.0] - 2026-10-21

이슈 [#34](https://github.com/dincal/agent_logbook/issues/34) · PR [#35](https://github.com/dincal/agent_logbook/pull/35)

이슈마다 Slack 쓰레드를 하나 만들어 진행 상황과 결정사항, 브리핑과 결과 화면을 올리고, 쓰레드에 달린 답글은 단계마다 읽어 사용자에게 알리게 했습니다. 채널(AGENTS.md의 채널 줄이나 환경 변수 `LOGBOOK_SLACK_CHANNEL`)이 정해지지 않은 저장소는 지금과 똑같이 동작합니다.

### 추가

- `scripts/slack.sh`: 쓰레드 만들기, 단계별 게시(시안 승인, 브리핑, 승인, 묶음 끝, 확인할 결과, PR, 디브리핑, 머지와 닫힘, 피드백 요약), 답글 읽기, 화면의 PNG와 독립 실행용 HTML 만들기
- `/rulebook --slack-channel <ID>`: 채널 ID를 AGENTS.md에 한 줄로 적습니다. 채널 줄이 없는 프로젝트는 환경 변수 `LOGBOOK_SLACK_CHANNEL`의 채널을 씁니다. 봇 토큰은 환경 변수 `LOGBOOK_SLACK_TOKEN`에 둡니다.
- `templates/slack-app.yml`: Slack 앱 매니페스트(앱 이름과 권한을 적은 설정 파일)
- 쓰레드 첫 메시지에는 GitHub에 들어갈 수 없는 기획자를 위해 이슈 내용을 쉬운 말로 풀어 씁니다(`slack.sh thread --text`, 이미 있는 쓰레드는 첫 메시지를 고칩니다).
- `templates/planner.md`: 쓰레드에 올리는 글을 기획자도 읽을 수 있게 쓰는 안내(브리핑은 유저 스토리, 디브리핑은 "이렇게 테스트해 보세요")
- 사용 설명서에 Slack 쓰레드 준비와 사용법, 한계를 추가했습니다.

## [0.12.1] - 2026-10-13

PR [#33](https://github.com/dincal/agent_logbook/pull/33)

### 바뀜

- `logbook:builder-deep`의 effort를 xhigh에서 high로 낮췄습니다. 모델은 그대로 세션 모델을 따릅니다.

## [0.12.0] - 2026-10-12

이슈 [#31](https://github.com/dincal/agent_logbook/issues/31) · PR [#32](https://github.com/dincal/agent_logbook/pull/32)

에픽을 없애 요청 하나를 이슈 하나와 PR 하나로 처리하고, `/brief`가 사람이 정할 것을 모두 객관식으로 물은 뒤 트랙 그래프까지 계획하면 새 명령 `/build`가 그래프대로 나눠 만들게 했습니다. 브리핑과 결과 보고는 이슈마다 그림으로 설명하는 화면으로 바꿨습니다.

### 바뀜

- `/brief`는 구조, 동작, 기술, 계약 네 관점으로 열린 결정을 찾고, 사람이 정할 것(쓰는 방식, 도메인 규칙과 예외 상황, 득실이 있는 기술 선택)을 모두 묻습니다. 이미 정해진 것과 조정값은 에이전트가 정하고 브리핑에 표시합니다.
- 선택지를 나열할 수 있는 질문은 세션 규칙과 모든 스킬에서 질문 도구로 객관식으로 묻습니다. 안내는 `templates/questions.md`에 있습니다.
- 계획 문서의 `## 상세`에 트랙 그래프(묶음, 트랙, 맡을 에이전트, 바꿀 파일, 기다리는 트랙, 위험, 확인 명령)를 씁니다. 단계 장은 없어졌습니다.
- 브리핑은 이슈마다 설계하는 그림 화면(`templates/briefing.md`)으로 만들고, 글 브리핑은 이슈 본문에 넣으며, 승인은 채팅에서 받습니다. 버튼과 움직임은 꼭 필요할 때만 쓰고, 승인된 화면 시안은 화면 안에 넣습니다.
- 플랜 모드에서는 플랜을 승인한 뒤 브리핑 화면을 만들어 채팅에서 한 번 더 승인받습니다. 플랜 hook은 미리보기 창을 띄우지 않고 브리핑 블록과 HTML만 검사합니다.
- `/debrief`는 결과 보고를 같은 방식의 그림 화면으로 만들고, 다음 단계와 머지 방식(squash, merge commit)을 한 번에 묻습니다.
- 슬라이드 렌더러(`scripts/render_brief.py`)는 핸드북과 markdown의 HTML 검사에만 씁니다.
- `/rulebook`이 만드는 이슈 라벨은 `status:*` 네 개입니다. 이미 있는 `epic` 라벨은 지우지 않습니다.

### 추가

- `/build`: 승인된 계획의 트랙 그래프대로 묶음 0의 공통 부분을 세션이 만들고, 묶음마다 builder 트랙을 Workflow 하나로 동시에 돌립니다. 묶음은 세션이 리뷰하고 합치는 단위라 크게 잡아, 공통 부분 다음에 나머지를 한 묶음으로 두는 것이 기본입니다. 위험한 트랙은 합치기 전에 리뷰하고, 트랙마다 커밋하며, 묶음마다 전체 테스트를 돌린 뒤 PR과 `/debrief`로 넘깁니다. 끊기면 `/build #번호`로 이어 가고, `status:in-progress`가 아니거나 계획 문서가 이 기기에 없으면 멈춥니다.
- `logbook:checker`: 계획 문서를 쓰기 전에 대화 원문과 결정 목록을 읽고, 근거 없는 결정과 빠진 결정을 질문으로 돌려주는 읽기 전용 에이전트입니다(Opus, high).
- 업무 규칙 문서 `docs/system/rules.md`: 도메인 규칙이 있는 프로젝트에만 둡니다. `/sync`가 처음 쓸 때와 full일 때 코드에서 초안을 쓰고 규칙마다 객관식으로 확인받으며, `/brief`가 첫 도메인 규칙을 정할 때 만들고, 규칙을 바꾼 PR이 고칩니다.

### 지움

- 에픽, `epic` 라벨, 에픽 브랜치, 단계 이슈와 단계 PR, 에픽 리뷰를 지웠습니다. 큰 작업도 이슈 하나 안에서 트랙으로 나눠 만듭니다.
- 브리핑과 결과 보고의 고정 슬라이드와 플랜 승인 때 브라우저로 여는 미리보기를 지웠습니다.

## [0.11.0] - 2026-10-02

이슈 [#29](https://github.com/dincal/agent_logbook/issues/29) · PR [#30](https://github.com/dincal/agent_logbook/pull/30)

에픽 단계는 유저 스토리가 명확히 갈릴 때만 크게 나누고, 단계 안에서 독립 트랙을 builder 에이전트에 동시에 맡기는 것을 기본으로 했습니다.

### 바뀜

- 에픽 단계는 유저 스토리가 갈리는 곳에서만 나눕니다. 같은 스토리의 토대 작업과 기능은 한 단계에 두고, 스토리가 하나면 크더라도 이슈 하나로 계획합니다.
- 한 이슈나 단계 안에 독립 트랙이 둘 이상이면 나누는 것이 기본입니다. 나누지 않으면 시작할 때 이유를 한 줄 적고 결과 보고에도 남깁니다. 규칙 이름은 "독립 트랙은 나눠서 동시에 만든다"로 바뀌었습니다.
- builder 트랙으로 만들었거나 2,000줄 이상 바뀐 PR은 `/debrief`의 첫 리뷰를 영역별 리뷰어와 이음새 리뷰어(영역이 만나는 곳을 보는 리뷰어)로 나눠 동시에 돌립니다.

### 지움

- 서로 기다리지 않는 에픽 단계를 단계마다 worktree에서 동시에 만들던 장치와, `/debrief`의 단계 worktree 처리를 지웠습니다. 단계는 표 순서대로 하나씩 진행합니다.

## [0.10.0] - 2026-10-01

이슈 [#27](https://github.com/dincal/agent_logbook/issues/27) · PR [#28](https://github.com/dincal/agent_logbook/pull/28)

git worktree(한 저장소를 여러 폴더에 동시에 checkout하는 git 기능)는 물어보고 만들고, 병렬 트랙과 병렬 단계에만 에이전트 판단으로 쓰게 했습니다.

### 바뀜

- 이슈와 에픽은 원래 checkout에서 브랜치만 바꿔 진행합니다. 에픽을 시작한다고 worktree를 만들지 않고, 원래 checkout을 쓰면 안 될 이유(커밋하지 않은 변경, 그 폴더에서 돌아가는 서비스, 다른 세션의 작업)가 보이면 만들기 전에 묻습니다.
- 병렬로 할지와 어디서 돌릴지는 구현할 때 에이전트가 정하고, 브리핑에 적거나 묻지 않습니다. 브리핑은 스펙만 정합니다.
- builder 트랙은 같은 폴더에서 돌리거나 트랙마다 worktree를 받습니다. worktree 트랙은 전체 테스트를 돌리고 트랙 브랜치에 커밋합니다.
- 서로 기다리지 않는 에픽 단계는 단계마다 worktree에서 동시에 만들 수 있습니다. PR과 합치기는 표 순서대로 하나씩 하고, 에픽 브랜치가 움직였으면 `/debrief`가 받아와 다시 확인합니다.

### 추가

- `scripts/worktree.sh`(add, remove, path): 원래 checkout의 `.logbook/worktrees/`에 기준 브랜치를 정해 worktree를 만들고, git이 무시하는 `.env` 파일을 링크합니다. 합친 뒤 바로 지우며, 커밋하지 않은 변경이 있으면 지우지 않습니다.

## [0.9.0] - 2026-10-01

이슈 [#25](https://github.com/dincal/agent_logbook/issues/25) · PR [#26](https://github.com/dincal/agent_logbook/pull/26)

계획 문서와 승인된 시안 사본을 저장소에서 빼고, 변경 이력은 CHANGELOG에 이슈와 PR 링크로 남기게 했습니다. 저장소에는 logbook이 없는 사람도 읽을 문서만 남습니다.

### 바뀜

- `/brief`는 계획 문서를 원래 checkout(git worktree가 아닌 처음 clone한 폴더)의 `.logbook/plans/<번호>-<slug>.md`에 쓰고 커밋하지 않습니다. 승인된 시안 사본도 `.logbook/designs/<번호>-<slug>/`에 둡니다. 플랜 모드의 계획은 승인 뒤 원래 checkout의 `.logbook/plans/<번호>-<slug>.md`로 옮깁니다(worktree에서 세운 플랜도 이때 옮겨집니다).
- 결정 이유(사용자가 정한 것과 버린 대안, 알린 우려, 에이전트가 정한 것)와 시안 링크는 PR을 열 때 PR 본문에 적습니다. `/debrief`는 계획과 달라진 점과 증거를 PR 본문에 더합니다.
- `/debrief`가 CHANGELOG에 이슈와 PR을 링크한 한 줄을 씁니다. 이미 있는 CHANGELOG는 그 위치와 형식을 따르고, 없으면 루트에 Keep a Changelog 형식으로 만듭니다. 버전이 없는 앱은 날짜별로 쌓습니다. 에픽은 단계마다 쓰지 않고 에픽 PR이 한 줄로 씁니다.
- `/brief`에서 나중에 하기를 고르면 계획 문서 전문을 이슈 댓글로 남기고, `/brief #<번호>`는 로컬 계획 문서가 없으면 그 댓글에서 이어서 합니다. 에픽은 단계 표, 완료 조건, 주요 결정을 에픽 이슈 본문에, 단계의 완료 조건을 단계 이슈 본문에 두어 다른 기기에서도 이어 갈 수 있게 했습니다. 에픽 PR과 `/sync` PR 본문에도 주요 결정을 적습니다.
- 문서 규칙 문단(`templates/docs-rules.md`)의 "변경 기록", "승인된 화면 시안" 줄을 "변경 이력: `CHANGELOG.md`" 줄로 바꿨습니다. `/sync`는 문서 구조를 정할 때 CHANGELOG 형식(버전별, 날짜별)도 묻고, 실행할 때마다 0.9 이전에 커밋된 계획 문서와 시안 사본이 남았는지 확인합니다.
- 이 저장소의 `docs/plans/`를 지우고, `docs/system/overview.md`의 근거 링크를 PR 링크로 바꿨습니다. 옛 버전 항목에 이슈와 PR 링크를 더했습니다.

### 옮기는 법

- 0.9 이전에 커밋한 `docs/plans/`, `docs/designs/`가 있는 프로젝트는 `/logbook:sync`를 실행합니다. 지우기 전에 로컬 `.logbook/`으로 복사하고, 계획 문서마다 CHANGELOG에 한 줄을 남기며, 그 문서를 가리키던 링크를 PR로 바꿉니다.
- AGENTS.md 문서 표의 "변경 기록", "승인된 화면 시안" 줄은 `/sync`가 정리할 때 "변경 이력" 줄로 바꿉니다. `/rulebook`은 이 문단을 고치지 않습니다.

## [0.8.0] - 2026-10-01

이슈 [#22](https://github.com/dincal/agent_logbook/issues/22) · PR [#24](https://github.com/dincal/agent_logbook/pull/24)

전체 리뷰에서 찾은, 스킬 사용 흐름에서 틀리게 동작하는 부분을 고쳤습니다([#22](https://github.com/dincal/agent_logbook/issues/22)).

### 고침

- `/sync`가 문서 구조를 정한 뒤 `rulebook.sh`를 다시 실행하면서 `.logbook/config.json`의 gh 계정을 빈 값으로 덮던 문제를 고쳤습니다. `rulebook.sh`는 인자로 받지 않은 값(repo, 기본 브랜치, gh 계정)을 기존 `config.json`에서 이어받고, `/sync`는 더 이상 `rulebook.sh`를 부르지 않습니다.
- 결과 보고가 없는 PR 브랜치에서 Stop hook이 턴마다 막던 문제를 고쳤습니다. 확인한 커밋을 기록해, 같은 커밋에서는 한 번만 막고 새 커밋이 생기면 다시 한 번 막습니다.
- HTML 검사가 `<path>`, `<label>` 같은 자리표시자를 HTML로 보던 오탐을 고쳤습니다. 닫는 태그, 속성이 있는 태그, `<br>` 같은 빈 요소, 자리표시자로 쓰지 않는 이름(`div`, `span` 등)은 지금처럼 잡습니다.

### 바뀜

- 플랜 모드의 계획 파일 위치(`plansDirectory`)를 git이 무시하는 `.logbook/plans`로 바꿨습니다. 승인된 계획만 `docs/plans/<번호>-<slug>.md`로 옮기므로, 작은 수정의 계획 파일이 저장소에 남지 않습니다.
- `/brief`에서 중단을 고르면 "나중에 하기 / 버리기"를 묻습니다. 나중에 하기는 이슈를 `status:backlog`로 돌리고 브랜치를 남겨 `/brief #<번호>`로 이어서 하게 하고, 버리기는 이슈를 not planned로 닫고 브랜치를 지웁니다.
- 코드보다 뒤처졌다고 나온 문서가 그대로 맞으면 첫 줄 주석의 `checked` 날짜만 고쳐 커밋합니다. `/sync` 규칙, 문서 템플릿, `system-check.sh`의 안내에 적었습니다.
- `/sync`가 문서 구조를 처음 정할 때는 이 변경의 계획 문서를 방금 고른 변경 기록 위치에 씁니다.
- `render-brief.sh`와 `render-system.sh`에 `--standalone` 옵션을 더했습니다. 게시하지 않고 로컬 파일로 열 HTML에 doctype을 붙입니다.

### 지움

- `scripts/legacy-scan.sh`와 `scripts/legacy_scan.py`. paperclip에서 옮겨 오는 일이 끝나서, 옛 도구 이름이 나오기만 해도 걸리는 오탐만 남았습니다. `/sync`는 정리할 것을 `git ls-files`로 직접 찾습니다.
- `rulebook.sh`의 `--plans` 옵션과 계획 폴더(`docs/plans/.gitkeep`) 만들기.

### 옮기는 법

- 0.8 이전에 설치한 프로젝트에서 `/logbook:rulebook`을 한 번 실행하면 `.claude/settings.json`의 `plansDirectory`가 `.logbook/plans`로 바뀝니다. 실행하기 전에는 세션 규칙에 안내가 붙고, 계획 파일은 지금처럼 예전 위치에 저장됩니다. 남아 있는 임의 이름의 계획 파일은 지워도 됩니다.

## [0.7.0] - 2026-10-01

이슈 [#20](https://github.com/dincal/agent_logbook/issues/20) · PR [#21](https://github.com/dincal/agent_logbook/pull/21)

작업 규칙을 프로젝트에 복사하지 않고 플러그인이 세션마다 넣게 했습니다. 플러그인을 올린 뒤 프로젝트마다 `/rulebook`을 다시 실행할 필요가 없습니다.

### 바뀜

- SessionStart hook(`hooks/session-rules.sh`)을 더했습니다. `.logbook/config.json`이 있는 저장소에서 세션을 시작하거나 다시 열거나 비우거나 압축할 때마다 `templates/session-rules.md`의 규칙과 트래커 정보(repo, 기본 브랜치, gh 계정)를 넣습니다. worktree에서는 원래 저장소의 설정을 읽고, 다른 hook 두 개도 같은 방식으로 바꿨습니다.
- `/rulebook`은 clone마다 한 번 logbook을 켜는 명령이 됐습니다. AGENTS.md에 규칙 블록을 쓰지 않고, 0.7 이전의 블록이 있으면 지우면서 그 안의 문서 규칙을 같은 자리에 일반 문단(`templates/docs-rules.md`)으로 옮깁니다. `--plans`로 변경 기록 위치를 받습니다.
- 문서 규칙(문서와 위치 표, 코드와 함께 고치는 약속)은 logbook과 상관없는 프로젝트의 약속으로 AGENTS.md에 둡니다. 스킬과 스크립트는 그 표의 위치를 따르고, 표가 없으면 기본 위치(`docs/system/`, `docs/plans/`, `docs/designs/`, `docs/manual/`)를 씁니다. `legacy-scan.sh`는 `--system`, `--plans`, `--designs`, `--manual`을 받습니다.
- `/sync`는 문서 구조가 AGENTS.md에 없거나 문서가 그 틀을 따르지 않으면 구조를 먼저 묻고, 문서 규칙 문단을 쓴 뒤 문서를 만듭니다. 틀을 따르면 지금처럼 뒤처진 문서만 고칩니다.
- `/brief`, `/debrief`, `/discuss`는 트래커 정보를 AGENTS.md가 아니라 hook이 넣은 규칙에서 읽습니다.

### 지움

- AGENTS.md 규칙 블록과 그 버전 번호(v8까지). 원문은 `templates/session-rules.md`로 옮겼습니다.

### 옮기는 법

- 0.7 이전에 설치한 프로젝트에서 `/logbook:rulebook`을 한 번 실행합니다. 옮기기 전에도 새 규칙은 들어가고, 옛 블록이 남아 있다는 안내가 함께 붙습니다.

## [0.6.0] - 2026-10-01

이슈 [#17](https://github.com/dincal/agent_logbook/issues/17) · PR [#19](https://github.com/dincal/agent_logbook/pull/19)

`/mission`을 없애고 `/brief` 하나가 작업 하나와 에픽을 모두 계획하게 했습니다. `/goal` 문장을 만드는 기능도 없앴습니다.

### 바뀜

- `/brief`는 여러 단계로 나뉘는 작업을 에픽(`epic` 라벨 이슈와 단계 이슈, 단계 계획 문서, `epic/<번호>-<slug>` 브랜치)으로 계획합니다. 브리핑을 승인하면 세션이 다시 승인을 묻지 않고 PR과 디브리핑까지 끝냅니다. 에픽이면 단계 사이에서 멈추지 않고 단계를 차례로 에픽 브랜치에 합친 뒤 에픽 PR까지 갑니다. 단계가 조건을 못 채우면 멈추고 "고친 뒤 이어서 / 중단"을 묻습니다.
- 규칙 블록 v8: 요청 방식에서 `/goal`을 빼고, 에픽은 `/brief`로 계획한다고 바꿨습니다. 설치한 프로젝트에서 `/rulebook`을 다시 실행하면 바뀝니다.
- `/discuss`는 결론을 `/brief`로만 넘깁니다. `/debrief`의 에픽 단계 경로는 그대로이고, `/goal` 대신 `/brief`의 에픽 진행에서 불립니다.

### 지움

- `/mission` 스킬, `/goal` 문장 틀(`templates/goal.md`), 계획 문서의 `## Goal` 절. 측정값이 목표에 닿을 때까지 반복하는 작업은 [#18](https://github.com/dincal/agent_logbook/issues/18)에서 따로 다룹니다.

## [0.5.0] - 2026-09-29

이슈 [#15](https://github.com/dincal/agent_logbook/issues/15) · PR [#16](https://github.com/dincal/agent_logbook/pull/16)

에픽을 에픽 브랜치에서 한 번에 진행하고, 병렬 작업을 Workflow로도 띄울 수 있게 했습니다.

### 바뀜

- 규칙 블록 v7: "에픽은 에픽 브랜치에서"를 더했습니다. `epic` 라벨 이슈는 `/mission`으로 계획하고 `epic/<번호>-<slug>` 브랜치를 만들며, `/goal` 세션 하나가 단계를 차례로 진행합니다. "끝나면 고르게 한다"에는 에픽 단계 PR이 예외로 에이전트가 직접 합친다는 말을 더했습니다. 설치한 프로젝트에서 `/rulebook`을 다시 실행하면 바뀝니다.
- `/mission`은 에픽에 단계마다 목표를 따로 만들지 않고, 에픽 전체를 도는 `/goal` 문장 하나를 만듭니다. 단계별 계획 문서는 남기되 HTML은 에픽 계획 문서에만 만듭니다.
- `/debrief`는 PR의 base로 경로를 고릅니다. 에픽 단계 PR은 결과 HTML 없이, 완료 조건이 모두 ✅이고 확인된 심각한 지적이 없으면 에픽 브랜치에 squash로 합치고 단계 이슈를 `status:done`으로 옮깁니다. 그렇지 않으면 멈춥니다. 에픽 PR은 에픽 리뷰와 결과 보고를 거쳐 일반 머지로 합칩니다. 문서 대조 범위도 PR의 실제 base를 씁니다.
- 리뷰어에 에픽 모드를 더했습니다. 전체 diff 대신 단계 사이의 연결과 에픽 완료 조건을 봅니다.
- 병렬 구현 트랙과 조사(`/brief`, `/mission`, `/discuss`, `/sync`)를 서브에이전트나 Workflow로 띄웁니다. 새 안내 `templates/parallel.md`가 고르는 기준과 트랙별 모델 지정(builder 등급, 조사는 Sonnet)을 적습니다.
- `/brief`는 `epic` 라벨 이슈를 `/mission`으로 넘깁니다.
- 결과 보고 hook의 안내 문구에 에픽 단계 PR은 HTML 없이 PR 본문에만 남긴다는 말을 더했습니다. 동작은 그대로입니다.

## [0.4.1] - 2026-09-29

이슈 [#13](https://github.com/dincal/agent_logbook/issues/13) · PR [#14](https://github.com/dincal/agent_logbook/pull/14)

이슈를 다른 개발자가 알아야 하거나 꼭 남길 작업에만 만들게 했습니다.

### 바뀜

- 규칙 블록 v6: "이슈부터 만든다"를 "이슈는 남길 일에만 만든다"로 바꿨습니다. 저장소를 고치지 않는 로컬 작업은 이슈, 브랜치, PR 없이 하고 채팅으로 보고합니다. 다른 작업에 따라오는 문서 갱신은 관련 작업의 PR에 얹고, 얹을 곳이 없으면 이슈 없는 PR로 엽니다. 애매하면 작업 전에 묻습니다. 설치한 프로젝트에서 `/rulebook`을 다시 실행하면 바뀝니다.
- 한 문장으로 설명되는 작은 수정은 이슈 없이 PR만 엽니다. `/brief`, `/debrief`, `/sync`가 이슈 없는 PR을 처리합니다.
- `/brief`, 플랜 모드, `/mission`은 받은 이슈의 댓글에 미뤄 둔 할 일이 있으면 같은 변경에 넣습니다.
- `/debrief`는 계획 문서가 없는 PR에서 결과 HTML 없이 PR 본문에 증거를 남깁니다. 한 문장 수정이 아니면 독립 리뷰는 그대로 합니다. 이슈를 받은 작은 수정은 `Closes #번호`로 그 이슈를 닫습니다.
- `/sync`가 뒤처진 문서만 고칠 때는 문서 수와 상관없이 이슈와 브리핑 없이 PR을 열고 리뷰를 받습니다.

## [0.4.0] - 2026-09-29

이슈 [#11](https://github.com/dincal/agent_logbook/issues/11) · PR [#12](https://github.com/dincal/agent_logbook/pull/12)

무엇을 만들지 정하기 전에 에이전트와 토론하는 명령을 더했습니다.

### 추가

- `/logbook:discuss`: 코드와 웹을 읽기만 하며 아이디어를 토론합니다. 에이전트는 근거를 대며 동의하거나 반론하고, 파일, 이슈, 브랜치를 건드리지 않습니다. 끝나면 요약을 보이고 `/brief`·`/mission`으로 넘기기, `status:backlog` 이슈로 남기기, 남기지 않기 중 권장안과 함께 고르게 합니다.

### 바뀜

- 규칙 블록 v5: "의견을 묻는 말에는 토론으로 답한다"를 더했습니다. 설치한 프로젝트에서 `/rulebook`을 다시 실행하면 바뀝니다.
- `/brief`는 토론 요약의 결정을 사용자가 정한 것으로 옮기고 남은 질문만 묻습니다. `status:backlog` 이슈를 받으면 `status:todo`로 바꿉니다.

## [0.3.1] - 2026-09-29

이슈 [#9](https://github.com/dincal/agent_logbook/issues/9) · PR [#10](https://github.com/dincal/agent_logbook/pull/10)

역할마다 모델을 맞게 고르고, 구현을 나눌 이득이 있으면 병렬로 맡기며, 사용자의 결정이 근거와 어긋나 보이면 알리게 했습니다.

### 바뀜

- 리뷰어를 Claude Code에서 Opus, high effort로 올렸습니다(이전 Sonnet, medium).
- `/brief`, `/sync`, `/mission`의 코드 조사 에이전트(Explore)는 Claude Code에서 Sonnet으로 띄웁니다.
- 규칙 블록 v4: "비합리적인 결정은 알린다"와 "구현은 이득이 있을 때만 나눈다"를 더했습니다. 설치한 프로젝트에서 `/rulebook`을 다시 실행하면 바뀝니다.
- 계획 문서 틀의 주요 결정 장에 "알린 우려" 줄을 두었습니다.
- 결과 보고의 리뷰 포인트에 리뷰에 걸린 시간과, builder가 맡은 트랙의 결과와 시간을 적습니다.

### 추가

- 병렬 구현 에이전트 세 개: `builder-fast`(Sonnet, medium), `builder`(세션 모델, medium), `builder-deep`(세션 모델, xhigh). 파일이 겹치지 않고 서로를 기다리지 않는 규모 있는 트랙이 둘 이상일 때만 씁니다. 실패한 트랙은 세션이 이어받습니다.

## [0.3.0] - 2026-09-29

이슈 [#7](https://github.com/dincal/agent_logbook/issues/7) · PR [#8](https://github.com/dincal/agent_logbook/pull/8)

md 문서가 md 뷰어에서도 잘 읽히도록 HTML을 뺐고, AI 모델 호출을 그림과 표로 자세히 적게 했습니다.

### 바뀜

- md 파일에는 HTML을 넣지 않습니다. 그림은 mermaid로 그리고, 숫자 요약은 굵은 숫자로 시작하는 목록(`- **9** 지운 파일: 설명`)으로 쓰면 슬라이드에서 타일이 됩니다. 비교와 구성은 표로 씁니다.
- `render-brief.sh`와 `render-system.sh`는 HTML이 든 md를 거부하고(종료 코드 4) 줄 번호를 알려 줍니다. `system-check.sh`는 HTML을 경고하고, 플랜 hook은 HTML이 든 플랜을 돌려보냅니다. 슬라이드 HTML을 거르던 정리 코드는 필요 없어져서 지웠습니다.
- AI 모델 호출 규칙: 흐름 그림에서 모델 호출을 육각형으로 그리고 모델 이름과 프롬프트 요지(넣는 것, 요청, 받는 것)를 적습니다. 그림 아래 표에 고르는 설정, 프롬프트 위치, 검사, 실패하면 어떻게 되는지를 적습니다. `stack.md`는 쓰는 모델을 표로 모읍니다.
- 규칙 블록 v3: "읽기 쉽게 쓴다"에 md의 HTML 금지와 모델 호출 설명 규칙을 더했습니다.
- 리뷰어가 모델 호출 설명과 md 안의 HTML도 봅니다.
- 이 저장소의 계획 문서와 프로젝트 문서에서 HTML을 걷어 냈습니다.

## [0.2.0] - 2026-09-28

이슈 [#3](https://github.com/dincal/agent_logbook/issues/3) · PR [#4](https://github.com/dincal/agent_logbook/pull/4)

프로젝트 문서를 코드와 맞추는 기능과, 기존 프로젝트를 logbook으로 옮기는 기능을 더했습니다. 브리핑 쓰는 방식도 바꿨습니다.

### 추가

- 명령 `sync`: 기존 프로젝트에 남은 옛 도구(paperclip 등)의 흔적과 자리 밖 문서를 정리하고, 프로젝트 문서 `docs/system/`(overview, stack, flows, data-model)을 코드에서 쓰거나 다시 씁니다. 규칙 블록이 없으면 `/rulebook`을 먼저 실행하라고 안내합니다.
- 스크립트 `system-check.sh`(문서가 설명하는 코드가 문서보다 나중에 바뀌었는지, ERD의 테이블 수가 스키마와 같은지 확인), `legacy-scan.sh`(옛 흔적과 자리 밖 문서 목록), `render-system.sh`(프로젝트 문서를 핸드북 슬라이드 하나로 렌더).
- 템플릿 `templates/system/`(프로젝트 문서 뼈대 네 개)와 `templates/writing.md`(모든 문서의 글쓰기 안내. 독자는 컴퓨터공학 학부를 졸업했지만 이 프로젝트는 모르는 사람).
- 화면 시안 단계: 화면을 새로 만들거나 크게 바꾸면 구현 전에 `/design` 캔버스(없으면 HTML)로 시안을 승인받고 사본을 `docs/designs/`에 남깁니다.
- `/debrief`가 프로젝트 문서를 코드와 대조하고, 머지 뒤 핸드북을 다시 게시합니다. 리뷰어도 `docs/system/`을 코드와 대조합니다.

### 바뀜

- 규칙 블록 v2: 사용 흐름이 달라지는 선택은 묻는다(사소한 것은 묻지 않음), 읽기 쉽게 쓴다, 프로젝트 문서를 코드와 맞춘다, 화면이 바뀌면 시안부터, 문서는 정해진 자리에 둔다.
- 그림 규칙: 그림으로 표현할 수 있는 것은 그림으로 표현하되 ERD와 흐름도는 억지로 그리지 않습니다. 브리핑과 디브리핑에는 주요 로직의 흐름과 DB 스키마 변화를 반드시 넣고, 프로젝트 문서의 ERD에는 모든 테이블을 넣습니다.
- 브리핑은 상사에게 보고하듯 결론과 요청부터 쓰고, 주요 결정은 사용자가 정한 것과 에이전트가 정한 것을 나눠 보여 줍니다.
- `/rulebook`은 기존 프로젝트에서 `/sync`를 안내합니다.

### 없앰

- 모든 브리핑에 흐름도와 ERD(또는 "ERD 변화 없음")를 요구하던 규칙, 플랜 모드 hook의 검사, 렌더러의 경고.

## [0.1.0] - 2026-09-28

이슈 [#1](https://github.com/dincal/agent_logbook/issues/1) · PR [#2](https://github.com/dincal/agent_logbook/pull/2)

첫 릴리스입니다.

### 추가

- 스킬 `rulebook`, `brief`, `mission`, `debrief`.
- 읽기 전용 리뷰어 에이전트 `reviewer`.
- hook `plan-preview`(플랜 승인 화면의 브리핑 미리보기)와 `debrief-gate`(디브리핑 없는 PR의 턴 종료 차단).
- 스크립트 `rulebook.sh`(규칙 설치, 멱등)와 `render-brief.sh`(계획 문서 → CTO 발표형 HTML).
- 템플릿: 상세 문서, 브리핑 HTML, `/goal` 문장, AGENTS.md 규칙 블록.
- 브리핑 자유 도식: `html`·`svg` 코드 블록과 도식 안내 `templates/diagram-kit.md`. 렌더러가 스크립트와 이벤트 핸들러를 지운다.
- 리뷰어는 Claude Code에서 Sonnet, medium effort로 실행한다. 다른 하네스는 세션 모델을 쓴다.
- 리뷰 원칙: PR마다 한 번, 리뷰 뒤 고친 게 동작을 바꾸면 고친 부분만 한 번 더. 리뷰 기록은 PR 본문의 `logbook:reviewed` 표식에 남긴다.
- `/debrief` 마지막 단계에서 재리뷰 필요 여부와 권장안을 알리고 머지·재리뷰·남은 지적 고치기·PR 열어두기를 고르게 한다.
- 브리핑과 디브리핑에 주요 로직 흐름도와 ERD 변화를 필수로 넣는다. 플랜 모드 hook이 검사하고 렌더러가 경고한다.
- 테스트 `tests/run.sh`(79개)와 사용설명서 `docs/manual/index.html`.
