# 멀티벤더 스킬 배포 계약

## 책임과 정본

- Git 정본: `skills/<skill-name>/`
- 무결성 기준: `distribution/manifests/<skill-name>.json`
- 배포 도구: `scripts/Manage-MultivendorSkills.ps1`
- VHK: AGENTS·Cursor 규칙 동기화만 담당하며 사용자 홈 스킬을 설치하지 않는다.
- Orca: 같은 Windows 사용자 프로필에서 실행될 때 전역 설치본을 상속한다. 원격 호스트는 별도 설치가 필요하다.

`plugins/`의 Claude Code 플러그인은 그대로 유지한다. 범용 스킬과 같은 이름의 복사본을 플러그인 안에 만들지 않는다.

## 발견 경로

| 소비자 | 정본 연결 경로 | 함께 검사하는 이전 활성 경로 |
|---|---|---|
| Codex·Cursor 공용 | `~/.agents/skills/<name>/` | `~/.codex/skills/<name>/`, `~/.cursor/skills/<name>/` |
| Claude Code | `~/.claude/skills/<name>/` | 없음 |
| Antigravity 표준 | `~/.gemini/config/skills/<name>/` | `~/.gemini/skills/<name>/` |
| Antigravity CLI 조건부 | `~/.gemini/antigravity-cli/skills/<name>/` | 유효한 표준 경로 발견 실패 증거가 있을 때만 사용 |

현재 Windows 환경에서는 관리자 권한이나 개발자 모드가 필요 없는 directory junction을 사용한다. 정본 디렉터리 내부의 reparse point는 manifest 검사에서 실패한다.

## Check

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -Skill All -OutputFormat Human
```

Check는 디렉터리·백업·로그를 만들지 않는 읽기 전용 작업이다. 다음을 검사한다.

- 정본이 tracked·clean 상태인지
- `SKILL.md` frontmatter가 `name`·`description`만 갖는지
- 전체 파일의 상대 경로·바이트·SHA-256과 baseline manifest가 일치하는지
- 특정 PC 절대경로가 스킬에 남아 있지 않은지
- 대상이 올바른 junction인지, 같은 manifest의 일반 디렉터리인지, 내용 충돌인지
- 제품별 활성 발견 경로에 중복본이 있는지
- 미완료 transaction이나 근거 없는 AGY fallback이 있는지

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

안전한 Install은 사용자 홈의 `.yohan-skill-backups/<BackupId>/`에 write-ahead transaction을 기록한다. 동일한 기존 디렉터리는 활성 발견 루트 밖으로 이동해 manifest를 다시 확인하고, 정본 junction을 만든 뒤 전체 Check가 `Healthy`인지 확인한다. 중간 실패 시 원래 상태로 rollback하며 rollback도 실패하면 `RecoveryRequired`로 남긴다. 이미 Healthy이면 백업을 추가하지 않는 no-op이다.

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

Restore는 현재 junction이 해당 transaction이 만든 정본 연결인지, 백업 manifest가 변조되지 않았는지 확인한다. 자신이 만든 junction만 제거하고 설치 전의 `Absent`·일반 디렉터리·junction 상태를 복원한다. 백업은 자동 삭제하지 않는다. 복원 뒤 이전 활성 중복본이 다시 나타날 수 있으므로 성공 기준은 일반 Healthy가 아니라 transaction의 설치 전 상태와 일치하는 것이다.

## Antigravity CLI fallback

기본 Install은 표준 `~/.gemini/config/skills`만 사용한다. 새 AGY 세션에서 표준 경로 발견이 실패한 경우에만 별도 Check·승인으로 fallback을 켠다.

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -Skill goal-cycle `
  -IncludeAgyCliFallback `
  -AgyEvidenceDirectory <EVIDENCE_DIRECTORY>
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

호스트·버전·정본 digest·표준 경로가 바뀌거나 새 세션 검사가 아니면 증거는 무효다. 표준 경로에서 발견에 성공했다면 fallback 생성은 금지한다.

## 정본 변경과 테스트

스킬 파일을 바꾸면 전체 파일 manifest도 같은 PR에서 의도적으로 갱신한다. baseline은 타임스탬프와 ACL을 제외하고 상대 경로·바이트·SHA-256을 고정한다. LF/CRLF 차이도 실제 바이트 drift로 취급하며 `skills/**`는 Git에서 LF로 고정한다.

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File tests\Manage-MultivendorSkills.Tests.ps1
```

테스트는 저장소의 무시 경로 `tests/.work/` 아래 HomeRoot만 사용한다. 실제 사용자 홈을 테스트 대상으로 사용하지 않는다.

## 범위 밖

- 일반 ChatGPT 웹·데스크톱 대화
- Codex Cloud
- 다른 Windows 사용자 프로필
- 원격 Orca 호스트
- 기존 dirty checkout 두 곳의 정리·삭제

이 표면들은 로컬 junction을 자동으로 읽지 않는다. 레포 내장형·업로드형·원격 호스트 배포는 후속 결정으로 다룬다.
