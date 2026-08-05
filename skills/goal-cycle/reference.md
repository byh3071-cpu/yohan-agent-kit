# goal-cycle 운영 참고

이 문서는 프로젝트에 아래 도구가 실제로 있을 때만 읽는다. 이름이 같아도 프로젝트 규칙이 다르면 가장 가까운 규칙과 활성 로스터가 우선한다.

## 단계와 역할 대조

| 일반 패턴 | 골 사이클 |
|---|---|
| 사람이 결정하고 에이전트가 실행 | 사람=ADR·Plan·머지 게이트, 에이전트=승인 범위 내 조사~PR |
| 작은 작업 단위 | 티켓 |
| Builder와 Validator 분리 | 만들기와 검수 분리 |
| 구현 전 합의 | 스펙·설계·티켓나누기 뒤 승인 |
| 배포 뒤 관찰 | 지켜보기·다듬기 |

## 생태계 도구의 조건부 매핑

| 도구가 존재할 때 | 역할 |
|---|---|
| `dump-gate`, `thought-to-prompt` | 사이클 전에 생각을 실행 가능한 요청으로 정리 |
| Plan 모드 + `goal-cycle` | 조사~티켓나누기 |
| VHK goal | 프로젝트 Git의 지속 goal 상태와 검증 게이트 |
| Orca | `execution_provider=orca-ready`인 L 작업의 worktree·터미널·에이전트 실행과 런타임 상태 |
| `vhk-auto` | 현재 계약이 허용하는 구현·커밋; 자동 PR이나 머지로 간주하지 않음 |
| `overnight-vhk-auto` + `auto_pr` | 해당 프로젝트 계약이 있을 때 PR올리기까지 연결 |
| `check-goal`, CI | 검증 증거 |
| 다른 벤더·독립 검토자 | 만든 이와 분리된 검수 |
| `morning-merge-check` | 사람의 머지판정 지원; 직접 머지하지 않음 |
| improvement loop | 다듬기와 교훈 역전파 |

`overnight-autoloop`처럼 이름이 비슷한 별도 트랙을 goal-cycle 실행기로 추정하지 않는다. 실제 계약 문서를 먼저 읽는다.

## 이름 충돌 방지

- 조사(Scout)는 경쟁사 조사 전용 `research-scout`와 다르다.
- Plan은 합의·설계 단계이며 임의의 계획 문서 전체를 뜻하지 않는다.
- 검증(Verify)은 테스트 증거이고 검수(Review)는 다른 눈의 실패 탐색이다.
- handoff는 컨텍스트 인계이며 티켓의 대체물이 아니다. 결정 경로·제약·미해결 위험·남은 사람 게이트를 잃지 않는다.
- `/goal`은 goal 상태를 지속하는 표면이다. L 작업 등급과 `orca-ready`·`native-approved`·`plan-only`·`blocked` 실행 공급자 상태를 합치지 않는다.

## Orca selector와 수명주기

1. 현재 세션에서 `ORCA_CLI_COMMAND` → `ORCA_DEV_REPO_ROOT`가 있는 세션의 `orca-dev` → Linux 비관리 터미널의 `orca-ide` → 그 밖의 `orca` 순서로 하나만 고른다.
2. 선택한 명령이 실패하면 다른 Orca 실행 파일로 폴백하지 않는다. `automatic_fallback=false`다.
3. 선택한 동일 CLI에서 `skills get orca-cli`, `skills get orchestration`, bounded status를 조회해 bootstrap과 runtime readiness를 분리한다.
4. runtime이 준비된 `orca-ready`에서만 Run·Task·Dispatch를 만들고, 현재 schema의 필수 플래그를 사용한다.
5. 완료 뒤에는 현재 계약에 따라 `worker_done`을 확인하고 `check`를 통과한 다음 `worker-release`로 격리 자원을 해제한다.
6. `native-approved`는 명시 승인된 별도 어댑터다. Orca 장애로 자동 선택하지 않고, Orca 전용 완료 신호를 강제하지 않는다.

## 한도와 실패 처리

1. 사용량 표시만으로 한도 소진을 추측하지 않는다.
2. 자동 failover는 현재 Orca·로스터 계약이 명시한 명령과 횟수 안에서만 수행하되, 다른 Orca CLI나 네이티브 공급자로 바꾸는 자동 폴백은 하지 않는다.
3. CLI 이전이 자동화되어 있지 않으면 필요한 재개 지점과 근거를 사용자에게 전달한다.
4. 완료 신호 형식은 현재 실행 계약에서 읽고, 모든 환경에 `worker_done`을 강제하지 않는다.
