---
vhk_format: 1
type: goal
id: 16
title: RetrievalReceipt·성과 학습 후보 루프
status: IN_PROGRESS
priority: P0
size: L
execution_provider: native-approved
automatic_fallback: false
started: 2026-08-24
---

# Goal 16: RetrievalReceipt·성과 학습 후보 루프

## 목표

yohan-mcp의 읽기 전용 retrieval diagnostics를 명시적 post-action 명령으로 Brain append-only 영수증에 기록하고, 실제 outcome만 연결해 결정론적 learning candidate를 만든다.

## 계약

- Brain은 schema·storage를 소유한다.
- yohan-mcp는 휘발성 diagnostics와 문서 계보를 제공하며 persistent write를 하지 않는다.
- Agent Kit은 HMAC query fingerprint, receipt/outcome recorder, candidate evaluator를 소유한다.
- contract는 dirty checkout이 아니라 호출자가 지정한 정확한 Brain Git ref에서 읽고 schema bundle digest를 재계산한다.
- 모든 recorder는 explicit 호출만 허용하며, raw query·prompt·answer·secret·절대경로를 저장하지 않는다.
- outcome 없는 receipt는 `review/no-outcome`이고, 명시적 helpful outcome만 `preserve`가 될 수 있다.
- candidate는 항상 `status=candidate`, `stable_auto_promotion=false`다.

## 완료 조건

- [ ] HMAC 키가 process environment에 없으면 write 전 실패한다.
- [ ] fingerprint 출력과 tracked JSONL에 query 원문·키가 없다.
- [ ] receipt/outcome append가 기존 bytes를 바꾸지 않고 duplicate·orphan·broken supersedes를 거부한다.
- [ ] contract ref·schema digest drift와 draft contract를 거부한다.
- [ ] BrainRoot 밖·reparse 경로 write를 거부한다.
- [ ] outcome 없는 candidate를 성공으로 추론하지 않는다.
- [ ] 같은 receipt/outcome 입력은 byte-stable candidate를 만든다.
- [ ] 실제 yohan-mcp 봉투 fixture가 receipt → outcome → candidate 한 바퀴를 통과한다.
- [ ] Brain·MCP·Agent Kit 전체 게이트와 독립 적대 검수가 통과한다.

## 비범위

- 모든 query 자동 기록
- raw prompt/response 보관
- LLM 자기채점
- 자동 ranking·rule·skill 승격
- Notion/Qdrant write
- 사용자 홈 HMAC 키 설치
- 원격 push·PR Ready·merge·배포·publish

## 악수

입력은 특정 Git ref의 활성 Brain schema와 동일 retrieval generation의 MCP diagnostics이고, 출력은 그 계보·HMAC fingerprint·실제 outcome만 담은 append-only receipt와 candidate다.
