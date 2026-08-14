# 두 PC·네 벤더 검증 Runbook

## 완료 의미

같은 GitHub 저장소를 clone했다는 것만으로 완료가 아니다. 집 PC와 노트북의 final evidence가 다음 네 값을 동일하게 가져야 한다.

- release ID
- exact Git commit
- asset catalog digest
- release manifest SHA-256

machine ID는 달라야 한다. machine ID는 hostname·OS·processor count를 해시한 식별자이며 원문 장치 정보를 evidence에 저장하지 않는다.

## 1. release 설치와 transaction 검증

각 PC에서 `AGENT_KIT_RELEASES.md`의 Check → Install/Update → Check 순서를 수행한다. 다음 결과를 `fixtures/agent-kit-transaction-results.example.json` 복사본에 기록한다.

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

Antigravity는 IDE와 CLI 발견 경로를 모두 확인한다. 일반 Agent는 이를 지원하는 `agy` CLI 새 세션에서 실행하고, IDE에서는 Skills·Rules·Hooks·MCP 로딩을 확인한다.

## 4. final evidence

session과 transaction JSON을 채운 뒤 finalize한다. 저장소의 `*.example.json`은 `TEST_ONLY:` 합성 증거라 실제 HomeRoot에서는 거부된다. 복사본의 각 항목을 실제 transcript·명령·exit code·BackupId 근거로 교체해야 한다.

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Finalize `
  -DraftEvidencePath <draft.json> `
  -SessionResultsPath <sessions.json> `
  -TransactionResultsPath <transactions.json> `
  -ApproveEvidenceWrite
```

노트북에서만 발견된 자산은 release에 바로 섞지 않고 `Manage-AgentIntake.ps1 -Mode Scan`으로 Inbox 후보화한다.

## 5. 두 evidence 비교

```powershell
.\scripts\Test-AgentKitCompatibility.ps1 -Mode Compare `
  -EvidencePath <home-final.json> `
  -OtherEvidencePath <laptop-final.json>
```

`Compatible`일 때만 Marketplace namespace를 `yohan-agent-kit`으로 전환하고 canonical checkout을 `C:\Users\Public\dev\automation\yohan-agent-kit`으로 바꾸는 별도 승인 단계로 간다. 전환 전에는 `yohan-cc-skills` Marketplace와 기존 canonical checkout을 유지한다.
