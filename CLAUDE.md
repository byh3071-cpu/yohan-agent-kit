<!-- YOHAN-VHK-AUTO-STOP:BEGIN -->
## VHK 전면 보류 (2026-10-07 사용자 결정)

- VHK는 문제가 해결되고 사용자가 명시적으로 재개를 승인할 때까지 모든 작업에서 전면 보류한다. 실행·설치·업데이트·주입·동기화·Goal 관리·verify/receipt/review·watch·autopilot을 호출하지 않는다.
- 검증 스킬(cross-check, release-gate, plan-audit, dogfood-crosscheck 등), Evaluator·평가 로그·적대적 리뷰 반복·검증용 자동 모델 호출도 기본 작업 절차로 실행하지 않는다. 추가 검토는 해당 작업에서 사용자가 명시적으로 요청한 경우에만 선택하며 VHK 재개는 별도 승인이다.
- goal-cycle·adr-cycle·오케스트레이션 등 다른 스킬로 우회해 중단한 절차를 연쇄 호출하지 않는다. 과거 문서·메모리·스킬·플러그인의 의무보다 이 결정이 우선한다. 개별 이슈 해결·새 버전 설치만으로 자동 재개하지 않는다.
- 변경 영향에 필요한 직접 확인·관련 테스트만 수행하고 관련 코드·테스트·입력·의존성·환경이 같은 통과 결과는 재사용한다. 관련 변경·실패 근거가 없는 전체 재검사와 기록 복제를 하지 않는다.
- 사용자 변경·시크릿 보호, 삭제·외부 전송·merge·배포·publish에 대한 사람 승인 경계는 유지한다.
<!-- YOHAN-VHK-AUTO-STOP:END -->

@AGENTS.md

# 기록 규칙 (Yohan Agent Kit)

## 상태 안내
- 고정 Phase·다음 액션은 이 파일에 기록하지 않는다.
- 현재 상태는 GitHub Issue·PR과 해당 작업 문서를 기준으로 확인한다.

<!-- vhk:rules:start -->
> ⚡ 아래 규칙 섹션은 RULES.md에서 자동 생성됨 (vhk sync). 직접 수정 금지.

## 기술 스택
- 범용 Markdown skills · 전체 디렉터리 manifest
- Claude Code plugins
- PowerShell 5.1 hooks·설치 도구 (Windows primary)

## 코딩 규칙
- 범용 스킬 정본 = `skills/<name>/`; `SKILL.md` frontmatter는 `name`·`description`만 사용
- 범용 스킬 변경 시 `distribution/manifests/<name>.json` 전체 파일 manifest를 같은 PR에서 갱신
- 범용 스킬에 특정 PC 홈·Public/dev 절대경로 하드코딩 금지; 가장 가까운 프로젝트 규칙 우선
- 멀티에이전트 라우팅은 가장 가까운 AGENTS를 먼저 따르고, yohan 생태계 공통 작업은 yohan-brain의 active `memory/core/agent-roster.yaml`을 대조
- `vhk sync`는 AGENTS·Cursor 규칙 전파만 담당하며 사용자 홈 스킬을 설치하지 않음
- `Check`는 읽기 전용; `Install`·`Restore`는 홈 쓰기 승인과 최신 PlanDigest 필수, 내용 불일치 우회 금지
- Claude-only ops: handoff · release-gate · parallel — 범용 `skills/`에 중복 복사 금지
- secrets in skills·hooks·배포 기록 금지
- plugin manifest 변경 시 marketplace.json 정합

## 기록 규칙
- loop protocol → `plugins/yohan-core/loop.md`
- 범용 스킬 원본 조정·배포 감사 → `docs/audits/`
- 범용 스킬 설치 계약 → `docs/MULTIVENDOR_SKILL_DISTRIBUTION.md`
- 패턴 문서 → `docs/patterns/`

<!-- vhk:rules:end -->
