# next-task

> append-only — 새 항목은 맨 아래에 추가만 한다(기존 줄 수정·삭제 금지). active goal 1개만 작업한다. (출처: `AGENTS.md` Loop Protocol)

- [ ] 2026-07-02 멀티모델 오케스트레이션 도입 — **승인 대기**. 상세: `docs/log/2026-07-02-handoff.md` (팩트체크 완료, 승인 시 서브에이전트 tier 고정 + Codex 플러그인 통합)
- [x] 2026-07-03 멀티모델 배분 정렬 완료 — planner·critic→opus, 독트린 3곳 정렬(CLAUDE.md·cost-guard·핀)+ARCHITECTURE·PRD 미러 동반, 순정 스위치 추가, plugin 0.3.1. 상세: `docs/log/2026-07-02-handoff.md` §5 정정. (Codex·cross-check 통합은 별건 대기)
- [x] 2026-07-06 문서 드리프트 정합 — README·PRD·ARCHITECTURE를 실측 4플러그인(critical-thinking 추가)·yohan-core studio-post 스킬·workflow overnight-autoloop·plugin.json 버전으로 통일, SETUP-HANDOFF STEP0 경로 정정(automation→yohan-ecosystem), 2026-07-02 핸드오프 상태선 반영완료로 정정. (Codex 통합은 이미 라이브 활성 — settings.json codex@openai-codex + 마켓 등록; 잔여 cross-check/release-gate 병렬통합)
- [ ] 2026-07-16 `/handoff` 채팅 종료 검증(scan/close/full·재고축) — 브랜치 `feat/handoff-session-end-verify` 커밋 2개 로컬만. **다음: push→PR→머지→plugin 0.3.4 갱신**. 상세 `docs/log/2026-07-16-handoff-session-end-verify.md`
- [x] 2026-07-16 `/handoff` 채팅 종료 검증 출시 완료 — PR #32 머지·workflow 0.3.4 설치·prac worktree 삭제. **다음: Claude 재시작 후 라이브 `채팅 종료 검증 ㄱㄱ`**. (선택) gone 로컬 브랜치 `fix/overnight-autoloop-crlf-launch` 삭제. 상세 log 동일 파일 §후속.
- [x] 2026-07-21 plan-audit `0.3.14`~`0.3.18` 출시 완료 — PR #54·#55·#57·#58·#59·#60 머지, yohan-core `0.3.18` 설치. Codex 벤더 교차검증 15건 처리(치명 3·높음 3·중간 7, 의도적 보류 1), V7·V8 블라인드 트리거 검증 6/6, 절차 실행 실전 검증 PASS. studio-post 규율 7 분량 정정(`0.3.16`) + PR #29 close. **다음: 블라인드 경로(2-C critic) 실전 미검증 — 다음 세션에서 미승인 계획 세우고 `검증 및 리뷰` 치면 자연 검증됨.** (선택) Codex가 의도적 보류한 `#10`(2회차 상호작용), 커서 연동 조사. 상세 `docs/log/2026-07-21-plan-audit.md`
- [ ] 2026-07-29 ADR-013·014 기반 adr-cycle·goal-cycle 멀티벤더 정본화 — active goal: `goals/1-multivendor-skill-sot.md`. 사용자 홈 설치와 dirty checkout 정리는 비범위.
