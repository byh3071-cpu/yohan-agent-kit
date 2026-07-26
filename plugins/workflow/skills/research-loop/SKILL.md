---
name: research-loop
description: "Use when 요한 wants to run a research question through the full pipeline — fan-out search, adversarial verify, save a cited research-report to brain, wire it into the knowledge compound loop, and back-fill the Notion 리서치 파이프라인 DB. Triggers: '리서치 돌려', '이거 조사해줘 <질문>', '검증 리서치', '리서치 파이프라인', '<주제> 파고들어줘', 'research this'."
---

# Research Loop

## Overview
리서치 질문 1건을 **수집→적대검증→리포트 저장→지식 복리 배선→검수용 HTML→brain PR→노션 백필→계측** 한 바퀴 돌린다. 산출물은 죽은 파일이 아니라 기존 지식 루프(KNOWLEDGE-LOOP)에 합류한다 — 리서치 리포트는 새 종류의 산출물이 아니라 `source-to-summary-protocol` **입력 타입 #10**이다. 전체 규약 = **ADR-010** (`yohan-brain/docs/adr/ADR-010-research-pipeline.md`).

**되돌리기 어려운 것 금지:** brain 반영은 PR까지만(머지=사람), 노션 쓰기는 **자기 행 additive만**(스키마·옵션 변경·삭제·타 행 금지, D6). LLM은 리포트(읽기 산출물)만 생산.

이 스킬은 **A단계 수동 모드**다. B단계 무인화(`research.workflow.js` + 클라우드 cron)는 A단계 졸업(연속 2회 수정지시≤1) 후 별도 추가.

## When to Use
- 트리거 문구(위 description) 또는 노션 "리서치 파이프라인" DB 인박스 행이 있을 때.
- 검증 안 된 주장(신모델 벤치·경쟁사 클레임 등)을 사실검증+실용판정 하고 싶을 때.

**When NOT:** 단순 사실 1개 조회(그냥 검색해 답) · 코드 구현·설계(다른 스킬) · 이미 아는 것 정리(리서치 아님).

## Steps

### ① 질문 정규화
- 질문이 불충분하면 스코프 2~3개만 먼저 확인(비교 축·용도·기간). 충분하면 바로 진행.
- 확정: `topic`(model-landscape / competitor / tech-eval / idea-validation / tooling …) · `slug`(kebab) · `valid_until`(벤치·순위 등 churn 빠르면 3개월, 안정적이면 6~12개월).

### ② 노션 인박스 행 → 진행중
- 노션 "리서치 파이프라인" DB에 해당 질문 행이 있으면 상태 `진행중`으로 업데이트(자기 행만). 없으면(대화 발단) 새 행 생성(질문·주제·상태=진행중·요청일).

### ③ 소스 수집 (fetch 폴백 체인)
- 웹 검색은 `deep-research`(내장) 또는 다각도 병렬 검색 + `agent-reach`(플랫폼별 조사) 활용.
- **fetch 폴백 체인** (한 소스가 막히면 다음으로): `WebFetch` → `playwright`/`claude-in-chrome`(JS 렌더·로그인 벽 우회) → **스크린샷 → vision(Read)로 차트·다이어그램 해석**.
- **미디어 한계 돌파** — `source-to-summary-protocol` 입력 분기 재사용(신규 구현 금지):
  - 이미지(벤치 차트 등): 브라우저 스크린샷 → vision 해석 → 수치를 본문에 반영 + 원본을 `research/assets/<slug>/`에 증거로 저장.
  - 동영상(발표·데모·리뷰): `yohan-core:youtube-summary`의 yt-dlp 자막 확보 절차 그대로 → 타임스탬프 인용. 필요 시 키프레임 추출 → vision.
- 원문 확보 실패 = 해당 주장 `[미검증]` 표기(추측 요약 금지).

### ④ 적대검증
- 핵심 주장(특히 수치·순위·우열 클레임)만 골라 적대검증 — `yohan-core:critic` 또는 `cross-check` 스킬. 신모델 자체벤치·체리픽 여부를 명시적으로 의심.
- 판정: 통과/조건부/기각 + 확신도(상~하). 근거엔 `[웹]`(출처 URL) / `[추론]` 태그.

### ⑤ 리포트 작성 + assets 커밋
- 저장: `yohan-brain/docs/yohanthinking/research/YYYY-MM-DD--<slug>.md`.
- frontmatter: `research/INDEX.md` 규약(id·date·type=research-report·method·topic·status·confidence·valid_until·tags).
- 본문: `## 0. 결론부터 (두괄식)` + 비교 축·가설별 판정표로 시작. 두괄식·표·[추론]/[웹] 태그(soul report 모드 — 핵심만, 검수 부담 낮게).
- 이미지 증거: `research/assets/<slug>/`에 커밋. **상한 ≤10장·장당 ≤500KB** — 초과 시 PowerShell 리사이즈, 그래도 초과면 장수 축소(가장 중요한 것만). git에 커밋되는지 확인(HTML은 gitignore, png는 추적).

### ⑥ INDEX 이중 갱신
- `docs/yohanthinking/research/INDEX.md` 표에 1행 추가 **그리고** `docs/yohanthinking/INDEX.md` research 섹션 미러도 갱신. **둘 다** — 한쪽만 하면 반드시 drift(ADR-010).

### ⑦ HTML 시각 요약 (검수용, 커밋 안 함)
- **표준 템플릿 사용**: `report-template.html`(이 스킬 폴더)을 `docs/yohanthinking/research/<slug>.html`로 복사 → `<!-- SLOT -->`만 실제 내용으로 교체. **CSS·구조는 건드리지 말 것**(검증된 디자인 유지). 매번 새로 뽑지 않는다.
- **전달감 규칙 (요한 회차① 핵심 교훈)**: 눈이 멈출 "큰 것"을 만들 것 — 가장 중요한 수치 대비를 `.score` 스코어라인으로 대형화(승패 즉각), 핵심 팩트 3개는 `.facts`로 크게. **핵심만 크고 진하게, 나머지는 조용히**(색은 핵심에만). 비교는 막대(`.bar`·`.mini`)로 시각화 — 눈으로 훑어 읽게 하지 말 것. 위계 폭 넓게(3.4rem~0.76rem). 폭 `max-width:840`(양옆 여백 최소).
- **레이아웃 규칙 (회차① 확정 — 어기면 되돌리기 왕복)**: **1컬럼 세로 한 줄기**로 쭉. 2컬럼·대시보드형 분할 금지, "한 화면 압축"(100vh 맞춤) 금지. 글은 **좌측 정렬**(보고서) — 제목·요약을 `text-align:center`로 만들지 말 것. 요한이 말하는 "가운데"는 **글자 정렬이 아니라 콘텐츠 블록이 화면 정중앙**이라는 뜻. 폰트는 **Pretendard 1종 통일**(숫자·코드까지 — 폰트 섞이면 완성도 깎임). 스크롤바가 오른쪽 여백을 먹어 본문이 밀려 보이므로 `html{scrollbar-gutter:stable both-edges}` 유지.
- **디자인 규칙 (AI스러움 금지)**: 그라디언트·이모지 헤더·장식용 stat 카드 grid 금지. 노션 문서 톤 + 편집디자인 완성도. 색은 신호등 red/green 말고 win=진초록·warn=러스트. 다크 우선+라이트+reduced-motion+모바일. **레퍼런스·안티패턴은 `references/design-references.md`**(Anthropic·Linear·AA·Stripe Press + 웜크림+serif=AI디폴트 함정).
- **카피 규칙 (이해 쉽게 + 정보전달 기법)**: 벤치·기술 용어 풀어쓰기(예: "AA Intelligence Index"→"여러 AI를 같은 잣대로 채점하는 독립 기관 점수"). 비유 금지. 두괄식(BLUF)+파인만(쉽게). **피라미드**: 근거를 유형별로 그룹. **토픽센텐스**: 각 덩어리·불릿 첫머리에 요지(`.lead`/li 첫 `<b>`) — 볼드만 훑어도 논리가 잡히게.
- (있으면) 로컬 assets 이미지 상대경로 임베드. 브라우저로 열어 검수.
- **렌더 검증**: 로컬 HTTP 서버 + playwright로 스크린샷 확인(file:// 직접 열기는 playwright 차단). ⚠️ **백그라운드 셸은 PATH에 python이 없어 `python -m http.server`가 exit 127로 죽는다** → `where python`으로 절대경로 확인 후 `"/c/Program Files/Python311/python.exe" -m http.server <포트>`로 기동. 확인 후 서버 kill(포트 기준). 임시 스크린샷 정리(삭제 정책에 막히면 사람에게 정리 요청).
- ⚠️ **뷰포트를 사람이 보는 창 크기에 맞출 것 (회차① 최대 시간 낭비 — 정렬 오판의 실제 원인)**: playwright 뷰포트 ≠ 창 크기면 정렬이 틀린 것처럼 보인다. 뷰포트가 창보다 **작으면** 오른쪽에 빈 띠가 남고 스크롤바가 화면 한가운데 뜬다. 뷰포트가 창보다 **크면** 오른쪽이 화면 밖으로 잘려 본문이 오른쪽으로 밀려 보인다. 사람이 스크린샷으로 "가운데 아닌 것 같다"고 하면 **CSS부터 고치지 말고 뷰포트를 먼저 의심**한다.
  - 배율 판별: 840px여야 할 요소가 스크린샷에 923px로 찍히면 줌·DPI 1.1 → 실제 CSS 창폭 = 물리폭 ÷ 배율. `window.outerWidth`가 힌트.
  - 정렬 판정은 눈이 아니라 **계측**으로: `docCenter - innerWidth/2 == 0`이면 정중앙(스크롤바 gutter 포함).
- `.gitignore`가 `research/*.html`을 잡으므로 `git status`에 안 떠야 정상.

### ⑧ 복리 배선 (추출 — 후보까지만)
- `source-to-summary-protocol` **Step 4.5→4.6→4.7 직행**(입력 #10 특칙 — Step 1·2 건너뜀). haiku 서브에이전트 위임 가능.
- 4.5 교차검증(기존 insights·triple-map 대조) → 4.6 역전파(기존 rules·docs 충돌·갱신 대조, 체크포인트1) → 4.7 온톨로지 추출(개체·트리플, 체크포인트2).
- 추출물: 키워드→`knowledge-hub/keywords.md` 후보 · 인물/스택→`wiki/entities/` 후보 · 개념→`concepts`/AI사전 후보 · 트리플→`triple-map.md` · 종합→`knowledge-hub/`.
- **승격은 후보 리스트업까지만.** 확정은 `wiki-ops` 사람 게이트. **결과 한 줄 보고 필수**("키워드 N·트리플 N·승격후보 N" 또는 "스킵: 이유") — 침묵 금지.

### ⑨ brain PR (머지 X)
- `docs/research-pipeline` 계열 브랜치에 커밋 → PR 생성. **머지 안 함**(사람 게이트). PR 본문에 두괄식 판정 + 승격 후보 목록.

### ⑩ 노션 행 백필 (additive)
- 자기 행만 업데이트: 상태 `완료(검수대기)` · 요약 3줄 · brain 경로(+GitHub 링크) · 확신도 · 완료일.
- **금지:** 스키마 변경·select 옵션 추가·삭제·타 행 수정(D6). 머지 후 사람이 `완료` 확정.

### ⑪ 계측 1행 (사람 검수 후)
- **타이밍**: 파이프라인 실행 직후가 아니라 **사용자 검수 피드백 후** 기록한다 — 핵심 지표인 "수정지시 수"가 검수 전엔 미확정(회차① 교훈).
- 노션 "바이브코딩 워크플로 계측" DB(`03a2cd6a`)에 1행: 수정지시 수 · 검수 소요분 · 승격 후보 수 · 결과(성공/부분성공/실패). A단계 졸업 판정(연속 2회 수정지시≤1) 근거.
- **주의**: 이 DB "프로젝트" select에 리서치용 옵션이 없다 → 옵션 추가는 파괴적(전역 규칙)이라 **사람 승인 필요**. 승인 전엔 세션/하네스 text 필드로 우회 기록.

#### 카운터 정의 (2026-07-21 확정 — 회차①에서 정의 부재로 값이 자의적이 된 뒤 고정)

| 카운터 | 정의 | 포함 | 제외 |
|---|---|---|---|
| `수정지시` | 산출물이 요구·의도와 **어긋나서** 되돌리거나 다시 만들게 한 **요구의 개수** | 오해·오작동·범위이탈 교정 | 새 정보로 요구가 구체화되는 정상 수렴(취향 수렴) |
| `에러` | 산출물·도구가 실제로 **실패**한 기술 사건 | 버그·렌더 실패·검증 방법 결함 | 취향 불일치 |
| `드리프트` | 요구 범위를 **넘어선** 산출 | 시키지 않은 구조 개편 | 요구 내 시행착오 |
| `승격후보` | **wiki·knowledge-hub로 올린(또는 올릴) 카드 수** | 개념·도구·조직 카드 | triple-map 등록 행 수(등록 ≠ 승격) |

**집계 규칙 2개** — 이게 없으면 같은 회차가 2로도 9로도 세어진다.
1. **요구 1개 = 1건.** 하나의 요구가 관철될 때까지의 왕복은 몇 번이든 1건으로 센다. 왕복 횟수로 세면 회차마다 값이 요동쳐 추세 비교가 불가능해진다.
2. **축 간 중복은 허용, 축 내 중복은 금지.** 한 사건이 수정지시·에러·드리프트 중 여럿에 해당하면 각 축에 1회씩 계상한다(축이 서로 다른 것을 측정하므로). 같은 축에 두 번 세지 않는다.

**미측정은 0이 아니라 빈칸**으로 두고 `세션` 텍스트에 사유를 적는다(기존 행 관행). 제외한 항목도 은폐하지 말고 텍스트에 병기한다(예: "취향 수렴 5회 별도").

## Quick Reference
| 항목 | 값 |
|---|---|
| 리포트 정본 | `yohan-brain/docs/yohanthinking/research/YYYY-MM-DD--slug.md` |
| 이미지 증거 | `research/assets/<slug>/` 커밋 (≤10장·장당≤500KB) |
| HTML | `research/<slug>.html` — 파생물, 커밋 안 함 |
| 복리 배선 | source-to-summary 입력 #10 → Step 4.5~4.7 |
| 게이트 | brain=PR+사람 머지 / 노션=자기 행 additive만 |
| INDEX | research/INDEX.md + yohanthinking/INDEX.md **둘 다** |
| 계측 | 바이브코딩 워크플로 계측 DB (졸업: 연속 2회 수정지시≤1) |

## Common Mistakes
- 신규 `docs/research/` 만들기 → 기존 `yohanthinking/research/` 관례 이중화. 반드시 기존 경로.
- 리서치를 별도 프로토콜로 취급 → source-to-summary 입력 #10로 태워 복리 배선 유지(신규 프로토콜 발명 금지).
- INDEX 한쪽만 갱신 → drift. research/INDEX.md + yohanthinking/INDEX.md 둘 다.
- HTML 커밋 → 파생물, gitignore로 제외. `git status`에 뜨면 잘못된 것.
- assets 500KB 초과 방치 → 리사이즈→장수 축소 폴백.
- 노션에서 옵션 추가·스키마 변경 → 파괴적, additive만(D6). 옵션 부족하면 대화형에서 사람 승인 후 기존 옵션 전부 포함해 추가+재fetch 검증.
- 승격을 AI가 확정 → 후보까지만, 확정은 wiki-ops 사람.
- 추출 결과 침묵 → "키워드 N·트리플 N·승격후보 N" 한 줄 보고 필수.
- PR 머지까지 자동 → 금지. PR까지만, 머지는 사람.
- "가운데 아닌 것 같다" → CSS 정렬부터 손대기 금지. **playwright 뷰포트 = 창 크기**인지 먼저 확인(회차① 왕복 5회의 실제 원인). 정렬은 계측으로 판정.
- 피드백 한 마디에 레이아웃 전면 개편(2컬럼·한화면 압축) → 금지. 요구 범위만 최소 수정, 구조 변경은 사람 확인 후.
- HTML 매번 새로 디자인 → 금지. `report-template.html` 복사·SLOT 교체만(회차① 교훈: AI 디폴트 디자인·어려운 벤치용어 카피 방지).
- 계측을 파이프라인 끝에 즉시 기록 → 수정지시 미확정 상태. 검수 후 기록(⑪).

## 관련
- 규약 SoT: `yohan-brain/docs/adr/ADR-010-research-pipeline.md`
- 복리 배선: `yohan-brain/memory/rules/source-to-summary-protocol.md` (#10) · `docs/KNOWLEDGE-LOOP.md` · `memory/rules/wiki-ops.md`
- 무인 루프 레퍼런스(B단계 이식 원형): `../overnight-autoloop/` (얇은 스킬 + workflow.js 엔진 + LF 사본 실행 + 되돌릴 수 없는 작업 차단)
- 범용 코어 독트린(되돌릴 수 없는 작업 4중 안전장치) = 글로벌 PAT-003.

## 파이프라인 계약
계약 SoT: `C:\Users\Public\dev\.agents\SKILL_PIPELINE.md` (골 사이클 ①조사)
- **받는 것:** 바통 `goal` · `open`(미결정). **`open`이 비면 실행하지 않는다** — 결정할 게 없는 조사는 연극.
- **남기는 것:** `open` 축소(답이 나온 항목 삭제) · `artifacts`(리포트·assets 경로) · `cost`(⑪ 계측 후 — 카운터 정의는 위 표가 정본)
- **다음:** 스펙 · `thought-to-prompt` 또는 `prd-generator` (gate: human)
