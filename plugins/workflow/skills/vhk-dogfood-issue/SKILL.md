---
name: vhk-dogfood-issue
description: "전면 보류된 과거 절차. VHK 문제 해결과 사용자 재개 승인 전에는 선택·실행하지 않는다. 검증 스킬은 자동 호출하지 않는다."
disable-model-invocation: true
---

> **2026-10-07 전면 보류 적용:** VHK의 실행·설치·업데이트·주입·동기화·Goal/verify/receipt/review·watch·autopilot은 문제 해결과 사용자 재개 승인 전까지 중단한다. 아래 과거 절차의 강제 검토·검증 스킬·Evaluator·평가 로그·자동 모델 호출·중복 기록 요구는 적용하지 않는다. 추가 검토는 해당 작업의 명시 요청이 있는 경우에만 선택한다. 사용자 변경·시크릿 보호·사람 승인 경계는 유지한다.

> 2026-10-03 사용자 결정: 자동 선택·자동 호출 중단. 현재 작업에서 사용자가 명시적으로 요청한 경우에만 이 스킬을 사용한다.


# VHK Dogfood Issue (L1 제품)

**SoT:** https://github.com/byh3071-cpu/vhk/issues

## 분류 (먼저)

| 유형 | 등록 | 예 |
|---|---|---|
| **도구 결함** | vhk 레po | goal silent skip, recap headless |
| **앱 버그** | **현재 프로젝트** 이슈/수정 | aroo 결제 로직 |
| **배선 갭** | 프로젝트 skill/RULES + (공통이면) vhk enhancement | verify만 하고 receipt 생략 |

교차검증 필요 시 **dogfood-crosscheck** 선행.

## 절차

1. **재현** — 최소 명령·exit code·`vhk --version`
2. **중복 검색**
   ```powershell
   gh issue list -R byh3071-cpu/vhk --search "키워드" --state all
   ```
3. **body 작성** — `.vhk/issue-<slug>.md` (재현/기대/실제/환경)
4. **등록** — 사용자가 "등록해" / "ㅇㅋ 이슈" 명시 후:
   ```powershell
   gh issue create -R byh3071-cpu/vhk --title "..." --label "bug,dogfooding" --body-file .vhk/issue-<slug>.md
   ```
5. **로컬 흔적** — `vhk learn "dogfood: ..."` (태그 dogfood)

## 금지

- 사용자 승인 없이 `gh issue create`
- 앱 버그를 vhk 레po에 등록
