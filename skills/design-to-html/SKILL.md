---
name: design-to-html
description: 승인된 이미지·스크린샷·Figma·HTML 시안이나 명확한 시각 기준을 반응형 인터랙티브 HTML로 구현하고 브라우저·접근성·디자인 QA로 검증한다. "HTML로 만들어줘", "이 시안 구현해", "반응형 프로토타입", "디자인을 코드로", "visualize에서 고른 안을 완성해" 요청에 사용한다. 시각 원본이 없는 탐색 단계, 단순 문서 작성, 백엔드만의 변경에는 사용하지 않는다.
---

# Design to HTML

1. 요청의 목적, 사용자, 대상 화면, 완료 기준을 한 문장으로 정리한다.
2. 가장 가까운 프로젝트 규칙과 관련 SoT만 선택해 작업 컨텍스트 요약을 표시한다.
3. 시각 원본이 없으면 구현하지 말고 시각 탐색 스킬로 보낸다.
4. 시각 원본이 있으면 원본을 source of truth로 고정한다.
5. 현재 벤더에 Product Design·browser·frontend-design이 있으면 execution adapters로만 사용하고, SoT는 current request → project Git → yohan-brain design context → Notion view 순서를 유지한다.
6. HTML의 핵심 탭·메뉴·입력·펼침·선택 상태를 실제로 동작시킨다.
7. 360·432·768·1280·1440px에서 반응형과 가로 overflow를 확인한다.
8. 원본과 구현 캡처를 같은 비교 화면에 놓고 P0·P1·P2를 수정한다.
9. `design-qa.md`에 `final result: passed`가 있을 때 산출물·검증 리포트·commit SHA를 전달한다.

Read `references/context-contract.md` when resolving SoT or multiple devices.
Read `references/quality-gate.md` before implementation and again before handoff.
