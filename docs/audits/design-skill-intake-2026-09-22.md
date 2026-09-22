# 외부 디자인 스킬 등록 감사 — 2026-09-22

SELOA 캘린더·프로젝트 설계 라운드를 앞두고 요한이 고른 디자인 스킬 다섯 개를 검토했다. 킷 규칙대로 파일을 복사하지 않고 `registry/assets.yaml`에 `external://` 자산으로 출처·커밋·라이선스만 기록한다. 복원은 `scripts/Restore-ExternalSkills.ps1`이 맡는다.

## 판정

| 스킬 | 출처 | 라이선스 | 판정 | 이유 |
| --- | --- | --- | --- | --- |
| `frontend-design` | anthropics/skills | Apache-2.0 | 등록 | 9KB 한 장. "AI 티" 나는 기본값(크림 배경 + 세리프, 카드 키트, 대문자 라벨)을 이름 붙여 금지한다. `visualize`와 `design-to-html`이 이미 이름으로 부르고 있었는데 설치 좌표가 없었다 |
| `hallmark` | Nutlope/hallmark | MIT | 등록, 범위 제한 | 랜딩·마케팅 페이지용이다. 21개 페이지 구조와 65개 슬롭 검사가 강점이지만 고정 디자인 시스템이 있는 앱 화면에 페이지 구조 규칙을 얹으면 시스템과 싸운다. 앱에는 `hallmark audit`만 쓴다 |
| `emil-design-eng` | emilkowalski/skills | MIT | 등록 | 애니메이션 곡선·속도·스프링과 컴포넌트 촉감. 시안마다 곡선이 달라지는 문제를 표 하나로 막는다 |
| `animate-expo` | emilkowalski/skills | MIT | 등록 (추가) | 요한이 고른 목록에는 없지만 같은 저장소·같은 커밋·같은 라이선스다. `emil-design-eng`가 웹 전용이라 React Native·Expo(SELOA, MOVA)에는 이쪽이 맞다. Reanimated·Gesture Handler·haptics를 UI 스레드에 두는 규칙까지 담고 있다 |
| `web-design-guidelines` | vercel-labs/agent-skills | MIT | 등록 | 1KB. 실행 때 Vercel Web Interface Guidelines를 받아 `file:line`으로 접근성·UX 위반을 낸다. 규칙이 스킬 밖에 있어 오래돼도 안 낡는다 |
| `ui-ux-pro-max` | nextlevelbuilder/ui-ux-pro-max-skill | MIT | 보류 | 3.6MB CSV 데이터 + Python 검색 스크립트가 필요하다. "제품 유형을 넣으면 팔레트·폰트·스타일을 골라 준다"는 방식이 `design-team`의 취향 인터뷰(디렉터가 실물 후보에서 고른다)와 반대 방향이다. 팔레트·폰트 데이터베이스가 실제로 아쉬워질 때 다시 본다 |

## 반영

- `registry/assets.yaml` — 다섯 항목 추가. lifecycle은 Intake 상한인 `reviewed`다. 이 PR 승인이 `approved` 전환 근거다
- `plugins/workflow/skills/visualize/SKILL.md` — Mode A 1단계에 네 스킬의 쓰임과 범위를 적었다. `hallmark`는 앱 화면에서 audit만, 모션은 웹·Expo로 갈라 쓰고, 시안 전에 `web-design-guidelines`를 한 번 돌린다
- `plugins/workflow` 0.3.10 → 0.3.11, `marketplace.json` 정합

## 확인한 것

- 다섯 저장소를 얕게 받아 SKILL.md와 LICENSE를 직접 읽었다. Vercel 저장소는 LICENSE 파일이 없고 README "License: MIT"만 있다
- `node scripts/Build-AssetCatalog.mjs --write` 뒤 check 통과
- PowerShell이 없는 환경이라 `Restore-ExternalSkills.ps1`은 돌리지 못했다. 설치 명령은 `npx skills add <owner/repo> --skill <id>`이고 `--skill` 값은 `skill.` 접두사를 뗀 id라 위 다섯 id는 각 저장소의 스킬 디렉터리 이름과 같게 맞췄다

## 남은 것

- 요한 PC에서 `Restore-ExternalSkills.ps1`(계획 출력) → `-ApproveInstall`로 실제 설치와 `claude --bare` 발견 확인
- SELOA 프로젝트 화면(#62) 설계 라운드에서 `visualize` Mode A로 첫 실사용. 효과가 없으면 여기 표의 판정을 뒤집는다
