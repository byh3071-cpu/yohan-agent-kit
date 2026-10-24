---
name: ship-it
description: 변경을 안전하게 출시(commit·push·release)할 때. pre-commit 점검→교차검증 게이트→두괄식 커밋→푸시. 게이트 통과 시 통과 커밋의 HEAD SHA를 .claude/.gate-pass에 바인딩(무관한 이후 변경의 자동통과 차단). 출시·배포 시 사용.
disable-model-invocation: true
allowed-tools: Bash(git add *), Bash(git commit *), Bash(git status *), Bash(git push *)
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# ship-it — 안전 출시

자동 실행 금지(`disable-model-invocation`). 사용자가 `/`로 호출하거나 shipper가 위임받았을 때만.

## 절차
1. `git status` / `git diff --cached`로 변경 확인.
2. **pre-commit 점검**: 비밀·대용량·토큰 패턴(pre-commit-check 훅이 한 번 더 강제).
3. **게이트**: cross-check 통과했는지 확인. 통과 못하면 여기서 중단.
4. **커밋**: 두괄식 한 줄 요약 + 본문(무엇을/왜).
5. **게이트 마커 바인딩**: 커밋 직후 그 커밋 해시를 마커에 기록 — `git rev-parse HEAD > .claude/.gate-pass`. 단순 touch·시간창(mtime) 방식 금지 → 검증된 바로 그 커밋에만 통과를 부여한다.
6. **푸시**: `git push`. critic-gate 훅이 `.gate-pass`의 SHA와 현재 HEAD를 대조 — 일치할 때만 통과, 마커 이후의 무관한 새 커밋은 자동 통과 못 함(게이트 미통과 시 확인 요청).

## 커밋 메시지 형식
타입: feat/fix/refactor/docs/chore/security

  <타입>: <두괄식 요약>

  - 무엇을 바꿨는지
  - 왜
