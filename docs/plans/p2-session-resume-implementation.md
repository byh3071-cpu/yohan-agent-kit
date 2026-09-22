# P2 Session Resume 구현 계획

## 결과

P1의 `task-context/v1`과 live Git/VHK 상태를 하나의 결정론적 `session-resume-packet/v1`로 묶고, 다른 프로세스가 source와 writer 상태를 다시 검증한 뒤 exact next gate를 ACK한다.

## 책임 경계

- yohan-mcp: task context와 runtime/index/catalog freshness 제공
- Agent Kit: packet schema, prepare/verify/ack, handoff 연결, client receipt
- 프로젝트 저장소: durable packet 소유 위치와 writer state
- MOVA P4: 자동 전달·재전송·재접속

## 티켓

1. 계약: JSON schema, canonical digest, content/delivery 상태 전이, 경로·시크릿 제한
2. 구현: portable Node CLI `prepare`, `verify`, `ack`; 명시적 입력/출력만 허용
3. 연결: `workflow:handoff` full 절차가 CLI와 project-owned packet 경로를 안내
4. 회귀: valid/stale/corrupt/conflict/secret/path/writer fixture와 Goal 15·16 회귀
5. 실증: actual yohan-mcp Muse envelope → packet → fresh process verify/ack
6. 전달: audit, exact SHA/digest, 독립 검토, Draft PR

## 데이터 흐름

`get_context envelope + repository root + explicit writer metadata` → prepare → canonical packet + content receipt → fresh receiver verify → explicit acknowledge → delivery receipt.

Prepare는 네트워크와 사용자 홈을 쓰지 않는다. Verify는 packet의 Git SHA·evidence hash·dirty state·freshness·writer epoch를 live state와 대조한다. ACK는 receiver와 current gate·next action을 요구하며 자동 takeover를 수행하지 않는다.

## 실패 계약

- schema/digest/duplicate key/path/secret 실패: INVALID
- source/evidence/dirty/freshness drift: STALE
- writer/epoch/live state 충돌: CONFLICTED
- 필요한 source 접근 불가: INDETERMINATE
- 검증 성공 뒤 명시 ACK 전: VERIFIED + delivery `sent` 또는 `not-sent`
- ACK 성공: content `verified`, delivery `acknowledged`

## 검증

- 결정론 단위 테스트와 adversarial fixture
- Goal 15·16·18 gate
- actual P1 stdio MCP envelope cross-repository fixture
- fresh Node process verify/ack
- secret-pr-guard와 `git diff --check`
- 독립 Sol 검토

## 남는 사람 게이트

Draft PR Ready·merge, 사용자 홈 설치, 실제 두 번째 기기 검증, Goal 완료 판정.
