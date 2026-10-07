---
name: new-repo
description: >-
  Use PROACTIVELY whenever the user starts or even just mentions a NEW project·app·tool·product — '레포 만들어줘' 라고 콕 집지 않아도 된다 (예: "X 만들어보자", "새 앱 하나", "OO 짜보고 싶어", "프로젝트 시작하자", "이거 따로 빼서 만들자"). 새 프로젝트 낌새를 감지하면 그룹·이름을 제시해 1회 확인 후(사용자가 '바로/확인없이/그냥 만들어' 하면 즉시) add-repo.ps1 -Create 로 GitHub 생성·그룹폴더 클론·repos.json push, 멀티PC 자동 전파. Triggers - 새 프로젝트·앱·도구·제품 시작 낌새 전반 + "레포 만들어줘"·"새 레포"·"리포지토리 생성".
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

# new-repo

새 GitHub 레포를 **그룹 폴더에 정리된 채** 한 번에 만들고, 모든 PC(집·노트북)가 자동으로 같은 구조를 갖게 한다. 1인 멀티머신 개발의 "새 레포 만들면 PC마다 위치가 달라지는" 혼동을 제거.

## 핵심 원리
- **GitHub = 단일 진실원(SoT).** 로컬에만 만들면 다른 PC가 영영 모름 → 반드시 GitHub 생성(`-Create`).
- **`add-repo.ps1` = 단일 진입점.** GitHub 생성 + 그룹 폴더 클론 + `repos.json` 등록·push 를 한 방에.
- **`repos.json` 그룹 = 멀티PC 폴더 일치의 열쇠.** 여기 그룹이 적히면, 다른 PC의 자동 풀(boot-auto-pull-setup 자동클론)이 그룹을 읽어 **같은 그룹 폴더**에 받는다.

## 발동 & 확인 (능동형)
- **능동 발동:** 사용자가 새 프로젝트·앱·도구·제품을 **시작하거나 언급만 해도**(명시 트리거 없이) 이 스킬을 켠다 — "아 이거 새 레포네" 하고 먼저 잡는다. 단 기존 레포 안에서의 일반 작업·기능 추가는 발동 금지(새 독립 산출물일 때만).
- **기본 = 1회 확인:** 그룹·이름을 정해 제시 — "`<그룹>` 그룹에 `<이름>`으로 레포 만들까?" → 사용자가 ㅇㅇ면 실행.
- **무확인 모드:** 사용자가 "바로/확인없이/그냥 만들어" 신호를 주면 확인 생략하고 즉시 실행. **단 안전장치** — 그룹이나 이름이 애매하면 무확인이어도 그것만은 1번 물어 오분류·오생성을 막는다.

## 절차 (todo로)
1. **레포명·목적 확인.** 이름은 소문자-하이픈(kebab-case). 목적(뭐 하는 레포인지)을 파악.
2. **그룹 자동판단** (아래 표). 확신 없으면 **사용자에게 1번만** 물어봄 — 추측 강행 금지(오분류 = 폴더 이동 비용).
3. **실행:**
   ```powershell
   cd C:\Users\Public\dev\automation\boot-auto-pull-setup
   .\add-repo.ps1 <이름> <그룹> -Create
   ```
   → GitHub private 생성 + `C:\Users\Public\dev\<그룹>\<이름>` 클론 + `repos.json` 등록·push.
4. **검증:** 클론 성공(`dev\<그룹>\<이름>\.git` 존재) · `repos.json` push 됨 · GitHub 레포 존재(`gh repo view <owner>/<이름>`).
5. **안내:** 다른 PC는 **자동 풀이 알아서** 같은 그룹 폴더에 받음(가서 손댈 것 없음 — 다음 부팅/풀 후 반영). 집컴서 즉시 원하면 그 PC에서 자동 풀 1회 실행.

## 그룹 판단 표
| 목적 | 그룹 |
|---|---|
| 제품·서비스 (수익·고객 대상) | `products` |
| 자동화·봇·스크립트·인프라 | `automation` |
| 게임 | `games` |
| 요한 생태계 코어 도구 (vhk·brain·mcp 류) | `yohan-ecosystem` |
| 실험·프로토타입·일회성 | `_sandbox` |
| 해커톤·이벤트 제출물 | `_hackathon` |
| 이미지·정적 에셋·리소스 저장 | `_assets` |
| 보류 | `_hold` |
→ **확신 없으면 사용자에게 물어봐.** 그룹은 `yohan-ecosystem`·`products`·`games`·`automation`·`_sandbox`·`_hackathon`·`_hold`·`_archive`·`_assets` 중 하나(add-repo.ps1 의 ValidateSet 허용값 9종 전부).

## 주의
- **`-Create` 필수** — 로컬만 만들면 멀티PC 동기화 안 됨(GitHub를 꼭 거쳐야 함).
- 이미 존재하는 이름이면 add-repo 가 중복 클론 없이 안내만 한다(안전).
- `repos.json` push 가 실패하면 다른 PC가 그룹 정보를 못 받음 → **push 성공을 반드시 확인.**
- gh 인증 필요(자동 풀의 자동클론과 동일 토큰). 미인증이면 `gh auth login` 안내.
