# goal-cycle 기존 사본 조정 감사

- 날짜: 2026-07-29
- 범위: 사용자 홈의 Claude Code·Cursor·Gemini 기존 사본 읽기 전용 조사
- 근거 결정: yohan-brain ADR-014
- 결과: 사용자 승인에 따라 Claude Code·Gemini의 긴 `reference.md`를 초기 정본 이관값으로 채택하고, 의미 보강은 후속 커밋으로 분리한다.

## 전체 디렉터리 manifest

| 출처 디렉터리 | 상대 경로 | 바이트 | SHA-256 |
|---|---|---:|---|
| `C:\Users\user\.claude\skills\goal-cycle` | `SKILL.md` | 3078 | `DD1059EB3B9D90D06C49D81C907EDA43FF0117158DB13A522EED0CEF02B4B704` |
| `C:\Users\user\.claude\skills\goal-cycle` | `reference.md` | 1776 | `8F32C856A5B72715124883095518E41EA58B639A2A346709730F291AE99F665E` |
| `C:\Users\user\.cursor\skills\goal-cycle` | `SKILL.md` | 3078 | `DD1059EB3B9D90D06C49D81C907EDA43FF0117158DB13A522EED0CEF02B4B704` |
| `C:\Users\user\.cursor\skills\goal-cycle` | `reference.md` | 1000 | `A7275EE7E614DABED32F5B5D070215A736F29473A008FD936FB1D74FD4FCBAE2` |
| `C:\Users\user\.gemini\skills\goal-cycle` | `SKILL.md` | 3078 | `DD1059EB3B9D90D06C49D81C907EDA43FF0117158DB13A522EED0CEF02B4B704` |
| `C:\Users\user\.gemini\skills\goal-cycle` | `reference.md` | 1776 | `8F32C856A5B72715124883095518E41EA58B639A2A346709730F291AE99F665E` |

각 디렉터리에는 위 두 파일만 있었다. 세 `SKILL.md`는 바이트 단위로 같고, Claude Code와 Gemini의 `reference.md`도 바이트 단위로 같다. Cursor의 `reference.md`만 다르다.

## 차이 판정

| 항목 | 긴 변형(Claude Code·Gemini) | 짧은 변형(Cursor) | 판정 |
|---|---|---|---|
| Agentic SDLC 매핑 | 티켓 단위와 품질 게이트까지 포함 | 핵심 네 항목으로 축약 | 긴 변형을 초기 이관값으로 보존 |
| 생태계 도구 매핑 | `vhk-auto`, `overnight-vhk-auto`, `overnight-autoloop`, 검수·다듬기까지 포함 | 핵심 도구만 포함 | 긴 변형을 초기 이관값으로 보존하되 현행 계약과 후속 대조 |
| 이름 충돌 방지 | 네 항목 포함 | 없음 | 긴 변형을 보존 |
| 한도 우회 | 본문 `SKILL.md`에만 있음 | `quota-failover.ps1`와 한도 2층을 참조에도 축약 | 자동 합집합하지 않고 후속 계약 보강에서 현행 로스터와 대조 |
| 외부 조사 이름 | 이름만 있고 직접 링크·검증일 없음 | 더 짧은 이름 목록 | 초기값에는 원문 보존, 후속 커밋에서 검증 가능한 근거만 남김 |

## 승인된 조정 원칙

1. 수정 시각이나 다수결만으로 정본을 선택하지 않는다.
2. 초기 이관 커밋은 공통 `SKILL.md`와 더 풍부한 긴 `reference.md`를 바이트 단위로 보존한다.
3. Cursor에만 있던 한도 우회 개념은 이 문서에서 소실 없이 보존하고, 최신 `agent-roster`·`DEV_FLOW_GLOSSARY`와 일치하는 부분만 후속 계약 보강에 반영한다.
4. `품질확인`, `adr-cycle` 악수, S/M/L별 Orca 조건, 근접 프로젝트 규칙 우선순위, 멀티호스트 경로 규칙은 원본 이관 뒤 별도 커밋에서 추가한다.
5. 기존 사용자 홈 사본은 이 감사와 정본 구현만으로 수정·이동·삭제하지 않는다.

## 초기 이관 검증값

초기 정본의 두 파일은 다음 값과 정확히 일치해야 한다.

| 상대 경로 | 바이트 | SHA-256 | 원본 |
|---|---:|---|---|
| `skills/goal-cycle/SKILL.md` | 3078 | `DD1059EB3B9D90D06C49D81C907EDA43FF0117158DB13A522EED0CEF02B4B704` | 세 벤더 공통 |
| `skills/goal-cycle/reference.md` | 1776 | `8F32C856A5B72715124883095518E41EA58B639A2A346709730F291AE99F665E` | Claude Code·Gemini 공통 |
