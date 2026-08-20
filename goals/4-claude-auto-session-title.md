---
vhk_format: 1
type: goal
id: 4
title: Claude Code 전역 세션 제목 자동화
status: IN_PROGRESS
priority: P1
---

# Goal 4: Claude Code 전역 세션 제목 자동화

## 배경

새 프로젝트와 새 세션에서도 첫 프롬프트를 바탕으로 찾기 쉬운 제목을 자동 설정한다. 사용자 지정 이름과 재개 세션은 보존하고, 플러그인 배포를 통해 머신별 수동 설정을 없앤다.

## 범위

- yohan-core 플러그인의 세션 제목 PowerShell 5.1 훅
- `SessionStart`·`UserPromptExpansion`·`UserPromptSubmit` 배선
- 세션별 1회 실행과 사용자 지정 제목 보존
- 한국어 프롬프트·Windows 경로·재개·서브에이전트 회귀 테스트
- 플러그인 캐시 갱신을 위한 yohan-core 패치 버전 범프

## 비범위

- Cursor 세션 제목 변경
- 기존 세션 기록의 일괄 이름 변경
- 모델 호출 기반 제목 요약

## 완료 조건

1. 이름 없는 신규 세션은 첫 일반 프롬프트에서 `날짜 · 프로젝트 · 주제` 제목을 받는다.
2. `--name`·`/rename`, 재개·분기·clear 세션의 기존 의미를 덮어쓰지 않는다.
3. 서브에이전트와 슬래시 명령은 제목 생성 횟수를 소비하지 않는다.
4. 동일 세션에서는 한 번만 제목을 출력한다.
5. PowerShell 5.1 회귀 테스트와 전체 레포 게이트를 통과한다.
6. yohan-core와 marketplace 버전이 함께 올라 새 캐시를 식별한다.

## 악수

Claude Code 공식 `sessionTitle` 훅 계약과 플러그인 배포 결과가 모든 로컬 프로젝트에서 같은 제목 정책을 뜻한다.
