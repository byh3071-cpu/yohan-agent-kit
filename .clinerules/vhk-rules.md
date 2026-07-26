# yohan-cc-skills — Cline Rules

> 코딩/디자인 전용. 기록/운영 → CLAUDE.md 참조.
> ⚡ 이 파일은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

## 필수 참조
- docs/PRD.md · docs/ARCHITECTURE.md · CLAUDE.md · RULES.md

## 기술 스택
- Markdown skills · Claude Code plugins
- PowerShell hooks (Windows primary)

## 코딩 규칙
- skills = SKILL.md + references; secrets in hooks 금지
- Claude-only ops: handoff · release-gate · parallel — Cursor duplicate 금지
- plugin manifest 변경 시 marketplace.json 정합
- 작업 단계 이동 = 바통 `docs/state/baton.yaml` 갱신 후 진행. 프롬프트 손으로 쓰지 말 것 — 계약 `C:\Users\Public\dev\.agents\SKILL_PIPELINE.md`
