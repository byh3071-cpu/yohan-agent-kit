---
name: "source-command-routing-review"
description: "상시 지휘자 라우팅 미스 주간 메타리뷰 — 미스 집계→클러스터→rubric diff PR (사람 게이트, 자동 머지 금지)"
---

# source-command-routing-review

Use this skill when the user asks to run the migrated source command `routing-review`.

## Command Template

# /routing-review — 라우팅 루프 주간 메타리뷰 (Goal 10 W2-3)

목적: 자동 감지된 라우팅 미스(`~/.Codex/.cache/routing-misses.jsonl`, W2-2 훅 산출)를 주기 검토해 roster `conductor_always_on.size_criteria`/rubric을 **근거 기반**으로 보정한다. 케이던스 = 주 1회. **자동 머지 절대 금지 — PR 오픈으로 종료.**

## 절차

1. **집계**: `powershell -File C:/Users/Public/dev/yohan-ecosystem/yohan-brain/ops/routing/collect-misses.ps1` 실행 → 오판 패턴·무선언·레포별 확인.
2. **클러스터**: `2회 이상` 반복된 오판 패턴만 조정 후보로 (예: `L→S` 반복 = 하드트리거 누락). **일회성 미스는 제외**(SoT 오염 방지 — 동일 미스 2회째부터 규칙 추가).
3. **골드셋 보강**: 반복 미스를 `ops/routing/routing-goldset.yaml` 케이스로 승격. holdout 비율 ~30% 유지. holdout:true 케이스는 이 리뷰에서 열지 말 것(과적합 감지용).
4. **수정안 제안**: roster `conductor_always_on.size_criteria`/`hard_triggers` 또는 `run-routing-eval.ps1`의 rubric diff. **rubric 길이 상한 200줄**.
5. **전후 검증**: `run-routing-eval.ps1 -Model sonnet`을 수정 전/후로 실행해 정확도·confusion 비교를 PR 본문에 첨부. (제안자=이 리뷰 ≠ 채점자=러너 — Goodhart 방지)
6. **PR 오픈으로 종료**. 머지는 사람. 브랜치는 worktree 격리(멀티세션 충돌 방지).

## 만들지 말 것
- 게이트 없는 자동 규칙 갱신 (mayur.ai 반면교사 — 효과 측정 불능·SoT 오염)
- LLM-as-judge (라우팅은 닫힌집합 → run-routing-eval의 문자열 일치 채점이 상위호환)
- 야간/매세션 케이던스 (주간 고정 — extremal Goodhart 방지)

## 참고
- 실측 교훈: goal 10 §2.5 (haiku 불안정→sonnet, 하드트리거 우선, PS5.1 BOM)
- SoT: yohan-brain `memory/core/agent-roster.yaml` `conductor_always_on`
