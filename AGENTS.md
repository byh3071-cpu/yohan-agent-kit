# yohan-cc-skills — AGENTS.md (에이전트 작동 규약)

> ⚡ 이 파일은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

## Loop Protocol
- 루프: `context → goal next → 작업 → goal check → goal done`
- 작업 시작 시 `.vhk/HARD_STOP` 확인 — 있으면 모든 자동화 즉시 중단.
- active goal 만 작업. `docs/state`(next-task/blockers)는 append-only.
- 교훈·결정·실패·성공은 `vhk memory`(memory v2 4버킷, 단일 출처).
- 게이트(tsc / test:run / build) 통과해야만 `vhk goal done`.

## VHK Project Rules

> Project rules are generated from `RULES.md`; optional user rules use the generic rules-file contract.

- **Cursor:** `.cursor/rules/ecosystem.mdc` (vhk inject-bootstrap)
- **Optional rules:** `VHK_RULES_FILE` or `vhk config set-rules-file <yaml>`
- **금지:** AGENTS.md 손수 편집 → `RULES.md` + `vhk sync`

## 기술 스택
- 범용 Markdown skills · 전체 디렉터리 manifest
- Claude Code plugins
- PowerShell 5.1 hooks·설치 도구 (Windows primary)

## 코딩 규칙
- 범용 스킬 정본 = `skills/<name>/`; `SKILL.md` frontmatter는 `name`·`description`만 사용
- 범용 스킬 변경 시 `distribution/manifests/<name>.json` 전체 파일 manifest를 같은 PR에서 갱신
- 범용 스킬에 특정 PC 홈·Public/dev 절대경로 하드코딩 금지; 가장 가까운 프로젝트 규칙 우선
- 멀티에이전트 라우팅은 가장 가까운 AGENTS를 먼저 따르고, yohan 생태계 공통 작업은 yohan-brain의 active `memory/core/agent-roster.yaml`을 대조
- `vhk sync`는 AGENTS·Cursor 규칙 전파만 담당하며 사용자 홈 스킬을 설치하지 않음
- `Check`는 읽기 전용; `Install`·`Restore`는 홈 쓰기 승인과 최신 PlanDigest 필수, 내용 불일치 우회 금지
- Claude-only ops: handoff · release-gate · parallel — 범용 `skills/`에 중복 복사 금지
- secrets in skills·hooks·배포 기록 금지
- plugin manifest 변경 시 marketplace.json 정합

## 기록 규칙
- loop protocol → `plugins/yohan-core/loop.md`
- 범용 스킬 원본 조정·배포 감사 → `docs/audits/`
- 범용 스킬 설치 계약 → `docs/MULTIVENDOR_SKILL_DISTRIBUTION.md`
- 패턴 문서 → `docs/patterns/`
