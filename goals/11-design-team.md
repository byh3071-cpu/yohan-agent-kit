---
vhk_format: 1
type: goal
id: 11
title: 범용 Design Team 스킬과 프로젝트 컨텍스트 계약
status: DONE
priority: P0
completed: 2026-08-22
---

# Goal 11: 범용 Design Team 스킬과 프로젝트 컨텍스트 계약

## 배경

특정 제품이나 고정 모델 조합에 종속되지 않고, 어떤 프로젝트·도메인에서도 실제 소유 저장소와 맥락을 먼저 파악한 뒤 필요한 디자인 역할만 구성하는 재사용 가능한 스킬이 필요하다.

## 범위

- 공통 운영 방법과 프로젝트별 DesignContext를 분리하는 2계층 계약
- 조사·UX·비주얼·기술·적대 검토 역할의 동적 구성
- 사람 선택 전 production UI 구현 금지와 세 가지 시각 방향 게이트
- 독립 top-level 디자인 세션과 child worker의 정직한 구분
- provider/model/tool 영수증과 멀티벤더 배포 메타데이터
- 요한 관제탑을 첫 실제 프로젝트로 사용한 forward test

## Completion Check

- [x] `skills/design-team/`이 프로젝트 고유 경로·제품·미학·모델을 하드코딩하지 않는다.
- [x] DesignContext가 대화 기억이 아니라 프로젝트 소유 versioned source of truth에서 다시 해석 가능하다.
- [x] 기존 `design-to-html`과 책임이 겹치지 않고 승인된 반응형 HTML만 구현 단계로 넘긴다.
- [x] 스킬 validator, 자산 registry/catalog, manifest 검증이 통과한다.
- [x] 요한 관제탑과 비요한 분야 시나리오에서 범용성을 독립 검토한다.

## Forbidden

- 프로젝트 사실·비공개 원문·시크릿을 공통 스킬에 축적
- 사용자 선택 없이 시각 방향 승인 또는 production UI 구현
- 확인할 수 없는 이미지 백엔드 모델명을 영수증에 기록
- 홈 디렉터리 설치·릴리즈·publish·main 직접 push

## 계보 메모

이 Goal은 `codex/design-team-skill` 격리 worktree의 작업 계보다. 기존 IN_PROGRESS Goal은 다른 작업 계보이므로 이 브랜치에서 상태를 변경하지 않는다.
