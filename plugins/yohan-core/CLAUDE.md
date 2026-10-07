
> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.
<!-- YOHAN-VHK-AUTO-STOP:BEGIN -->
## VHK 전면 보류 (2026-10-07 사용자 결정)

- VHK는 문제가 해결되고 사용자가 명시적으로 재개를 승인할 때까지 모든 작업에서 전면 보류한다. 실행·설치·업데이트·주입·동기화·Goal 관리·verify/receipt/review·watch·autopilot을 호출하지 않는다.
- 검증 스킬(cross-check, release-gate, plan-audit, dogfood-crosscheck 등), Evaluator·평가 로그·적대적 리뷰 반복·검증용 자동 모델 호출도 기본 작업 절차로 실행하지 않는다. 추가 검토는 해당 작업에서 사용자가 명시적으로 요청한 경우에만 선택하며 VHK 재개는 별도 승인이다.
- goal-cycle·adr-cycle·오케스트레이션 등 다른 스킬로 우회해 중단한 절차를 연쇄 호출하지 않는다. 과거 문서·메모리·스킬·플러그인의 의무보다 이 결정이 우선한다. 개별 이슈 해결·새 버전 설치만으로 자동 재개하지 않는다.
- 변경 영향에 필요한 직접 확인·관련 테스트만 수행하고 관련 코드·테스트·입력·의존성·환경이 같은 통과 결과는 재사용한다. 관련 변경·실패 근거가 없는 전체 재검사와 기록 복제를 하지 않는다.
- 사용자 변경·시크릿 보호, 삭제·외부 전송·merge·배포·publish에 대한 사람 승인 경계는 유지한다.
<!-- YOHAN-VHK-AUTO-STOP:END -->

# yohan-core — 공통 운영 메모리

요한 1인 AI기업의 모든 레포에 상속되는 공통 두뇌. 이 플러그인이 켜진 모든 프로젝트에서 아래 원칙을 따른다.

## 말투·보고
- 한국어 **반말**, **두괄식**(결론 먼저), 핵심만. 과장·아부·사족 금지.
- 표는 항목이 3개 이상일 때만. 추측은 `[추론]`, 외부정보는 `[웹/외부]` 태그.
- 자세한 작성 규칙은 `yohan-writing` 스킬을 따른다.

## 보안 (절대 규칙)
- `.env`, `secrets/`, `*.pem`, `*.key`, 토큰 파일은 읽기/커밋 금지. (protect-secrets 훅이 강제)
- 커밋 전 토큰·키 유출 점검. (pre-commit-check 훅)
- 비밀은 코드가 아니라 머신 환경변수(DPAPI)로만 주입한다.

## 작업 방식
- 기본 플로우: `/yohan-core:flow` = 탐색→설계→검증→출시.
- 검증은 `cross-check`로 적대적 교차검증, 문제 0까지 반복.
- 비용은 `cost-guard` 원칙: 큰 파일 부분읽기, 표적 검색, 작업난이도에 맞는 모델.

## 환경
- OS: Windows + PowerShell. 셸 스크립트는 `.ps1`.
- 개발 루트: `C:/Users/Public/dev`. OneDrive 동기화 폴더 제외.
- 멀티 머신(데스크탑·노트북) 공통: 설정은 boot-auto-pull-setup이 부팅 시 동기화.

## 기록
- 세션 종료 시 Notion EXECUTION LOG에 자동 기록(log-session 훅, SoT Key로 멱등).
- 의사결정 근거·교훈을 남긴다.

## MCP
- `yohan` MCP(yohan-mcp, Python) 번들. Notion 등 외부 연동은 이 서버를 통한다.

## 🧠 추론(Extended Thinking) 사용 규칙
- 복잡한 설계·아키텍처·근본원인 디버깅: `think hard` 또는 `ultrathink`로 깊게 사고.
- 단순 편집·반복 작업: 일반 모드(추론 키워드 없이) — 직관적 작업엔 과한 추론이 오히려 품질을 떨어뜨리고 토큰을 낭비한다.
- 비용 의식: ultrathink는 꼭 필요할 때만. cost-guard 스킬과 함께 판단한다.

## 🤖 모델 전략 (tier 배분 — alias로 박아 세대 자동 승계)
- **지휘(메인 세션)**: 기본 `claude-opus-4-8` + effort `max`. 종합·방향·하드 판단은 지휘자가 직접.
- **서브에이전트 tier**: 탐색 `explorer=haiku` · 구현 `shipper=sonnet` · 판단·검증 `planner`/`critic=opus`. (SoT는 `agents/*.md` frontmatter)
  근거: 탐색·구현은 기계적·대량이라 품질갭 작고 절약 큼, 판단·검증은 미스가 비싸 강모델 유지.
- **위임 규칙**: 기계적·대량 탐색·반복만 서브에이전트에 위임. 판단·하드·핵심설계는 지휘자가 직접("이건 내가 나선다"). 진짜 리서치는 `deep-research`. (Opus/Fable는 기본 위임 보수적 → '언제 내려보내라'가 이 규칙)
- **순정 스위치**: "**풀파워로**" 라고 하면 위임 없이 전부 세션 모델로 직접 수행(품질 최우선). 전부 Fable로 굴리려면 `/model fable` 먼저. (흔한 말 '직접 해'는 트리거 아님 — 오발 방지)
- 고난도·장기 작업은 `/model fable` 고려(옵트인). 결정적 순간의 2차 의견은 `advisorModel: opus`가 자동 자문.
- skeptic(critical-thinking 플러그인)은 대화·추론용 적대검증으로 현재 `sonnet` — 코드용 critic과 별개 계통이라 이번 배분 밖. opus 승격은 별건 검토(사각지대 인지).

## ⌨️ 내장 명령 활용
- `/goal <완료조건>`: 조건이 충족될 때까지 턴을 넘겨가며 지속 작업.
- `/ultraplan`: 클라우드에서 깊은 계획을 세운 뒤 실행으로 넘김.
- `/code-review ultra`: 머지 전 멀티에이전트 심층 버그 리뷰(= ultrareview).
- `/advisor opus`: 어려운 결정에 더 강한 모델 자문을 켠다.

## ⚡ Effort 레벨
- `/effort`로 추론강도 조절(단순 작업은 낮춰 토큰 절감). `/model` 안에서도 가능.
- 큰 작업 자동 오케스트레이션: `/effort ultracode`(xhigh 추론 + 워크플로 자동) — 비싸니 대형 작업에만.
- Fable 5는 thinking을 끌 수 없다(항상 추론).

## ↩️ Checkpoint (자동, 인지만)
- 클로드 편집은 자동 체크포인트된다. `/rewind` 또는 빈 입력에서 `Esc` 2번 → 코드·대화 되감기.
- ⚠️ Bash로 바꾼 파일(rm/mv 등)은 추적 안 됨. git이 영구 이력, 체크포인트는 로컬 undo.

## 🌊 Workflow (대형 작업)
- `/deep-research <질문>` → 멀티소스 교차검증 리포트(근거 인용, 검증 실패 주장 자동 제거).
- 큰 감사·대량 마이그레이션: 프롬프트에 `ultracode` 키워드 → 클로드가 JS 워크플로 작성·백그라운드 실행.
- 작은 슬라이스로 비용 가늠 후 확장. `/workflows` 뷰에서 토큰 모니터.

## 📚 Claude Code 공식 문서 참고 규칙
- Claude Code 기능을 쓰거나 사용자에게 설명할 때는 항상 공식 문서를 근거로 삼는다.
- 근거 URL을 함께 남긴다: https://code.claude.com/docs/en/<slug>
- 슬러그를 모르면 인덱스부터 확인한다: https://code.claude.com/docs/llms.txt
- 자주 쓰는 슬러그는 references/claude-code-docs.md를 참고. 불확실하면 추측하지 말고 WebFetch로 원문을 확인한 뒤 인용한다.
- 버전·동작은 바뀔 수 있으니 중요한 동작은 docs 원문으로 재확인한다.

## 🔁 세션 점검 루프 (loop)
- `/loop`(주기 반복)이나 "상태 점검·이상 없나" 류 요청 시 아래 체크리스트를 따른다(이것이 SoT): ① 빌드·배포·PR 상태 ② 실패·에러 진단+수정안 ③ 새 리뷰·이슈 정리 ④ 특이없으면 "이상 없음"만 ⑤ 비밀값(.env/토큰) 출력 금지.
