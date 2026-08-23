# 멀티벤더 스킬 배포 계약

## 책임과 정본

- Git 정본: `skills/<skill-name>/`
- 무결성 기준: `distribution/manifests/<skill-name>.json`
- 배포 도구: `scripts/Manage-MultivendorSkills.ps1`
- VHK: AGENTS·Cursor 규칙 동기화만 담당하며 사용자 홈 스킬을 설치하지 않는다.
- Orca: 같은 Windows 사용자 프로필에서 실행될 때 전역 설치본을 상속한다. 원격 호스트는 별도 설치가 필요하다.

현재 `All` 선택은 `adr-cycle`, `design-team`, `design-to-html`, `goal-cycle`, `restart-safe-handoff`, `runtime-incident-investigator`, `supervised-session-conductor`의 정본과 manifest를 함께 검사한다. 개별 이름으로도 같은 읽기 전용 Check와 승인 기반 Install·Restore 계약을 사용한다.

`plugins/`의 Claude Code 플러그인은 그대로 유지한다. 범용 스킬과 같은 이름의 복사본을 플러그인 안에 만들지 않는다.

## 발견 경로

| 소비자 | 정본 연결 경로 | 함께 검사하는 이전 활성 경로 |
|---|---|---|
| Codex·Cursor 공용 | `~/.agents/skills/<name>/` | `~/.codex/skills/<name>/`, `~/.cursor/skills/<name>/` |
| Claude Code | `~/.claude/skills/<name>/` | 없음 |
| Antigravity 표준 | `~/.gemini/config/skills/<name>/` junction | 없음 |
| Antigravity CLI 조건부 | `~/.gemini/skills/<name>/` 물리 생성 어댑터 | `~/.gemini/antigravity-cli/skills/<name>/`의 실패한 이전 fallback junction |

표준 경로에는 관리자 권한이나 개발자 모드가 필요 없는 directory junction을 사용한다. AGY CLI 1.1.8은 표준 경로와 별도 CLI junction을 새 세션에 주입하지 않고 `~/.gemini/skills`의 물리 디렉터리만 주입한다는 실측 결과가 있어, 유효한 음성 증거가 있을 때만 정본 파일과 `.yohan-adapter.json`을 담은 생성 어댑터를 배포한다. 정본 디렉터리와 생성 어댑터 내부의 reparse point는 manifest 검사에서 실패한다. 사용자 홈 대상과 백업 경로의 **모든 기존 조상**도 reparse point가 아니어야 하며, 부모 junction을 통한 허용 루트 탈출은 작업 전에 거부한다.

## Check

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -Skill All -OutputFormat Human
```

Check는 디렉터리·백업·로그를 만들지 않는 읽기 전용 작업이다. 다음을 검사한다.

- 정본과 baseline이 tracked·clean 상태인지, 실제 스킬 파일 중 ignored·untracked 파일이 없는지, 각 working file blob이 Git index blob과 같은지
- `SKILL.md` frontmatter가 `name`·`description`만 갖는지
- 전체 파일의 상대 경로·바이트·SHA-256과 baseline manifest가 일치하는지
- 특정 PC 절대경로가 스킬에 남아 있지 않은지
- 대상이 올바른 junction인지, 출처 메타데이터와 manifest가 일치하는 AGY 물리 어댑터인지, 같은 manifest의 이관 가능한 일반 디렉터리인지, 내용 충돌인지
- 제품별 활성 발견 경로에 중복본이 있는지
- 미완료 transaction이나 근거 없는 AGY fallback이 있는지
- destination 조상·백업 transaction·transaction 파일에 경로 탈출 reparse point가 없는지

Git 검사는 `GIT_OPTIONAL_LOCKS=0`인 프로세스 범위에서 수행하고 각 파일을 index blob과 직접 비교한다. PATH 선두의 재귀 `git.cmd` wrapper를 다시 호출하지 않도록 실제 `git.exe`를 해석해 절대경로로 실행한다. 회귀 테스트는 같은 크기·수정 시각으로 위장한 내용 변경도 잡으며, Check 전후 worktree index의 바이트 해시와 수정 시각이 같은지도 확인한다.

| 상태 | exit | 의미 |
|---|---:|---|
| `Healthy` | 0 | 모든 연결이 정본을 가리키고 활성 중복이 없음 |
| `Installable` | 2 | 누락 또는 동일 manifest의 안전한 이관 후보; PlanDigest 제공 |
| `Conflict` | 3 | 내용 차이·파일 장애물·잘못된 junction·fallback 근거 문제 |
| `SourceInvalid` | 3 | 정본·frontmatter·baseline·Git 상태 문제 |
| `RecoveryRequired` | 3 | 중단된 transaction이 있어 새 설치 금지 |

JSON 자동화 표면은 `-OutputFormat Json`을 사용한다. 차이 보고는 stdout으로만 반환하며 파일을 만들지 않는다.

## Install

Install은 다음 두 조건을 모두 요구한다.

1. 실행 직전 사용자가 사용자 홈 쓰기를 승인했다.
2. 직전 Check의 `PlanDigest`와 현재 상태를 다시 계산한 값이 같다.

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Install -Skill All `
  -PlanDigest <CHECK_DIGEST> `
  -ApproveGlobalHomeWrite
```

정본과 다른 일반 디렉터리, 파일 장애물, 잘못된 junction은 승인 여부와 무관하게 실패한다. `Force`나 불일치 우회 옵션은 없다.

안전한 Install은 HomeRoot별 named mutex로 다른 Install·Restore와 직렬화하고, 사용자 홈의 `.yohan-skill-backups/<BackupId>/`에 schema 4 write-ahead transaction을 기록한다. schema 3 백업은 기존 경로 계약과 seal 계산을 그대로 사용해 계속 복원할 수 있다. 정본 junction은 먼저 transaction 내부의 결정적 staging 경로에 만들고 NTFS file ID·target 기반 객체 지문을 저널에 저장한다. AGY 어댑터는 Check가 계산한 source path·commit·digest·CLI version을 `.yohan-adapter.json`에 기록하고 정본 파일과 합친 전체 manifest를 staging에서 검증한다. 그다음 동일한 기존 디렉터리를 활성 발견 루트 밖으로 이동해 전·후 manifest를 확인하고, staging junction 또는 물리 어댑터를 active leaf로 `[IO.Directory]::Move`한다. 이 이동은 목적지 leaf가 이미 생기면 실패한다. junction은 NTFS file ID를 보존하고, 어댑터는 봉인된 전체 digest로 소유권을 판정한다.

transaction JSON은 같은 디렉터리에 완전한 임시 파일을 쓴다. 최초 생성은 `[IO.File]::Move`, 갱신은 고유한 non-null backup 경로를 제공한 `[IO.File]::Replace`를 사용하고 성공 뒤 임시 backup을 제거한다. 설치 전 고정 메타데이터와 staging·removal binding의 `installSeal`, 커밋 시점의 상태·junction 지문·adapter 상태를 포함한 `commitSeal`이 우발적 transaction 변조를 검출한다. identity가 기록되기 전 프로세스가 죽었거나 현재 junction의 identity가 다르면 같은 target이라도 도구 소유물로 채택하지 않는다. 생성 어댑터 digest가 다를 때도 자동 채택하거나 덮어쓰지 않고 Conflict로 중단한다.

모든 항목을 적용한 뒤 전체 Check가 `Healthy`인지 확인한다. 중간 실패 시 원래 상태로 rollback하며, 백업 manifest가 달라졌다면 활성 경로에 옮기지 않는다. rollback도 실패하면 `RecoveryRequired`로 남긴다. 프로세스 종료로 `Executing`에 멈췄거나 `commitSeal` 없이 `RecoveryRequired`가 된 transaction도 exact BackupId의 Check·Restore로 `InstallRollback` 계획을 만들 수 있다. 이미 Healthy이면 백업을 추가하지 않는 no-op이다.

## Restore

`latest`나 임의 경로 대신 Install이 반환한 정확한 BackupId만 사용한다.

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -BackupId <BACKUP_ID>

powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Restore -BackupId <BACKUP_ID> `
  -PlanDigest <RESTORE_DIGEST> `
  -ApproveGlobalHomeWrite
```

Restore는 transaction의 HomeRoot·RepositoryRoot·skill·role·source·target·backup·staging·adapter removal 경로를 현재 CLI 입력에서 결정적으로 다시 계산한다. `installSeal`은 항상 검증하고, 완료된 설치는 `commitSeal`도 검증한다. 커밋 전 중단은 봉인된 action과 현재 파일시스템을 함께 읽어 `InstallRollback`으로 분류한다. 완료 여부와 무관하게 active·staging junction은 transaction에 선저널링된 NTFS 객체 지문이 실제 객체와 같을 때만 소유물로 인정한다. 생성 어댑터는 봉인된 digest가 일치할 때만 transaction 내부 `removed/` 경로로 정확히 이동하며 재귀 삭제하지 않는다. 같은 대상을 가리키더라도 삭제 후 다시 만든 junction, identity가 비어 있는 junction, 수정된 어댑터는 제거하지 않는다. Check가 확인한 active·staging·removed 상태는 Restore PlanDigest에 묶인다.

각 항목은 `Original`·`Installed`·`RestorePending`·`Conflict`로 다시 판정한다. junction 제거 뒤 프로세스가 멈춰 target은 없고 유효한 backup만 남은 `RestorePending`도 재개한다. `Restoring`·`RecoveryRequired` transaction은 이미 원복된 항목을 건너뛴다. 모든 항목이 실제 설치 전 상태인지 확인한 뒤에만 `recoverySeal`과 `Restored`를 함께 기록하며, 상태 문자열만 바뀐 경우에는 no-op으로 인정하지 않는다. 백업은 자동 삭제하지 않는다. 복원 뒤 이전 활성 중복본이 다시 나타날 수 있으므로 성공 기준은 일반 Healthy가 아니라 transaction의 설치 전 상태와 일치하는 것이다.

## Antigravity CLI fallback

기본 Install은 표준 `~/.gemini/config/skills` junction만 사용한다. 새 AGY 세션에서 표준 경로 발견이 실패한 경우에만 별도 Check·승인으로 `~/.gemini/skills/<name>` 물리 생성 어댑터를 켠다. AGY CLI 1.1.8에서 실효성이 없었던 `~/.gemini/antigravity-cli/skills/<name>` junction은 현재 음성 발견 증거가 결합된 같은 승인 transaction에서만 백업 가능한 이전 경로로 이관한다. fallback 옵션과 증거가 없는 일반 Check·Install은 이 junction을 자동 제거하지 않고 Conflict로 중단한다.

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -Skill goal-cycle `
  -IncludeAgyCliFallback `
  -AgyEvidenceDirectory <EVIDENCE_DIRECTORY> `
  -AgyCurrentVersion <AGY_VERSION>
```

증거 파일명은 `<skill>.json`이며 다음 필드를 가진다.

```json
{
  "schemaVersion": 1,
  "host": "CURRENT_HOST",
  "agyVersion": "실측 버전",
  "skill": "goal-cycle",
  "sourceDigest": "정본 manifest digest",
  "standardPath": "검사한 표준 절대경로",
  "testedAt": "ISO-8601",
  "newSession": true,
  "standardDiscovered": false
}
```

`-AgyCurrentVersion`에는 실행 직전 읽은 현재 CLI 버전을 전달한다. 도구도 `agy --version`을 직접 실행해 전달값과 설치된 CLI를 대조한다. 증거의 호스트·버전·정본 digest·표준 경로가 바뀌거나 `newSession`·`standardDiscovered`가 JSON boolean이 아니면 무효다. `testedAt`은 ISO-8601 round-trip 형식이어야 하며 미래 5분을 넘거나 24시간보다 오래되어도 무효다. 표준 경로에서 발견에 성공했다면 fallback 생성은 금지한다.

생성된 `.yohan-adapter.json`에는 schema·adapter kind·skill·정본 절대경로·Git commit·정본 manifest digest·검증한 AGY CLI 버전을 기록한다. 생성 시각은 넣지 않아 같은 입력의 어댑터가 결정론적 해시를 갖게 한다. 메타데이터나 복사된 스킬 파일에 drift가 생기거나 정본 commit이 바뀌어 예상 어댑터 digest가 달라지면 Check는 자동 갱신하지 않고 Conflict로 중단한다. Accepted ADR-014의 불일치 덮어쓰기 금지를 지키므로, 정본 변경 시에는 기존 설치 BackupId로 먼저 Restore한 뒤 새 음성 발견 증거·Check·승인을 거쳐 다시 Install한다.

## 정본 변경과 테스트

스킬 파일을 바꾸면 전체 파일 manifest도 같은 PR에서 의도적으로 갱신한다. baseline은 타임스탬프와 ACL을 제외하고 상대 경로·바이트·SHA-256을 고정한다. LF/CRLF 차이도 실제 바이트 drift로 취급하며 `skills/**`는 Git에서 LF로 고정한다.

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File tests\Manage-MultivendorSkills.Tests.ps1
```

테스트는 저장소의 무시 경로 `tests/.work/` 아래 HomeRoot만 사용한다. 실제 사용자 홈을 테스트 대상으로 사용하지 않는다. 정상 상태 전이뿐 아니라 부모·목적지 junction 탈출, transaction·backup 변조, 커밋 전 Install 중단 복구, identity 없는 InstallRollback 거부, staging→active 원자 이동의 file ID 보존, HomeRoot 동시 mutation 차단, transaction JSON 원자 교체, `RestorePending` 재개, schema 3 복원 호환성, NTFS file ID 교체, 생성 어댑터 설치·drift·복원, 실패한 이전 fallback 이관과 무증거 이관 거부, 재귀 `git.cmd` wrapper 우회, ignored 파일과 동일 stat의 tracked 파일 주입, Git index 무변경, AGY 실제 CLI·타입·만료·버전 불일치를 실패 고정한다.

## 운영 한계

- `Local\` named mutex는 같은 Windows 로그인 세션의 동일 정규화 HomeRoot만 직렬화한다. 다른 로그인 세션이나 경로 별칭을 통한 동시 실행은 별도 운영 통제가 필요하다.
- mutation 직전까지 reparse 조상을 반복 검사하지만, 적대적 외부 프로세스가 검사 직후 경로를 바꾸는 경쟁을 완전히 제거하는 directory-handle 기반 보안 경계는 아니다.
- 같은 볼륨의 `File.Move`·`File.Replace`는 프로세스 중단에 대한 원자 교체를 제공하지만, 별도 flush-through가 없으므로 갑작스러운 전원 손실까지 완전한 내구성을 보장하지 않는다.

## 범위 밖

- 일반 ChatGPT 웹·데스크톱 대화
- Codex Cloud
- 다른 Windows 사용자 프로필
- 원격 Orca 호스트
- 기존 dirty checkout 두 곳의 정리·삭제

이 표면들은 로컬 junction을 자동으로 읽지 않는다. 레포 내장형·업로드형·원격 호스트 배포는 후속 결정으로 다룬다.
