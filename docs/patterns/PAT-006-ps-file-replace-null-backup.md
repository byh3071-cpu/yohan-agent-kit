---
id: PAT-006
패턴명: PowerShell 5.1 File.Replace의 null 백업 경로 함정
카테고리: env
증상: |
  임시 JSON을 만든 뒤 `[IO.File]::Replace($temp, $target, $null)`로 transaction 파일을 갱신하면 Windows PowerShell 5.1에서 `The path is not of a legal form` 예외가 발생한다. 최초 파일 생성은 성공하지만 두 번째 저널 저장이 실패해 transaction이 `Executing`에 머문다.
원인: |
  Windows PowerShell 5.1이 사용하는 .NET Framework의 `File.Replace` 3인자 overload에서 세 번째 backup 경로의 null을 안전한 "백업 없음"으로 취급한다고 가정했다. 이 환경에서는 null이 유효한 경로가 아니어서 예외가 발생했다. 최초 생성 경로는 `File.Move`를 사용하므로 설치의 첫 변경 직전까지는 증상이 드러나지 않는다.
해결: |
  대상과 같은 디렉터리에 고유한 임시 파일을 완전히 쓴 뒤 `Move-Item -LiteralPath $temp -Destination $target -Force`로 교체한다. 교체 뒤 JSON을 다시 읽어 상태를 검증하고, 다음 실행의 Check에서 `Executing`·`RecoveryRequired` transaction을 차단한다. 백업 파일 자체가 필요한 경우에는 null 대신 검증된 명시 경로를 사용한다.
적용조건: Windows PowerShell 5.1 + .NET Framework에서 write-ahead JSON·상태 파일을 임시 파일로 교체하는 자동화
출처프로젝트: yohan-cc-skills
태그: [powershell, dotnet-framework, file-replace, transaction, json, windows]
발견일: 2026-07-29
출처DevLog: "2026-07-29 adr-cycle·goal-cycle 멀티벤더 정본화"
---

# PAT-006 — File.Replace null 백업 경로 함정

## 핵심 한 줄

PowerShell 5.1에서 `File.Replace`의 backup 인자에 null이 된다고 가정하지 말고, 같은 디렉터리 임시 파일을 `Move-Item -Force`로 교체한 뒤 transaction을 재검증한다.

## 재현된 실패 순서

1. transaction.json 최초 생성은 성공했다.
2. 첫 설치 항목 직전 또는 직후 상태를 다시 저장할 때 `File.Replace(..., $null)`이 예외를 냈다.
3. 설치 wrapper는 실패했지만 최초 저널은 `Executing`으로 남았다.
4. Check가 미완료 transaction을 탐지하지 않으면 다음 Install이 겹칠 수 있었다.

## 역전파

- 파일 교체 방식뿐 아니라 crash 뒤 상태를 판정하는 recovery gate가 필요하다.
- 실제 Install→저널 갱신→post-Check를 실행하는 상태 전이 테스트가 단순 parser 테스트보다 먼저 이 결함을 잡았다.
- transaction 파일의 오류는 덮어쓰지 말고 exact BackupId와 함께 보존해야 복구 판단이 가능하다.
