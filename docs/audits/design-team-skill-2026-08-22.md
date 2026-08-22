# 범용 Design Team 스킬 설계 감사 — 2026-08-22

## 결론

`design-team`은 고정된 에이전트 조직도나 특정 제품용 프롬프트가 아니라, 프로젝트 맥락을 먼저 해석하고 필요한 역할만 구성하는 상위 디자인 운영 스킬로 설계한다. 프로젝트 사실을 스킬 안에 축적하지 않고 프로젝트 소유 versioned source of truth의 DesignContext와 결정 로그에 남기는 2계층 구조가 핵심이다. Git을 쓰는 프로젝트는 Git을 사용한다.

## 소유권

- 공통 방법·역할·산출물 계약: Yohan Agent Kit `skills/design-team/`
- 프로젝트별 사용자·제품·자산·결정·검증: 각 소유 프로젝트의 versioned source of truth(Git을 쓰는 프로젝트는 Git)
- 승인된 시각 결과의 제작: 반응형 HTML은 `design-to-html`, 그 밖의 매체는 프로젝트가 승인한 제작 책임자·방식
- 공유 패턴 승격: 반복 증거와 사람 검토가 있을 때만 Agent Kit intake

## 기존 자산과의 경계

- `research-brief`는 짧은 경쟁·레퍼런스 조사에 재사용할 수 있다.
- Product Design 도구는 실제 시각 옵션, 컨텍스트 확보, audit와 QA에 재사용한다.
- `design-to-html`은 선택된 시각 기준 이후의 구현·브라우저 검증만 소유한다.
- `design-team`은 위 기능을 복제하지 않고 순서, 맥락, 역할, 사람 게이트와 인수인계를 조율한다.

## 주요 판단

1. 모델명은 역할 계약이 아니다. 현재 roster와 런타임에서 사용할 수 있는 공급자를 선택하고 노출된 이름만 기록한다.
2. “자체 컨텍스트”는 대화 히스토리나 스킬 내부 프로젝트 메모가 아니라, 재해석 가능한 프로젝트 소유 스냅샷과 append-only 결정 로그다.
3. 열린 시각 탐색은 동일한 과업·매체·scale/context를 공유하는 세 가지 실제 시안으로 비교한다. 인터랙티브 화면은 viewport와 state도 고정한다.
4. 선택 전에는 production 구현을 시작하지 않는다. 독립 디자인 세션은 Git 프로젝트에서는 별도 worktree, 그 밖의 매체에서는 동등한 versioned workspace와 handoff로 소유권을 분리한다.
5. 프로젝트별 산출물과 바이너리는 프로젝트가 소유하며, 공유 저장소는 방법과 검증된 범용 패턴만 소유한다.
6. 규제·안전 중요 작업은 관할·프레임워크·intended use·hazard·risk control·traceability·자격 있는 승인자를 필수로 기록하고, 디자인 QA를 공식 validation이나 compliance 증거로 주장하지 않는다.

## 첫 검증 대상

요한 관제탑은 복잡한 로컬 운영 제품이므로 context discovery, 정보 감축, 5개 탭 상한, 사람 승인 경계, Brain SoT 읽기 전용 제약을 동시에 검증하는 첫 적용 사례로 사용한다. 레스토랑 브랜드·공간, 임상 모니터링, 에디토리얼 다큐멘터리 시나리오의 독립 forward test에서 발견한 Git/UI 편향과 규제 경계를 보정한 뒤 다시 검증한다.

## 독립 forward test 결과

- 검토자: Codex GPT-5.6 Terra xhigh, read-only
- 검증 분야: 레스토랑 브랜드·메뉴·공간, 규제 임상 모니터링, 에디토리얼 다큐멘터리 microsite
- 1차 결과: non-Git 소유권, 매체별 제작 계약, 규제·안전 traceability와 qualified approver 경계 부족으로 FAIL
- 보정: owner workspace/versioned SoT, viewport·print size·physical scale·environment 통합, QMS 형식 우선, formal validation과 design QA 분리, medium-appropriate handoff 추가
- 2차 결과: Markdown/QMS 충돌과 independent-session UI 용어 잔여로 FAIL
- 최종 결과: 세 분야 모두 PASS. Yohan Control Tower의 Git/worktree·사람 게이트·HTML handoff도 보존됨
- 매니페스트: 최종 skill 5개 파일의 byte와 SHA-256 일치 확인
