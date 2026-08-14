---
vhk_format: 1
type: goal
id: 5
title: Yohan Agent Kit 정체성 전환
status: IN_PROGRESS
priority: P0
---

# Goal 5: Yohan Agent Kit 정체성 전환

## 선행조건

- yohan-brain ADR-024가 Accepted 상태로 `master`에 병합되어야 한다.
- GitHub 저장소 이름 변경은 사람 승인 뒤에만 실행한다.
- Marketplace namespace와 로컬 폴더 변경은 첫 호환 릴리스 이후 별도 승인 게이트로 남긴다.

## 범위

- GitHub 정본을 `byh3071-cpu/yohan-agent-kit`으로 제자리 변경
- 현재 문서·manifest·Registry·Brain 계약의 canonical identity 갱신
- 기존 Marketplace namespace, plugin ID, 로컬 폴더의 호환 경계 고정
- 디자인 resolver/recorder의 새 Brain 소유권 계약 exact ref 고정
- 전환·롤백 문서와 자동 검증 gate

## 비범위

- Marketplace namespace 전환과 기존 Marketplace 제거·재등록
- 로컬 canonical 폴더 이름 변경
- 사용자 홈 설치·수정
- release store와 벤더별 패키지 생성

## Completion Check (완료 조건)

- [x] ADR-024가 Accepted 상태로 Brain `master`에 병합됐다.
- [x] GitHub 저장소 이름이 `yohan-agent-kit`으로 바뀌고 repository ID·PR·redirect가 보존됐다.
- [x] 로컬 `origin`이 새 GitHub URL을 가리킨다.
- [ ] Brain 계약 PR #194가 Agent Kit PR보다 먼저 Ready 전환·병합됐다.
- [x] Agent Kit의 현재 문서·Registry·catalog가 새 identity를 사용한다.
- [x] Marketplace name `yohan-cc-skills`와 네 plugin ID가 호환용으로 유지된다.
- [x] 디자인 resolver/recorder가 Brain 계약 커밋 `37068a625d85bb3955579a04d87cc0f5c503c823`을 고정한다.
- [x] Goal 1·2·3·4·5 gate, secret scan, `git diff --check`가 통과한다.
- [ ] Agent Kit PR #74가 Brain 계약 다음 순서로 병합됐다.

## 사람 게이트

- Brain PR #194와 Agent Kit PR #74 Ready 전환·순서 병합
- Marketplace namespace 전환
- 로컬 canonical folder 전환
- 사용자 홈 쓰기

## 검증 증거

- Agent registry: 95 assets
- catalog digest: `581fd7e3140b45a5021e128c2586d9c688cab46a808fd8e017ba5c160242641b`
- Goal 1: PASS
- Goal 2: PASS, 5 suites 488 assertions
- Goal 3: PASS, resolver/recorder 30 assertions and browser QA 5 viewports
- Goal 4: PASS, LF/CRLF-neutral catalog self-test 포함
- Goal 5: PASS
- secret-pr-guard: forbidden path 0, high-risk pattern 0, tracked env backup 0
- 전체 회귀 환경: short detached worktree `C:\Users\Public\yak-g5-final`
