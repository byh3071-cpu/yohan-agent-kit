# 집 PC·네 벤더 검증 Runbook

> 파일명은 기존 링크 호환을 위해 유지한다. 노트북 검증은 선택적 multi-machine 후속 절차다.

## 완료 의미

같은 GitHub 저장소를 clone했다는 것만으로 완료가 아니다. 집 PC final evidence가 다음 네 값을 설치된 release와 동일하게 가져야 한다.

- release ID
- exact Git commit
- asset catalog digest
- release manifest SHA-256

machine ID는 hostname·OS·processor count를 해시한 식별자이며 원문 장치 정보를 evidence에 저장하지 않는다.

## 1. release 설치와 transaction 검증

집 PC에서 `AGENT_KIT_RELEASES.md`의 Check → Install/Update → Check 순서를 수행한다. 다음 결과를 `fixtures/agent-kit-transaction-results.example.json` 복사본에 기록한다.

- install
- update
- repeated Check/Install idempotency
- exact BackupId rollback
- injected failure와 rollback

실제 사용자 홈에서 `TestFault`를 쓰지 않는다. partial-failure 결과는 disposable HomeRoot 자동 테스트의 fixture·exit code를 인용한다.

## 2. draft evidence 생성

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Probe `
  -Release <id> -ApproveEvidenceWrite
```

Probe는 release 파일 해시, 다섯 package manifest, Agent Plugins v1 component 경계를 자동 검증한다. 벤더 session 결과는 `NOT_RUN`으로 남는다.

Probe가 봉인한 네 CLI identity는 그 CLI가 업데이트되면 어긋난다. Finalize는 `CLI identity changed since Probe`로 거부하므로, 벤더 session을 시작한 뒤 CLI가 자동 업데이트되면 2절부터 다시 한다.

### 버전 계약은 패치가 아니라 계열을 묶는다

Claude Code는 봉인 창보다 빨리 자동 업데이트된다(2026-08-21 실측: 한 세션 안에서 `2.1.233`→`2.1.237`→`2.1.238`). 그래서 계약은 두 값을 분리해 쓴다.

| 필드 | 뜻 |
|---|---|
| `testedVersion` | 실제로 돌려본 정확한 버전. 기록으로만 쓴다 |
| `compatibleVersionPrefix` | 호환 판정 기준 계열. 예: `2.1.` |

판정은 계열 접두사가 **버전 경계에서** 맞을 때만 통과한다. `2.1.`은 `2.1.238`을 받아들이고 `2.2.0`과 `12.1.4`를 거부한다. 접두사가 없으면 예전처럼 정확한 `testedVersion`을 요구한다.

계열이 바뀌면(`2.1.` → `2.2.`) 계약을 갱신하고 그 계열에서 벤더 session을 다시 돌려야 한다.

## 3. 네 벤더 session

### 실행 방식 — 결과를 화면이 아니라 파일에 먼저 남긴다

`Invoke-VendorSmoke.ps1`이 벤더 CLI를 대신 실행한다. 손으로 세션을 열어 결과를 옮겨 적지 않는다.

```powershell
.\scripts\Invoke-VendorSmoke.ps1 -Vendor claude-code
```

이 도구가 지키는 계약은 셋이다.

- 벤더 CLI를 띄우기 **전에** `record.json`을 `RUNNING` 상태로 디스크에 쓴다. 세션이 끊겨도 무엇을 돌리던 중이었는지 남는다.
- 판정은 화면 출력이 아니라 **디스크에서 다시 읽은 transcript**로 계산한다.
- 벤더 CLI가 최종 요약을 돌려주지 않아도 판정 불가로 멈추지 않고 `NO_OUTPUT`으로 기록한다. `TIMEOUT`·`LAUNCH_ERROR`·`AMBIGUOUS`도 마찬가지다.

`AMBIGUOUS`는 스킬이 로드되긴 했으나 검증 대상 release가 아닌 경로에서 해석됐다는 뜻이다. Claude personal skill은 [Goal 17](../goals/17-claude-skill-deployment.md)의 승인된 contract 5에서 봉인 physical adapter를 사용하지만, manager의 filesystem `Healthy`만으로 runtime discovery를 PASS로 올리지 않는다. actual HomeRoot의 새 PlanDigest로 설치한 canary가 exact `~/.claude/skills/<name>/SKILL.md`에서 해석되고 repo-local skill·plugin shadow가 없다는 fresh `--bare` receipt가 있어야 한다.

산출물은 `.vhk/smoke/<vendor>/<runId>/`에 남고 Git에 포함하지 않는다.

- `<probe>/prompt.txt`·`<probe>/stdout.txt`·`<probe>/stderr.txt` — 원문
- `<probe>/record.json` — 명령줄, exit code, 매칭된 표지, 판정 사유
- `session-results.<vendor>.json` — 4절 `-SessionResultsPath`에 그대로 넣는 파일

probe 정의는 `registry/vendor-smoke-probes.json`에 있다. 벤더를 추가하려면 코드가 아니라 이 파일을 늘린다.

### 각 session에서 확인하는 것

Claude Code, Codex, Cursor, Antigravity의 새 session에서 다음을 각각 실행하고 transcript나 명령·exit code를 기록한다.

1. 명시적 Skill 호출
2. 설명에 맞는 요청의 자동 호출
3. 호출되면 안 되는 요청의 negative routing
4. 공통 Script 실행
5. 일반 Subagent 실행
6. Hook 실패가 나머지 기능을 막지 않는지
7. MCP 인증·연결 실패가 다른 Skill을 막지 않는지

Antigravity는 먼저 `agy plugin list`에 정확한 이름 `yohan-agent-kit`이 한 번만 나타나는지 확인한다. `~/.gemini/config/plugins/yohan-agent-kit`은 junction이 아닌 ordinary directory여야 하며 release package와 전체 digest가 같아야 한다. 그다음 일반 Agent와 Skill을 새 `agy` CLI session에서 실행하고, IDE에서는 Skills·Rules·Hooks·MCP 로딩을 확인한다. Restore 뒤에는 같은 이름이 목록에서 사라지고 이전 release 복원이라면 다시 공식 등록되는지도 확인한다.

## 4. final evidence

session과 transaction JSON을 채운 뒤 finalize한다. 저장소의 `*.example.json`은 `TEST_ONLY:` 합성 증거라 실제 HomeRoot에서는 거부된다. 복사본의 각 항목을 실제 transcript·명령·exit code·BackupId 근거로 교체해야 한다.

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Finalize `
  -DraftEvidencePath <draft.json> `
  -SessionResultsPath <sessions.json> `
  -TransactionResultsPath <transactions.json> `
  -ApproveEvidenceWrite
```

## 5. 집 PC final evidence 검증

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Verify `
  -EvidencePath <home-final.json>
```

`SingleMachineVerified`일 때 v0.1의 검증 완료 조건을 충족한다. 그다음 Marketplace namespace를 `yohan-agent-kit`으로 전환하고 canonical checkout을 `C:\Users\Public\dev\automation\yohan-agent-kit`으로 바꾸는 별도 승인 단계로 갈 수 있다.

`Verify`는 봉인 JSON만 확인하지 않는다. evidence v2가 현재 machine ID, 원문 경로를 노출하지 않는 canonical HomeRoot SHA-256, `~/.yohan-agent-kit/active.json`, active junction, 설치된 release manifest, 현재 네 CLI resolved entrypoint identity·reported version과 모두 일치할 때만 성공한다. v1 evidence는 묵시 변환하지 않고 재생성을 요구한다.

resolved entrypoint identity는 해석된 직접 실행파일의 canonical path, `CommandType`, 파일 SHA-256을 봉인한다. Antigravity는 네이티브 `agy.exe` `Application`만 허용한다. Claude Code·Codex·Cursor에서는 현재 PowerShell wrapper 자체와 reported version까지만 검증한다. 따라서 `SingleMachineVerified`는 wrapper 뒤 backend payload-chain 무결성을 증명하지 않는다. 그 attestation은 [Goal 9](../goals/9-vendor-payload-chain-attestation.md)에서 별도 설계하며 완료 전에는 공급망 무결성 근거로 사용하지 않는다.

## 6. 선택적 multi-machine 후속 검증

노트북을 처음 실제 사용할 때 동일 release를 설치한다. 노트북에서만 발견된 자산은 release에 바로 섞지 않고 `Manage-AgentIntake.ps1 -Mode Scan`으로 Inbox 후보화한다.

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Compare `
  -EvidencePath <home-final.json> `
  -OtherEvidencePath <laptop-final.json>
```

`Compatible`이면 상태를 `multi-machine verified`로 올린다. 이 비교는 v0.1 출시나 Marketplace·canonical checkout 전환을 차단하지 않는다.
