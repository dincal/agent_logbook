<!-- logbook:system sources=".claude-plugin/** hooks/** scripts/** templates/** tests/** agents/**" checked="2026-09-29" -->
# 기술 스택

## 구성과 기술 스택

logbook은 실행 서버 없이 Claude Code 안에서 동작하는 파일 묶음이고, 명령 설명서, hook, 스크립트, 템플릿으로 나뉩니다.

```mermaid
flowchart LR
  M["플러그인 정의 · JSON"] --> S["명령 5개 · Markdown"]
  M --> H["hook 2개 · POSIX sh"]
  M --> V["하위 에이전트 4개 · Markdown"]
  S --> P["스크립트 · bash와 Python 3"]
  H --> P
  P --> T["템플릿 · Markdown과 HTML"]
```

| 조각 | 기술 | 하는 일 | 고른 이유 |
|---|---|---|---|
| 플러그인 정의 | JSON(`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) | 이름, 버전, 설치 정보 | Claude Code와 Codex가 같은 파일로 설치합니다 |
| 명령 5개 | Markdown(`skills/<이름>/SKILL.md`) | rulebook, brief, mission, debrief, sync의 절차 | 에이전트가 읽는 설명서라서 코드가 필요 없습니다 |
| hook 2개 | POSIX sh와 jq(없으면 python3) | 플랜 미리보기, 결과 보고 확인 | 어느 환경에서나 도는 가장 흔한 셸입니다 |
| 스크립트 | bash, Python 3 표준 라이브러리 | 규칙 설치, 브리핑과 핸드북 렌더, 문서와 코드 대조, 옛 흔적 검사 | 따로 설치할 패키지가 없습니다 |
| 템플릿 | Markdown, HTML과 CSS | 계획 문서, 규칙 블록, 슬라이드 모양, 프로젝트 문서의 뼈대, 글쓰기와 그림 안내 | 한 곳을 고치면 모든 프로젝트에 적용됩니다 |
| 리뷰어 | Markdown(`agents/reviewer.md`) | PR을 새 컨텍스트에서 읽기만 하며 검토 | 품질 검사라 Claude Code에서는 Opus 모델, high effort로 실행합니다 |
| builder 3개 | Markdown(`agents/builder-fast.md`, `builder.md`, `builder-deep.md`) | 나눈 구현 트랙을 동시에 구현 | effort는 호출할 때 넘길 수 없어서 등급마다 파일을 따로 둡니다 |

## 배포와 실행 환경

logbook은 GitHub 저장소를 플러그인 마켓플레이스로 등록해 설치하고, 사용자의 PC에서 Claude Code가 불러 씁니다.

```mermaid
flowchart LR
  A["PR 머지"] --> B["마켓플레이스 갱신"]
  B --> C["플러그인 갱신"]
  C --> D["새 세션에서 사용"]
```

- 마켓플레이스 갱신은 `claude plugin marketplace update agent-logbook`, 플러그인 갱신은 `claude plugin update logbook@agent-logbook`입니다.
- 쓰는 PC에는 git, GitHub CLI(`gh`), python3가 있어야 합니다. jq는 있으면 쓰고, 없으면 python3로 대신합니다.
- Artifact와 `/design`은 claude.ai에 로그인한 Claude Code에서만 됩니다. 다른 곳에서는 로컬 HTML 파일을 씁니다.

## AI 모델

logbook은 역할마다 모델을 정해 두고, 본 작업은 사용자가 고른 세션 모델에 맡깁니다.

| 모델 | 고르는 설정(기본값) | 쓰는 곳 | 부르는 방법 |
|---|---|---|---|
| Opus 5.5, high effort | `agents/reviewer.md`의 `model: opus`, `effort: high` | 구현 후 결과 보고의 별도 리뷰 | Claude Code 하위 에이전트. 다른 하네스에서는 세션 모델 |
| Sonnet 5.5 | 스킬 문구의 `model: sonnet` | `/brief`, `/sync`, `/mission`의 코드 조사(Explore) | Claude Code 하위 에이전트. 다른 하네스에서는 세션 모델 |
| Sonnet 5.5, medium effort | `agents/builder-fast.md` | 규모는 있지만 정형화된 병렬 구현 트랙 | Claude Code 하위 에이전트 |
| 세션 모델, medium effort | `agents/builder.md`의 `model: inherit` | 범위가 분명한 병렬 구현 트랙 | Claude Code 하위 에이전트 |
| 세션 모델, xhigh effort | `agents/builder-deep.md`의 `model: inherit` | 까다로운 병렬 구현 트랙 | Claude Code 하위 에이전트 |
| 세션 모델 | 사용자가 Claude Code에서 고른 모델 | 모든 명령의 본 작업(조사 정리, 계획, 구현, 문서 작성) | Claude Code 세션 |
| `/goal`의 평가 모델 | Claude Code가 정함 | `/mission`으로 시작한 무인 실행이 끝났는지 판단 | Claude Code의 `/goal` |

- effort는 모델이 얼마나 깊이 생각할지 정하는 단계입니다(low, medium, high, xhigh, max).
- 사용자가 환경 변수 `CLAUDE_CODE_SUBAGENT_MODEL`에 모델을 적고 `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`을 켜면, 위 설정보다 그 모델이 앞섭니다. `FORCE` 없이 적기만 하면 위 설정이 앞섭니다.

## 개발 도구

테스트는 셸 스크립트 하나로 돌리고, 플러그인 구조는 Claude Code의 검사 명령으로 확인합니다.

| 할 일 | 명령 |
|---|---|
| 테스트 | `bash tests/run.sh` |
| 플러그인 구조 검사 | `claude plugin validate .` |
| 브리핑 렌더 | `scripts/render-brief.sh <계획 문서> brief <출력 파일>` |
| 핸드북 렌더 | `scripts/render-system.sh docs/system <출력 파일>` |
| 문서와 코드 대조 | `scripts/system-check.sh` |
