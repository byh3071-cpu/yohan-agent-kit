---
name: handoff
description: Use when a session is ending/pausing, moving between machines, or the user asks for chat/session end verification — scan→close(기본)→full. 채팅 종료 검증=재고+안전 조치. Triggers - "채팅 종료 검증", "채팅 종료 섹션 검증", "세션 종료 검증", "핸드오프", "마무리하자", "오늘 끝", "내일 이어서", "노트북으로 전달", "정리하고 끝", "다른 기기에서 이어서", "컨텍스트 work로 남겨".
---

# handoff

세션 맥락을 디스크에 고정하고, 다른 기기 복원용 **전달 프롬프트**를 만든다.
「채팅 종료 검증」= **재고(감사) + 안전한 마감 조치** (리포트만 아님 — history 실측).

## 모드 (R1)

| 모드 | 언제 | 하는 일 |
|------|------|---------|
| **scan** | "표만", "확인만", "아직 건드리지 마" | **재고만** 보고. 쓰기·삭제·커밋 금지 |
| **close** | **"채팅/세션 종료 검증"**·"섹션 검증"·"종료 검증 ㄱㄱ" (기본) | 재고 → **안전 조치** (문서/핸드오프/next-task/log). 커밋·push·삭제는 **승인 후** |
| **full** | 핸드오프·마무리·내일·전달·정리하고 끝 **또는** 종료검증+핸드오프가 한 메시지 | close + 전달 프롬프트 + (승인 시) 커밋·설정 동기화 |

- 종료검증만 = **close** (verify-only 아님).
- 애매하면 close로 진행하되, 위험 조치는 승인 받고.
- `/release-gate`·머지 강행과 섞지 말 것.

## 원칙

- 핸드오프 **파일** = 1차 진실 (노션만 복원 약함).
- 산출물 **경로 포인터** 필수.
- 브랜치/worktree **삭제·머지·force** = 승인 후만.
- Notion **적재** = 강제 자동화 말고 후보+템플릿(또는 MCP 있으면 제안 후 승인).

## 재고 축 (R2) — 네 말 그대로

실측 (`git status -sb`, 파일 존재, 세션에서 한 일). 없으면 **N/A**.

| 축 | 볼 것 | 결과 값 |
|----|------|---------|
| **문서화** | log/ADR/TS/README/HANDOFF 초안 필요? | 없음 / 후보경로 / 갱신함 |
| **적재** | Notion Dev Log 등 외부 적재 필요? | 없음 / 후보1줄 / 승인후적재 |
| **갱신** | next-task·LIVE·기존 HANDOFF·버전 줄 stale? | OK / stale→고침 |
| **핸드오프** | 이어가기 문서·전달 블록 필요? | 불필요 / 갱신·생성 |
| **Goal·이슈** | goals·이슈·blockers로 남길 것? | 없음 / 초안1줄 |
| **git** | 미커밋·미추적·푸시 안 됨? | clean / 잔여목록 |
| **브랜치·worktree** | 죽은 브랜치·worktree? | 없음 / 목록(삭제=승인) |
| **거짓완료** | 미완·게이트 실패인데 완료 톤? | OK / `vhk review` 권고 |

## 출력 (모든 모드 공통 뼈대)

```text
## 채팅 종료 검증
모드: scan | close | full

### 재고
| 축 | 상태 | 근거 | 조치 |
| 문서화 | … | … | 지금/나중/안함 |
| 적재 | … | … | … |
| 갱신 | … | … | … |
| 핸드오프 | … | … | … |
| Goal·이슈 | … | … | … |
| git | … | … | … |
| 브랜치·worktree | … | … | … |
| 거짓완료 | … | … | … |

### 조치 분류
- 지금 함: …
- 승인 필요: … (커밋/push/삭제/머지/Notion쓰기)
- 나중에/안 함: …

### 다음에 이어갈 한 줄
…
```

## close 절차 (todo)

1. **재고** (위 표).
2. **지금 함 (안전):** 해당되는 것만 — `docs/log/...` append · next-task/LIVE/HANDOFF 갱신 · Goal/이슈 **초안 문구** · 브랜치 목록.
3. **승인 필요**만 따로 묻고 실행 (커밋·push·삭제·Notion 적재).
4. 짧게 “이어갈 한 줄” + (원하면) full 제안.

## full 절차 (todo) — close 위에 얹음

1~4 = close
5. **프로젝트 소유 Resume packet 준비:** 저장소 규칙이 정한 입력을 읽고 아래처럼 ignored project state인 `.vhk/receipts/` 아래에 명시적으로 쓴다. 사용자 홈·Temp·채팅 본문은 정본 경로로 쓰지 않는다.

   ```sh
   node scripts/SessionResumePacket.mjs prepare --context <task-context.json|-> --repo-root <clean-git-root> --evidence-root <yohan-brain-root> --ownership-state .vhk/ownership/current.json --source-ref <relative-posix-ref> --current-gate <exact-gate> --writer <writer-id> --writer-epoch <positive-integer> --allow <allowed-work> --forbid <forbidden-work> --human-gate <human-gate> --output .vhk/receipts/session-resume-packet.json
   ```

6. **수신 측 재검증:** 새 프로세스·세션은 같은 프로젝트 소유 packet에 대해 아래 read-only 검증을 실행한다. source SHA·evidence hash·dirty state·freshness·active writer/epoch이 live state와 다르면 `STALE`·`CONFLICTED`·`INDETERMINATE`로 닫고 작업을 시작하지 않는다.

   ```sh
   node scripts/SessionResumePacket.mjs verify --packet .vhk/receipts/session-resume-packet.json --context <task-context.json|-> --repo-root <clean-git-root> --evidence-root <yohan-brain-root> --ownership-state .vhk/ownership/current.json --expected-writer <writer-id> --expected-writer-epoch <positive-integer> --expected-packet-digest <externally-recorded-sha256>
   ```

7. **명시 ACK:** 검증 성공 뒤 receiver·owner scope·source ref·current gate·exact next action을 명시해 ACK를 프로젝트 소유 경로에 별도로 쓴다. ACK가 만든 delivery receipt가 있어야 `acknowledged`다.

   ```sh
   node scripts/SessionResumePacket.mjs ack --packet .vhk/receipts/session-resume-packet.json --context <task-context.json|-> --repo-root <clean-git-root> --evidence-root <yohan-brain-root> --ownership-state .vhk/ownership/current.json --receiver <receiver-id> --owner-scope <repo-id> --source-ref <same-relative-posix-ref-bound-by-prepare> --current-gate <exact-gate> --next-action <exact-next-action> --expected-writer <writer-id> --expected-writer-epoch <positive-integer> --expected-packet-digest <externally-recorded-sha256> --output .vhk/receipts/session-resume-ack.json
   ```
8. **전달 프롬프트** (packet의 프로젝트 상대경로·브랜치·명령·기기차·yohan-cc-skills install). raw prompt·raw answer·시크릿·기기별 절대경로를 packet에 복사하지 않는다.
9. **커밋 승인 후** (push/머지도 승인 후)
10. 설정 드리프트 → install (파일복사 X)
11. (VHK) `vhk work handoff` 보조. packet 검증과 ACK를 대체하지 않는다.
12. (선택) 복원 자가평가 1~5

### Resume packet 규칙

- `prepare`, `verify`, `ack`는 모두 명시적 입력을 사용한다. durable 산출물인 packet과 ACK는 `--output`으로 **프로젝트가 소유한 명시적 경로**에 쓴다. stdout은 canonical 결과 확인용이며 사용자 홈 저장이나 외부 자동 전송에 기대지 않는다.
- prepare와 verify는 clean Git repository에서만 진행한다. dirty 상태를 packet에 정상 상태로 봉인하거나 수신 시점 변경과 섞지 않는다.
- `--ownership-state`는 repository 내부 상대 POSIX 경로의 `session-ownership/v1` regular JSON file이다. 세 명령 모두 live content digest·writer·epoch·liveness·source ref·current gate를 packet과 다시 맞춘다.
- ownership `updated_at`의 고정 한도는 `max_age_seconds: 3600`, 허용하는 미래 시계 오차는 `future_skew_seconds: 300`이다. 1시간을 넘긴 상태는 `ownership_stale`, 현재 UTC보다 5분을 초과해 미래인 상태는 `ownership_from_future`로 `INDETERMINATE` 처리하며 prepare·verify·ACK 모두 멈춘다.
- ownership이 `active`이고 기대 writer가 정확히 일치할 때만 `scoped_write`다. `yielded`는 `read_only_pending_ownership`으로 implementation·repository write·takeover를 금지하고, `unknown`은 `INDETERMINATE`로 닫는다.
- live branch는 packet branch와 정확히 같아야 한다. SHA가 같아도 branch가 다르면 `CONFLICTED`이며 작업을 재개하지 않는다.
- prepare는 `--source-ref`를 packet에 묶는다. ACK는 임의 ref가 아니라 packet에 묶인 같은 상대 POSIX ref를 다시 확인한다.
- verify와 ACK는 원본 `--context`의 canonical digest와 `volatile: true`·`persisted: false` provenance를 다시 확인하고, `--evidence-root`의 regular file을 live rehash한다. evidence 누락·변경·중복·document 충돌·symlink/reparse 이탈은 성공으로 완화하지 않는다.
- `--expected-packet-digest`는 필수 외부 기대값이다. 수신한 packet 내부에서 읽어 자기 자신을 승인하지 말고, prepare 시 별도로 기록·전달된 SHA-256과 비교한다.
- **Content receipt**는 packet 내용과 source가 현재임을 증명한다. **Delivery receipt**는 대상이 수신하고 exact next gate를 ACK했음을 증명한다. `prepared`·`verified`·`sent`를 `acknowledged`로 간주하지 않는다.
- stale source/index/evidence/dirty state, writer 충돌, epoch 불일치, 접근 불가 상태에서는 fail-closed한다. live state와 packet을 임의 병합하거나 새 writer를 자동 생성하지 않는다.
- takeover는 이 절차의 자동 동작이 아니다. 기존 writer가 살아 있거나 liveness가 불명확하면 읽기 전용으로 멈추고 `restart-safe-handoff`의 명시적 ownership 절차를 따른다.
- ACK는 packet과 context를 각각 한 번만 읽은 동일 immutable object로 검증·생성하고 항상 `takeover: false`다. verify 뒤 파일을 다시 읽어 바뀐 내용을 승인하지 않는다.
- 한 기기에서 새 프로세스로 검증한 결과는 교차 클라이언트 local evidence다. 실제 두 번째 기기를 사용하지 않았다면 receipt와 보고서에 `REAL_MACHINE_UNVERIFIED`를 유지한다.

## 중복 방지

| 이 스킬 | 다른 것 |
|---------|---------|
| 세션 마감 재고·close | `/release-gate` = 릴리즈 직전 |
| 전달 프롬프트 | `vhk context` = 저장소 |
| 거짓완료 | `vhk review` 권고만 |
| Notion 적재 | 강제 MCP 실행 X — 후보/승인 |
