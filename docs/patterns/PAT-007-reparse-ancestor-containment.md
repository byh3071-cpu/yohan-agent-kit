---
id: PAT-007
패턴명: Windows 경로 prefix 검증만으로는 부모 reparse point 탈출을 막을 수 없음
카테고리: env
증상: |
  쓰기 대상의 정규화 절대경로가 허용 루트 문자열 아래에 있어도, 중간 부모 디렉터리가 junction·symlink이면 실제 변경이 허용 루트 밖에서 일어난다. 백업·복구 도구가 외부 파일을 이동하거나 자신이 만들지 않은 junction을 삭제할 수 있다.
원인: |
  `GetFullPath`와 case-insensitive prefix 비교는 `..` 탈출만 막는다. NTFS reparse point가 해석되는 실제 파일시스템 경계와 junction 객체의 소유권은 증명하지 못한다. 대상 문자열과 link target만 비교하면 삭제 후 같은 target으로 다시 만든 junction도 원래 객체로 오인한다.
해결: |
  허용 루트 containment를 먼저 확인하고, 볼륨 루트부터 destination 부모까지 기존 각 경로 성분의 ReparsePoint 속성을 검사한다. 파일 목적지는 leaf 자체도 reparse point인지 별도로 확인한다. 쓰기 직전과 부모 생성 직후에 같은 검사를 반복한다. 디렉터리 이동은 destination leaf가 존재하면 실패하는 정확한 API를 쓴다. 새 junction은 transaction 내부 staging에서 만든 뒤 NTFS file ID 기반 지문을 저널링하고 active leaf로 원자 이동한다. 삭제는 저장된 지문과 target이 실제 객체와 모두 일치할 때만 허용하며 identity가 없으면 현재 객체를 채택하지 않는다. transaction의 source·target·backup·staging 경로는 저장값을 신뢰하지 말고 현재 CLI 입력에서 다시 계산한다.
적용조건: Windows에서 사용자 제공 루트 아래 파일 이동·백업·복구·junction 설치를 수행하는 PowerShell 자동화
출처프로젝트: yohan-cc-skills
태그: [windows, powershell, reparse-point, junction, path-containment, transaction, restore]
발견일: 2026-07-29
출처DevLog: "2026-07-29 adr-cycle·goal-cycle 멀티벤더 정본화"
---

# PAT-007 — 부모 reparse point까지 검증하는 경로 containment

## 핵심 한 줄

Windows 쓰기 안전성은 정규화 path prefix로 끝나지 않는다. destination의 모든 기존 부모와 leaf 점유를 확인하고, junction 삭제에는 target과 NTFS file ID 기반 객체 지문을 함께 요구한다.

## 실패하기 쉬운 순서

1. 대상 `HomeRoot\.agents\skills\x`가 문자열상 HomeRoot 내부인지 확인한다.
2. 공격자나 기존 설치가 `.agents`를 외부 경로 junction으로 둔다.
3. `New-Item`, container 의미의 `Move-Item`, `Directory.Delete`가 외부 트리에서 실행된다.
4. Restore transaction의 경로까지 신뢰하면 백업 경로 변조가 같은 문제를 다시 만든다.

## 검증 방법

- 부모 junction과 backup-root junction을 격리 fixture에 만들고 외부 sentinel의 tree hash가 전후 동일한지 확인한다.
- 설치 뒤 junction을 삭제하고 같은 target으로 재생성한 다음 Restore가 identity mismatch로 거부하는지 확인한다.
- transaction의 backupPath를 외부 경로로 바꿔 seal·결정적 path binding이 쓰기 전에 실패하는지 확인한다.
- destination leaf에 외부 junction을 삽입해 정확한 directory move가 실패하고 source·외부 sentinel이 그대로인지 확인한다.
- junction을 즉시 같은 target으로 재생성해도 NTFS file ID 기반 identity가 달라지는지 확인한다.

## 한계

객체 지문과 비밀키 없는 seal은 같은 사용자 권한의 의도적 공격자에 대한 인증 수단이 아니라 우발적 교체·변조 탐지 장치다. 적대적 로컬 사용자를 경계로 삼는다면 ACL·서명·별도 신뢰 저장소가 추가로 필요하다.
