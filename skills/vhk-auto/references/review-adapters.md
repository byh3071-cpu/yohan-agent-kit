
> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# 독립 리뷰 어댑터

현재 호스트에서 실제로 제공되는 어댑터 하나만 고른다. 사용할 수 있는지 확인하지 못했거나 실행·인증이
실패하면 리뷰를 통과한 것으로 간주하지 않고 `blocked`로 끝낸다. 어떤 어댑터도 공통 Skill의 중단 조건을
완화할 수 없다.

| 호스트 | 독립 리뷰 1패스 |
|---|---|
| OpenAI Codex · Windows | `codex.cmd review --uncommitted` |
| OpenAI Codex · POSIX | `codex review --uncommitted` |
| Claude Code | 설치되어 있고 현재 세션에서 확인되는 `/code-review` Skill |
| Cursor · Google Antigravity | 현재 호스트가 제공하는 독립 리뷰 기능. 기능을 확인할 수 없으면 `blocked` |

리뷰의 자유 텍스트는 결함 신호로만 읽는다. 자동 합격 입력은 `vhk verify` 결과와 각 명령의 종료 코드뿐이다.
