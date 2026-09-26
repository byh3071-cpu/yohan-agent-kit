---
name: visualize
description: Use when the user (a non-developer) wants to SEE something - generate 5~6 distinct UI design 시안 as one switchable HTML, OR turn verification results / version diffs / final reports into a browser-openable 두괄식 HTML. Triggers - "디자인 시안 N개 보여줘", "트렌디하게/감각적으로", "HTML로 시각화/결과 보고서", "비개발자용 두괄식", "버전 비교 보여줘".
---

# visualize

비전공 사용자가 **눈으로 확인**할 수 있게 만든다. 두 모드.

## 공통 원칙
- **두괄식 + 비개발자용.** 결론·핵심 먼저, 전문용어 최소(쓰면 1줄 풀이). 사용자는 디자인/개발 용어를 모른다고 명시함.
- **단일 파일 HTML.** 빌드 없이 바로 열림. 끝에 `! start <file>.html`(Windows)로 사용자가 직접 열게.
- **단일파일 아티팩트 제약 (PAT-005·006):** Tailwind 코어 유틸만(임의값 금지), import 화이트리스트, cdnjs, localStorage 금지. ★자체호스팅 Next.js/Vite 프로젝트엔 적용 금지(오적용 주의)★.

## Mode A — 디자인 시안 N개
1. 방향 먼저: `frontend-design` 스킬 필독 + `lazyweb` 레퍼런스 검색(토스·Linear·Raycast·Hermes 등 사용자가 지목한 레퍼런스 반영).
   - 랜딩·마케팅 페이지면 `hallmark`도 읽는다. 앱 화면(고정 디자인 시스템이 있는 제품)에는 `hallmark audit`만 쓰고 페이지 구조 규칙은 적용하지 않는다.
   - 모션이 들어가면 곡선·속도는 `emil-design-eng`(웹) 또는 `animate-expo`(React Native·Expo)로 정한다. 시안마다 다른 곡선을 쓰지 않는다.
   - 시안을 내놓기 전에 `web-design-guidelines`로 접근성·UX 규칙을 한 번 돌린다. 걸린 건 시안 안에서 고치고, 못 고친 건 시안 라벨 옆에 적는다.
   - 위 넷은 외부 스킬이다. 설치 좌표는 `registry/assets.yaml`의 `external://` 항목이고 `scripts/Restore-ExternalSkills.ps1`로 복원한다. 없으면 건너뛰되 건너뛰었다고 적는다.
2. **5~6개**만(10개+ 금지 — 사용자가 "품질 떨어진다"고 명시). 각 시안 `#1`~`#6` 라벨, 한 HTML 안에서 전환(탭/스크롤).
3. 사용자가 번호 킵 → 그 시안만 변주 반복.

## Mode B — 결과 HTML 보고서
검증결과·버전 diff(예: `0.2.0 vs 0.1.3`)·최종 보고서를 브라우저용 단일 HTML로.
1. 맨 위 **한 문장 결론** + 핵심 3줄.
2. 표·배지·아이콘 중심(이미지 X), 비개발자가 읽는 언어.
3. `! start docs\<name>.html`로 열기.

### 아이콘 = 요한 브랜드 이모지 세트
보고서에 아이콘을 쓸 땐 유니코드 이모지 대신 브랜드 세트를 쓴다. 채널(웹·네이버·보고서)마다 얼굴이 달라지면 브랜드가 흩어진다.

```html
<img src="https://yohanstudio.co/images/emoji/<개념>-solid.png"
     width="18" height="18" style="vertical-align:-.18em;margin-right:.3em" alt="">
```

**개념 18개** (유니코드 → 파일명 키):
📊`result` ❓`question` 💡`idea` ✅`success` 💥`fail` 🛠️`tool` 🚀`launch` 🛡️`security`
⚠️`warning` 🎓`learn` 🐛`bug` 🤖`ai` 🌱`growth` ⏱️`time` ☀️`summer` ❄️`winter` 🌸`spring` 🍂`autumn`

- **오렌지 단색**(#FF5C28) 고정 — 파일 자체가 오렌지라 색 지정 불필요.
- **크기**: 본문 16~18px / 소제목은 그 줄 글자보다 살짝 크게(굵은 제목이면 +2px). 아이콘은 글자보다 시각 무게가 커서 비례 계산만으론 커 보인다 — 실제로 놓고 눈으로 맞춰라.
- **줄 맨 앞에만.** 문장 중간에 넣으면 텍스트 흐름이 끊긴다.
- 팔레트에 없는 개념은 **아이콘 없이 텍스트로.** 한 보고서에 브랜드 아이콘과 유니코드가 섞이면 톤이 깨진다.
- SoT는 yohan-studio의 `src/data/emojiSet.json`. 세트가 바뀌면 URL만으로 자동 반영된다(여기에 SVG를 복사해두지 마라 — 드리프트 난다).
- 인터넷이 끊긴 환경이면 아이콘이 안 뜬다. 그럴 땐 아이콘을 빼고 텍스트만으로 가라(유니코드로 대체하지 말 것).

## 출력
HTML 파일 경로 + 여는 명령. 코드 설명이 아니라 "열어서 보는 것"이 산출물.
