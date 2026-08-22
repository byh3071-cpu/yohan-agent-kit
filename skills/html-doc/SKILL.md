---
name: html-doc
description: 설명용 HTML 문서 6종(개념·코드·리서치·점검·결정·현황)을 만들고 계측까지 끝낸다. 요한이 "HTML로 보여줘"·"시각화해줘"·"보고서로 뽑아줘"라고 하거나, 검증·조사·판정 결과를 브라우저에서 볼 형태로 낼 때. 앱 UI·제품 화면에는 쓰지 않는다(그건 frontend-design).
---

# 설명용 HTML 문서 (html-doc)

요한은 시각 학습자다. 표·도식으로 사고하고 기억한다. 이 스킬은 **읽는 문서가 아니라 보는 문서**를 만든다.

## ⚠️ 이 스킬이 존재하는 이유 — 규칙만 지키면 실패한다

글로벌 `CLAUDE.md`의 HTML 규칙은 **가독성 하한선**이다(한국어 안 깨짐·대비 확보·토큰 사다리). 하한선을 통과해도 좋은 문서가 되지 않는다.

2026-08-02 실측 — 하한선을 전부 통과한 문서를 요한이 이렇게 평했다:

> "너무 HTML 디자인이나 가독성이나 여러가지로 전부다 별로임 최악임"

그때 만든 것: 회색 상자 + 같은 무게의 표 5개 + 작은 카드 4개 + 위계 없음.
고쳐서 통과한 것: 반전 히어로에 결론 한 문장 + 데이터를 그래픽으로 바꾼 막대 하나 + 표 1개 + 분량 30% 감축.

**규칙은 통과 조건이고, 아래 §3이 합격 조건이다.**

---

## 1단계 — 6종 중 무엇인지 먼저 정한다

| 종 | 언제 | 히어로에 올 것 |
|---|---|---|
| **개념** | 원리·구조를 이해시킨다 | 이 구조를 한 문장으로 |
| **코드** | 명령·로그를 비개발자에게 설명한다 | 이 명령이 하는 일 |
| **리서치** | 조사·트렌드를 근거와 함께 전한다 | 조사가 뒤집은 것 |
| **점검** | 검사 결과를 보고한다 | 판정 (통과/실패/조건부) |
| **결정** | 선택지를 비교해 고르게 한다 | 추천안과 이유 |
| **현황** | 진행 상황과 다음 할 일 | 지금 상태 한 문장 |

정하지 않고 쓰기 시작하면 여섯 개가 섞인 잡탕이 된다. 섞였다는 신호 = 표가 3개 넘게 연속으로 나온다.

각 종의 섹션 순서·컴포넌트 배정은 **`assets/skeletons.md`** 참조.

## 2단계 — 뼈대와 CSS를 가져온다

`assets/base.css`를 `<style>` 안에 통째로 붙이고 **안 쓰는 컴포넌트 블록은 지운다.**

파일은 **조각 HTML**로 쓴다 — `<!doctype>`·`<html>`·`<head>`·`<body>` 없이 `<style>` + `<main>`. 미리보기 서버가 감싼다.

## 3단계 — 합격 조건 (여기가 진짜다)

| # | 조건 | 실패 신호 |
|---|---|---|
| 1 | **히어로에 결론 한 문장.** 반전 배경(먹 위 흰 글씨)으로 본문과 분리한다 | 제목이 "○○ 보고서"이고 결론은 스크롤해야 나온다 |
| 2 | **시그니처 하나.** 이 문서에서 가장 중요한 데이터 하나를 그래픽으로 바꾼다 | 전부 표다 |
| 3 | **표는 2개 이하** | 표 3개 이상 연속 |
| 4 | **타입 스케일을 벌린다.** 히어로 3rem대 ↔ 본문 1.08rem | 제목과 본문 크기가 비슷하다 |
| 5 | **덜어낸다.** 초안에서 20~30% 잘라낸다 | 스크롤이 화면 5개를 넘는다 |
| 6 | **위험은 한 곳에만.** 나머지는 조용하게 | 색 배지가 화면마다 있다 |

시그니처 고르는 법은 `skeletons.md` 말미의 대응표.

## 4단계 — 저작 규율 (불변)

- `word-break:keep-all` 필수. 없으면 한국어가 세로로 깨진다
- 좁은 고정 폭 칼럼 금지 → `minmax()`·`auto-fit`
- 본문 ≥1.05rem, 캡션 ≥1rem. 작은 글씨로 밀도를 올리지 않는다
- **색은 배경·테두리·막대·배지에만. 글씨는 잉크 하나**
- 간격·모서리는 토큰 사다리에서만 (`--g1~7` · `--r1~3`)
- 한 문서 = 한 어휘. 같은 뜻 두 낱말(검사/점검/검증) 섞지 않는다
- 긴 문장은 논리 단위로 자르고, 귀결 줄은 `→`로 시작
- 비유는 첫 등장 때 대응표로 정의한다. 정의 안 한 비유는 안 쓴다
- 접근성: `<main>` · 탭은 `role="tablist"/"tab"/"tabpanel"` + 화살표 이동 + 숨긴 패널에 `hidden`

### 쓰기

숫자는 **비교 대상과 함께** 적는다. "16일"이 아니라 "판정 예정일에서 16일". 라벨은 사람이 아는 말로 — "웹훅 설정"이 아니라 "알림 보내는 곳". 빈 상태·실패는 무엇을 하라는 안내로 쓴다.

## 5단계 — 계측 (눈대중 금지)

```
node ~/.claude/scripts/preview-server.mjs <파일> 8899
```

브라우저(또는 playwright MCP `browser_evaluate`)에서 아래를 돌린다. **1100px·380px 두 폭에서 각각.**

```js
(() => {
  const L=c=>{const [r,g,b]=c.match(/\d+/g).map(Number).map(v=>{v/=255;return v<=0.03928?v/12.92:Math.pow((v+0.055)/1.055,2.4)});return 0.2126*r+0.7152*g+0.0722*b};
  const bg=el=>{let n=el;while(n){const c=getComputedStyle(n).backgroundColor;if(c&&!/rgba\(0, 0, 0, 0\)|transparent/.test(c))return c;n=n.parentElement}return 'rgb(255,255,255)'};
  const R=(f,b)=>{const a=L(f),c=L(b);return (Math.max(a,c)+0.05)/(Math.min(a,c)+0.05)};
  const fails=[];
  document.querySelectorAll('main *').forEach(el=>{
    const t=[...el.childNodes].filter(n=>n.nodeType===3&&n.textContent.trim()).length;
    if(!t)return;
    const s=getComputedStyle(el),fs=parseFloat(s.fontSize);
    const need=(fs>=24||(fs>=18.66&&parseInt(s.fontWeight)>=700))?3:4.5;
    const r=R(s.color,bg(el)); if(r<need)fails.push({c:el.className||el.tagName,fs,r:+r.toFixed(2)});
  });
  const de=document.documentElement, gaps=new Set();
  document.querySelectorAll('main *').forEach(el=>{const s=getComputedStyle(el);['gap','rowGap','columnGap'].forEach(p=>{const v=s[p];if(v&&v!=='normal'&&v!=='0px')gaps.add(v)})});
  const over=[...document.querySelectorAll('main *')].filter(e=>e.getBoundingClientRect().right>de.clientWidth+1&&!e.closest('.wrap')).map(e=>e.className||e.tagName);
  return {contrastFails:fails, hScroll:de.scrollWidth>de.clientWidth, overflowing:over.slice(0,5),
          gapKinds:[...gaps].length, bars:[...document.querySelectorAll('.fill,.brick')].map(e=>+e.getBoundingClientRect().width.toFixed(1))};
})()
```

**통과선**: `contrastFails` 0 · `hScroll` false · `overflowing` 빈 배열 · `gapKinds` ≤7 · `bars`에 0 없음.

간격·모서리 정리는 `node ~/.claude/scripts/normalize-tokens.mjs <파일>`.

마지막으로 **전체 스크린샷을 직접 본다.** 계측은 통과했는데 눈으로 보면 밋밋한 경우가 실제로 있었다(§⚠️).

## 6단계 — 남긴다

- 파일은 그 논의가 사는 폴더에 `YYYY-MM-DD-<주제>.html`
- 스크린샷 `.png`를 같이 저장하면 채팅·인계에서 바로 보인다
- 임시 산출물(`.playwright-mcp/` 등)은 `.gitignore`에

---

## ⚠️ 과거 실수 (상한 10줄 — 넘치면 병합·프루닝)

- **하한선 통과 = 합격이 아니다.** 2026-08-02 첫 산출물이 규칙을 전부 지켰는데 "전부 다 별로임 최악임" 평을 받았다. 원인 = 회색 상자·표 5개 연속·타입 스케일 평평·시그니처 없음. → §3 합격 조건을 초안 단계에서 먼저 확인한다.
- **좁은 폭 계측을 빠뜨리지 마라.** 같은 날 380px에서 막대와 수치가 한 줄에 강제돼 10px 넘쳤다(1100px에서는 통과). `.meter{flex-wrap:wrap}` + `.fill{max-width:100%}`로 해소.
- **CSS 주석 안에 닫는 스타일 태그 문자열을 쓰지 마라.** HTML 파서는 CSS 주석을 모른다. 그 지점에서 스타일 태그가 닫히고 **이후 CSS 전체가 본문 텍스트로 샌다.** 2026-08-02 `base.css` 첫 주석이 정확히 이걸로 무너졌고, 증상은 "막대 폭이 전부 0 · gap 종류 0"이었다. 계측이 잡아냈다 — 눈으로만 봤으면 "왜 밋밋하지"로 끝났을 것이다.
- **파일을 직접 열지 마라 — quirks mode.** `.B`가 `class="b"`에 매칭돼 실제 환경에 없는 버그가 생긴다. 반드시 `preview-server.mjs` 경유.
- **playwright MCP는 유휴 시 세션이 끊긴다.** `browser_evaluate`가 "Target page closed"로 실패하면 `browser_navigate`를 다시 호출한 뒤 이어간다.
