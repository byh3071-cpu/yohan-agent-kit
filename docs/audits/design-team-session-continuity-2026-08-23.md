# Design Team 세션 연속성 감사

- 날짜: 2026-08-23
- Goal: 14
- 브랜치: `feat/design-team-session-continuity`
- 상태: 구현·검증 중

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

완료 뒤 실제 명령, 판정, 잔존 위험을 기록한다.
