# Session Resume Packet v1

`session-resume-packet/v1`은 P1 `task-context/v1`과 현재 Git 상태를 묶어 다른 세션이 같은 작업을 재개하기 전에 검증하게 하는 로컬 계약이다. 이 계약은 자동 인계나 writer takeover를 수행하지 않는다.

## 입력과 출력

CLI는 Node.js 내장 모듈만 사용한다. P1 `get_context` 봉투는 `--context <file>` 또는 `--context -`로 명시해서 전달한다. 네트워크를 호출하지 않고 사용자 홈에 암묵적으로 쓰지 않는다.

```text
node scripts/SessionResumePacket.mjs prepare \
  --context context-envelope.json \
  --repo-root <git-root> \
  --evidence-root <yohan-brain-root> \
  --ownership-state .vhk/ownership/current.json \
  --source-ref codex/tasks/p2-session-resume \
  --current-gate implementation \
  --writer codex-p2 \
  --writer-epoch 7 \
  --allow "Implement the approved P2 contract" \
  --forbid "Merge without a human gate" \
  --human-gate "PR Ready and merge" \
  --output .vhk/receipts/session-resume.json
```

`--allow`, `--forbid`, `--human-gate`는 여러 번 줄 수 있다. complete packet은 세 목록에 각각 최소 한 항목이 필요하다. partial packet의 allow/forbid 핵심값은 CLI가 안전한 read-only 정책으로 고정하며 human gate는 최소 한 항목이 필요하다. P1이 next action을 여러 개 반환하면 `--next-action`으로 그중 정확한 문자열 하나를 선택한다. `--max-age-seconds` 범위는 60초부터 7일까지이며 기본값은 24시간이다. 테스트에서는 `--now <ISO-8601 UTC>`를 쓸 수 있다.

P1이 `status: partial`과 `missing_project_goal`, `missing_next_action`을 반환한 경우 goal이나 구현 행동을 만들어내지 않는다. 다음처럼 goal 선택을 위한 exact resolution action을 명시해야 한다.

```text
node scripts/SessionResumePacket.mjs prepare \
  --context partial-context-envelope.json \
  --repo-root <git-root> \
  --evidence-root <yohan-brain-root> \
  --ownership-state .vhk/ownership/current.json \
  --source-ref codex/tasks/p2-session-resume \
  --current-gate goal-resolution \
  --resolution-next-action "Select and record one active project goal before any implementation" \
  --writer codex-p2 \
  --writer-epoch 7 \
  --forbid "Merge without a human gate" \
  --human-gate "Goal selection approval" \
  --output .vhk/receipts/session-resume-partial.json
```

이 경우 packet은 P1 `status`와 `reason_codes`를 순서까지 그대로 보존한다. goal은 `state: missing`이고 id·status·title·source ref는 `null`이다. next action source는 `explicit_resolution`이다. policy는 caller가 준 allow 문구를 실행 권한으로 쓰지 않고 `execution_mode: read_only_until_goal_selected`, `goal_selection_required: true`를 고정한다. 허용 범위는 context 확인·goal 선택·resolution evidence 준비뿐이고 `implementation`, `repository_writes`, `writer_takeover`를 항상 금지한다. `shared_repository_evidence_included`와 `other_repository_evidence_excluded`는 provenance로 보존하지만 blocker로 승격하지 않는다. blocker에는 원래 P1 blocker와 `missing_project_goal`, `missing_next_action`만 들어간다. 이 네 reason 이외의 partial reason, `conflict`, `unresolved`는 fail closed 한다.

`--ownership-state`는 repository 내부의 상대 POSIX 경로이며 regular JSON file이어야 한다. 고정 schema는 아래 여덟 필드만 허용한다.

```json
{
  "schema": "session-ownership/v1",
  "active_writer": "codex-p2",
  "writer_epoch": 7,
  "liveness": "active",
  "source_ref": "codex/tasks/p2-session-resume",
  "current_gate": "implementation",
  "updated_at": "2026-09-22T00:05:00Z",
  "content_digest": "<sha256>"
}
```

`content_digest`는 해당 필드만 제외한 object의 sorted JSON UTF-8 SHA-256이다. prepare는 `--writer`, `--writer-epoch`, `--source-ref`, `--current-gate`가 live ownership state와 정확히 같을 때만 packet을 만든다. `liveness: unknown`은 `INDETERMINATE`다. ownership `updated_at`에는 고정 freshness 한도 `max_age_seconds: 3600`과 미래 시계 오차 `future_skew_seconds: 300`을 적용한다. 1시간보다 오래됐으면 `ownership_stale`, 현재 UTC보다 5분을 초과해 미래면 `ownership_from_future`로 `INDETERMINATE` 처리하며, prepare와 verify/ACK 모두 scoped write 전에 이를 검사한다. complete context라도 `yielded`이면 `read_only_pending_ownership`으로만 만들고 구현·쓰기·takeover를 금지한다. `scoped_write`는 신선한 `active` writer가 정확히 일치할 때만 허용한다. packet에는 ownership 파일의 상대경로·digest·liveness·writer·epoch·source ref·gate·updated time과 고정 freshness 한도를 묶는다.

`--output`은 선택 사항이며 반드시 현재 프로젝트의 `.vhk/receipts/` 아래 상대 POSIX 경로여야 한다. 이 저장소는 해당 디렉터리를 로컬 runtime receipt로 ignore한다. 기존 output은 덮어쓰지 않는다. 기존 경로 구성요소의 symlink·junction·reparse link, realpath 이탈, Windows ADS colon, reserved device name, control/NUL, trailing dot/space를 거부한다. CLI는 같은 canonical JSON을 stdout에도 출력한다. 임의 절대경로, 사용자 홈 기본값, 네트워크 대상은 지원하지 않는다.

성공한 prepare 출력의 식별자는 다음과 같다.

```json
{"schema":"session-resume-packet/v1"}
```

## 패킷이 고정하는 상태

- 등록된 repository id, canonical 상대경로, repository manifest 상대경로
- 명시적인 source ref와 clean live Git SHA·정확한 branch (`dirty: false`만 허용)
- 선택된 단일 active goal의 id·상태·제목·content ref 또는 명시적인 missing goal
- P1 task-context status·reason code, 현재 사람/자동화 gate, exact P1/resolution next action, blocker
- active writer, 양의 writer epoch, `takeover: forbidden`
- project-owned ownership state의 상대경로·digest·liveness·updated time·고정 freshness 한도(3600초/미래 300초)
- 허용 작업, 금지 작업, 사람 gate
- P1 runtime implementation digest와 source revision
- index revision, generation, 관측 시각, freshness, catalog revision
- 원본 P1 context envelope canonical SHA-256 및 `volatile: true`, `persisted: false`
- bounded evidence locator와 재계산한 content SHA-256
- 생성·만료 시각과 canonical content receipt

경로로 쓰이는 값은 상대 POSIX 경로만 허용한다. prepare와 verify 모두 작업 repository가 clean이어야 한다. `--evidence-root`는 basename이 `yohan-brain`이어야 하며 각 evidence locator는 regular file이어야 한다. 모든 경로 구성요소에서 symlink·junction·realpath 이탈을 막고, `document_id == "brain:" + locator`를 확인하고, LF-normalized UTF-8 SHA-256을 다시 계산한다. duplicate tuple과 같은 document id의 충돌은 거부하며 packet evidence는 결정론적으로 정렬한다.

패킷은 32 KiB, 입력 봉투는 256 KiB, evidence와 각 policy 목록은 16개로 제한한다. schema 외 필드, command별 allowlist 밖 option, 중복 JSON key, 손상된 JSON, secret처럼 보이는 key/value, 절대·native 경로는 fail closed 한다. `expires_at - created_at`은 정확히 `max_age_seconds`여야 한다.

`receipts.content.digest`는 `receipts` 전체를 제외한 패킷을 key 정렬된 JSON UTF-8로 canonicalize한 SHA-256이다. `receipts.delivery`는 항상 `null`이다. 전달 성공은 패킷 내용을 바꾸지 않고 별도의 ACK artifact로 증명한다.

현재 fixture와 로컬 검증은 단일 기기에서만 수행되므로 packet과 ACK는 정확히 `REAL_MACHINE_UNVERIFIED`를 기록한다. 이 구현은 해당 값을 다른 값으로 바꿔 실제 노트북↔PC 검증을 주장할 수 없게 한다. 실제 교차 기기 검증은 별도 evidence가 생긴 뒤 계약을 개정해야 한다.

## 검증

```text
node scripts/SessionResumePacket.mjs verify \
  --packet .vhk/receipts/session-resume.json \
  --context context-envelope.json \
  --repo-root <git-root> \
  --evidence-root <yohan-brain-root> \
  --ownership-state .vhk/ownership/current.json \
  --expected-writer codex-p2 \
  --expected-writer-epoch 7 \
  --expected-packet-digest <sha256>
```

verify는 위 ownership 두 값과 expected packet digest를 모두 필수로 받는다. 원본 `--context`를 다시 읽어 canonical envelope digest와 `volatile/persisted`, runtime/index/catalog/task-context lineage를 비교하고, `--evidence-root`의 모든 evidence를 다시 hash한다. `--ownership-state`도 다시 읽어 자체 digest와 packet에 묶인 모든 필드를 비교한다. missing·변경·unknown liveness뿐 아니라 3600초 초과 stale 상태와 300초 초과 future 상태도 fail closed 한다. live branch는 packet branch와 정확히 같아야 하므로 같은 SHA의 다른 branch도 `branch_changed` conflict다.

성공은 `classification: VERIFIED`다. 실패는 exit code 2와 다음 분류 중 하나를 반환한다.

| 분류 | 의미 |
|---|---|
| `INVALID` | JSON/schema, path, secret, content digest 또는 receipt가 유효하지 않음 |
| `STALE` | packet/index 시간이 만료됐거나 live Git SHA가 변경됨 |
| `CONFLICTED` | repository identity, dirty 상태, writer 또는 epoch가 달라짐 |
| `INDETERMINATE` | Git이나 필수 P1 lineage를 확인할 수 없고 안전한 판단이 불가능함 |
| `VERIFIED` | packet integrity, freshness, live Git, writer 기대값이 모두 일치함. partial resolution blocker가 해결됐다는 뜻은 아님 |

검증 실패를 빈 성공이나 실행 허가로 해석하면 안 된다.

## ACK

```text
node scripts/SessionResumePacket.mjs ack \
  --packet .vhk/receipts/session-resume.json \
  --context context-envelope.json \
  --repo-root <git-root> \
  --evidence-root <yohan-brain-root> \
  --ownership-state .vhk/ownership/current.json \
  --receiver claude-desktop \
  --owner-scope yohan-agent-kit \
  --source-ref codex/tasks/p2-session-resume \
  --current-gate implementation \
  --next-action "Implement prepare, verify, and acknowledge" \
  --expected-writer codex-p2 \
  --expected-writer-epoch 7 \
  --expected-packet-digest <sha256> \
  --output .vhk/receipts/session-resume-ack.json
```

ACK는 packet과 context를 각각 한 번만 읽은 뒤 같은 immutable object로 verify를 수행한다. receiver, repository owner scope, packet에 prepare 시 묶인 exact source ref, current gate, exact next action, expected writer/epoch/digest를 모두 명시해야 한다. 일치한 경우에만 별도 `session-resume-ack/v1` artifact가 `status: ACKNOWLEDGED`로 생성된다. ACK는 기존 writer와 epoch를 복사하고 `takeover: false`를 고정한다.

partial packet의 ACK는 `execution_mode: read_only_until_goal_selected`를 그대로 복사한다. yielded packet의 ACK도 `read_only_pending_ownership`을 유지한다. 따라서 전달 확인은 구현 권한이나 writer takeover를 부여하지 않는다.

## 테스트

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/SessionResumePacket.Tests.ps1
```

fixture는 complete active/yielded, 실제 P1 missing-goal partial shape와 informational reason, missing·tampered·writer/epoch/liveness/gate/source 변경 ownership state, unknown/stale/future ownership, omitted ownership 기대값, wrong expected digest, arbitrary ACK source ref, same-SHA branch drift, dirty prepare/verify, stale SHA, missing·changed·duplicate·conflicting evidence, context mutation, volatile provenance, duplicate/corrupt JSON, secret, absolute path, writer conflict, unknown option, ADS output, 지원 환경의 symlink output, stdin packet single-read ACK를 포함한다.
