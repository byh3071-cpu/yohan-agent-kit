---
vhk_format: 1
type: goal
id: 8
title: 집 PC 네 벤더 최종 검증
status: IN_PROGRESS
priority: P0
---

# Goal 8: 집 PC 네 벤더 최종 검증

> 경로명은 기존 Goal 이력 호환을 위해 유지한다. 2026-08-15 결정으로 노트북 검증은 v0.1 완료 차단 조건에서 후속 운영 검증으로 변경했다.

## 목적

집 PC의 검증된 단일 release에서 설치·업데이트·복원과 네 벤더의 지원 기능·실패 격리가 실제로 동작한다는 서명된 final evidence를 남긴다.

## Tasks

1. 기계·벤더별 smoke test와 evidence schema를 구현한다.
2. 집 PC disposable HomeRoot에서 전체 transaction과 패키지 구조를 검증한다.
3. 실제 집 PC 사용자 홈과 네 벤더 세션을 승인 후 검증한다.
4. 집 PC final evidence의 seal, release ID, Git commit, catalog digest를 `Verify`로 판정한다.
5. 집 PC 성공 뒤 Marketplace namespace와 canonical 폴더 전환을 별도 승인으로 수행한다.
6. 노트북을 처음 실제 사용할 때 같은 release 설치·로컬-only 자산 대조·선택적 `Compare`를 후속 Task로 수행한다.

## Completion Check

- [ ] 집 PC final evidence가 `SingleMachineVerified`이며 machine ID와 SHA-256 seal을 가진다.
- [ ] evidence v2가 canonical HomeRoot digest와 네 CLI resolved entrypoint identity·reported version을 봉인하며 v1 evidence를 fail-close한다.
- [ ] Antigravity CLI는 네이티브 `agy.exe` Application으로 확인된다.
- [ ] evidence의 release ID, Git commit, catalog digest, release manifest SHA-256이 설치된 release와 일치한다.
- [ ] Claude Code, Codex, Cursor, Antigravity에서 지원 capability의 명시·자동·부정 호출 결과가 기록된다.
- [ ] 공통 Script, Hook 실패 격리, MCP 인증 실패 격리, rollback 결과가 기록된다.
- [ ] Antigravity IDE·CLI처럼 표면이 다른 벤더는 각 공식 발견 경로와 지원 capability를 분리해 검증한다.
- [ ] Marketplace와 canonical 폴더 전환 전후 rollback 문서가 검증된다.
- [ ] 전체 Goal 1–8, 회귀, secret scan, `git diff --check`가 통과한다.

## 후속 운영 검증 — 비차단

- 노트북 첫 실제 사용 시 동일 release ID를 설치한다.
- 노트북에만 있는 자산은 Inbox 후보로 수집한다.
- 두 final evidence가 준비되면 `Compare`로 multi-machine verified 상태를 추가한다.
- 이 후속 검증은 v0.1 출시·Marketplace 전환·canonical 폴더 전환을 차단하지 않는다.
- Claude Code·Codex·Cursor wrapper 뒤 payload-chain attestation은 [Goal 9](9-vendor-payload-chain-attestation.md)로 추적하며 Goal 8의 완료를 차단하지 않는다.

## 사람 게이트

- 실제 사용자 홈 쓰기
- Marketplace namespace·canonical 폴더 전환
- PR Ready·순차 병합·워크트리 정리
