# blockers

> append-only — 새 차단요인은 맨 아래에 추가만 한다(기존 줄 수정·삭제 금지). 해소 시에도 줄을 지우지 말고 상태를 덧붙인다. (출처: `AGENTS.md` Loop Protocol)

- [ ] 2026-07-30 AGY CLI 1.1.8은 표준 `~/.gemini/config/skills`의 adr-cycle·goal-cycle을 새 세션에서 발견하지 못함 — 조건부 fallback 두 junction의 별도 사용자 승인 대기. Claude Code 자동·명시·부정 호출은 주간 한도 리셋(2026-08-01 15:00 Asia/Seoul) 후 검증 대기.
- [ ] 2026-07-31 위 fallback junction 승인은 집행됐으나 AGY 1.1.8 런타임이 `~/.gemini/antigravity-cli/skills`도 주입하지 않아 반증됨 — `~/.gemini/skills` 물리 생성 어댑터의 구현 PR·머지와 정확한 전역 변경 재승인 뒤 AGY 명시·자동·부정 호출을 재검증한다. 기존 두 fallback junction은 새 승인 전까지 유지한다. Claude Code 검증 대기도 유지한다.
