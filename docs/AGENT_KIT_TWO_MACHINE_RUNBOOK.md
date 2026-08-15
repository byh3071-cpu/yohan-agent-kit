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

## 3. 네 벤더 session

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
