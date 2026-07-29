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

`distribution/manifests/<name>.json`은 모든 일반 파일의 상대 경로·바이트·SHA-256과 정렬된 전체 digest를 고정한다. 타임스탬프·ACL은 제외하고, 추가·누락·줄바꿈 차이는 drift로 본다. 스킬 내부 reparse point와 대소문자 충돌은 거부한다.

## 4. 배포 대상 모델

```text
skills/<name> (Git 정본)
  ├─junction─▶ ~/.agents/skills/<name>          Codex + Cursor
  ├─junction─▶ ~/.claude/skills/<name>          Claude Code
  ├─junction─▶ ~/.gemini/config/skills/<name>   Antigravity 표준
  └─조건부───▶ ~/.gemini/antigravity-cli/skills/<name>
```

`~/.codex/skills`, `~/.cursor/skills`, `~/.gemini/skills`의 같은 이름 사본은 활성 중복 후보로 읽기 전용 검사한다. 정본과 동일할 때만 Install이 backup transaction으로 발견 루트 밖에 이동한다. 내용이 다르면 Conflict다.

Antigravity CLI fallback은 별도 소비자 표면으로 취급한다. 표준 경로에서 새 세션 발견에 실패했다는 호스트·버전·manifest 결합 증거가 유효할 때만 표준 앱 경로와 공존할 수 있다.

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

### 5.2 Install

```text
Check 재계산
  → 사용자 홈 쓰기 승인 + 같은 PlanDigest
  → transaction=Executing 기록
  → 동일 디렉터리 backup / legacy junction 제거
  → canonical junction 생성
  → post-Check=Healthy
  → transaction=Committed
```

실패하면 변경 항목을 역순 rollback한다. rollback 실패는 `RecoveryRequired`로 기록하며 새 Install을 막는다. Healthy 상태의 Install은 백업 없는 no-op이다.

### 5.3 Restore

```text
정확한 BackupId
  → backup manifest + 현재 junction preflight
  → Restore PlanDigest
  → 사용자 홈 쓰기 승인
  → 자신이 만든 junction만 제거
  → 원래 Absent / Directory / Junction 복원
  → transaction=Restored
```

백업은 자동 삭제하지 않는다. 두 번째 Restore는 no-op이다.

## 6. ADR과 goal 악수

```text
되돌리기 비싼 미확정 결정
  → adr-cycle
  → Proposed ──사람 승인──▶ Accepted
  → {ADR 경로, 결정, 제약, 후속 작업, 위험}
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
- 격리 HomeRoot 상태 전이 테스트: `tests/Manage-MultivendorSkills.Tests.ps1`
- full manifest baseline Check
- PR 전 시크릿 검사와 staged diff 검토
- 새 벤더 세션의 자동·명시·부정 호출 smoke test

실제 사용자 홈 Install·Restore와 새 벤더 세션 검증은 각각 사람 승인과 제품 세션이 필요한 외부 게이트다.
