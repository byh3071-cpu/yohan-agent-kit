# 멀티벤더 전역 설치·새 세션 스모크 감사

- 날짜: 2026-07-30~31
- 상태: 진행 중
- 정본: `automation/yohan-cc-skills` commit `969d59848266a9f7808dfc43d521f20c80c4ec8a`
- 근거 결정: yohan-brain `ADR-013`, `ADR-014` (`Accepted`)
- 비범위: 기존 dirty checkout 두 곳의 수정·이동·삭제, main 직접 push·자동 머지

## 정본과 결정 게이트

| 항목 | 현재 증거 | 판정 |
|---|---|---|
| 책임 경계 | yohan-brain PR #168 merge commit `78d0e0f`; ADR-013·014 frontmatter와 본문 모두 `Accepted` | PASS |
| Public/dev 역전파 | yohan-brain PR #169 merge commit `91d1e38`; `repos.json`의 group=`automation` | PASS |
| 스킬·배포 도구 | yohan-cc-skills PR #65 merge 후 main, 후속 조정 PR #66 merge commit `969d598` | PASS |
| 스킬 구조 | skill-creator `quick_validate.py` 두 디렉터리 모두 valid | PASS |
| 구현 회귀 | `node scripts/check-goal-1.mjs`: Goal 1 gate와 PowerShell distribution state machine PASS | PASS |

## 기존 사본 보존과 표준 설치

전역 홈 변경은 정확한 대상·백업·junction 계획을 먼저 제시한 뒤 사용자 승인을 받아 실행했다. 기존 사본을 덮어쓰거나 삭제하지 않고 활성 발견 경로 밖의 별도 백업 루트로 이동했다.

### 기존 goal-cycle 보존

- 수동 보존 transaction: `C:\Users\user\.yohan-skill-legacy-backups\20260729-232728-goal-cycle-reconcile\manual-transaction.json`
- 상태: `Committed`
- 보존 대상: Claude Code·Cursor legacy·Gemini legacy의 기존 디렉터리 3개
- 보존 파일: `SKILL.md`, `reference.md` 각 3쌍
- 현재 백업 SHA-256 재검증: 6/6 PASS
- 활성 legacy 경로 `~/.cursor/skills/goal-cycle`, `~/.gemini/skills/goal-cycle`, `~/.codex/skills/goal-cycle`: 모두 없음

### 표준 junction 설치

- 공식 BackupId: `20260730-000550908-bcab11d6`
- 공식 transaction 상태: `Committed`
- 설치 대상: `adr-cycle`, `goal-cycle` 각각 Agents·Claude·AgyStandard, 총 6개
- 설치 후 일반 Check: `Healthy`
- Check PlanDigest: `6CB528A4657CC2DD59EAFAFDA5E46E9CC41C63433D8C10110D4DAFF60020654D`
- Restore 사전 점검: `RestoreReady`
- Restore RecoveryKind: `CommittedRestore`
- Restore PlanDigest: `C1F145A3CAFC6D1486CB56FDEDC1C0CF83E0EBAACDACFCDBDE1F1C7D7EEFE02B`

| 소비자 표면 | adr-cycle | goal-cycle | 상태 |
|---|---|---|---|
| `~/.agents/skills` | 정본 junction | 정본 junction | Healthy |
| `~/.claude/skills` | 정본 junction | 정본 junction | Healthy |
| `~/.gemini/config/skills` | 정본 junction | 정본 junction | Healthy |

## Orca 새 세션 스모크

Orca 1.4.158이 관리하는 정본 레포 터미널에서 실행하되, 레포 내부 `skills/`가 가짜 양성을 만들지 않도록 세션 작업 디렉터리를 `C:\Users\Public\dev`로 바꿨다. 모델 파일 쓰기는 read-only·ask·plan 모드로 차단했고, 로컬 raw 실행 로그는 `.vhk/events/`에만 두어 Git에 포함하지 않는다.

| 소비자 | 발견·명시 호출 | 자동 호출 | 부정 호출 | 판정 |
|---|---|---|---|---|
| Codex CLI 0.146.0 | 두 정본 스킬을 로드하고 Proposed 의존 구현을 BLOCK | 스킬 이름 없는 요청에서 `adr-cycle → 사람 ADR 승인 → goal-cycle` 선택 | “ADR이 뭐야?”에 한 문장 답변, `FILES_CREATED=no`; yohan-brain Git 상태 무변경 | PASS |
| Cursor Agent 2026.07.23-e383d2b | 두 스킬을 로드하고 Proposed 의존 구현을 BLOCK | 두 워크플로와 ADR 승인 게이트 자동 선택 | 한 문장 답변, `FILES_CREATED=no`; yohan-brain Git 상태 무변경 | PASS |
| Claude Code 2.1.220 | 새 세션 init 목록에서 두 스킬 발견 | 주간 한도 때문에 응답 검증 불가 | 주간 한도 때문에 응답 검증 불가 | 대기 |
| AGY CLI 1.1.8 | 표준 경로와 최초 CLI fallback junction 모두 미등록으로 판정 | 물리 어댑터 보정 전이라 미실행 | 한 문장 답변, `FILES_CREATED=no`; yohan-brain Git 상태 무변경 | FAIL-CLOSED |

Cursor Agent는 이 환경에서 공용 `~/.agents/skills`보다 Claude 호환 `~/.claude/skills` 경로를 실제 로드했다. 두 경로 모두 같은 정본 junction이므로 내용 드리프트는 없지만, 공용 경로 단독 발견을 증명한 것으로 확대 해석하지 않는다.

## AGY 조건부 fallback

AGY 1.1.8 새 세션에서 표준 `~/.gemini/config/skills` 발견 실패를 확인했다. 증거는 host·CLI 버전·두 manifest digest·표준 절대경로·24시간 만료에 결합했고 Git에서 무시되는 로컬 실행 증거에만 보관했다.

### 최초 junction fallback과 반증

사용자가 정확한 두 경로를 승인한 뒤 `~/.gemini/antigravity-cli/skills/{adr-cycle,goal-cycle}` junction을 설치했다.

- 승인 전 PlanDigest: `68DED270BB37B34DA365CE2163FF30D105E1566FAE4EBEF2719254D7BE859DC6`
- BackupId: `20260730-005800595-97913ff2`
- transaction: schema 3, `Committed`
- 설치 후 파일시스템 Check: `Healthy`, PlanDigest prefix `9EA3D944`
- Restore preflight: `RestoreReady`, PlanDigest prefix `AF9CF3D58`

그러나 새 AGY 세션은 이 두 junction도 주입하지 않았다. 즉 파일시스템 `Healthy`는 런타임 발견 성공 증거가 아니었다. junction은 현재 안전하게 남아 있지만 실효성이 없으며, 별도 승인 없이 제거하거나 복원하지 않는다.

### 실제 탐색 규약과 보정 방향

격리 probe에서 다음을 확인했다.

- AGY 1.1.8은 기존 `~/.gemini/skills`의 물리 디렉터리를 새 세션에 주입한다.
- `--add-dir` workspace의 물리 `.agents/skills`는 두 스킬을 발견하고 원문을 로드했다.
- 같은 위치의 junction은 이름 노출까지는 됐지만 target이 선언한 workspace 밖으로 해석되어 비대화식 세션의 읽기 권한 게이트에 걸렸다.
- 표준 문서와 내장 가이드는 `~/.gemini/config/skills`를 안내하지만, 현재 CLI 1.1.8의 실제 동작은 이 실측과 달랐다.

따라서 새 fallback은 `~/.gemini/skills/{adr-cycle,goal-cycle}`의 물리 생성 어댑터로 보정한다. 어댑터는 정본 파일과 `.yohan-adapter.json`을 포함하고 source path·Git commit·manifest digest·AGY version을 결정론적으로 봉인한다. 기존 `~/.gemini/antigravity-cli/skills` junction은 같은 향후 승인 transaction에서 이전 경로로 이관하며, 기존 schema 3 BackupId의 Restore 호환성은 유지한다.

보정 코드의 격리 회귀는 189 assertions를 통과했다. 실제 기존 schema 3 BackupId `20260730-000550908-bcab11d6`와 `20260730-005800595-97913ff2`도 보정 코드로 읽기 전용 재검사해 각각 `RestoreReady`를 확인했다. 새 물리 어댑터는 아직 실제 사용자 홈에 설치하지 않았다.

## 보존 대상 확인

두 dirty checkout은 이번 단계에서도 읽기 전용 상태 확인만 했다.

| 경로 | 현재 브랜치·상태 요약 | 조치 |
|---|---|---|
| `yohan-ecosystem/yohan-cc-skills` | `feat/html-doc-plugin`, origin/main보다 1 commit ahead, dirty 5 entries | 변경 없음 |
| `products/yohan-cc-skills` | `feat/skill-pipeline-baton`, dirty 5 entries | 변경 없음 |

## 완료 전 남은 증거

1. 물리 생성 어댑터·schema 3 호환 Restore의 격리 회귀와 구현 PR
2. 사람 머지 게이트 뒤 정확한 전역 변경 계획 재확인·별도 승인
3. 승인 뒤 물리 어댑터 Install·post-Check·RestoreReady와 AGY 새 세션 명시·자동·부정 호출
4. Claude Code 한도 리셋 뒤 새 세션의 명시·자동·부정 호출
5. 로컬 운영 문서와 yohan-brain bootstrap 미러의 설치 상태 역전파
6. 시크릿 검사·변경 파일 검수·별도 PR

## 교훈

설치 도구의 `Healthy`는 junction·adapter와 manifest의 정합을 뜻할 뿐, 각 벤더 실행기가 현재 버전에서 그 경로를 실제 발견한다는 뜻은 아니다. 배포 완료는 새 세션의 명시·자동·부정 호출까지 관찰한 뒤 판정한다. 이는 기존 `PAT-003`의 “상속 전제는 현재 실값으로 재검증” 원칙을 배포 표면에 적용한 사례다. 또한 Orca가 PATH 선두에 둔 `git.cmd` wrapper가 bare `git`을 재귀 호출한 문제는 `PAT-008`로 역전파했다.
