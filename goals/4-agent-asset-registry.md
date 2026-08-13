---
vhk_format: 1
type: goal
id: 4
title: Agent 자산 Registry와 집 PC 인벤토리
status: IN_PROGRESS
priority: P0
---

# Goal 4: Agent 자산 Registry와 집 PC 인벤토리

## 선행조건

- yohan-brain PR #191이 `master`에 먼저 병합되어야 한다.
- yohan-cc-skills PR #73이 그다음 `main`에 병합되어야 한다.
- 구현은 병합된 `origin/main`의 깨끗한 격리 worktree에서 시작한다.

## 범위

- 저장소가 소유하는 Skill, Plugin, Agent, Command, Hook, Rule, MCP, Script, Template, Config, Manifest의 논리 자산 인벤토리
- 사람이 관리하는 `registry/assets.yaml`
- 결정론적으로 생성되는 `distribution/asset-catalog.json`
- 집 PC 사용자 홈의 read-only 발견·분류 도구와 sanitized 감사 문서
- `PORTABLE`, `ADAPTER_REQUIRED`, `VENDOR_SPECIFIC`, `PROJECT_SPECIFIC`, `LOCAL_ONLY`, `SECRET`, `DUPLICATE`, `LEGACY`, `UNKNOWN` 분류
- 프로젝트 전용 Agent와 반복 검증된 일반 Agent의 소유권 경계

## 비범위

- 사용자 홈 쓰기와 `~/.yohan-agent-kit/inbox/` 생성
- 외부 자산의 자동 복사·승격·push
- GitHub 저장소와 Marketplace 이름 변경
- release store와 실제 벤더 설치
- 요한 관제탑 UI·백엔드

## Completion Check (완료 조건)

- [ ] 모든 registry record가 `id`, `kind`, `owner`, `sourcePath`, `portability`, `vendors`, `lifecycle`, `provenance`, `license`, `requiredEnv`, `evidenceRefs` 필드를 정확히 가진다.
- [ ] 저장소 논리 자산의 미분류 항목과 중복 정본이 각각 0개다.
- [ ] `registry/assets.yaml`에서 catalog가 결정론적으로 생성되고 stale catalog를 검출한다.
- [ ] registry와 catalog에 API key·token·로그인 세션·Windows 절대경로가 없다.
- [ ] 집 PC 스캔은 read-only이며 raw 결과를 stdout 또는 명시적 로컬 경로로만 내보낸다.
- [ ] `html-doc`, `planning-diagrams`, 끊어진 `competitive-brief`·`interview-me`, 프로젝트 전용 `yohan-instagram-cardnews`의 현재 분류와 근거가 남는다.
- [ ] 프로젝트 전용 Subagent는 프로젝트에 남고 일반 Agent만 승격 후보가 된다는 계약이 문서화된다.
- [ ] Goal 4 gate, 기존 Goal 1·2·3 gate, secret scan, `git diff --check`가 통과한다.

## 사람 게이트

- 사용자 홈 raw Inbox 쓰기
- 외부 Skill fork 또는 라이선스 미확정 자산 편입
- registry candidate의 `approved` 또는 `released` 승격

