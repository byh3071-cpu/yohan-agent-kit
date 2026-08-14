# PRD — Yohan Agent Kit

> 정본: `RULES.md`, `skills/`, `distribution/`, `.claude-plugin/marketplace.json`, `plugins/`

## 1. 제품 정의

Yohan Agent Kit은 두 배포 표면을 한 Git 이력에서 관리한다.

1. Codex·Cursor·Claude Code·Antigravity가 공유하는 범용 개인 스킬의 원문·무결성 manifest·Windows 설치 자동화
2. Claude Code 전용 스킬·서브에이전트·훅·명령·MCP를 묶는 기존 플러그인 마켓플레이스

범용 스킬은 레포 루트 `skills/<name>/`이 정본이며, Claude 플러그인은 `plugins/`가 정본이다. 두 표면은 같은 이름의 파일을 중복 복사하지 않는다.

## 2. 해결하는 문제

- 사용자 홈의 제품별 스킬 사본이 서로 달라지고 어느 것이 최신인지 알 수 없다.
- 새 PC·새 CLI에 설치가 누락되어도 “배포 완료”로 오인한다.
- 기존 파일을 정본으로 덮어쓸 때 사용자의 미수집 변경을 잃을 수 있다.
- VHK 규칙 동기화와 사용자 스킬 설치의 책임이 섞여 있다.
- Claude Code 플러그인 자산을 유지하면서도 다른 벤더가 같은 워크플로를 써야 한다.

## 3. 목표

1. 범용 스킬을 Git에서 리뷰하고 전체 디렉터리 manifest로 drift를 검출한다.
2. Check를 완전 읽기 전용으로 제공한다.
3. 사용자 홈 쓰기 승인과 최신 PlanDigest가 있을 때만 동일본을 백업·junction 또는 출처가 봉인된 생성 어댑터로 전환한다.
4. 정확한 BackupId와 경로·transaction·junction·adapter 소유권 검증으로 설치 전 상태를 복원하고, 커밋 전 Install과 중단된 Restore를 재개한다.
5. 자동·명시·부정 호출 계약과 사람 승인 게이트를 스킬 원문에 고정한다.
6. 기존 Claude Code 플러그인 마켓플레이스 구조와 이력을 보존한다.

## 4. 범위

### 포함

- `adr-cycle`: 되돌리기 비싼 결정의 Proposed 초안·검토·수명주기·goal-cycle 악수
- `goal-cycle`: 승인된 결정 아래 12단계 개발 목표 흐름과 S/M/L 라우팅
- Codex UI 메타데이터 `agents/openai.yaml`
- 전체 파일 manifest baseline
- PowerShell 5.1 Check·Install·Restore
- Codex·Cursor 공용, Claude Code, Antigravity 표준 발견 경로
- 실측 실패 증거가 있을 때만 `~/.gemini/skills`에 배포하는 Antigravity CLI 물리 생성 어댑터
- 기존 Claude Code 플러그인·마켓플레이스

### 제외

- 일반 ChatGPT 웹·데스크톱 대화와 Codex Cloud의 로컬 스킬 자동 발견
- 원격 Orca 호스트와 다른 사용자 프로필의 자동 배포
- 기존 dirty checkout의 이동·삭제·덮어쓰기
- 사용자 승인 없는 전역 홈 쓰기
- main/master 자동 머지

## 5. 사용자 흐름

### 5.1 결정에서 구현까지

```text
대화·인박스
  → 되돌리기 비용 분류
  → [필요 시] adr-cycle: Proposed → 사람 승인 → Accepted
  → goal-cycle: 조사→스펙→설계→티켓→승인
  → S 직접 | M 서브에이전트 | L + 실행 공급자 상태
  → 만들기→검증→검수→품질확인→PR
  → 사람 머지판정→지켜보기→다듬기
```

L 실행 공급자는 안정 배포 정책과 현재 관측값으로 `orca-ready`·`native-approved`·`plan-only`·`blocked` 중 하나를 고른다. Orca 선택 실패는 네이티브 실행 승인이 아니며 자동 폴백하지 않는다.

### 5.2 로컬 배포

```text
Git 정본 + baseline manifest
  → Check(읽기 전용)
  → Healthy | Installable | Conflict | SourceInvalid | RecoveryRequired
  → 사람 홈 쓰기 승인 + PlanDigest
  → backup transaction → junction·조건부 adapter → post-Check
  → 필요 시 BackupId preflight → 사람 승인 → Restore
```

## 6. 성공 조건

- 두 스킬의 frontmatter·참조·UI 메타데이터가 구조 검증을 통과한다.
- `skills/**`가 OS와 무관하게 LF 바이트를 유지하고 baseline manifest와 일치한다.
- 테스트 HomeRoot에서 Check→Install→Check→Restore가 결정론적으로 통과한다.
- 내용 drift, ignored 파일, 동일 stat의 tracked 파일 변조, stale PlanDigest, 승인 누락, 활성 중복, 부모·목적지 reparse 탈출, transaction·backup 변조, junction 교체, adapter 변조, 근거 없거나 만료된 AGY fallback이 무변경 실패한다.
- Check 전후 Git index 바이트와 수정 시각이 같고, 커밋 전 Install과 `RestorePending`을 포함한 부분 Restore가 exact BackupId로 재개된다.
- `Restored`는 recoverySeal과 실제 원상태가 모두 맞을 때만 no-op이며, junction 소유 지문은 NTFS file ID를 포함한다.
- schema 4 transaction은 junction을 staging에서 만들고 identity를 선저널링한 뒤 active leaf로 원자 이동한다. AGY adapter는 source path·commit·digest·CLI version을 기록하고 전체 digest를 봉인하며, 제거 대신 transaction 내부로 이동한다. schema 3 transaction은 기존 경로 계약과 seal로 계속 복원한다.
- 같은 HomeRoot의 Install·Restore는 named mutex로 직렬화하고 transaction JSON 갱신은 non-null backup을 둔 `File.Replace`로 원자 교체한다.
- Install 두 번째 실행과 Restore 두 번째 실행은 추가 백업 없는 no-op이다.
- PR 전 시크릿 검사와 변경 파일 검토를 통과한다.

## 7. 운영 불변식

- VHK sync는 `RULES.md`에서 AGENTS·Cursor 규칙을 생성할 뿐 사용자 홈 스킬을 설치하지 않는다.
- 자동 호출은 모델 판단이며 사람 게이트를 대체하지 않는다.
- 새 ADR은 `Proposed`로 시작하고 승인 전 결정 의존 구현을 금지한다.
- 내용이 다른 기존 사본은 승인 플래그가 있어도 덮어쓰지 않는다.
- AGY fallback은 24시간 안의 새 세션에서 표준 경로 발견 실패를 실측하고, 도구가 직접 읽은 현재 `agy --version`과 JSON boolean·round-trip timestamp가 모두 유효할 때만 `~/.gemini/skills` 물리 어댑터를 허용한다. 실패한 이전 `~/.gemini/antigravity-cli/skills` junction은 같은 승인 transaction에서 이관한다.
- 플러그인 manifest 변경 시 marketplace mirror 정합을 유지한다.

## 8. 검증 명령

```powershell
python <SKILL_CREATOR_ROOT>\scripts\quick_validate.py skills\adr-cycle
python <SKILL_CREATOR_ROOT>\scripts\quick_validate.py skills\goal-cycle
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests\Manage-MultivendorSkills.Tests.ps1
```

첫 두 명령의 skill-creator 설치 경로는 개발 호스트별로 다를 수 있으며 제품 배포 계약이 아니다. 배포 도구 자체는 특정 PC 절대경로를 사용하지 않는다.
