---
vhk_format: 1
type: goal
id: 6
title: 버전 고정 release store와 멀티벤더 패키징
status: DONE
priority: P0
---

# Goal 6: 버전 고정 release store와 멀티벤더 패키징

## 목적

Git checkout을 직접 가리키는 설치 상태를 검증된 불변 release artifact로 분리하고, 하나의 Registry 정본에서 다섯 배포 형식을 생성한다.

## Tasks

1. Agent Plugins, Claude Code, Codex, Cursor, Antigravity 패키지 생성 계약을 고정한다.
2. release ID, Git commit, catalog digest, 파일별 SHA-256, 호환성, rollback 정보를 포함한 manifest를 생성한다.
3. `Manage-AgentKit.ps1`에 Check, Install, Update, Restore 상태기계와 승인 digest를 구현한다.
4. disposable HomeRoot에서 설치·업데이트·재실행·부분 실패·복원을 검증한다.

## Completion Check

- [x] `dist/`는 생성물이며 Git 정본이 아니다.
- [x] Agent Plugins 산출물은 Skills와 MCP만 포함한다.
- [x] 네이티브 산출물은 공통 자산을 복사해 만들며 직접 관리하는 중복 정본이 없다.
- [x] release store의 기존 release는 수정되지 않고, active 포인터만 승인된 transaction으로 전환된다.
- [x] 모든 artifact 파일이 manifest SHA-256으로 검증된다.
- [x] Check는 HomeRoot를 만들거나 변경하지 않는다.
- [x] Install, Update, Restore는 `PlanDigest`와 `ApproveGlobalHomeWrite` 없이는 실패한다.
- [x] PowerShell 5.1 테스트와 Goal 6 gate가 통과한다.

## 사람 게이트

- 실제 사용자 홈 설치·업데이트·복원
- Marketplace namespace 전환
