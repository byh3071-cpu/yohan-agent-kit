---
name: vhk-bootstrap-cursor
description: "전면 보류된 과거 절차. VHK 문제 해결과 사용자 재개 승인 전에는 선택·실행하지 않는다. 검증 스킬은 자동 호출하지 않는다."
disable-model-invocation: true
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# VHK Bootstrap Cursor (설치 + 배선)

**목표:** `vhk doctor` green + **goal/receipt/review/learn 루프 연결** + gate 1회 PASS.

## Phase 0 — CLI

```powershell
vhk doctor
vhk context
vhk brief
vhk sync
vhk mcp-init
```

## Phase 1 — Goal (필수)

```powershell
vhk goal list
```

- silent skip 있으면 → **vhk-goal-health**
- 없으면 `goals/_meta.md` + active goal 1개

## Phase 2 — Cursor 산출물

| 산출물 | 최소 |
|---|---|
| `.cursor/rules/` | context, windows-shell |
| `.cursor/skills/` | vhk-gate, vhk-evolve-loop, vhk-dogfood-issue, vhk-bootstrap-cursor, recap |
| `.cursor/hooks.json` | session-start, stop-recap |
| `docs/state/` | next-task, blockers |
| `docs/context/agent-compact.md` | 1페이지 |

프로젝트 skill은 **vhk-gate 위임** (로직 중복 금지).

## Phase 3 — 배선 검증

```powershell
vhk pattern detect
pnpm.cmd typecheck; pnpm.cmd test; pnpm.cmd lint
vhk verify
vhk receipt
vhk review
```

review skip → goal-health 재실행.

## Phase 4 — L1 갭

bootstrap 중 CLI 결함 → **vhk-dogfood-issue** (inject-bootstrap 누락, doctor goal 미검 등).

## 완료 기준

- `vhk goal list` ≥ 1 active
- vhk-gate skill 존재
- verify PASS; receipt not BLOCK (또는 사유 해소)
