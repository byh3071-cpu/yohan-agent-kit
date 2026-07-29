# Learnings

_Append-only. 한 줄 = 한 교훈._

- 2026-07-29 — 범용 스킬의 정본 이관과 의미 보강을 다른 커밋으로 나누면 기존 사본의 provenance와 새 계약을 동시에 검증할 수 있다.
- 2026-07-29 — 바이트 manifest를 OS 간 재현하려면 `skills/**`의 Git EOL을 LF로 고정해야 한다.
- 2026-07-29 — PowerShell 5.1의 `File.Replace(temp, target, null)`은 transaction 갱신에 안전하지 않으므로 같은 디렉터리 temp + `Move-Item -Force`와 recovery gate를 함께 사용한다.
- 2026-07-29 — Restore 멱등 no-op은 승인 매개변수 바인딩보다 먼저 판정해야 하지만 최초 Restore의 승인·PlanDigest는 유지해야 한다.
