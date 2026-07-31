# ARCHITECTURE — yohan-cc-skills

## 1. 세 평면

이 레포는 범용 스킬, Claude Code 플러그인, 프로젝트 규칙을 서로 다른 평면으로 관리한다.

```text
범용 스킬 평면                     Claude 플러그인 평면
skills/<name>/                     plugins/<plugin>/
  ├─ SKILL.md                        ├─ .claude-plugin/plugin.json
  ├─ references                     ├─ skills · agents · commands
  └─ agents/openai.yaml              └─ hooks · MCP · output styles
         │                                      │
distribution/manifests                         .claude-plugin/marketplace.json
         │
Manage-MultivendorSkills.ps1
         │
사용자 홈의 제품별 junction

규칙 평면
RULES.md ──vhk sync──▶ AGENTS.md · .cursorrules
```

VHK 규칙 평면은 사용자 홈 스킬을 설치하지 않는다. 범용 스킬은 Claude 플러그인 디렉터리에 중복 복사하지 않는다.

## 2. 디렉터리 구조

```text
yohan-cc-skills/
├─ skills/
│  ├─ adr-cycle/
│  │  ├─ SKILL.md
│  │  ├─ references/review-checklist.md
│  │  └─ agents/openai.yaml
│  └─ goal-cycle/
│     ├─ SKILL.md
│     ├─ reference.md
│     └─ agents/openai.yaml
├─ distribution/manifests/
│  ├─ adr-cycle.json
│  └─ goal-cycle.json
├─ scripts/Manage-MultivendorSkills.ps1
├─ tests/Manage-MultivendorSkills.Tests.ps1
├─ docs/
│  ├─ MULTIVENDOR_SKILL_DISTRIBUTION.md
│  ├─ audits/
│  ├─ patterns/
│  └─ state/
├─ .claude-plugin/marketplace.json
├─ plugins/                         # 기존 Claude Code 플러그인
├─ RULES.md                         # 생성 규칙 SoT
├─ AGENTS.md                        # 생성물
└─ .cursorrules                     # 생성물
```

## 3. 범용 스킬 정본

각 스킬은 다음 계약을 갖는다.

- `SKILL.md` frontmatter는 `name`·`description`만 둔다.
- description이 자동 호출의 주 라우팅 표면이며 명시·부정 호출 조건도 포함한다.
- 상세 자료는 SKILL에서 한 단계 상대 링크로 연결한다.
- `agents/openai.yaml`은 Codex UI 이름·짧은 설명·기본 프롬프트·implicit policy를 제공한다.
- 특정 PC 홈이나 Public/dev 절대경로를 런타임 계약에 넣지 않는다.
- `skills/**`는 Git에서 LF로 고정한다.

`distribution/manifests/<name>.json`은 모든 일반 파일의 상대 경로·바이트·SHA-256과 정렬된 전체 digest를 고정한다. 타임스탬프·ACL은 제외하고, 추가·누락·줄바꿈 차이는 drift로 본다. 스킬 내부 reparse point와 대소문자 충돌을 거부하고, 실제 파일이 모두 Git tracked인지 확인한 뒤 working blob을 index blob과 직접 비교한다. ignored 파일이나 같은 크기·수정 시각으로 위장한 변경도 정본에 섞이지 못한다.

## 4. 배포 대상 모델

```text
skills/<name> (Git 정본)
  ├─junction─▶ ~/.agents/skills/<name>          Codex + Cursor
  ├─junction─▶ ~/.claude/skills/<name>          Claude Code
  ├─junction─▶ ~/.gemini/config/skills/<name>   Antigravity 표준
  └─생성복사──▶ ~/.gemini/skills/<name>          AGY CLI 1.1.8 조건부
```

`~/.codex/skills`, `~/.cursor/skills`의 같은 이름 사본은 활성 중복 후보로 읽기 전용 검사한다. 정본과 동일할 때만 Install이 backup transaction으로 발견 루트 밖에 이동한다. `~/.gemini/skills`는 fallback을 끈 상태에서는 승인되지 않은 활성 경로로, fallback을 켠 상태에서는 출처 메타데이터와 전체 manifest가 일치하는 물리 어댑터로 판정한다. 내용이 다르면 Conflict다.

Antigravity CLI fallback은 별도 소비자 표면으로 취급한다. 표준 경로에서 새 세션 발견에 실패했다는 호스트·버전·manifest 결합 증거가 유효할 때만 표준 앱 경로와 공존할 수 있다. 실효성이 없었던 `~/.gemini/antigravity-cli/skills` junction은 schema 4 transaction의 이전 경로 이관 대상으로만 남긴다.

## 5. 상태기계

### 5.1 Check

```text
Source + Target snapshot
  ├─ all canonical junctions, no duplicate ─▶ Healthy(0)
  ├─ missing or identical directory        ─▶ Installable(2) + PlanDigest
  ├─ content/wrong link/file/evidence      ─▶ Conflict(3)
  ├─ source/frontmatter/Git drift          ─▶ SourceInvalid(3)
  └─ unfinished transaction                ─▶ RecoveryRequired(3)
```

Check는 stdout 외에 어떤 파일도 만들지 않는다.

대상·백업 경로는 문자열 prefix만 보지 않는다. 볼륨 루트부터 destination 부모까지 기존 reparse point가 없는지 확인해 junction 조상을 통한 허용 루트 탈출을 차단한다. 디렉터리 이동은 정확한 destination leaf만 허용하는 `Directory.Move`를 쓰며, junction 소유 지문에는 NTFS file ID를 포함한다. Git 검사는 optional index lock을 끄며 index 바이트와 수정 시각 무변경을 테스트한다.

### 5.2 Install

```text
Check 재계산
  → 사용자 홈 쓰기 승인 + 같은 PlanDigest
  → HomeRoot 전용 named mutex 획득
  → schema 4 transaction=Executing + installSeal 기록
  → junction: transaction staging 생성 + NTFS file ID 선저널링
  → AGY adapter: 정본+provenance 파일 생성 + 전체 digest 검증
  → 동일 디렉터리 backup / legacy junction 제거
  → staging junction·adapter를 active leaf로 원자 이동
  → post-Check=Healthy
  → commitSeal + transaction=Committed
```

transaction JSON은 첫 생성에 `File.Move`, 갱신에 같은 디렉터리 임시 파일과 명시적 backup 경로를 둔 `File.Replace`를 사용한다. 실패하면 변경 항목을 역순 rollback한다. backup은 이동 전·후 manifest를 검증하며, 변조된 backup은 활성 경로에 두지 않는다. rollback 실패는 `RecoveryRequired`로 기록하며 새 Install을 막는다. `Executing` 또는 commitSeal 없는 `RecoveryRequired`는 exact BackupId의 `InstallRollback` 경로로 복구한다. active·staging junction은 transaction에 미리 기록된 동일 NTFS file ID가 있을 때만 제거한다. AGY 물리 어댑터는 봉인된 digest가 일치할 때만 transaction 내부 removal 경로로 이동하며 재귀 삭제하지 않는다. schema 3 transaction은 기존 정의와 seal로 계속 복원한다. Healthy 상태의 Install은 백업 없는 no-op이다.

### 5.3 Restore

```text
정확한 BackupId
  → 입력에서 source·target·backup 경로 재계산
  → installSeal + [완료 설치면] commitSeal + backup manifest + junction 객체 지문·adapter digest preflight
  → Original | Installed | RestorePending | Conflict 판정
  → Restore PlanDigest
  → 사용자 홈 쓰기 승인
  → 자신이 만든 junction·adapter만 활성 경로에서 제거
  → 원래 Absent / Directory / Junction 복원
  → 실제 원상태 확인 + recoverySeal + transaction=Restored
```

Restore는 항목별 완료를 기록한다. 중단된 `Restoring`·`RecoveryRequired` 상태는 이미 원복된 항목과 junction 제거 뒤 backup만 남은 `RestorePending`을 식별해 재개할 수 있다. `Restored` 문자열만 신뢰하지 않고 recoverySeal과 실제 원상태를 다시 확인한다. 백업은 자동 삭제하지 않는다. 두 번째 Restore는 no-op이다.

## 6. ADR과 goal 악수

```text
되돌리기 비싼 미확정 결정
  → adr-cycle
  → Proposed ──사람 승인──▶ Accepted
  → {ADR 경로, 결정, 제약, 후속 작업, 미해결 위험, 남은 사람 게이트}
  → goal-cycle
  → S 직접 | M 서브에이전트 | L Orca
```

Proposed를 근거로 조사·계획할 수 있지만 결정 의존 구현은 금지한다. Orca와 `/goal`, `worker_done`, failover는 L 작업에서 현재 환경 계약이 제공할 때만 사용한다.

## 7. Claude Code 플러그인 평면

`.claude-plugin/marketplace.json`이 `plugins/` 아래 플러그인을 등록한다. 각 플러그인은 자체 `.claude-plugin/plugin.json`과 선택적 skills·agents·commands·hooks·MCP를 가진다.

- 플러그인 버전 SoT는 각 `plugin.json`이다.
- marketplace의 버전은 수동 mirror이므로 plugin manifest 변경과 함께 맞춘다.
- 범용 top-level 스킬 변경만으로 plugin 버전을 올리지 않는다.
- handoff·release-gate·parallel 등 Claude 전용 묶음은 `plugins/`에 남긴다.

## 8. 규칙 전파

```text
RULES.md
  └─ vhk sync
      ├─ AGENTS.md
      └─ .cursorrules
```

생성물을 직접 편집하지 않는다. 규칙 동기화 성공이 범용 스킬 설치 성공을 뜻하지 않으며, 사용자 홈 상태는 배포 도구의 Check로만 판정한다.

## 9. 검증

- skill-creator 구조 검증: 두 `SKILL.md`
- PowerShell 5.1 AST parser
- 격리 HomeRoot 상태 전이·경로 탈출·변조·복구 재개 테스트: `tests/Manage-MultivendorSkills.Tests.ps1`
- full manifest baseline Check
- PR 전 시크릿 검사와 staged diff 검토
- 새 벤더 세션의 자동·명시·부정 호출 smoke test

실제 사용자 홈 Install·Restore와 새 벤더 세션 검증은 각각 사람 승인과 제품 세션이 필요한 외부 게이트다.
