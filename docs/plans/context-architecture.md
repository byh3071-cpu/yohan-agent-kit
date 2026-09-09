# Context Architecture 실행 계획 — #112

## 이번 구현과 경계

#108만 구현한다. 기준 main은 eed334d48606ba2c66a2fd66b98d890e9ff25784다. Phase 1 브랜치는 feat/context-core-phase1-108이며 파일 정본·스키마·검증·RULES 포인터·기존 CI 연결을 포함한다. 새 DB, MCP 서버, Router, Graphify 설치, Qdrant 재색인, 사용자 홈 설치는 포함하지 않는다.

## 보드 정리 — 2026-09-09

[요한 생태계 개발 Project #3](https://github.com/users/byh3071-cpu/projects/3)은 비공개 개발 포트폴리오다. 실제 옵션과 설명은 아이디어(미약속 생각), 백로그(작업 계약이 있는 실행 후보), 다음(다음 착수 후보), 진행 중(실제 작업·검증), 검토(PR·독립 검수·사람 판정 대기), 완료(검증·전달 완료)다.

기존 Agent Kit 이슈 카드는 #1 하나였다. 대상 5개는 없음을 확인한 뒤 URL로 연결했다. #108=진행 중, #109/#110/#111=백로그, #112=백로그다. Epic은 단계 추적용 컨테이너로 두고 실제 착수는 #108만 표시한다. 다른 카드와 저장된 뷰는 바꾸지 않았다. 기존 7일 수동 파일럿 표본은 추가 카드와 별개다. PR 생성만으로 이슈를 완료로 바꾸지 않는다.

## 중복 구현 방지 조사

| 확인한 자산 | 이번 결정 / 후속 재사용 |
|---|---|
| Agent Kit scripts/check-context-contract.mjs, .github/workflows/context-contract.yml | marketplace·plugin 버전·Qdrant 환경 충돌 검사 유지, Phase 1 정적 검사만 추가 |
| RULES.md → VHK sync → AGENTS/CLAUDE/.cursorrules 등 8개, .cursor/rules/ecosystem.mdc | 생성 규칙 원본에 포인터 추가; VHK sync --check와 context 포인터 검사 병행 |
| yohan-mcp core/router.py SmartRouter | notion·memory·qdrant 검색, RRF, per-page cap, 부분 장애 처리 존재. 새 Router 복제 대신 Phase 2에서 확장 지점 결정 |
| yohan-mcp core/tools.py, adapters/qdrant_adapter.py, tests/test_get_context_vector.py | get_context 진입점·data/verification/provenance 봉투·벡터 회수 검사 재사용. QDRANT_URL/PATH 선택은 기존 서버 소유 |
| yohan-brain docs/CONTEXT-AND-HARNESS-SYSTEM.md | memory는 축적 지식·결정 정본 유지. Context Core의 현재 사용자 상태와 소유 범위를 Phase 2 응답에서 분리 |
| VHK src/commands/sync.ts, src/lib/drift.ts | 세션 시작 필독 섹션의 모든 규칙 전파와 생성물 drift 검사 재사용 |
| Project #3의 Graphify VHK 읽기 전용 파일럿 / yohan-mcp adapter 아이디어 | 기존 후보와 #110 중복 착수 금지. 현재 로컬 조사 범위에서는 설치된 Graphify 구현/API를 확인하지 못함. 부재로 단정하지 않음 |

로컬 repos.json에서 GitHub yohan-agent-kit의 물리 정본은 automation/yohan-cc-skills임을 확인했다. 구현은 현재 승인된 작업공간의 격리 사본에서 수행한다. 로컬 MCP/Brain/VHK 자산은 읽기 조사 자료이며 후속 구현 직전에 원격 main과 다시 대조한다.

## 단계별 별도 브랜치·PR

| 단계 | 착수 조건 | 별도 브랜치 / acceptance |
|---|---|---|
| #108 Phase 1 | 이번 사용자 승인 | feat/context-core-phase1-108. 정본·시간·출처·stale 회귀, 기존 context contract, 규칙 drift, 새 클라이언트 세션 3질문 |
| #109 Phase 2 | #108 자동 검증과 실제 새 세션 검증 완료, 사람 검토·merge 후 최신 main에서 시작 | feat/context-mcp-phase2-109. 기존 yohan-mcp 확장 판단 기록. current/profile/project/timeline/memory/status 최소 계약, 요청별 최소 Pack, 출처/유효시간 보존, 검색 점수보다 current 우선, 한 실제 MCP 클라이언트 왕복, 장애·미권한·누락 시 명시적 실패. Agent Kit 계약 PR과 MCP 구현 PR은 교차 연결 |
| #110 Phase 2.5 | #109 acceptance와 merge, Graphify 자산·설치·API 및 파일럿 소유 위치 확인 | feat/context-graphify-phase25-110. 기존 VHK 파일럿 아이디어와 MOVA 추천의 선택을 기록. MOVA 한 repo에서 related/impact와 실제 import/reference 비교, commit/ref·generated_at·provider/version, stale graph 표기·GitHub 정본 우선, provider 장애 시 축소 응답, 모든 쓰기 0 |
| #111 Phase 3 | #110 acceptance와 merge | feat/context-memory-phase3-111. Temporal 경계·최소 관계 질의·기존 Qdrant 후보 검색 재사용. 벡터 1위가 과거라도 current 우선, inferred candidate 자동 승격 금지, 사용자 수정 시 기존 current의 historical 전환, 출처·유효시간·충돌·승인 실패 테스트 |

각 PR은 구현 → 자동 검증 → 실제 acceptance 증거 → Draft PR → 사람 검토 순서다. Ready·merge·운영 배포·유료 호출 확대는 사람 게이트다. 선행 단계가 실패하거나 미검증이면 다음 구현을 시작하지 않는다. 이번 전달은 Phase 1 Draft와 나머지 단계의 실행 계획까지다.

## Phase 1 검증 기록

- Node 자동 테스트: 22개 통과(현재/과거/stale, 날짜 경계, 잘못된 출처·스키마, 새 프로세스, 세 에이전트 규칙 포인터 drift).
- 기존 context contract와 신규 정본 검증: 통과.
- VHK sync --check: 생성 규칙 drift 0, 필수 섹션 누락 0.
- 실제 Codex 0.153.2 새 세션(2026-09-09): CURRENT/TIMELINE/README/AGENTS를 읽고 세 질문에 카페레이브 / 카페사이 historical·날짜 미상 / stale보다 카페레이브 우선으로 응답했다. 해당 읽기 전용 세션의 검증 명령은 실행 정책에 차단되어, 검증 명령은 부모 작업 세션에서 별도로 통과했다. 답변 회수는 통과, 클라이언트 내부 검사 실행은 제한됨.
- Claude Code: 설치된 shim이 가리키는 실행 파일이 없어 새 세션 실행 불가. 설치·사용자 홈 변경은 수행하지 않았다.
- Cursor: 로그인 상태를 확인했지만 읽기 전용 샌드박스 실행은 Windows 미지원으로 종료됐다. 샌드박스를 해제하지 않았다.
- Claude/Cursor의 실제 세 질문 acceptance가 남기 전 #108 전체 완료·#109 착수 금지. 실제 클라이언트 환경 복구 후 같은 PR 브랜치에서 재검증한다.
