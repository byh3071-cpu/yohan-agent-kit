---
vhk_format: 1
type: goal
id: 9
title: 벤더 wrapper payload-chain attestation
status: NOT_STARTED
priority: P2
---

# Goal 9: 벤더 wrapper payload-chain attestation

## 목적

Claude Code·Codex·Cursor의 resolved PowerShell entrypoint가 실제로 호출하는 backend payload까지 안정적으로 식별해, wrapper와 reported version이 같아도 설치 payload가 drift한 상태를 검출한다.

## Tasks

1. 벤더별 공식 설치 구조와 업데이트 방식을 조사해 고정 경로 가정과 동적 선택 규칙을 분리한다.
2. Claude Code의 wrapper → native payload, Codex의 wrapper → Node runtime·JS entrypoint, Cursor의 wrapper → 선택된 version directory·Node runtime·JS entrypoint resolver를 정의한다.
3. 각 chain 항목의 canonical path, 파일 유형, SHA-256, reparse-point 정책을 결정론적으로 봉인한다.
4. evidence schema를 명시적으로 올리고 구형 evidence는 자동 변환하지 않는다.
5. byte-identical wrapper·동일 reported version에서 backend만 교체한 fixture가 fail-close하는지 검증한다.

## Completion Check

- [ ] 세 벤더의 실제 실행 대상 선택 규칙이 공식 설치·업데이트 동작과 일치한다.
- [ ] wrapper, runtime, payload 중 하나라도 drift하면 `Verify`가 실패한다.
- [ ] 정상 vendor update는 새 Probe·Finalize로 재봉인할 수 있다.
- [ ] symlink·junction·PATH shadow·동일 버전 위장이 fail-close한다.
- [ ] 로컬 절대경로 원문은 공개 산출물에 남기지 않는다.
- [ ] Windows PowerShell 5.1과 실제 세 벤더 설치에서 회귀가 통과한다.

## 비범위

- 벤더 바이너리의 코드 서명 체인이나 공급자 서버까지의 종단 간 provenance 증명
- Goal 8의 집 PC 실설치·capability evidence 완료 차단

## 사람 게이트

- 벤더별 resolver 계약 승인
- evidence schema 전환 승인
