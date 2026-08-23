# 범용 세션 운영 스킬 감사

- 날짜: 2026-08-23
- Goal: 15
- 브랜치: `feat/design-team-session-continuity`
- 상태: 구현 완료, 로컬 검증 결과 기록 예정

## 목적

디자인 세션에서 드러난 연속성 문제를 특정 프로젝트나 이번 대화의 요령으로 남기지 않고, 멀티벤더 에이전트가 반복 사용할 수 있는 표준 운영 구조로 승격한다. 프로젝트 Git이 지속 상태를 소유하고 대화 기록·터미널·런타임 신호는 독립 증거로 취급한다.

## 구조 결정

| 자산 | 소유 책임 | 연결 |
| --- | --- | --- |
| `supervised-session-conductor` | 여러 작업자의 소유권·보고서·완료 신호·충돌을 조정하고 단일 사람 게이트를 제시 | 상세 운영 흐름을 자체 `references/operating-manual.md`로 배포 |
| `restart-safe-handoff` | 재시작 번들, 전달 시도, content/delivery 이중 영수증, writer takeover | `design-team` 연속성 계약을 선택적 도메인 확장으로 연결 |
| `runtime-incident-investigator` | App·Runtime·Terminal·Provider·Project 계층의 읽기 전용 조사와 반증 | remediation과 인수인계 권한을 소유하지 않음 |
| `design-team` session continuity | 디자인 승인·취향·시각 영수증·production boundary | 범용 handoff로 역링크하되 디자인 문구는 도메인에 유지 |

세 스킬은 같은 사건에 함께 쓰일 수 있지만 서로의 완료 주장을 대체하지 않는다. 지휘자는 대화와 ledger를, handoff는 전달·소유권을, investigator는 원인 판단을 소유한다.

## 반복 방지 계약

- 보고서와 `worker_done`을 별도 증거로 화해한다.
- send attempt와 receiver acknowledgement를 별도 상태로 기록한다.
- 살아 있는 coordinator 위에 두 번째 writer를 세우지 않는다.
- timeout·프로세스 종료·터미널 폐쇄만으로 takeover를 허용하지 않는다.
- 같은 시각의 오류를 공통 메커니즘 증거 없이 인과로 결론 내리지 않는다.
- 로컬 resource guard가 작동하면 새 worker를 늘리지 않고 먼저 project-owned checkpoint를 남긴다.
- 디자인과 QA가 충돌하면 양쪽 근거를 보존하고 한 번의 명시적 사람 게이트로 올린다.

## 멀티벤더 배포 구조

정본은 `skills/<name>/`이며 각 디렉터리 전체가 `distribution/manifests/<name>.json`에 해시된다. `registry/assets.yaml`과 생성된 `distribution/asset-catalog.json`이 자산 종류·이동성·벤더·수명주기·계보를 색인한다. 세 스킬은 `reviewed`로 등록하며 release bundle, 사용자 홈 설치, 외부 provider 실호출은 이 Goal에 포함하지 않는다.

## 검증 계획

- 세 스킬과 design-team의 `skill-creator` quick validator
- 적대 fixture 5건과 `node scripts/check-goal-15.mjs`
- 네 skill manifest 전체 파일·digest 검증
- registry/catalog 생성 및 check
- Goal 11–14 회귀 게이트
- 멀티벤더 `Check` 모드
- `git diff --check`

## 검증 결과

구현 게이트 실행 뒤 명령, 결과, manifest digest, catalog digest를 이 절에 기록한다. 사용자 홈 설치·외부 provider 실행은 수행하지 않는다.

## 사람 게이트와 잔존 위험

- 정적 검증은 실제 벤더 새 세션의 자동 발견을 증명하지 않는다. 실홈 설치와 실호출은 별도 승인 범위다.
- `reviewed`는 release가 아니다. push, PR, release, merge, publish는 수행하지 않는다.
- 런타임별 명령은 이 스킬에 고정하지 않는다. 실제 운용 시 설치된 version-matched live guide를 읽고 관측된 receipt만 보고한다.
