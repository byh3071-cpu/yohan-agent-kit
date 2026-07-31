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
- 격리 HomeRoot 상태 전이·보안 회귀: 167 assertions PASS
- 검증 범위: 읽기 전용 Check, stale PlanDigest, 승인 누락, Install/Restore 멱등, drift 무변경 차단, AGY 실제 CLI·JSON 타입·미래 시각·만료·버전, legacy 동일본 백업·복원, 부모·목적지 reparse 탈출, ignored 파일·동일 stat tracked 변조, transaction 재봉인 path binding·backup 변조, 커밋 전 Install 복구, identity 없는 InstallRollback 거부, staging→active 원자 이동·file ID 보존, HomeRoot 동시 mutation 차단, transaction JSON 원자 교체, 사람용 복구 상태 출력, `RestorePending` 재개, Restored 상태 위조, transaction file reparse, NTFS file ID junction 교체, Git index 무변경
- 실제 사용자 홈 쓰기: 실행하지 않음
- 기존 dirty checkout 두 곳: 읽기 전용 감사 외 변경 없음

### 실제 소비자·사용자 홈 읽기 전용 확인

- 실제 사용자 홈 Check: `Conflict`(exit 3). 기존 `~/.claude/skills/goal-cycle`, `~/.cursor/skills/goal-cycle`, `~/.gemini/skills/goal-cycle`이 보강된 정본과 달라 계약대로 Install을 중단했다.
- Antigravity: 인증과 CLI 1.1.8을 확인했다. 현재 `gemini skills list`는 이전 `~/.gemini/skills/goal-cycle`만 발견하므로 새 `adr-cycle` 자동 발견 증거가 아니다.
- AGY 독립 프롬프트 검수: 파일 원문을 입력으로 전달한 8개 자동·명시·부정·상태 게이트 사례는 PASS. AGY는 보조 전용이므로 상위 검증을 별도로 유지한다.
- Cursor: 명시 goal 요청은 기존 `goal-cycle`을 찾았지만 ADR 자동 후보는 `NONE`이었다. 새 정본을 설치하지 않았으므로 예상된 제한이며 새 세션 발견 완료로 계산하지 않는다.
- Claude Code: 사용자 quota 일정에 따라 이번 검수에서 호출하지 않았다.

## 에러와 교훈

### transaction JSON 두 번째 저장 실패

- 증상: 승인된 격리 Install이 첫 transaction 생성 뒤 exit 3, 저널은 `Executing`에 남음
- 원인: PowerShell 5.1/.NET Framework에서 `File.Replace(temp, target, null)`의 null backup 경로가 유효하지 않음
- 초기 해결: 같은 디렉터리 임시 파일을 `Move-Item -Force`로 교체해 상태 전이 검증을 이어갔다.
- 최종 보강: 최초 생성은 `File.Move`, 갱신은 고유한 non-null backup 경로를 제공한 `File.Replace`로 원자 교체하고 미완료 transaction을 공식 복구 또는 Conflict로 판정한다.
- 역전파: `docs/patterns/PAT-006-ps-file-replace-null-backup.md`

### 두 번째 Restore가 no-op 전에 매개변수 바인딩 실패

- 증상: 첫 Restore는 성공했지만 이미 Restored인 BackupId를 PlanDigest 없이 다시 호출하면 exit 3
- 원인: no-op 판정 전에 `ApprovedDigest`가 Mandatory string으로 바인딩됨
- 해결: 바인딩을 선택값으로 바꾸고 함수 안에서 `Restored`를 먼저 판정
- 교훈: 멱등 경로는 승인·쓰기 검증보다 앞서 읽기 전용으로 판정하되, 아직 복원되지 않은 상태에는 기존 게이트를 유지한다.

### 배포·복구 독립 보안 리뷰

- 지적: 부모 junction 경로 탈출, backup 이동 뒤 늦은 저널링, mutable transaction 경로 신뢰, 부분 Restore 재개 부재, 같은 target junction 소유권 오인, ignored 정본 파일, AGY 증거 무기한 재사용.
- 해결: destination 조상·transaction file reparse 검증, 변경 의도 선저널링, schema 3 install/commit seal과 staging binding, 입력 기반 source·target·backup·staging 재계산, 항목별 Restore 재개, junction 생성 지문, 실제 파일 tracked 검사와 `GIT_OPTIONAL_LOCKS=0`, AGY 현재 버전·24시간 만료를 구현했다.
- 실패 고정: 외부 sentinel 무변경, transaction·backup 변조 거부, same-target junction identity mismatch, 부분 복구 성공을 격리 테스트로 고정했다.
- 역전파: `docs/patterns/PAT-007-reparse-ancestor-containment.md`

### 두 번째 복구 안정성 재리뷰

- 지적: commitSeal 생성 전 중단된 Install의 공식 복구 경로 부재, BackupAndLink에서 junction 제거 직후 재개 불가, `Move-Item` 목적지 leaf 경합, 변조 backup rollback, `Restored` 상태 필드 신뢰, transaction file leaf reparse, timestamp 기반 junction 지문, 호출자 문자열만 믿는 AGY 버전.
- 해결: `CommittedRestore`와 `InstallRollback` 복구 경로 분리, `RestorePending` 상태 추가, 정확한 `[IO.Directory]::Move`와 이동 전·후 manifest 검증, recoverySeal과 실제 원상태 재검증, transaction leaf 검사, NTFS file ID 지문, `agy --version` 직접 대조와 JSON boolean·round-trip timestamp 검증을 구현했다.
- 실패 고정: 저널 직후·backup 이동 뒤·junction 생성 뒤와 동등한 커밋 전 상태, commitSeal 없는 RecoveryRequired, 목적지 junction, 재봉인된 target·backup 경로, Restored 위조, 변조 rollback backup을 격리 회귀로 고정했다.

### 세 번째 junction 소유권 재리뷰

- 지적: commitSeal 없는 `InstallRollback`에서 transaction identity가 비어 있어도 현재 same-source junction의 관찰 identity를 채택하면, 다른 프로세스가 만든 junction을 도구 소유물로 오인해 삭제할 수 있다.
- 해결: schema 3에서 junction을 transaction 내부 staging에 먼저 만들고 NTFS file ID를 active 변경 전에 저널링한다. 저널링된 객체를 `[IO.Directory]::Move`로 active leaf에 옮겨 identity를 보존하며, active·staging 모두 저장 identity가 없거나 다르면 fail-closed한다. 같은 HomeRoot의 Install·Restore는 named mutex로 직렬화한다.
- 추가 보강: transaction JSON 갱신을 명시적 backup 경로를 둔 `File.Replace`로 원자화하고, Human Check에 `RecoveryKind`와 항목 상태를 표시한다. `fsutil`은 System32 절대경로로 호출한다.
- 실패 고정: identity 없는 InstallRollback의 Restore 차단과 replacement 보존, staging 이동 전후 identity 동일성, 동시 mutation 거부, JSON 임시 파일 무잔류를 격리 회귀로 고정했다.

### 독립 최종 재리뷰

- 판정: Draft PR 진행 가능. HIGH 0, MEDIUM 0.
- 증거: PowerShell 구문·`git diff --check`·167 assertions PASS, 원본 backup 뒤 junction이 staging에 남은 추가 중단 재현에서 `RestorePending → Restored` PASS.
- 비차단 한계: `Local\` mutex는 같은 Windows 세션 범위이며, 적대적 외부 TOCTOU를 제거하는 handle 기반 구현과 전원 손실용 flush-through는 v1 범위가 아니다.

## 남은 게이트

- 새 정본 설치 뒤 Codex·Cursor·Claude Code·AGY 새 세션 자동·명시·부정 호출 forward test
- 시크릿 검사·staged diff·Draft PR
- 별도 yohan-brain/Public-dev 계약·repos.json·Orca 중복 등록 정리 PR
- 실제 사용자 홈 Install은 기존 goal-cycle 차이 수동 화해와 별도 승인 전 실행 금지

## 역전파 확인

- 규칙: `RULES.md`와 VHK 생성물에 범용 스킬 정본·배포 경계 반영
- 아키텍처: `docs/ARCHITECTURE.md`에 세 평면과 상태기계 반영
- 운영: `docs/MULTIVENDOR_SKILL_DISTRIBUTION.md`에 경로·승인·복원·AGY 증거 반영
- 패턴: PAT-006·PAT-007 생성; Notion 직접 주입은 하지 않음

## 2026-07-31 — AGY CLI 실제 탐색 규약 보정

### 발견과 원인

- 사용자 승인으로 설치한 `~/.gemini/antigravity-cli/skills/{adr-cycle,goal-cycle}` junction은 도구 Check에서 `Healthy`였지만 AGY CLI 1.1.8 새 세션에 주입되지 않았다.
- 격리 probe에서는 물리 `.agents/skills`가 발견됐고, 실제 전역 세션은 기존 `~/.gemini/skills`의 물리 디렉터리를 주입했다. junction은 이름 노출 뒤 target 읽기 권한 경계에 걸려 물리 생성물이 필요했다.
- Orca 터미널의 PATH 선두 `git.cmd` wrapper를 bare `git`이 다시 호출해 `Maximum setlocal recursion level reached`가 발생했다.

### 구현

- 현재 transaction을 schema 4로 올려 `~/.gemini/skills/<name>`에 정본 파일과 `.yohan-adapter.json`을 담은 결정론적 물리 어댑터를 staging→active exact move로 배포한다.
- 메타데이터는 source path·Git commit·source manifest digest·검증한 AGY version을 봉인한다. active 어댑터를 제거할 때는 재귀 삭제하지 않고 transaction의 `removed/` 경로로 이동한다.
- 실패한 이전 `~/.gemini/antigravity-cli/skills` junction은 `AgyCliFallbackLegacy` 이관 항목으로 다룬다.
- schema 3 경로 정의와 install/commit seal 계산을 별도로 보존해 기존 BackupId를 계속 복원할 수 있게 했다.
- Git 정본 검사는 bare command 대신 실제 `git.exe` 절대경로를 사용한다. 범용 교훈은 `PAT-008`에 역전파했다.

### 검증

- PowerShell AST와 격리 HomeRoot 회귀 201 assertions PASS. 이전 fallback junction도 현재 음성 발견 증거 없이는 이관하지 않는 게이트를 포함한다.
- 생성 어댑터 Install→Healthy→의도적 drift Conflict→원문 복구→Restore, 실패한 이전 fallback junction 제거·복원, schema 3 fixture Restore를 통과했다.
- 실제 기존 schema 3 BackupId `20260730-000550908-bcab11d6`와 `20260730-005800595-97913ff2`를 새 코드로 읽기 전용 재검사해 모두 `RestoreReady`를 확인했다.
- 실제 사용자 홈은 새 코드로 읽기만 했고, 현재 보정 계획은 이전 fallback junction 두 개의 `RemoveLegacyJunction`이다. 물리 어댑터 생성과 이전 junction 이관은 구현 PR 머지·새 음성 증거·정확한 사용자 승인 전 실행하지 않는다.

### 남은 게이트

- 시크릿 검사·변경 파일 적대 리뷰·Draft PR·사람 머지 판정
- 머지 뒤 새 AGY 증거와 전역 변경 재승인, 물리 어댑터 설치 후 새 세션 명시·자동·부정 호출
- Claude Code 한도 리셋 뒤 명시·자동·부정 호출
- 기존 Notion Dev Log 행 갱신과 Public/dev bootstrap 역전파
