# Design Team 세션 연속성 감사

- 날짜: 2026-08-23
- Goal: 14
- 브랜치: `feat/design-team-session-continuity`
- 상태: 구현·로컬 검증 완료, 사람 통합 게이트 대기

## 결정 영향

Design Team의 프로젝트 기억 계약을 “문서를 남긴다”에서 “다음 독립 세션이 같은 승인 상태와 대화 지점에서 실제로 재개한다”로 강화한다. 작성·전송·수신 확인을 분리하고, 디자인 디렉터에게 보이지 않은 시안이나 짧은 진행 동의를 선택·최종 승인으로 승격하지 않는다.

## 실제 사용에서 확인된 구멍

1. 보고서가 Git에 있어도 대상 지휘자 세션이 받았는지 별도 증거가 없었다.
2. 세션 전달 명령 실패와 실제 수신 성공이 다른 채널에서 동시에 성립할 수 있었지만 상태 모델이 없었다.
3. 짧은 진행 동의가 방향 선택 또는 최종 승인으로 해석될 여지가 있었다.
4. 이미지 도구가 성공해도 대화 화면에 시안이 보이지 않아 사용자가 여러 번 재전송을 요구했다.
5. 다음 세션이 읽을 취향·금지 패턴·대화 방식·정확한 다음 질문의 최소 번들이 정의되지 않았다.

## 범용으로 승격한 패턴

- 프로젝트 소유 continuation bundle과 시작 acknowledgement
- `continue / direction selected / final design accepted / production authorized` 승인 단계
- `prepared / sent / acknowledged / failed` 전달 단계
- 시각 산출물의 `prepared / rendered / director-visible / failed` 영수증
- 해결된 취향 질문을 반복하지 않고 정확한 다음 사람 게이트에서 재개하는 규칙
- 한 명의 지휘자만 디자인 디렉터와 대화하고 사용자 어휘를 유지하는 규칙

## 범용 스킬에서 제외한 값

첫 적용 프로젝트의 색상, 글꼴, 화면 구조, 아이콘 크기, 특정 도구·모델 조합, 개인 경로와 대화 원문은 공통 스킬에 넣지 않는다. 해당 값은 프로젝트 저장소의 DesignContext·taste profile·session handoff가 소유한다.

## 검증 계획

- `skill-creator` quick validator
- `node scripts/check-goal-14.mjs`
- Goal 11–13 회귀 게이트
- `New-SkillManifest.ps1` 전체 파일 manifest 재생성
- `Build-AssetCatalog.mjs` registry/catalog 정합
- `Manage-MultivendorSkills.ps1 -Mode Check -Skill design-team`
- 실제 프로젝트 continuation bundle을 사용한 독립 read-only 복원 시험

## 검증 결과

- `python -B -X utf8 <skill-creator>/scripts/quick_validate.py skills/design-team` — PASS (`Skill is valid!`). `<skill-creator>`는 실행 환경이 제공한 현재 validator 경로이며 저장소 산출물에는 고정하지 않았다.
- `node scripts/check-goal-14.mjs` — PASS. 세션 연속성 계약, 승인·전달·시각 영수증, 고정 경로·프로젝트·벤더·모델 배제, Goal 11–13 회귀가 모두 통과했다.
- `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/New-SkillManifest.ps1 -Skill design-team` — PASS. 생성 결과가 tracked manifest와 일치했고 digest는 `C3B3059048BA63AC471E22F8E7817D04D4DF324E567511311CDC106900B09265`였다.
- `node scripts/Build-AssetCatalog.mjs` — PASS. 203개 자산, catalog digest `03b90bb3ed4627971b6d48f90f5e9aa6475e11ecc8e8b4374e6bf707a5b8727f`.
- `git diff --check` — PASS.
- `Manage-MultivendorSkills.ps1 -Mode Check -Skill design-team` — source 무결성 충돌 없이 `Installable`. 현재 사용자 홈의 네 표준 대상이 비어 있어 설치 계획만 산출됐으며, Goal 비범위와 사용자 금지에 따라 Install은 실행하지 않았다.

## 잔존 위험과 사람 게이트

- `Installable`은 실홈 새 세션 발견을 증명하지 않는다. 실제 홈 설치와 벤더별 새 세션 확인은 별도 사용자 승인 뒤에만 가능하다.
- 현재 검증은 정적 계약과 저장소 fixture에 대한 증거다. 외부 세션 런타임의 전달 성공은 대상 acknowledgement가 있을 때만 별도로 주장할 수 있다.
- push, PR, release, 실홈 설치, merge, publish는 수행하지 않는다.
