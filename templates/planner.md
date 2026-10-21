# Writing for planners

Every Slack post logbook makes is read by planners and other people who do not write code. This guide says how to write them. The briefing and debriefing posts are full planner documents; the other posts are a few plain sentences.

## The reader

A planner who knows the product and its users well and knows nothing about how it is built.

- They think in people and what those people can do: a member signs up, an admin approves a refund.
- They do not know code, files, commands, git, pull requests, reviews, tests by name, APIs, databases, agents, waves or tracks, and they should not need to.
- They read Slack on a phone between meetings: short lines, the point first.
- They cannot open GitHub. Everything they need is in the Slack text itself; a link is never the only place something is said.

## Rules

1. Say what a person can do, see or decide, not how the system does it. "회원은 비밀번호를 잊어도 이메일로 다시 만들 수 있습니다", not "reset 토큰 API를 추가합니다".
2. Leave out developer words. Replace them with what they mean for the user, or drop them:

   | Developer word | Write instead |
   |---|---|
   | API, endpoint, DB, 테이블, 스키마 | 저장하는 정보, 화면, 기능의 이름 |
   | PR, 머지, 브랜치, 커밋 | 반영, 합치기 전 마지막 확인 |
   | 코드 리뷰, 리뷰 회차, 지적 | (drop it) |
   | 테스트 통과, e2e, CI | 확인을 마쳤습니다 |
   | 트랙, 묶음, 에이전트, 빌드 | 부분, 단계 |
   | 버그, 예외, 에러 처리 | 이럴 때는 이렇게 됩니다 |

3. Developer links (the PR, the issue) go in one last line, `개발자용: <link>`, never in the body.
4. Write full Korean sentences in the polite report tone (~합니다). Short sentences, one point each. No emoji in the text (the script puts each stage's icon in the title), no exaggeration.
5. Slack formatting only: `*굵게*` for a heading line, `•` or `-` for bullets, `<url|글자>` for links. Slack does not render `#` headings or tables. The script adds the title, the progress line and the footer, so do not write them; keep the `개발자용:` line of rule 3, which the script moves into the footer.

## First message of the thread

The issue written out, so the thread makes sense without opening GitHub. Pass it to `slack.sh thread <issue> --text <file>`; the script adds the title on top and the GitHub link as the last line.

```
*무엇을*: 회원이 비밀번호를 잊어도 스스로 다시 만들 수 있게 합니다.
*왜*: 지금은 고객센터에 문의해야 해서 하루에 30건씩 요청이 들어옵니다.
*누구에게 좋은가*: 회원은 기다리지 않아도 되고, 고객센터는 이 일을 하지 않아도 됩니다.
```

- Write it from the issue body and its comments (and the `/discuss` summary when there is one), in the plain words of the rules above.
- Do not write the current state; the script shows the phase.

## Briefing post

What will be made and why, as user stories.

```
*한 줄 요약*: 회원이 비밀번호를 잊어도 스스로 다시 만들 수 있게 합니다.

*누가 무엇을 할 수 있게 되나*
• 비밀번호를 잊은 회원은 로그인 화면에서 "비밀번호 찾기"를 눌러 이메일로 새 비밀번호를 만들 수 있습니다.
• 고객센터 담당자는 더 이상 비밀번호 초기화 요청을 직접 처리하지 않아도 됩니다.

*달라지는 점*
• 지금: 고객센터에 문의해야 합니다. → 앞으로: 회원이 3분 안에 혼자 끝냅니다.

*정해진 것*
• 링크는 30분 동안만 쓸 수 있습니다.

*확인 부탁*
• 이메일 문구는 기획에서 정해 주세요.

개발자용: <issue link>
```

- One bullet per user story under 누가 무엇을 할 수 있게 되나: who, what they can do, and what gets better for them.
- 정해진 것 lists the decisions in plain words; leave out purely technical ones.
- 확인 부탁 holds the 판단 필요 items a planner can answer, or is left out.

## Debriefing post

What is finished, and how a planner can try it.

```
*완성되었습니다*: 회원이 비밀번호를 스스로 다시 만들 수 있습니다.

*이렇게 써 볼 수 있습니다*
1. 로그인 화면에서 "비밀번호 찾기"를 누릅니다.
2. 가입한 이메일을 넣고 "보내기"를 누릅니다.
3. 받은 메일의 버튼을 누르면 새 비밀번호를 만드는 화면이 나옵니다. 30분이 지나면 "링크가 만료되었습니다"가 보여야 합니다.

*계획과 달라진 점*
• 이메일 대신 문자로도 받을 수 있게 했습니다. 회의에서 요청이 있었습니다.

*아직 남은 것*
• 이메일 문구는 임시 문구입니다.

개발자용: <PR link>
```

- 이렇게 써 볼 수 있습니다 is numbered steps a planner can follow in the product: where to go, what to do, what they should see. Cover each user story from the briefing and the edge cases worth trying.
- Say where to try it (the test server, the app version) when that is known, otherwise say it will be available after it is merged.
- Leave out reviews, test commands and evidence; say only that it was checked.

## Other posts

One to three sentences each, the same plain words. Examples:

- 시안 (before approval): 회원 가입 화면 3개의 시안입니다. 의견이 있으면 이 글에 남겨 주세요.
- 시안 승인 (text only): 시안이 승인되었습니다.
- 개발 시작: 브리핑이 승인되어 개발을 시작합니다.
- 나중에 하기: 이번에는 만들지 않고 나중에 할 일로 남겼습니다. 기획 일정이 정해지면 다시 시작합니다.
- 중단: 만들지 않기로 했습니다. 같은 기능이 이미 있어서입니다.
- 개발 끝 (posted once): 비밀번호 찾기가 모두 만들어졌고 확인을 마쳤습니다.
- 확인할 결과: 실제로 눌러 본 화면입니다. 3번째 그림에서 만료 안내가 보여야 합니다.
- 마지막 확인: 만든 내용을 합치기 전에 마지막으로 확인하고 있습니다.
- 반영 완료: 반영을 마쳤습니다. 다음 배포부터 쓸 수 있습니다.
- 피드백 반영: 진행 중에 바뀐 것을 한 줄씩, 무엇을 요청했고 무엇이 달라졌는지 씁니다.
