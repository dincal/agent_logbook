<!-- logbook:system sources="{이 문서가 설명하는 코드의 경로 패턴. 예: README.md package.json}" -->
# {프로젝트 이름}

> 핸드북: {게시한 핸드북 링크. 처음 쓸 때는 이 항목을 지운다} · 저장소: {저장소 링크}

## 한눈에 보기

{누구에게 무엇을 해 주는 시스템인지 한 문장}

```html
<div class="tiles">
  <div class="tile"><div class="num">{N}</div><div class="what">주요 흐름</div><div class="how">{흐름 이름}</div></div>
  <div class="tile"><div class="num">{N}</div><div class="what">DB 테이블</div><div class="how">{DB 종류. DB가 없으면 이 타일을 지운다}</div></div>
  <div class="tile"><div class="num">{N}</div><div class="what">바깥 서비스</div><div class="how">{서비스 이름}</div></div>
</div>
```

## 시스템 지도

{쓰는 사람, 이 시스템, 바깥 시스템이 어떻게 이어지는지 한 문장}

```mermaid
flowchart LR
  U["{쓰는 사람}"] -->|"{무엇을 하나}"| S["{이 시스템}"]
  S -->|"{무엇을 주고받나}"| X["{바깥 시스템}"]
```

## 바꾸기 어려운 선택과 위험

{되돌리기 어려운 선택과 알려진 위험을 한 문장으로}

| 선택 또는 위험 | 내용 | 근거 |
|---|---|---|
| {DB, 인증, 배포처 같은 선택} | {무엇을 골랐고 왜 골랐는지} | {계획 문서 링크} |
| {위험이나 기술 부채} | {무엇이 문제이고 어떻게 다루는지} | |

## 용어

{이 시스템에서 쓰는 말 {N}개를 한 문장으로. 필요 없으면 이 절을 지운다}

| 용어 | 쉬운 설명 | 코드에서 부르는 이름 |
|---|---|---|
| {용어} | {설명} | `{이름}` |
