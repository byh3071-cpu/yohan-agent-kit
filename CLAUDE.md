# 기록 규칙 (yohan-cc-skills)

## 현재 상태
- **Phase:** **FILL**
- **블로커:** 없음
- **다음 액션:** **FILL**
- **마지막 업데이트:** 2026-07-27

<!-- vhk:rules:start -->
> ⚡ 아래 규칙 섹션은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

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

<!-- vhk:rules:end -->
