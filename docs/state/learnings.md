# Learnings

_Append-only. 한 줄 = 한 교훈._

- 2026-07-29 — 범용 스킬의 정본 이관과 의미 보강을 다른 커밋으로 나누면 기존 사본의 provenance와 새 계약을 동시에 검증할 수 있다.
- 2026-07-29 — 바이트 manifest를 OS 간 재현하려면 `skills/**`의 Git EOL을 LF로 고정해야 한다.
- 2026-07-29 — PowerShell 5.1의 `File.Replace(temp, target, null)`은 transaction 갱신에 안전하지 않으므로 같은 디렉터리 temp + `Move-Item -Force`와 recovery gate를 함께 사용한다.
- 2026-07-29 — Restore 멱등 no-op은 승인 매개변수 바인딩보다 먼저 판정해야 하지만 최초 Restore의 승인·PlanDigest는 유지해야 한다.
- 2026-07-29 — Windows 경로 containment는 정규화 prefix만으로 부족하며 destination의 기존 부모 reparse point와 junction 객체 지문까지 확인해야 한다.
- 2026-07-29 — Restore transaction의 source·target·backup 경로는 저장 JSON을 신뢰하지 말고 현재 CLI 입력에서 결정적으로 다시 계산하며, 고정 메타데이터 seal로 우발적 변조를 검출한다.
- 2026-07-29 — 읽기 전용 Git 검사는 ignored 파일의 실제 존재와 tracked 목록을 대조하고 `GIT_OPTIONAL_LOCKS=0` 뒤 index 바이트·시각 무변경을 회귀 테스트해야 한다.
- 2026-07-29 — 벤더 fallback 실패 증거는 host·정본 digest뿐 아니라 현재 CLI 버전과 짧은 만료 시간을 묶어야 오래된 음성 증거가 배포 계약이 되는 일을 막는다.
- 2026-07-29 — write-ahead transaction은 commit 전에도 exact BackupId·immutable seal·실제 파일시스템 상태만으로 공식 rollback 계획을 재구성할 수 있어야 중단 교착을 피한다.
- 2026-07-29 — PowerShell `Move-Item`은 기존 destination 디렉터리를 container로 해석하므로 백업·복원 leaf에는 destination 존재 시 실패하는 `Directory.Move`와 이동 전·후 manifest 검증을 사용한다.
- 2026-07-29 — `Restored` 같은 mutable 상태 필드는 완료 증거가 아니며 recovery seal과 실제 원상태를 함께 재검증해야 멱등 no-op을 안전하게 판정할 수 있다.
- 2026-07-29 — Windows junction 교체 탐지는 timestamp만으로 부족하므로 NTFS file ID·경로·target을 결합하고 Check의 관찰 지문을 실행 PlanDigest에 묶는다.
- 2026-07-29 — 읽기 전용 Git 정본 검증은 status stat cache만 믿지 말고 각 working file을 index blob과 직접 비교해야 같은 크기·mtime 위장도 잡는다.
- 2026-07-29 — 정정: 위 `Move-Item -Force` 권고는 임시 우회였다. transaction JSON 갱신은 같은 디렉터리 temp와 non-null backup 경로를 둔 `File.Replace`를 쓰고, 최초 생성만 `File.Move`를 사용해야 원자 교체 계약을 분명히 할 수 있다.
- 2026-07-29 — commit 전 junction 복구는 현재 same-target 객체를 사후 채택하지 말고 transaction staging에서 file ID를 선저널링한 객체만 active로 원자 이동해야 다른 프로세스의 junction을 삭제하지 않는다.
- 2026-07-29 — 사용자 홈 mutation은 HomeRoot별 named mutex로 직렬화하되 Check는 읽기 전용으로 남기고, identity가 없거나 다르면 자동 복구보다 fail-closed를 우선한다.
- 2026-07-29 — 로컬 배포 안전성의 위협 모델은 명시해야 한다. `Local\` mutex·reparse 재검사·원자 파일 교체는 동일 세션 프로세스 중단에는 강하지만, 교차 로그인 세션·적대적 handle race·전원 손실 내구성까지 자동으로 보장하지 않는다.
