---
name: studio-post
description: yohan.studio 블로그 글을 저작·검증·발행할 때. MDX 템플릿, 저작 규율(용어 정의·표 금지), BOM·이미지 함정 회피, 발행 절차(published 게이트→라이브 검증→멀티채널 변환)까지 전 과정. vhk 등 외부 레포 릴리즈 홍보물의 멀티채널 변환 통로이기도 함. "블로그 글 써줘", "studio에 발행", "글 초안" 트리거.
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# studio-post — yohan.studio 글 저작·발행

## 정본 참조 (이 스킬은 얇은 진입점 — 상세는 brain이 SoT)

| 무엇 | 어디 (yohan-brain) |
|---|---|
| 발행 전·중·후 체크리스트 | `memory/rules/publish-checklist.md` (사고 이력 포함 — 반드시 대조) |
| 멀티채널 변환 스펙 (10채널: 소셜 8 + 개발자 커뮤니티 2 = GeekNews·Show HN) | `memory/rules/content-platform-specs/*.md` |
| 환경 함정 (BOM·vitest·MDX) | `memory/wiki/concepts/windows-agent-pitfalls.md` |
| 스타일 | yohan-writing 스킬 + 기존 발행 글 (studio `src/content/blog/`) |

## MDX 템플릿

```mdx
---
title: "구체 결과가 들어간 제목: 부제"
description: "검색 스니펫용 1~2문장 — 훅과 실측 수치 포함."
date: "YYYY-MM-DD"
tags:
  - 태그3~5개
category: "AI/바이브코딩"
published: false        # 초안은 반드시 false — 발행은 사람 게이트
---

> **한눈에 요약**
> 3문장 이내 — 결론·수치·핵심 규칙.

(도입 1~2문단: 1인칭 일기체 훅 — "나는 바리스타 출신 비전공자다" 계열의 구체 상황)

(전문용어 첫 등장 시 한 줄 정의 — PR·머지 등)

{/* [이미지 1: 설명] */}   ← 이미지 자리 주석 마커

## 섹션 제목 (질문형 or 행동형)
...
```

## 저작 규율 (2026-07 두 편 검토 + 벤치마킹 1회전 반영 — 위반 시 반려됨)

1. **수치는 실측만** — 원장(audits·git·gh) 대조 가능한 숫자만. 추정치 금지.
2. **실패 포함 + 도입부 예고** — 성공담 금지. 실패·헛돈은 **도입부에서 예고**하고 결말에서 교훈으로 재포장 (벤치 실측 최대 호응 구조 — 브런치 라이킷 1,151 사례). 중반에 숨기지 않는다.
3. **마크다운 표 금지** — MDX 렌더 미지원. 목록으로.
4. **3-3-3 대칭 리스트 남발 금지** — AI 티의 최대 마커. 문단 흐름 위주.
5. 메타 발화 금지("과장 없이 쓰면") · "실측" 같은 엔지니어 용어 지양.
6. 용어 첫 등장 정의 — 비개발자 독자 기준.
7. **분량 — 마스터는 상한 없음.** studio 원본(MDX)은 소재 깊이만큼 길게 쓴다(실측: 발행글 다수 3,000자+). `1,500~2,000자`는 **파생 채널**(티스토리 등) 목표치이지 마스터 목표가 아니다 — 상한으로 읽으면 초안이 실제 발행글보다 짧게 나온다. 직전 글 내부링크로 마무리.
8. thumbnail은 실파일 있을 때만 frontmatter에 (없는 경로 = 깨진 히어로 / 생략 시 OG 텍스트 카드 자동 폴백 — studio #35).
9. **제목 = 결과 숫자 선행** — 궁금증 유발형보다 결과 스포일러형이 한·해외 공통 우세 [가설, 벤치 B2×B3]. 이모지·리스티클("~5가지") 금지 (한국 상위 10/10 이모지 0).
10. **실물 스크린샷/재현 출력 ≥ 1장** — 다이어그램만으로 채우지 않기 ("진짜 돌아간 증거"가 신뢰 장치, 해외 6:1 우세).
11. **정보 구간에도 자기 서사 껍질** — 도입·결말의 개인 서사가 AI 정보글과의 구분 기제 (벤치 B2). 멀티채널 변환물에도 유지.

## 커버·배포 규약 (벤치 1회전)

- **커버 시리즈 톤 고정**: 다크+오렌지 소프트 브루탈리즘 일러스트(텍스트 없음), gpt-image 생성. 프롬프트 베이스: "Editorial illustration, soft brutalism, deep charcoal + vivid orange accent, flat vector shapes, grainy texture, no text anywhere." — 발행 6편이 4가지 톤으로 흩어졌던 갭 해소(B4). 과거 커버 소급은 유저 승인 후.
- **배포 우선순위**: 블로그=아카이브, **트래픽 엔진=커뮤니티**(Reddit·디스콰이엇) — 동일 소재 Medium 클랩 2 vs IH 138업보트 실측(B3). 커뮤니티용 제목은 결과선행형으로 변환.
- 벤치 원장·재판정 조건: brain `docs/audits/content-benchmark-2026-07-05.md` (계측 4주 후 재판정).

## 파일 함정 (전부 실사고 이력)

- **BOM 금지**: PowerShell `Set-Content -Encoding UTF8` 절대 금지 — BOM이 frontmatter 파싱을 깨서 라이브 404 (studio #30 사고). Write 도구 또는 `UTF8Encoding($false)`.
- **BlogImage는 문자열 attr**: `width="1280"` (JSX 표현식 `{1280}`은 next-mdx-remote가 드롭 → 크롭 사고).
- **다이어그램 = SVG 파일** (`public/images/blog/<slug>/*.svg` + BlogImage) — 텍스트 선명·수정 1줄·비용 0. 사진풍·커버는 GPT 이미지(OPENAI_API_KEY 필요).
- 검증은 로컬 dev가 아니라 **프로덕션 빌드**: published:true 임시 토글 → `npm run build` + `npx next start` → 대조군(기존 글) 포함 확인 → false 원복.

## 발행 절차 (요약 — 상세는 publish-checklist)

1. 초안 PR (published:false) → 사람 검토 (아티팩트 렌더 제공).
2. 승인 시: published:true + 발행일 갱신 → 머지 → Vercel 배포 대기.
3. 라이브 검증: `yohanstudio.co`(도메인 정본 = `src/lib/siteUrl.ts`)에서 200 + 내용. sitemap·신규 자산 삼각측량.
   → **라이브 검증 통과 = naver-convert 자동 선제 시작 트리거** (요한 확정 2026-07-20, **네이버만** — 나머지 채널은 4단계 수동 절차 그대로). 묻지 말고 허브 중복 조회 → 원고 준비 → 진솔 슬롯 채팅 질문까지 진행.
4. **멀티채널 변환**(10채널 스펙 = brain `content-platform-specs/`): **에이전트가 스펙을 읽고 손으로 재편집**해 `docs/content/exports/<slug>/<platform>.md` 산출 → 사람 검수 → PR. 각 채널 실발행은 사람.
   - ⚠️ **자동 변환 도구 미구현**: `yohan-voice`(변환 엔진)는 `content-platform-specs/_common.md`상 v0.1 **스펙 단계(코드 없음)**. "voice CLI / voice check" 자동 도구는 아직 없다 — 그때까진 **스펙 기반 수작업이 정본**(기계 검증 없음, 사람 검수로 대체).
   - 네이버·웹 MDX는 dual-blog(`pnpm blog:naver`)가 실재 스크립트 정본.

## vhk(외부 레포) 릴리즈 홍보 → 멀티채널 (2026-07-14 배선)

vhk 등 다른 레포의 릴리즈 홍보물도 이 스튜디오 파이프라인을 **통로**로 쓴다(중복 배선 대신 SoT 재사용 — 선례: `studio/docs/content/exports/vhk-npm-cli-launch/`).

1. **마스터 승격**: vhk `docs/blog/<slug>.md` 초안 → studio `src/content/blog/<slug>.mdx`로 마스터화(사실·수치·링크·이미지 기준 원본). 평문 .md는 파이프라인 마스터로 직접 못 먹는다(네이버 `mdx-to-naver.mjs`도 studio MDX 구조 가정).
2. **채널 선택**(개발자 커뮤니티 릴리즈): 1차 = **GeekNews(Show GN) + Show HN + 네이버**. 스펙: `geeknews.md`·`showhn.md`·dual-blog.
3. 변환 → `studio/docs/content/exports/<slug>/{geeknews,showhn,naver}.md` → 사람 검수 → 실발행은 사람.
4. ⚠️ **Show HN 프레이밍 지뢰**: "vX.Y.Z 릴리즈"로 올리면 자격 미달(showhn.html — "신규기능/업그레이드는 부족"). → **"도구를 만들었다(첫 Show HN)"** 프레임 필수.
5. ⚠️ **upvote 동원 금지**(양 플랫폼 밴/karma 리스크). GeekNews는 자기출처 반복 등록 = 배포채널 간주 등록 제한.

## 금지

- 밤·무인 세션에서 published:true 전환 금지 (라이브 발행 = 사람 게이트).
- 같은 글의 캐러셀·카드뉴스 동시 발행 금지 (스펙 참조).
- **upvote·추천 동원 금지** (GeekNews·Show HN·Reddit 공통 — voting ring = 도메인 영구밴/등록 제한).
