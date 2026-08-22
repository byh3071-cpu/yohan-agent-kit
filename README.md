# Yohan Agent Kit

요한의 **멀티벤더 범용 스킬 Git 정본**이자 기존 **Claude Code 플러그인 마켓플레이스**다. 범용 스킬은 Codex·Cursor·Claude Code·Antigravity가 같은 원문을 읽고, Claude 전용 훅·명령·에이전트 번들은 기존 `plugins/`에서 독립적으로 유지한다.

GitHub 정본은 `byh3071-cpu/yohan-agent-kit`이다. 첫 호환 릴리스 동안 Claude Marketplace namespace `yohan-cc-skills`와 `@yohan-cc-skills` 설치 suffix는 유지한다. 전체 전환 순서와 롤백은 [Yohan Agent Kit 이름 전환](docs/YOHAN_AGENT_KIT_MIGRATION.md)을 따른다.

## 왜 레포인가
에이전트 스킬은 사용자 홈의 제품별 경로에 설치되므로 수동 복사만으로는 정본·리뷰·복원이 보장되지 않는다.

- Git의 `skills/<name>/`이 원문 정본이다.
- 사용자 홈의 표준 경로에는 정본을 가리키는 directory junction을 둔다. AGY CLI 1.1.8처럼 junction을 실제로 발견하지 못하는 소비자에는 출처가 봉인된 물리 생성 어댑터만 예외로 둔다.
- 전체 파일 manifest로 추가·누락·내용 drift를 검사한다.
- 설치 전 백업과 exact BackupId·transaction seal·NTFS 파일 ID 기반 junction 객체 지문·생성 어댑터 해시를 검증하는 재개 가능한 복원을 제공한다.
- 다른 PC와 원격 Orca 호스트는 각 호스트에서 별도로 설치·검증한다.

일반 ChatGPT 웹·데스크톱 대화와 Codex Cloud는 로컬 사용자 홈 스킬을 자동으로 읽지 않는다.

## 범용 스킬

| 스킬 | 책임 |
|---|---|
| `adr-cycle` | 되돌리기 비싼 결정의 조사·Proposed 초안·검토·대체·폐기와 사람 승인 게이트 |
| `design-to-html` | 승인한 시각 원본을 반응형 HTML로 구현하고 같은 상태 디자인 QA까지 검증 |
| `goal-cycle` | 승인된 결정 아래 조사→스펙→설계→티켓→구현→검증→검수→품질확인→PR→관찰·개선 |

자동 호출은 모델 판단이므로 100% 강제되지 않는다. 확실한 호출은 **“adr-cycle로 …”**, **“design-to-html로 …”**, **“goal-cycle로 …”**처럼 벤더 공통 자연어를 사용한다. 새 PC 설치·검증 순서는 [HTML 디자인 환경 인계](docs/DESIGN_TO_HTML_HANDOFF.md)를 따른다.

### 읽기 전용 검사

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 -Mode Check -Skill All
```

Check는 사용자 홈과 Git index를 바꾸지 않는다. `Installable`이면 exit code 2와 `PlanDigest`를, 충돌이면 exit code 3과 다른 상대 경로를 반환한다. 중단된 Install은 반환된 exact `BackupId`로 복구 계획을 다시 만들 수 있다. 실제 Install·Restore는 사용자 홈 쓰기이므로 실행 직전 별도 사람 승인이 필요하다.

### 정본 밖 자산 탐지

사용자 홈(`.agents`·`.claude`·`.codex`·`.cursor`)에 설치됐지만 `registry/assets.yaml`에 없는 스킬을 찾는다. 읽기 전용이며 미등록이 있으면 exit code 2를 반환한다.

```powershell
powershell -NoProfile -NonInteractive -File scripts\Get-AgentAssetDrift.ps1
powershell -NoProfile -NonInteractive -File scripts\Get-AgentAssetDrift.ps1 -NewOnly
```

`-NewOnly`는 기준선에 없는 신규만 보고한다. 기준선은 `~/.yohan-agent-kit/asset-drift-baseline.json`이며 `-UpdateBaseline`을 명시할 때만 갱신된다(유일한 쓰기 동작). `-OutputFormat Hook`은 Claude Code 훅 계약에 맞춘 JSON을 내보내며 신규가 없으면 조용히 통과한다. 탐지된 자산을 정본으로 올리는 경로는 [노하우 Intake](docs/AGENT_KIT_INTAKE.md)를 따르고, 승격 상한은 `reviewed`다.

### 외부 스킬 복원

남이 만든 스킬은 파일을 정본으로 복사하지 않는다. 원본 저장소가 정본이고 킷은 **출처·커밋·라이선스만** `registry/assets.yaml`에 `external://` 자산으로 기록한다. 업스트림 갱신 경로를 끊지 않기 위해서다. 새 머신에서는 레지스트리를 읽어 재설치한다.

```powershell
powershell -NoProfile -NonInteractive -File scripts\Restore-ExternalSkills.ps1
powershell -NoProfile -NonInteractive -File scripts\Restore-ExternalSkills.ps1 -ApproveInstall
```

인자 없이 실행하면 출처 저장소별로 묶은 설치 계획만 출력하고 exit code 2를 반환한다(읽기 전용). 실제 설치는 `-ApproveInstall`을 명시할 때만 수행한다. 목록은 하드코딩하지 않고 레지스트리에서 만들므로 등록이 늘면 복원 범위도 함께 늘어난다. `-Owner`로 한 저장소만, `-Agent`로 대상 에이전트를 좁힐 수 있다(기본 `claude-code`).

설치되는 내용은 각 저장소의 **현재 기본 브랜치**이며 레지스트리에 적힌 SHA로 고정되지 않는다. SHA는 등록 시점에 대조한 기록이므로, 업스트림이 바뀌었는지 확인할 좌표로 쓴다.

SessionEnd 훅의 timeout 상한은 다음 읽기 전용 검사로 확인한다. 인자를 생략하면 yohan-core의 hooks.json을 검사하며, 명시 파일은 **-Path**, 여러 플러그인을 찾을 루트는 **-RecursePath**에 전달한다. 재귀 검사는 reparse point를 따라가지 않고 이름이 hooks.json인 파일만 읽는다.

```powershell
powershell -NoProfile -NonInteractive -File scripts\Test-SessionEndTimeout.ps1
powershell -NoProfile -NonInteractive -File scripts\Test-SessionEndTimeout.ps1 `
  -Path plugins\yohan-core\hooks\hooks.json
powershell -NoProfile -NonInteractive -File scripts\Test-SessionEndTimeout.ps1 `
  -RecursePath plugins
powershell -NoProfile -NonInteractive -File tests\Test-SessionEndTimeout.Tests.ps1
```

모든 SessionEnd timeout은 0초보다 크고 3초 이하여야 한다. JSON 파싱 실패, 잘못된 timeout, 검사 대상 부재는 exit code 1이며 JSON 원문·command·파서 예외 내용은 출력하지 않는다.

```powershell
# 승인 뒤에만 직전 Check의 PlanDigest를 사용한다.
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Install -Skill All -PlanDigest <CHECK_DIGEST> -ApproveGlobalHomeWrite

# 정확한 BackupId를 먼저 Check한 뒤 복원한다.
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check -BackupId <BACKUP_ID>
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Restore -BackupId <BACKUP_ID> -PlanDigest <RESTORE_DIGEST> -ApproveGlobalHomeWrite
```

내용이 정본과 다르면 승인 플래그가 있어도 덮어쓰지 않는다. 자세한 경로·상태·AGY fallback 계약은 [멀티벤더 스킬 배포](docs/MULTIVENDOR_SKILL_DISTRIBUTION.md)를 따른다.

## 버전 고정 Agent Kit 릴리스

개별 Skill junction과 별도로, 검증된 commit에서 다섯 패키지(Agent Plugins·Claude Code·Codex·Cursor·Antigravity)를 만들고 동일 release ID로 활성화한다. v0.1의 필수 게이트는 집 PC 단일 머신 final evidence이며, 노트북 비교는 첫 실제 사용 시 수행하는 후속 검증이다. Antigravity 공유 플러그인은 단순 junction이 아니라 공식 `agy plugin install`로 등록하며, release manager가 물리 디렉터리의 전체 digest와 `agy plugin list` 등록 상태를 함께 검증한다. Check가 출력한 `AntigravityCommandDigest`는 해석된 네이티브 `agy.exe`의 경로·명령 형식·파일 SHA-256을 묶는다. Antigravity를 바꾸는 Install·Update·Restore에는 `PlanDigest`와 함께 바로 앞 Check의 이 값을 전달해야 한다.

```powershell
node .\scripts\Build-AgentKit.mjs --release v0.1.0-<short-sha> --output-root dist\releases
.\scripts\Manage-AgentKit.ps1 -Mode Check -Release <id> -Targets All
.\scripts\Manage-AgentKit.ps1 -Mode Install -Release <id> -Targets All `
  -PlanDigest <digest> -AntigravityCommandDigest <agy-digest> `
  -ApproveGlobalHomeWrite
```

`dist/`는 생성 결과이고 정본이 아니다. 신규 노하우는 자동 push하지 않으며 로컬 Inbox에서 검사·검토한 뒤 승인된 Draft PR로 승격한다. 자세한 계약은 [릴리스 저장소](docs/AGENT_KIT_RELEASES.md), [노하우 Intake](docs/AGENT_KIT_INTAKE.md), [집 PC·네 벤더 검증](docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md)을 따른다.

## Claude Code 플러그인을 새 머신에 설치
GitHub 에 push 된 뒤:
```
claude plugin marketplace add byh3071-cpu/yohan-agent-kit
claude plugin install statusline@yohan-cc-skills
```
또는 `~/.claude/settings.json` 에 직접:
```json
"extraKnownMarketplaces": {
  "yohan-cc-skills": { "source": { "source": "github", "repo": "byh3071-cpu/yohan-agent-kit" } }
},
"enabledPlugins": { "statusline@yohan-cc-skills": true }
```
설치 후 상태줄 세팅:
```
/setup-statusline
```

## 수록 Claude Code 플러그인

> 열거·버전 SoT는 `.claude-plugin/marketplace.json` + 각 `plugin.json`. 아래 표는 그 미러다(하드코딩 버전 금지).

| 플러그인 | 구성 | 내용 |
|---|---|---|
| `yohan-core` | 스킬 10 · 서브에이전트 6 · 훅 9 · MCP | 모든 레포에 상속되는 공통 두뇌. 스킬(cc-docs·cost-guard·cross-check·cursor-docs·naver-convert·**plan-audit**·ship-it·studio-post·yohan-writing·youtube-summary) + 서브에이전트(explorer·planner·critic·shipper·prd-generator·prd-validator) + 보안/포맷/세션로그·라우팅미스감지 훅 + yohan-voice 출력스타일 + yohan MCP(Notion) |
| `statusline` | `/setup-statusline` | Windows PowerShell 상태줄 배포 + settings.json 병합. ctx 1M 자동감지, tok=실작업량(cache_read 제외), caveman 태그 머지, UTF-8 출력 |
| `workflow` | 스킬 7 | 반복 작업 워크플로 묶음 (아래 표) |
| `critical-thinking` | `/critical` · skeptic | 비판적 사고 모드 — 소크라테스식 질문·CoVe 자가검증·steelman-attack으로 아첨·할루시네이션 억제. `/critical lite\|full\|ultra\|auto\|off` 토글 + critical-thinking 스킬 + skeptic 서브에이전트. 대화·추론 시점 담당(코드용 critic과 분리). 기본 OFF 옵트인 |

### `workflow` 스킬 (7)
| 스킬 | 내용 |
|---|---|
| `/release-gate` | 머지·publish 전 게이트(tsc→eslint→build)+테스트+적대적 리뷰를 문제 0까지, PR→머지→태그. 사람몫(2FA)만 스킵 |
| `/dogfood-crosscheck` | VHK 독푸딩 → CC 독립분석 교차대조 → 도구결함 vs 앱버그 분류 → 이슈 초안 |
| `/visualize` | 디자인 시안 5~6개(단일 HTML) / 결과·버전비교 HTML 보고서(두괄식·비개발자용) |
| `/handoff` | **채팅 종료 검증** scan/close(기본)/full — 재고(문서·적재·갱신·핸드오프·Goal·git·브랜치) + 안전 조치 + 전달프롬프트 |
| `/new-repo` | 새 GitHub 레포 생성 + 그룹 자동분류 + repos.json 등록·push → 멀티PC 같은 폴더 자동 정리 |
| `/parallel` | 병렬·동시 작업 시 worktree 자동 격리(생성·작업·정리) → 충돌 0. worktree 몰라도 됨 |
| `/overnight-autoloop` | 무인 야간 결함 발굴→수정→검증→PR 루프(머지 금지). run 간 이월 + 같은 파일 배칭 |

## 구조
```
.claude-plugin/marketplace.json        # 마켓플레이스 매니페스트 (플러그인 4종)
skills/
  adr-cycle/                           # 범용 ADR 워크플로 정본
  design-to-html/                      # 승인 시각 원본의 반응형 HTML 구현·디자인 QA
  goal-cycle/                          # 범용 개발 목표 워크플로 정본
distribution/manifests/               # 스킬 전체 파일 manifest
scripts/Manage-MultivendorSkills.ps1   # Check · Install · Restore
tests/Manage-MultivendorSkills.Tests.ps1
registry/assets.yaml                   # 자산 Registry 정본
registry/release-bundles.json          # 패키지·호환 버전 계약
adapters/                              # Claude/Codex/Cursor/Antigravity 어댑터
scripts/Build-AgentKit.mjs             # 불변 release artifact 생성
scripts/Manage-AgentKit.ps1            # release Check · Install · Update · Restore
scripts/Manage-AgentIntake.ps1         # 로컬 Inbox 후보 수집·검토
scripts/Test-AgentKitCompatibility.ps1 # 집 PC 증거 봉인·검증, 선택적 멀티 머신 비교
plugins/
  yohan-core/                          # 공통 코어 "두뇌"
    .claude-plugin/plugin.json
    CLAUDE.md · .mcp.json · loop.md
    agents/ · commands/ · hooks/ · output-styles/ · references/ · skills/
  statusline/
    .claude-plugin/plugin.json
    skills/setup-statusline/
      SKILL.md                         # 배포·병합·검증 절차 + 인코딩 불변식
      assets/statusline.ps1            # 배포되는 실제 스크립트(검증본)
  workflow/                            # 워크플로 스킬 7종
    .claude-plugin/plugin.json
    skills/{release-gate,dogfood-crosscheck,visualize,handoff,new-repo,parallel,overnight-autoloop}/
  critical-thinking/                   # 비판적 사고 모드 (기본 OFF 옵트인)
    .claude-plugin/plugin.json
    agents/skeptic.md · commands/critical.md · skills/critical-thinking/
```

## 향후 추가 후보
작업 패턴 분석(history 618프롬프트/76세션 기준)에서 나온 반복 작업을 스킬로 추가 예정. (별도 분석 결과 참조)
