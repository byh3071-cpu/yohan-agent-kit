---
name: thought-to-prompt
description: >-
  Prompt factory orchestrator. Turns gated dumps into paste-ready prompts via
  prompt-forge then prompt-auditor then file+link report. Triggers - after
  dump-gate [공장], 프롬프트 공장, 완성 프롬프트. Wraps prompt-architect ideas;
  single output schema here.
---

# thought-to-prompt (factory orchestrator)

## Pipeline
0. Ensure dump-gate ran (or run it)
1. **prompt-forge** — draft only
2. **prompt-auditor** — PASS/FAIL; on FAIL, forge **one** rewrite using 수정지시 only, then auditor again once
3. **Main (you)** — write files, report paths, ask `[실행]|[복붙만]|[더 다듬어]`

## Pass-3 write paths (project repo only)
SoT: `<개발 루트>/.agents/operator/project-docs-paths.md`

> 개발 루트 = `.agents/` 디렉터리를 품은 상위 폴더. 확정할 수 없으면 사용자에게 묻는다.
- **Must** be inside active project git root:
  - prompt → `docs/prompts/<slug>-prompt.md`
  - brief (idea / plan_design / impl_plan) → `docs/briefs/<YYYYMMDD>-<slug>.md`
  - spec (plan_design only) → `docs/specs/<slug>-spec.md`
- No active project / workspace is the `<개발 루트>` only → **ask project path**; do **not** write product docs under `.agents/operator/`
- **Never auto-commit**

## After [실행] when kind needs a plan
1. Ensure brief exists under `docs/briefs/`
2. Owner confirms brief
3. Only then write short plan → `docs/plans/<YYYYMMDD>-<slug>-plan.md` (목표1 · 성공≤3 · 안함≤5 · 할일≤5)

## Report template
- kind, verdict, rewrite_count (0|1)
- Absolute paths to files
- Next: `[실행]` / `[복붙만]` / `[더 다듬어]`

## Re-entry (F8)
- Refine only → auditor → forge 1 → pass-3
- New long dump added → dump-gate again
- New topic → new run

## [실행] handoff (F9)
| kind | action |
|------|--------|
| research | research-brief → Notion |
| plan_design / impl_plan | brief confirmed → `docs/plans/` short plan → CreatePlan/planner |
| idea | offer prd-generator / interview-me |
| ops | master-orchestrator |
| decision | show options; wait |
| rumination | no execute |

## Phone / cafe
Cafe uses **Notion AI** pack, not this CLI 3-pass. When picking up Notion rows, if no audit trail → run auditor only before trust.

## 파이프라인 계약
계약 SoT: `<개발 루트>/.agents/SKILL_PIPELINE.md` (골 사이클 ②스펙)
- **받는 것:** 인계 표 `목표` · `아직 안 정한 것` · `산출물`(조사 산출 + **고르기**에서 취한 것).
  **인계 표가 있으면 dump-gate(0단계)를 건너뛴다** — 이미 정제된 입력이라 뇌덤프 분류가 불필요하다. 없을 때만 종래대로 dump-gate부터.
- **남기는 것:** `성공 정의` · `안 할 것` · `악수` (스펙의 본체) · `산출물`에 prompt/brief 경로 추가
- **다음:** 설계 · Plan 모드(하네스) 또는 `prd-validator`(에이전트) — **멈춤: 사람 고정** (스펙 승인은 사람)

### 인계 표 → prompt-forge (손으로 프롬프트 쓰지 않기)
pass 1에서 forge에 넘길 때 인계 표를 7섹션에 태운다.
**매핑표와 호출 시점(경계에서만) 규칙은 `SKILL_PIPELINE.md` §3 이 정본이다** — 여기 복사하지 마라(드리프트).
