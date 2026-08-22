---
name: planning-diagrams
description: >-
  Produces tables, org charts, pipeline/flow sketches, and Mermaid or ASCII
  diagrams for early planning and ideation. Use when brainstorming, initial
  product or project planning, org structure, data/CI pipelines, architecture
  sketches, or when the user asks for 표·다이어그램·조직도·파이프라인 그림 in the
  idea phase. Prefer concise visuals over long prose.
---

# Planning diagrams (기획·아이디어 초기 시각화)

## When to apply

- 주제가 **기획 초기**, **구조만 잡는 단계**, **여러 안을 비교**하는 경우.
- 산출물은 **의사결정 보조용 초안**이다. 최종 설계 문서·공식 아키텍처로 단정하지 않는다.

## Default workflow

1. **한 줄로 목적**을 확인한다 (예: “팀 역할만”, “배포 파이프 한 줄”).
2. **가장 작은 단위**부터 그린다 (노드·열이 많으면 먼저 나눈다).
3. 아래 **형식 선택**에 맞춰 1차 산출물을 만든다.
4. 필요하면 **대안 1개**(예: 평면 조직 vs 매트릭스)만 추가한다.

## 형식 선택 (기본값)

| 필요한 것 | 권장 형식 |
|-----------|-----------|
| 역할·팀·보고 관계 | Mermaid `flowchart` 또는 `graph` (간단한 조직도) |
| 단계·순서·파이프라인 | Mermaid `flowchart LR` 또는 `sequenceDiagram` |
| 시스템·모듈 관계 | Mermaid `flowchart` / `graph` (방향과 화살표만) |
| 비교·옵션 나열 | Markdown **표** |
| 빠른 초안·터미널 친화 | ASCII 박스/화살표 (짧게) |

- **Mermaid**는 Cursor·많은 Markdown 뷰어에서 바로 렌더된다. 문법은 공식 스펙을 따른다.
- **표**는 열이 4~5개 넘어가면 행을 나누거나 “요약 표 + 상세 표”로 쪼갠다.

## 스타일

- 레이블은 **한국어**를 기본으로 한다. 사용자가 영어만 쓰라고 하면 영어로 맞춘다.
- 범례·단위가 있으면 **짧게** 붙인다.
- “정확도 100%” 같은 표현은 쓰지 않는다. 초안임을 전제로 한다.

## 피할 것

- 요청 없이 **장문 설명**으로 그림을 대체하지 않는다.
- **실제 인명·시크릿·내부 URL**을 예시에 넣지 않는다. 필요하면 `예시 팀 A` 식으로 가명을 쓴다.
- 기획 스케치인데 **구현 코드·배포 절차**까지 확장하지 않는다 (사용자가 요청한 경우만).
