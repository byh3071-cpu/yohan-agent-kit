# yohan-cc-skills

요한의 **멀티벤더 범용 스킬 Git 정본**이자 기존 **Claude Code 플러그인 마켓플레이스**다. 범용 스킬은 Codex·Cursor·Claude Code·Antigravity가 같은 원문을 읽고, Claude 전용 훅·명령·에이전트 번들은 기존 `plugins/`에서 독립적으로 유지한다.

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
| `goal-cycle` | 승인된 결정 아래 조사→스펙→설계→티켓→구현→검증→검수→품질확인→PR→관찰·개선 |

자동 호출은 모델 판단이므로 100% 강제되지 않는다. 확실한 호출은 **“adr-cycle로 …”**, **“goal-cycle로 …”**처럼 벤더 공통 자연어를 사용한다.

### 읽기 전용 검사

```powershell
powershell -NoProfile -File scripts\Manage-MultivendorSkills.ps1 -Mode Check -Skill All
```

Check는 사용자 홈과 Git index를 바꾸지 않는다. `Installable`이면 exit code 2와 `PlanDigest`를, 충돌이면 exit code 3과 다른 상대 경로를 반환한다. 중단된 Install은 반환된 exact `BackupId`로 복구 계획을 다시 만들 수 있다. 실제 Install·Restore는 사용자 홈 쓰기이므로 실행 직전 별도 사람 승인이 필요하다.

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

## Claude Code 플러그인을 새 머신에 설치
GitHub 에 push 된 뒤:
```
claude plugin marketplace add byh3071-cpu/yohan-cc-skills
claude plugin install statusline@yohan-cc-skills
```
또는 `~/.claude/settings.json` 에 직접:
```json
"extraKnownMarketplaces": {
  "yohan-cc-skills": { "source": { "source": "github", "repo": "byh3071-cpu/yohan-cc-skills" } }
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
  goal-cycle/                          # 범용 개발 목표 워크플로 정본
distribution/manifests/               # 스킬 전체 파일 manifest
scripts/Manage-MultivendorSkills.ps1   # Check · Install · Restore
tests/Manage-MultivendorSkills.Tests.ps1
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
