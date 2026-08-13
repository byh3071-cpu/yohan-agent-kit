---
vhk_format: 1
type: goal
id: 3
title: DesignContext resolver와 HTML 세로절단
status: IN_PROGRESS
priority: P0
---

# Goal 3: DesignContext resolver와 HTML 세로절단

## 선행조건

- yohan-brain ADR-023의 실제 파일과 상태 표면이 `Accepted`여야 한다.
- Goal 20 계약이 존재하는 승인 branch와 exact commit SHA를 확인해야 한다.
- 두 근거의 경로·결정·제약·후속 작업이 handoff와 일치해야 한다.
- 선행조건이 확인되기 전에는 계약 의존 resolver·recorder·HTML 구현을 시작하지 않는다.

## 범위

- 읽기 전용 `Resolve-DesignContext.ps1`
- append-only `Record-DesignDecision.ps1`
- `reuse|adapt|remix|create` 결정 allowlist와 결정론 테스트
- 기존 WorkContext 앞단의 최소 DesignContext envelope
- 승인 원본의 단계 우선·확인 흐름을 보존한 HTML 세로절단 fixture
- project-relative 승인 source·final evidence·`design-qa.md`

## 비범위

- 관제탑 UI
- PPT·이미지·보고서 확장
- automatic stable promotion
- 사용자 홈 Install·Restore
- main 머지·ready 전환·publish

## 완료 조건

1. DesignContext가 current request → project Git → media → common taste → golden 순서로 결정론적으로 해석된다.
2. 승인 source는 yohan-brain Context Trust Navigator의 Git ref와 repository-relative path로 식별된다.
3. 결정 기록은 append-only이고 action allowlist 밖의 입력을 거부한다.
4. 기존 WorkContext 계약을 보존하며 DesignContext는 앞단 최소 envelope로만 연결된다.
5. HTML fixture가 승인 원본의 단계 우선·확인 흐름을 보존하고 generic card-grid로 재해석되지 않는다.
6. 360·432·768·1280·1440px에서 overflow 0, console error 0, keyboard path, WCAG AA, same-state source comparison, P0/P1 0을 증명한다.
7. `design-qa.md`의 마지막 줄이 정확히 `final result: passed`다.
8. 테스트·secret guard·VHK verify→receipt→review·적대 검수를 통과하고 main 대상 Draft PR을 연다.

## 악수

yohan-brain Accepted 계약의 source trust 순서와 이 저장소 resolver·HTML evidence가 같은 Git ref·repository-relative path·UI state를 뜻한다.

## 남은 사람 게이트

- ADR-023 Accepted와 Goal 20 계약의 승인 branch·exact SHA 전달
- Brain contract PR보다 이 PR을 뒤에 머지
- Draft PR의 ready 전환과 merge
