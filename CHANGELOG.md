# 변경 이력

## [0.1.0] - 2026-09-28

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
