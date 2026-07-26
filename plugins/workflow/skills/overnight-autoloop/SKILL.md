---
name: overnight-autoloop
description: "Use when 요한 wants an unattended autonomous overnight run that finds, fixes, and PRs code defects on the yohan ecosystem repos. Triggers: '자는 동안 돌려', '자는 동안 goal', '오토파일럿 밤새', '무인 결함루프', '자율 수정 돌려', '밤새 고쳐놔', 'overnight loop', 'autonomous fix loop'."
---

# Overnight Autoloop

## Overview
요한이 자는 동안 무인으로 코드 결함을 **감사발굴→진단→수정→검증+적대리뷰→PR(머지 X)** 한 바퀴 돌리고 아침에 머지권고만 보고. 엔진은 Workflow 스크립트(`autoloop.workflow.js`), 이 스킬은 파라미터 수집 + 런칭 + 아침 보고 담당.

**되돌리기 어려운 것 전면 금지**(머지·close·force-push·외부데이터 재적재·노션쓰기). LLM 은 수정·검증만, 머지 결정은 아침에 사람.

run 간 연속성 2종 (2026-07-04 실전 2회에서 역설계):
- **이월(carry-over)**: 미시도(deferred) 결함을 `deferredPath` JSON 파일에 최신 상태로 overwrite 저장(시도분 제거)하고, 다음 run Discover 가 발굴 결과에 선주입 → 발굴 비결정성 제거(run1 미시도 med 2건이 run2 에서 재발굴 안 되던 문제).
- **배칭(batching)**: evidence/title 에서 같은 파일 경로를 공유하는 결함들은 1그룹=1브랜치=1PR (같은 호출부 수정 2건이 PR 2개로 나가 두 번째가 리베이스 충돌 나던 문제). 경로 추출은 보수적 — 확신 없으면 안 묶음. **`capPRs` 는 그룹(=PR) 수 기준**.

## When to Use
- 트리거 문구(위 description) 나오면 발동.
- 무인으로 결함을 고쳐 PR까지 만들어두고 싶을 때.
**When NOT:** 대형 기능 구현·설계판단 필요 작업(무인 부적합) · 단일 버그 즉시수정(그냥 고쳐라).

## Launch Steps
1. **파라미터를 런치층에서 완전히 확정** (`AskUserQuestion`) — 필수 3(scope·repos·capPRs) + 이월 2(deferredPath·resumeDeferred). 사용자가 "알아서"라 하면 아래 기본값을 **명시적으로 확정해 args 에 실어 전달**한다(스크립트에 기본값 없음 — 아래 ⚠️. 유일한 예외: resumeDeferred 만 스크립트에 문서화된 명시 기본 true):
   - **scope**: `audit`(감사발굴, 기본) | `github`(열린 이슈) | `both`
   - **repos**: 기본 `[{name:'yohan-mcp',path:'C:/Users/Public/dev/yohan-ecosystem/yohan-mcp',kind:'python'}, {name:'control-tower',path:'C:/Users/Public/dev/yohan-ecosystem/yohan-control-tower',kind:'next'}]`. 다르면 `{name,path,kind}` 배열. **런칭 전 각 path 실재 확인**(`Test-Path`) — 없는 경로 있으면 런칭 중단하고 사용자에게 확인 (머신마다 레포 위치 다를 수 있음). ⚠️ **vhk 금지** — vhk ADR-007 이 Workflow 자동 push 오케스트레이션을 금지한다(스크립트도 name/path 로 차단·즉사). vhk 는 수동 `vhk-auto` 계약으로.
   - **capPRs**: 해결 시도 상한(기본 6, 양의 정수) — **단위=그룹(=브랜치=PR)**. 같은 파일 공유 결함은 1그룹으로 배칭되므로 실제 수정 결함 수는 cap 보다 많을 수 있음. 나머지는 발굴목록만.
   - **deferredPath** (선택이지만 **기본 포함 권장**): 미시도 결함 이월 파일의 **절대경로**. 기본 `C:/Users/Public/dev/yohan-ecosystem/yohan-brain/docs/audits/overnight-deferred.json` (주레포=yohan-brain, 아침보고 저장처와 같은 폴더). **미전달 = 이월 전체 비활성** — 스크립트가 `[이월] deferredPath 미전달 — 이월 비활성` 1줄 로그 후 저장·주입 모두 스킵(silent 아님). 이월 없으면 미시도가 다음 run 에 안 넘어가 발굴이 비결정적으로 돌아감. 런칭 전 상위 폴더 실재 확인(`Test-Path`).
   - **resumeDeferred** (선택, 명시 기본 `true` — 미전달=true 는 스크립트에 문서화된 기본값): 이전 run 이월분을 발굴에 선주입할지. `false` 는 **주입만** 끔 — 이번 run 미시도 **저장은 deferredPath 만 있으면 항상 수행**(비대칭 게이팅)하고, 미주입 이월분은 저장 시 대기열에 그대로 보존(유실 없음, 이번 run 큐와 중복되는 건만 새 것으로 대체). 이번 run 만 이월 무시하고 순수 새 발굴을 원할 때 false.
2. **scriptPath 절대경로 해석 + CRLF 안전 사본 (필수 선행)**: 엔진은 이 스킬과 같은 폴더의 `autoloop.workflow.js` (논리 경로 `${CLAUDE_PLUGIN_ROOT}/skills/overnight-autoloop/autoloop.workflow.js`). ⚠️ **Workflow tool 은 `${CLAUDE_PLUGIN_ROOT}` 를 확장하지 않는다** — 리터럴로 넘기면 파일 못 찾고 죽는다. 반드시 절대경로로 풀어서 전달:
   - Glob `~/.claude/plugins/cache/yohan-cc-skills/workflow/*/skills/overnight-autoloop/autoloop.workflow.js` → 매칭 경로 사용 (복수면 최신 버전 디렉터리).
   - 매칭 0건이면 중단하고 사용자에게 `/plugin update` 요청 (구버전 플러그인).
   - **Windows 플러그인 캐시 CRLF 대응**: Glob 으로 찾은 `$src` 를 scratchpad LF 사본 `$dst` 로 복사한 뒤 **Workflow `scriptPath`에는 `$dst`만** 전달한다 (원본 `$src` 직접 전달 금지 — Workflow 가 CR control character 거부).
     - PowerShell 예: `$dst = Join-Path $env:TEMP "autoloop-lf-$(Get-Date -Format yyyyMMdd-HHmmss).js"; Get-Content -Raw $src | ForEach-Object { $_ -replace "`r", '' } | Set-Content -NoNewline $dst -Encoding utf8`
3. **Workflow 런칭**: `Workflow({ scriptPath: "<2에서 만든 LF scratchpad 절대경로>", args: { scope, repos, capPRs, deferredPath, resumeDeferred } })`. 백그라운드 완주 후 알림. (이월을 의도적으로 안 쓸 때만 deferredPath 생략.)
   - ⚠️ **args 미전달/불완전이면 스크립트가 즉사한다**(silent fallback 금지, 7/1 오실행 재발방지). 기본값 폴백은 이제 스크립트가 아니라 **이 런치층 책임** — "알아서"여도 반드시 완전한 `{scope,repos,capPRs,deferredPath}` 를 만들어 넘길 것.
   - ✅ **args 전달 확인**: 진행로그 첫 줄에 `[params ✓] scope=… · capPRs=… · repos=… · deferredPath=… · resumeDeferred=…` 가 떠야 정상. 이 줄이 없거나 workflow 가 `[overnight-autoloop] 파라미터 검증 실패` 로 죽으면 = Workflow args 하네스 버그 재현 → 하드코딩 args 로 재런칭(임시) + blockers 기록.
4. 사용자에게 "가동 + 자도 됨" 1줄 + 안전요약 보고.

## On Completion (알림 턴)
- 워크플로 반환 `report_md` 를 `<주레포>/docs/audits/overnight-<날짜>.md` 로 저장(날짜는 알림 시점 stamp).
- `summary`(PR수·로컬커밋·park) + **PR별 머지권고**(권고/보류+근거)를 두괄식으로 보고. 배칭 PR(`results[].defects>1`)은 포함 결함 각각을 권고에 명시.
- **이월 파일은 워크플로가 직접 갱신**(deferredPath 전달 시): 미시도만 남긴 최신 상태로 overwrite 됨 — 아침에 따로 저장할 것 없음. 단 반환 `deferredFile.saved=false` 면 반환 `deferred` 원본으로 수동 저장 필요.
- **self-merge 주의**: 자동승인 분류기가 PR 생성/머지를 막을 수 있음(실측). 막힌 건 "로컬커밋(차단/대기)"로 표기되고 아침에 사람 탭 1회 필요.

## Quick Reference
| 항목 | 값 |
|---|---|
| 엔진 | `autoloop.workflow.js` (args 파라미터화) |
| 게이트 | 검증(pytest / typecheck+lint) + 적대리뷰 blocker 0 |
| 재시도 | 그룹(결함 1~n건)당 ≤3회, 초과 시 park |
| 밤 산출 | 브랜치 commit + (가능 시)push+PR. 머지 0 |
| 폴백 | push/PR 차단 시 로컬커밋까지 + 아침보고 |
| 이월 | `deferredPath` JSON — Report 에서 미시도 overwrite 저장(시도분 제거), 다음 run Discover 선주입(`resumeDeferred` 기본 true). 미전달=비활성(명시 로그) |
| 배칭 | evidence/title 파일 경로 공유 결함 → 1그룹=1브랜치=1PR. 보수적 추출(확신 없으면 안 묶음). `capPRs`=그룹 수 |

## Common Mistakes
- scriptPath 에 `${CLAUDE_PLUGIN_ROOT}` 리터럴 그대로 전달 → Workflow tool 은 변수 확장 안 함. Glob 으로 절대경로 해석 후 전달 (Launch Steps 2).
- Windows 플러그인 캐시 CRLF → Workflow CR control character 거부. Glob 원본 `$src` 직접 전달 금지, scratchpad LF 사본 `$dst` 만 scriptPath 에 전달 (Launch Steps 2).
- 파라미터 없이 바로 런칭 → scope/repos/cap 먼저 **런치층에서 완전 확정**해 args 로 전달(스크립트 기본값 폴백 없음, "알아서"여도 명시 확정).
- args 전달 확인 생략 → `[params ✓]` 로그 줄 확인 필수(안 뜨면 args 미도달 = 오실행 위험).
- deferredPath 생략 → 미시도 결함이 다음 run 에 이월 안 됨(매 run 비결정적 재발굴 — 7/4 실측: run1 미시도 med 2건이 run2 에서 증발). 특별한 이유 없으면 yohan-brain 경로를 항상 전달.
- 완료 보고를 chat 에만 → 반드시 `docs/audits/` 파일로도 떨굼(산출물 색인).
- 머지까지 자동 시도 → 금지. 권고만, 머지는 사람.
- 배칭 한계 인지: 파일 2개+ 언급하는 다중 파일 결함은 그룹핑에서 자동 제외(과병합 가드, 2026-07-05). 잔존 한계 — **서로 다른 디렉터리의 동일 비범용 basename**(예: `adapters/models.py` vs `core/db/models.py`)은 여전히 오묶일 수 있음. 그런 이름이 흔한 레포를 대상에 추가할 땐 아침 보고에서 그룹 구성을 확인할 것.

## 관련
범용 코어 독트린(되돌릴 수 없는 작업 4중 안전장치) = 글로벌 PAT-003. 메모리 `overnight-autoloop-spec` 와 동기화.
