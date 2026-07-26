# yohan-cc-skills — AGENTS.md (에이전트 작동 규약)

> ⚡ 이 파일은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

## Loop Protocol
- 루프: `context → goal next → 작업 → goal check → goal done`
- 작업 시작 시 `.vhk/HARD_STOP` 확인 — 있으면 모든 자동화 즉시 중단.
- active goal 만 작업. `docs/state`(next-task/blockers)는 append-only.
- 교훈·결정·실패·성공은 `vhk memory`(memory v2 4버킷, 단일 출처).
- 게이트(tsc / test:run / build) 통과해야만 `vhk goal done`.

## Ecosystem (cross-repo)

> Contract SoT: yohan-brain `memory/core/ecosystem-contract.yaml` (obey when status=active).

- **Tier:** yohan-brain `memory/core/inheritance-registry.yaml`
- **Roster:** yohan-brain `memory/core/agent-roster.yaml` (CLI·모델·effort; obey when active)
- **Cursor:** `.cursor/rules/ecosystem.mdc` (vhk inject-bootstrap)
- **금지:** AGENTS.md 손수 편집 → `RULES.md` + `vhk sync`

## 기술 스택
- Markdown skills · Claude Code plugins
- PowerShell hooks (Windows primary)

## 코딩 규칙
- skills = SKILL.md + references; secrets in hooks 금지
- Claude-only ops: handoff · release-gate · parallel — Cursor duplicate 금지
- plugin manifest 변경 시 marketplace.json 정합
- 작업 단계 이동 = 바통 `docs/state/baton.yaml` 갱신 후 진행. 프롬프트 손으로 쓰지 말 것 — 계약 `C:\Users\Public\dev\.agents\SKILL_PIPELINE.md`

## 기록 규칙
- loop protocol → `plugins/yohan-core/loop.md`
- 패턴 문서 → `docs/patterns/`
- 작업 이어받기 = 바통 `docs/state/baton.yaml` (계약: `C:\Users\Public\dev\.agents\SKILL_PIPELINE.md`)
- 단계 이동 시 프롬프트를 손으로 쓰지 말 것 — 바통에서 생성. 사용법 `.agents/operator/pipeline-usage.md`
