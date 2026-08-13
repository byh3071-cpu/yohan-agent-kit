---
vhk_format: 1
type: goal
id: 1
title: adr-cycle·goal-cycle 멀티벤더 정본화
status: DONE
priority: P0
completed: 2026-08-14
---

# Goal 1: adr-cycle·goal-cycle 멀티벤더 정본화

## 배경

Accepted ADR-013·014에 따라 yohan-cc-skills를 두 범용 스킬과 배포 도구의 Git 정본으로 확장한다. 기존 홈 사본과 dirty checkout은 입력 증거로만 읽고 자동 덮어쓰지 않는다.

## 범위

- goal-cycle 원본·변형 조정 보고서와 정본 이관
- adr-cycle 신규 스킬과 goal-cycle 악수
- Codex UI 메타데이터와 멀티벤더 배포 문서
- PowerShell 5.1 Check·Install·Restore 도구 및 결정론 테스트
- 기존 Claude 플러그인 구조 보존

## 비범위

- 사용자 홈 실제 설치·백업·교체
- 기존 dirty checkout 정리
- main 머지

## 완료 조건

1. 스킬 원본·의미 변경·배포 도구가 검토 가능한 별도 커밋으로 분리된다.
2. goal-cycle 전체 디렉터리 manifest와 두 reference 변형의 보존·판정 근거가 남는다.
3. adr-cycle 자동·명시·부정 호출 계약과 Proposed→Accepted 사람 게이트가 명시된다.
4. 설치 도구가 내용 불일치·활성 중복·AGY fallback을 안전하게 차단 또는 보고한다.
5. 테스트·시크릿 검사·독립 검수를 통과하고 Draft PR을 연다.

## 악수

ADR-013·014의 책임 경계와 사용자 승인 없는 홈 쓰기 금지가 코드·문서·테스트에서 같은 의미를 가진다.
