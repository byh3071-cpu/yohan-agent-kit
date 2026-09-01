# 기록 규칙 (Yohan Agent Kit)

## 상태 안내
- 고정 Phase·다음 액션은 이 파일에 기록하지 않는다.
- 현재 상태는 GitHub Issue·PR과 해당 작업 문서를 기준으로 확인한다.

<!-- vhk:rules:start -->
> ⚡ 아래 규칙 섹션은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

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

<!-- vhk:rules:end -->
