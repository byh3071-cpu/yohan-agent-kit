---
name: vhk-goal-health
description: "전면 보류된 과거 절차. VHK 문제 해결과 사용자 재개 승인 전에는 선택·실행하지 않는다. 검증 스킬은 자동 호출하지 않는다."
disable-model-invocation: true
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

> 2026-10-03 사용자 결정: 자동 선택·자동 호출 중단. 현재 작업에서 사용자가 명시적으로 요청한 경우에만 이 스킬을 사용한다.


# VHK Goal Health

## 진단

```powershell
vhk goal list
vhk review
```

`스키마 불일치로 무시` / `goal 없음` → frontmatter修復.

##修復

각 `goals/*.md` frontmatter:

```yaml
---
type: goal
id: 4          # 숫자
title: ...
status: IN_PROGRESS   # NOT_STARTED | IN_PROGRESS | DONE (대문자 enum)
---
```

Legacy 매핑: `active`→`IN_PROGRESS`, `done`→`DONE`, `pending`→`NOT_STARTED`

- legacy `id`만 있으면 `type: goal` 추가
- `goals/_meta.md` 없으면 `vhk goal init` 참고 생성

## 검증

```powershell
vhk goal list    # 4 files recognized
vhk goal peek    # IN_PROGRESS 1개
vhk review       # skip 아님
```

## L1

doctor/goal list가 legacy status를 경고 없이 무시 → **vhk-dogfood-issue** (#465, #467 follow-up).
