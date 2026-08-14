---
vhk_format: 1
type: goal
id: 8
title: 두 PC 네 벤더 최종 검증
status: IN_PROGRESS
priority: P0
---

# Goal 8: 두 PC 네 벤더 최종 검증

## 목적

집 PC와 노트북이 동일 release ID와 catalog digest를 사용하고, 각 벤더에서 지원되는 기능과 실패 격리가 실제로 동작한다는 서명된 증거를 남긴다.

## Tasks

1. 기계·벤더별 smoke test와 evidence schema를 구현한다.
2. 집 PC disposable HomeRoot에서 전체 transaction과 패키지 구조를 검증한다.
3. 실제 집 PC 사용자 홈과 네 벤더 세션을 승인 후 검증한다.
4. 노트북에서 같은 release를 설치하고 네 벤더 세션 및 로컬-only 자산 대조를 수행한다.
5. 두 evidence를 합쳐 release ID, catalog digest, 지원/비지원 capability를 판정한다.
6. 두 PC 성공 뒤 Marketplace namespace와 canonical 폴더 전환을 별도 승인으로 수행한다.

## Completion Check

- [ ] 집 PC와 노트북 evidence가 서로 다른 machine ID를 가진다.
- [ ] 두 evidence의 release ID, Git commit, catalog digest가 동일하다.
- [ ] Claude Code, Codex, Cursor, Antigravity에서 지원 capability의 명시·자동·부정 호출 결과가 기록된다.
- [ ] 공통 Script, Hook 실패 격리, MCP 인증 실패 격리, rollback 결과가 기록된다.
- [ ] Antigravity IDE·CLI처럼 표면이 다른 벤더는 각 공식 발견 경로와 지원 capability를 분리해 검증한다.
- [ ] Marketplace와 canonical 폴더 전환 전후 rollback 문서가 검증된다.
- [ ] 전체 Goal 1–8, 회귀, secret scan, `git diff --check`가 통과한다.

## 사람 게이트

- 실제 사용자 홈 쓰기
- 노트북 실행 및 evidence 반입
- Marketplace namespace·canonical 폴더 전환
- PR Ready·순차 병합·워크트리 정리
