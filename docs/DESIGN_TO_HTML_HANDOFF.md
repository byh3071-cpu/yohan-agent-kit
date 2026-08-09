# HTML 디자인 환경 인계

## 결론

HTML 요청은 `design-to-html` 스킬이 **작업 컨텍스트 요약 → 구현 → 같은 상태 시각 비교 → 검증 리포트** 순서로 처리해. 스킬·규칙·레퍼런스는 Git으로 두 PC에 맞추고, junction·Product Design 사용자 컨텍스트·플러그인은 각 PC에서 따로 설치하고 검사해. 한 번 설치해도 다음 작업 전에는 읽기 전용 환경 검사로 상태를 확인해.

## 세 가지 운영 약속

### 1. 원하는 HTML

시각 원본과 요청 의도를 먼저 고정해. SoT 충돌은 아래 우선순위로 해결하고, 낮은 순위가 높은 순위를 덮지 못해.

1. 현재 요청
2. 프로젝트 Git
3. yohan-brain 디자인 컨텍스트
4. Notion view

구현 전에는 아래 `WorkContext`를 **작업 컨텍스트 요약**으로 먼저 보여줘.

```markdown
## 작업 컨텍스트 요약
- goal:
- user and target screen:
- approved visual source:
- selected source of truth:
- applicable project rules:
- acceptance criteria:
```

그다음 아래 기준을 모두 통과해야 결과를 넘겨.

- 승인한 이미지·스크린샷·Figma·HTML 시안을 시각 원본으로 고정
- 360·432·768·1280·1440px 반응형과 가로 overflow 확인
- 본문 16px·보조 텍스트 14px, 텍스트 대비 WCAG AA 확인
- CSS 그림·직접 그린 SVG·이모지 대용품이 아닌 실제 아이콘 라이브러리 사용
- 탭·메뉴·입력·펼침·선택 상태를 실제로 동작하게 구현
- 브라우저 console error 0건과 인터랙티브 컨트롤의 keyboard path 기록
- 원본과 구현을 같은 viewport·같은 UI 상태로 비교
- P0·P1은 모두 해결하고 P2는 남은 이유를 기록
- 승인한 시각 원본과 최종 evidence를 project Git에 보존
- `design-qa.md` 마지막 줄이 정확히 `final result: passed`인지 확인
- 통과 뒤에만 viewport·상태 비교·미해결 항목·commit SHA를 담은 **검증 리포트** 전달

### 2. 노트북과 집 PC의 같은 결과

Git에는 PC 경로가 없는 `skills/design-to-html/`, 디자인 규칙, 승인 레퍼런스만 둬. 각 PC는 이 Git 정본을 junction으로 Codex·Claude Code·agents 계열 발견 경로에 연결해. `design-to-html`은 멀티벤더 공통 스킬이고, `Manage-ProductDesignContext.ps1`이 만드는 사용자 컨텍스트는 Codex Product Design 전용 어댑터야.

Product Design 사용자 컨텍스트에는 해당 PC의 yohan-brain 절대경로가 들어가. 생성 파일 `.codex/state/plugins/product-design/user-context.md`와 소유권 기록 `.yohan-product-design-context.transaction.json`은 PC 로컬 상태로만 유지하고 Git·OneDrive에 넣지 마.

플러그인도 PC별로 설치해. 환경 검사기는 아래 검증 계약 버전이 그 PC에 실제로 있는지 확인해. 계약 버전과 더 최신 버전이 함께 있으면 warning만 남기고, 최신 버전만 있고 계약 버전이 없으면 `Drift`야. 이 값은 **최신 버전 목록이 아니라 검증한 계약**이야.

| 플러그인 | 검증한 버전 |
| --- | --- |
| `product-design` | `0.1.52` |
| `yohan-core` | `0.3.22` |
| `workflow` | `0.3.9` |

### 3. 새 세션과 다른 벤더의 자동 시작

아래처럼 요청하면 `design-to-html`을 명시적으로 호출할 수 있어.

- `design-to-html로 HTML 만들어줘`
- `이 시안 HTML로 구현해`
- `이 화면을 반응형 프로토타입으로 만들어줘`
- `visualize에서 고른 안을 완성해`

스킬은 현재 요청, 가장 가까운 프로젝트 규칙, 관련 Git·yohan-brain SoT, 승인한 시각 원본, 현재 벤더의 Product Design·browser·frontend-design 같은 실행 어댑터, 품질 게이트를 작업에 맞게 조립해.

시각 원본이 없으면 구현을 멈추고 시각 탐색부터 해. 원본끼리 충돌하면 임의로 섞지 말고 어떤 원본을 우선할지 확인해. 완료 기준을 바꿀 정도로 요청이 모호해도 작업 컨텍스트 요약 단계에서 멈춰.

## PC별 설치 순서

아래 절차를 **노트북과 집 PC에서 각각 한 번씩** 실행해. `<...>` 대신 승인한 실제 값과 그 PC의 로컬 경로를 넣어.

### A. 두 Git 정본 맞추기

```powershell
$skillsRoot = '<THIS_PC_SKILLS_REPO_PATH>'
$brainRoot = '<THIS_PC_BRAIN_REPO_PATH>'
$userHome = [Environment]::GetFolderPath('UserProfile')
$skillsRepo = '<SKILLS_REPO_URL>'
$brainRepo = '<BRAIN_REPO_URL>'
$skillsBranch = '<APPROVED_SKILLS_BRANCH>'
$brainBranch = '<APPROVED_BRAIN_BRANCH>'
$skillsSha = '<APPROVED_SKILLS_COMMIT_SHA>'
$brainSha = '<APPROVED_BRAIN_COMMIT_SHA>'
$gitApplications = @(Get-Command git.exe -CommandType Application -ErrorAction Stop)
if ($gitApplications.Count -lt 1) { throw 'git.exe application was not found' }
$gitCommand = [string]$gitApplications[0].Source

function Invoke-GitChecked {
  param([Parameter(Mandatory = $true)][string[]]$GitArguments)

  & $gitCommand @GitArguments
  $gitExitCode = $LASTEXITCODE
  if ($gitExitCode -ne 0) { throw "git failed with exit code $gitExitCode" }
}

if (Test-Path -LiteralPath (Join-Path $skillsRoot '.git')) {
  Invoke-GitChecked -GitArguments @('-C', $skillsRoot, 'fetch', 'origin')
  Invoke-GitChecked -GitArguments @('-C', $skillsRoot, 'switch', $skillsBranch)
  Invoke-GitChecked -GitArguments @('-C', $skillsRoot, 'pull', '--ff-only', 'origin', $skillsBranch)
} else {
  Invoke-GitChecked -GitArguments @('clone', '--branch', $skillsBranch, $skillsRepo, $skillsRoot)
}

if (Test-Path -LiteralPath (Join-Path $brainRoot '.git')) {
  Invoke-GitChecked -GitArguments @('-C', $brainRoot, 'fetch', 'origin')
  Invoke-GitChecked -GitArguments @('-C', $brainRoot, 'switch', $brainBranch)
  Invoke-GitChecked -GitArguments @('-C', $brainRoot, 'pull', '--ff-only', 'origin', $brainBranch)
} else {
  Invoke-GitChecked -GitArguments @('clone', '--branch', $brainBranch, $brainRepo, $brainRoot)
}

$skillsWorktreeState = @(Invoke-GitChecked -GitArguments @('-C', $skillsRoot, 'status', '--porcelain=v1', '--untracked-files=all'))
$brainWorktreeState = @(Invoke-GitChecked -GitArguments @('-C', $brainRoot, 'status', '--porcelain=v1', '--untracked-files=all'))
if ($skillsWorktreeState.Count -ne 0) { throw 'skills worktree is not clean' }
if ($brainWorktreeState.Count -ne 0) { throw 'brain worktree is not clean' }

$actualSkillsSha = ([string](Invoke-GitChecked -GitArguments @('-C', $skillsRoot, 'rev-parse', 'HEAD'))).Trim()
$actualBrainSha = ([string](Invoke-GitChecked -GitArguments @('-C', $brainRoot, 'rev-parse', 'HEAD'))).Trim()
if ($actualSkillsSha -ne $skillsSha) { throw 'skills SHA mismatch' }
if ($actualBrainSha -ne $brainSha) { throw 'brain SHA mismatch' }
```

각 저장소는 `.git` 존재 여부에 따라 clone 또는 fetch·switch·pull 중 하나만 실행해. 모든 native Git 명령은 exit code가 0이 아니면 즉시 중단해. 두 저장소 모두 승인 branch·SHA와 clean worktree가 확인돼야 다음 단계로 가. tracked·untracked 변경이 하나라도 있으면 yohan-brain 어댑터가 승인 commit과 다른 working-tree bytes를 읽을 수 있으므로 중단해.

### B. 환경 사전 검사

```powershell
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $skillsRoot

$preflightJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Test-DesignToHtmlEnvironment.ps1 `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$preflightExitCode = $LASTEXITCODE
if ($preflightExitCode -notin @(0, 2, 3)) {
  throw "Environment preflight returned unexpected exit code $preflightExitCode"
}

$preflightState = [string]::Join("`n", @($preflightJson)) | ConvertFrom-Json
$expectedPreflightExit = @{ Healthy = 0; Missing = 2; Drift = 3 }
if (-not $expectedPreflightExit.ContainsKey([string]$preflightState.status)) {
  throw 'Environment preflight returned an unknown status'
}
if ([int]$preflightState.exitCode -ne $preflightExitCode -or
    $preflightExitCode -ne [int]$expectedPreflightExit[[string]$preflightState.status]) {
  throw 'Environment preflight status and exit code do not match'
}

$driftEvidence = @($preflightState.drift)
$unsafeEvidence = @(
  @($preflightState.brainFiles) | Where-Object { [string]$_.state -eq 'Unsafe' }
  @($preflightState.plugins) | Where-Object { [string]$_.state -eq 'Unsafe' }
  $driftEvidence | Where-Object { [string]$_.code -eq 'UnsafePath' }
)
if ($preflightState.status -eq 'Drift' -or
    $driftEvidence.Count -gt 0 -or
    $unsafeEvidence.Count -gt 0) {
  throw 'Environment preflight contains drift or Unsafe evidence'
}

$missingEvidence = @($preflightState.missing)
$brainMissing = @($missingEvidence | Where-Object { [string]$_.category -eq 'brain' })
$requiredSkillMissing = @($missingEvidence | Where-Object {
  [string]$_.category -eq 'skill' -and [string]$_.name -eq 'design-to-html'
})
$unexpectedMissing = @($missingEvidence | Where-Object {
  -not ([string]$_.category -eq 'skill' -and [string]$_.name -eq 'design-to-html')
})
if ($brainMissing.Count -gt 0) {
  throw 'Required Brain evidence is missing; fix the approved Brain Git or path before C or D'
}

if ($preflightState.status -eq 'Missing') {
  if ($missingEvidence.Count -ne 1 -or
      $requiredSkillMissing.Count -ne 1 -or
      $unexpectedMissing.Count -gt 0) {
    throw 'Missing evidence is not exactly skill:design-to-html'
  }
  Write-Output 'Preflight: Missing without drift or Unsafe; run C as needed and then D'
} else {
  if ($missingEvidence.Count -ne 0) { throw 'Healthy preflight contains unexpected missing evidence' }
  Write-Output 'Preflight: Healthy; skip C install and continue with D'
}
$preflightJson
```

| exit | 상태 | 다음 행동 |
| ---: | --- | --- |
| 0 | `Healthy` | `drift`·`Unsafe` 0건을 확인하고 C 설치는 생략, D Check는 실행 |
| 2 | `Missing` | 정확히 `skill:design-to-html` 한 건일 때만 C 실행 후 D Check. Brain·기타 누락은 중단 |
| 3 | `Drift` | 항상 중단하고 충돌·버전·경로부터 해결 |

환경 검사기는 `Missing`을 `Drift`보다 먼저 전체 상태로 선택해. 그래서 exit 2만 보고 진행하면 안 되고 JSON의 `drift`·`missing` 배열과 모든 `Unsafe` 상태를 항상 별도로 확인해야 해. Brain 누락은 승인한 Brain Git·경로부터 고친 뒤 B를 다시 실행하고 C·D로 넘어가지 마. 알 수 없거나 추가된 누락도 중단해. D의 읽기 전용 Check는 환경 상태와 무관하게 항상 실행해. 환경 검사기와 Product Design 컨텍스트 어댑터의 공개 JSON은 로컬 절대경로를 내보내지 않는 path-neutral 결과야.

환경 검사기의 exit 0 `Healthy`는 차단되는 skill·Brain drift가 없다는 뜻이야. PC 로컬 캐시에서 검증 계약 버전을 감지하지 못하면 JSON `plugins` 항목은 `MissingCapability` warning이지만 전체 상태는 여전히 `Healthy`일 수 있어. 이 상태만으로 설치 여부를 단정할 수 없고, 검증 계약 버전의 설치·사용 가능성을 확인할 수 없어 완료할 수 없어. 전체 PC 동등성은 세 플러그인의 `state`가 각각 `Tested` 또는 `TestedWithNewerAvailable`인지 별도로 확인해야 해. `TestedWithNewerAvailable`은 검증 계약 버전과 더 최신 버전이 함께 있는 warning이고, 최신 버전만 있고 계약 버전이 없으면 `Drift`야.

이 환경 검사기는 Product Design 사용자 컨텍스트와 transaction을 검사하지 않아. Product Design 사용자 컨텍스트 무결성은 D·E의 별도 Check로 확인해.

2026-08-09 사전 검증 당시 노트북은 `design-to-html` junction 한 건이 빠져 전체 `Missing`으로 판정됐어. yohan-brain 필수 문서와 검증 계약 버전은 확인됐지만, 이 기록은 최종 상태도 설치 완료 기록도 아니야.

### C. 멀티벤더 스킬 연결

Check는 읽기 전용이고 `Installable`일 때 exit 2가 정상이다. 출력된 `PlanDigest`를 사람이 확인한 뒤 같은 값을 Install에 넣어.

```powershell
Set-Location -LiteralPath $skillsRoot
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check `
  -Skill design-to-html `
  -HomeRoot $userHome

$skillPlanDigest = '<PLAN_DIGEST_FROM_IMMEDIATELY_PRECEDING_CHECK>'
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Install `
  -Skill design-to-html `
  -HomeRoot $userHome `
  -PlanDigest $skillPlanDigest `
  -ApproveGlobalHomeWrite

powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-MultivendorSkills.ps1 `
  -Mode Check `
  -Skill design-to-html `
  -HomeRoot $userHome
```

마지막 Check가 `Healthy`가 아니면 D로 넘어가지 마. 스킬 복원은 Install이 반환한 exact `BackupId`가 필요하니 [멀티벤더 스킬 배포 계약](MULTIVENDOR_SKILL_DISTRIBUTION.md)을 따라.

### D. Codex Product Design 컨텍스트 연결

이 어댑터는 yohan-brain의 두 문서를 읽어 PC 로컬 사용자 컨텍스트를 만들어. 환경 검사 결과와 무관하게 D의 읽기 전용 Check는 항상 실행해. `Healthy + owned`면 Install 없이 E로 가고, `Installable`일 때만 `PlanDigest`를 사람이 확인한 뒤 승인 Install해. `Conflict`·`Unsafe`·unowned는 중단하고 덮어쓰지 마.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $skillsRoot

$contextCheckJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Check `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$contextCheckExitCode = $LASTEXITCODE
if ($contextCheckExitCode -notin @(0, 2, 3)) {
  throw "Product Design context Check returned unexpected exit code $contextCheckExitCode"
}

$contextCheckState = [string]::Join("`n", @($contextCheckJson)) | ConvertFrom-Json
if ([int]$contextCheckState.exitCode -ne $contextCheckExitCode) {
  throw 'Product Design context status and exit code do not match'
}

$contextNeedsInstall = $false
if ($contextCheckState.status -eq 'Healthy') {
  if ($contextCheckExitCode -ne 0 -or -not [bool]$contextCheckState.owned) {
    throw 'Healthy Product Design context is not owned'
  }
  Write-Output 'Product Design context: Healthy and owned; skip Install and continue with E'
} elseif ($contextCheckState.status -eq 'Installable') {
  if ($contextCheckExitCode -ne 2 -or [string]$contextCheckState.planDigest -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'Installable Product Design context has an invalid plan'
  }
  $contextPlanDigest = [string]$contextCheckState.planDigest
  $contextNeedsInstall = $true
  Write-Output "Review PlanDigest before approval: $contextPlanDigest"
} else {
  throw 'Product Design context is Conflict, Unsafe, or unowned; do not overwrite'
}
$contextCheckJson
```

`$contextNeedsInstall`이 `$false`면 아래 Install block을 실행하지 말고 E로 가. `$true`면 출력된 `PlanDigest`를 사람이 확인하고 사용자 홈 쓰기를 별도로 승인한 뒤, **같은 PowerShell session에서만** 아래 block을 실행해.

```powershell
if (-not $contextNeedsInstall -or $contextCheckState.status -ne 'Installable') {
  throw 'Install is allowed only after an Installable Check in this session'
}

$contextInstallJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Install `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -PlanDigest $contextPlanDigest `
  -ApproveGlobalHomeWrite `
  -OutputFormat Json
$contextInstallExitCode = $LASTEXITCODE
if ($contextInstallExitCode -ne 0) {
  throw "Product Design context Install failed with exit code $contextInstallExitCode"
}

$postContextJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Check `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$postContextExitCode = $LASTEXITCODE
$postContextState = [string]::Join("`n", @($postContextJson)) | ConvertFrom-Json
if ($postContextExitCode -ne 0 -or
    $postContextState.status -ne 'Healthy' -or
    -not [bool]$postContextState.owned) {
  throw 'Post-install Product Design context Check failed'
}
$contextInstallJson
$postContextJson
```

복원할 때는 `BackupId`를 쓰지 않아. Restore는 도구가 소유한 상태를 설치 전으로 되돌리려는 의도가 분명할 때만 실행해. fresh Check가 `owned = true`이고 상태가 `Healthy` 또는 `Conflict`일 때만 그 결과의 새 `PlanDigest`를 사용할 수 있어. `Unsafe`·unowned에는 Restore하지 마.

```powershell
Set-Location -LiteralPath $skillsRoot
$restoreCheckJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Check `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$restoreCheckExitCode = $LASTEXITCODE
if ($restoreCheckExitCode -notin @(0, 3)) {
  throw "Restore Check returned unexpected exit code $restoreCheckExitCode"
}
$restoreCheckState = [string]::Join("`n", @($restoreCheckJson)) | ConvertFrom-Json
$expectedRestoreCheckExit = @{ Healthy = 0; Conflict = 3 }
if (-not $expectedRestoreCheckExit.ContainsKey([string]$restoreCheckState.status) -or
    [int]$restoreCheckState.exitCode -ne $restoreCheckExitCode -or
    $restoreCheckExitCode -ne [int]$expectedRestoreCheckExit[[string]$restoreCheckState.status]) {
  throw 'Restore Check status and exit code do not match'
}
if (-not [bool]$restoreCheckState.owned -or
    $restoreCheckState.status -notin @('Healthy', 'Conflict') -or
    [string]$restoreCheckState.planDigest -notmatch '^[A-Fa-f0-9]{64}$') {
  throw 'Restore is allowed only for an owned Healthy or Conflict state'
}
$restorePlanDigest = [string]$restoreCheckState.planDigest
Write-Output "Review owned Restore PlanDigest before approval: $restorePlanDigest"
```

사람이 설치 전 상태로 되돌릴 의도와 `PlanDigest`를 확인하고 사용자 홈 쓰기를 별도로 승인한 뒤, 같은 PowerShell session에서만 실행해.

```powershell
if (-not [bool]$restoreCheckState.owned -or $restoreCheckState.status -notin @('Healthy', 'Conflict')) {
  throw 'Restore approval is not bound to an owned Check'
}
$restoreJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Restore `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -PlanDigest $restorePlanDigest `
  -ApproveGlobalHomeWrite `
  -OutputFormat Json
$restoreExitCode = $LASTEXITCODE
if ($restoreExitCode -ne 0) { throw "Restore failed with exit code $restoreExitCode" }
$restoreJson
```

`-ApproveGlobalHomeWrite`는 Install·Restore처럼 사용자 홈을 바꾸는 명령에만 붙여. Check에는 붙이지 마.

### E. 플러그인과 최종 검사

`product-design`, `yohan-core`, `workflow`는 각 PC의 Codex 플러그인 관리자에서 설치해. 특정 CLI를 가정하지 마. 마지막에는 Product Design 사용자 컨텍스트와 전체 환경을 각각 검사하고 JSON 증거를 함께 판정해.

```powershell
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $skillsRoot

$finalContextJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Manage-ProductDesignContext.ps1 `
  -Mode Check `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$finalContextExitCode = $LASTEXITCODE
if ($finalContextExitCode -ne 0) { throw "Product Design context Check failed with exit code $finalContextExitCode" }
$finalContextState = [string]::Join("`n", @($finalContextJson)) | ConvertFrom-Json
if ($finalContextState.status -ne 'Healthy' -or -not [bool]$finalContextState.owned) {
  throw 'Product Design context is not Healthy and owned'
}

$finalEnvironmentJson = & powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\Test-DesignToHtmlEnvironment.ps1 `
  -BrainRoot $brainRoot `
  -HomeRoot $userHome `
  -OutputFormat Json
$finalEnvironmentExitCode = $LASTEXITCODE
if ($finalEnvironmentExitCode -ne 0) { throw "Environment Check failed with exit code $finalEnvironmentExitCode" }
$finalEnvironmentState = [string]::Join("`n", @($finalEnvironmentJson)) | ConvertFrom-Json
if ($finalEnvironmentState.status -ne 'Healthy') { throw 'Environment is not Healthy' }

$allowedPluginStates = @('Tested', 'TestedWithNewerAvailable')
$finalPlugins = @($finalEnvironmentState.plugins)
$invalidPlugins = @($finalPlugins | Where-Object { [string]$_.state -notin $allowedPluginStates })
if ($finalPlugins.Count -ne 3 -or $invalidPlugins.Count -ne 0) {
  throw 'Tested plugin contract is not available'
}

$finalContextJson
$finalEnvironmentJson
```

전체 상태가 exit 0 `Healthy`이고 JSON `plugins`의 세 항목이 각각 `Tested` 또는 `TestedWithNewerAvailable`일 때만 두 PC가 전체 계약을 만족한다고 기록해. `MissingCapability`가 하나라도 있으면 검증 계약 버전의 설치·사용 가능성을 확인할 수 없어 완료로 보지 마.

## 상태와 동기화 경계

| 상태 계층 | 예시 | 동기화 방법 | 충돌 판정 주체 |
| --- | --- | --- | --- |
| Git SoT | `skills/design-to-html/`, 규칙, 승인 레퍼런스 | 승인 branch·SHA를 commit·push·pull | Git과 리뷰된 commit |
| PC 로컬 생성 상태 | 제품별 skill junction, Product Design 사용자 컨텍스트·transaction | 각 PC에서 Check → 승인 → Install/Restore | 배포 manager와 컨텍스트 어댑터 |
| PC 로컬 플러그인 캐시 | `product-design`, `yohan-core`, `workflow` | 각 PC의 Codex 플러그인 관리자 | 환경 검사기의 검증 계약 |

Git SoT만 PC 사이에 동기화해. 생성 상태와 플러그인 캐시는 복사·클라우드 동기화하지 말고 각 PC에서 다시 검사하고 설치해.

## Conflict와 Drift 처리

`Conflict`나 `Drift`가 나오면 덮어쓰지 말고 바로 멈춰.

1. 두 Git 저장소를 승인 branch·SHA로 먼저 pull해.
2. 같은 Check를 다시 실행해.
3. 계속 충돌하면 도구가 소유한 상태만 fresh Check의 digest로 Restore해. 다른 내용은 수동 삭제하지 마.
4. 플러그인 버전 불일치는 해당 PC의 Codex 플러그인 관리자에서 검증 계약 버전이 존재하게 한 뒤 다시 검사해. 최신 버전만 있고 계약 버전이 없으면 `Drift`가 유지돼.
5. 새 Install은 다시 받은 PlanDigest와 별도 사람 승인을 사용해.

## 두 PC 작업 규칙

같은 branch는 첫 PC에서 작업을 commit·push한 뒤 두 번째 PC에서 pull하고 이어가. 동시에 작업해야 하면 PC별로 서로 다른 branch나 worktree를 사용해. 같은 branch·같은 파일을 두 PC에서 동시에 수정하지 마.

### 노트북 최소 체크리스트

- 노트북 로컬 경로를 `$skillsRoot`, `$brainRoot`, `$userHome`에 넣음
- 두 Git 정본의 승인 branch·SHA 일치
- 사전 환경 Check 실행
- C Check → `Healthy`면 생략, `Installable`이면 승인 Install → Check
- D 항상 Check → `Healthy + owned`면 설치 생략, `Installable`이면 승인 Install → Check
- PC별 플러그인 계약 확인 뒤 최종 환경 Check가 `Healthy`

### 집 PC 최소 체크리스트

- 집 PC 로컬 경로를 `$skillsRoot`, `$brainRoot`, `$userHome`에 넣음
- 두 Git 정본의 승인 branch·SHA 일치
- 사전 환경 Check 실행
- C Check → `Healthy`면 생략, `Installable`이면 승인 Install → Check
- D 항상 Check → `Healthy + owned`면 설치 생략, `Installable`이면 승인 Install → Check
- PC별 플러그인 계약 확인 뒤 최종 환경 Check가 `Healthy`
