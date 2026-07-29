# 2026-07-29 adr-cycle·goal-cycle 멀티벤더 정본화

## 목표

Accepted ADR-013·014에 따라 yohan-cc-skills를 `adr-cycle`·`goal-cycle` 범용 스킬의 Git 정본과 안전한 배포 자동화 레포로 확장한다. 기존 Claude Code 플러그인 구조는 유지하고, 사용자 홈과 dirty checkout은 승인 없이 바꾸지 않는다.

## 완료한 단위

- 깨끗한 automation checkout과 Orca worktree에서 active goal 구성
- 세 기존 `goal-cycle` 사본의 전체 파일·바이트·SHA-256 감사
- 공통 원본과 긴 reference 원본을 기존 해시 그대로 초기 이관
- 차이가 있던 Cursor reference를 감사 문서에 보존하고 사용자 승인 원칙으로 조정
- `adr-cycle` 수명주기·Proposed 승인 게이트·goal-cycle 악수 구현
- `goal-cycle`의 품질확인, ADR 선행, S/M/L, 조건부 Orca·AGY 계약 보강
- 두 스킬의 `agents/openai.yaml`과 implicit·명시 호출 표면 추가
- 전체 디렉터리 manifest와 PowerShell 5.1 Check·Install·Restore 구현
- RULES·README·PRD·ARCHITECTURE·배포 계약 문서 갱신과 VHK 규칙 생성물 동기화

## 검증

- skill-creator quick validation: 두 스킬 PASS
- PowerShell 5.1 AST parser: 배포 도구·테스트 runner PASS
- 격리 HomeRoot 상태 전이: 43 assertions PASS
- 검증 범위: 읽기 전용 Check, stale PlanDigest, 승인 누락, Install/Restore 멱등, drift 무변경 차단, AGY evidence, legacy 동일본 백업·복원
- 실제 사용자 홈 쓰기: 실행하지 않음
- 기존 dirty checkout 두 곳: 읽기 전용 감사 외 변경 없음

## 에러와 교훈

### transaction JSON 두 번째 저장 실패

- 증상: 승인된 격리 Install이 첫 transaction 생성 뒤 exit 3, 저널은 `Executing`에 남음
- 원인: PowerShell 5.1/.NET Framework에서 `File.Replace(temp, target, null)`의 null backup 경로가 유효하지 않음
- 해결: 같은 디렉터리 임시 파일을 `Move-Item -Force`로 교체하고 미완료 transaction을 다음 Check에서 차단
- 역전파: `docs/patterns/PAT-006-ps-file-replace-null-backup.md`

### 두 번째 Restore가 no-op 전에 매개변수 바인딩 실패

- 증상: 첫 Restore는 성공했지만 이미 Restored인 BackupId를 PlanDigest 없이 다시 호출하면 exit 3
- 원인: no-op 판정 전에 `ApprovedDigest`가 Mandatory string으로 바인딩됨
- 해결: 바인딩을 선택값으로 바꾸고 함수 안에서 `Restored`를 먼저 판정
- 교훈: 멱등 경로는 승인·쓰기 검증보다 앞서 읽기 전용으로 판정하되, 아직 복원되지 않은 상태에는 기존 게이트를 유지한다.

## 남은 게이트

- 독립 에이전트의 자동·명시·부정 호출 forward test
- 실제 사용자 홈 read-only Check 결과 검토
- 시크릿 검사·staged diff·Draft PR
- 별도 yohan-brain/Public-dev 계약·repos.json·Orca 중복 등록 정리 PR
- 실제 사용자 홈 Install은 별도 승인 전 실행 금지

## 역전파 확인

- 규칙: `RULES.md`와 VHK 생성물에 범용 스킬 정본·배포 경계 반영
- 아키텍처: `docs/ARCHITECTURE.md`에 세 평면과 상태기계 반영
- 운영: `docs/MULTIVENDOR_SKILL_DISTRIBUTION.md`에 경로·승인·복원·AGY 증거 반영
- 패턴: PAT-006 생성; Notion 직접 주입은 하지 않음
