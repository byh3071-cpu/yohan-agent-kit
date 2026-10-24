---
name: vhk-evolve-loop
description: "전면 보류된 과거 절차. VHK 문제 해결과 사용자 재개 승인 전에는 선택·실행하지 않는다. 검증 스킬은 자동 호출하지 않는다."
disable-model-invocation: true
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

> 2026-10-03 사용자 결정: 자동 선택·자동 호출 중단. 현재 작업에서 사용자가 명시적으로 요청한 경우에만 이 스킬을 사용한다.


# VHK Evolve Loop (L2 프로젝트)

**SoT:** `.vhk/memory.json` → `vhk evolve` → `RULES.md` (프로젝트만). VHK CLI 버그는 **vhk-dogfood-issue** (L1).

## 1. 기록

```powershell
vhk learn "한 줄 교훈 — why 포함"
vhk win "한 줄 성공 — reinforce"
```

팀 공유 필요 시 `docs/context/recurring-defects.md` 또는 ADR.

## 2. 패턴

```powershell
vhk pattern detect
vhk pattern list
vhk evolve suggest
vhk evolve list
```

## 3. 반영

- TTY + 사람 확인: `vhk evolve apply <id>` → `vhk sync`
- Headless/agent: `vhk evolve digest` → RULES 초안 제안만 (자동 apply 금지)

## 4. L3 후보

동일 교훈이 **2+ VHK 프로젝트**면 yohan-cc-skills 스킬/RULES 템플릿 PR 검토.

## 금지

- L1 CLI 결함을 learn만으로 끝내기 — vhk 레포 이슈 병행
- memory.json만 믿고 RULES 미갱신 (로컬 전용, gitignore)
