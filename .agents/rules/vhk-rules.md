# Yohan Agent Kit — Antigravity Rules

> 코딩/디자인 전용. 기록/운영 → CLAUDE.md 참조.
> ⚡ 이 파일은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

## 필수 참조
- docs/PRD.md · docs/ARCHITECTURE.md · CLAUDE.md · RULES.md

## 세션 시작 필독
- 사용자 현재 상태는 `context/README.md`를 먼저 읽고 `context/CURRENT.yaml`에서 확인한다. 과거 이력은 `context/TIMELINE.yaml`, 안정 정보·프로젝트·출처는 같은 디렉터리의 정본을 따른다.
- 새 세션은 `node scripts/check-context-contract.mjs`로 정본과 포인터를 검증한다. 실패하거나 정본에 접근할 수 없으면 현재 사실을 추측하지 말고 확인 불가로 보고한다.
- 사용자 사실을 AGENTS·CLAUDE·Cursor 규칙에 복제하지 않는다. 과거 메모리·검색 결과·stale copy는 정본을 덮어쓰지 못한다. 새 사용자 수정은 정본 변경 검토 대상으로 남긴다.

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
