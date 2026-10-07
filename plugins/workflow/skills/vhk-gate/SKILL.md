---
name: vhk-gate
description: "전면 보류된 과거 절차. VHK 문제 해결과 사용자 재개 승인 전에는 선택·실행하지 않는다. 검증 스킬은 자동 호출하지 않는다."
disable-model-invocation: true
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# VHK Gate

코드·완료 주장 전 **반드시** 실행. red/BLOCK/skip이면 아래 분기 스킬로.

## 순서 (Windows)

```powershell
pnpm.cmd typecheck
pnpm.cmd test
pnpm.cmd lint
vhk verify
vhk receipt
vhk review
```

## 판정 분기

| 결과 | 다음 |
|---|---|
| verify red | `.vhk/reports/latest.json` → 수정 → 재실행 |
| receipt BLOCK | dirty/stale → commit 또는 `vhk receipt --mark-start` → **vhk-evolve-loop** |
| review skip (goal 0) | **vhk-goal-health** |
| review fail | **vhk-evolve-loop** + 앱 결함이면 수정 |

## L1 vs L2

- VHK CLI 버그/크래시 → **vhk-dogfood-issue**
- 프로젝트 반복 실수 → **vhk-evolve-loop**

## Pass criteria

verify exit 0 + receipt pass/caution + review pass (또는 skip 사유 goal-health 해결 후).

완료 선언 금지 until pass.
