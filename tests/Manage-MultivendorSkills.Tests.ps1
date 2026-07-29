#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolPath = Join-Path $repoRoot 'scripts\Manage-MultivendorSkills.ps1'
$fixtureRoot = Join-Path $PSScriptRoot ".work\run-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
$script:assertionCount = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:assertionCount++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:assertionCount++
    if ([string]$Expected -cne [string]$Actual) {
        throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function Invoke-Manager {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $baseArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $toolPath,
        '-RepositoryRoot', $repoRoot,
        '-OutputFormat', 'Json'
    )
    $output = @(& powershell @baseArguments @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    try {
        $data = [string]$text | ConvertFrom-Json
    }
    catch {
        throw "Manager returned invalid JSON (exit=$exitCode): $text"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Raw = $text }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Get-TreeSignature {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $root = (Resolve-Path -LiteralPath $Directory).Path
    $rows = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        "$relative|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    } | Sort-Object)
    return [string]::Join("`n", $rows)
}

try {
    $emptyHome = Join-Path $fixtureRoot 'empty-home'
    $check = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'All', '-HomeRoot', $emptyHome)
    Assert-Equal -Expected 2 -Actual $check.ExitCode -Message 'Missing targets must be installable'
    Assert-Equal -Expected 'Installable' -Actual $check.Data.status -Message 'Missing target status'
    Assert-Equal -Expected 6 -Actual @($check.Data.targets | Where-Object { $_.action -eq 'CreateJunction' }).Count -Message 'Three canonical junctions per skill'
    Assert-True -Condition (-not [IO.Directory]::Exists($emptyHome)) -Message 'Check must not create HomeRoot'

    $stale = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'All', '-HomeRoot', $emptyHome, '-PlanDigest', ('0' * 64), '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 3 -Actual $stale.ExitCode -Message 'Stale plan must fail'
    Assert-True -Condition ($stale.Data.error -match 'stale or mismatched') -Message 'Stale plan error must be explicit'
    Assert-True -Condition (-not [IO.Directory]::Exists($emptyHome)) -Message 'Rejected install must not write'

    $install = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'All', '-HomeRoot', $emptyHome, '-PlanDigest', [string]$check.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $install.ExitCode -Message 'Approved install must pass'
    Assert-Equal -Expected 'Committed' -Actual $install.Data.status -Message 'Install transaction status'
    Assert-True -Condition ([string]$install.Data.backupId -match '^\d{8}-\d{9}-[a-f0-9]{8}$') -Message 'BackupId must be exact and opaque'

    $healthy = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'All', '-HomeRoot', $emptyHome)
    Assert-Equal -Expected 0 -Actual $healthy.ExitCode -Message 'Installed targets must be healthy'
    Assert-Equal -Expected 'Healthy' -Actual $healthy.Data.status -Message 'Healthy status after install'
    Assert-Equal -Expected 0 -Actual @($healthy.Data.targets | Where-Object { $_.action -ne 'None' }).Count -Message 'Healthy Check has no actions'
    $backupRoot = Join-Path $emptyHome '.yohan-skill-backups'
    $backupCount = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force).Count

    $secondInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'All', '-HomeRoot', $emptyHome, '-PlanDigest', [string]$healthy.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $secondInstall.ExitCode -Message 'Second install must pass'
    Assert-Equal -Expected 'NoOp' -Actual $secondInstall.Data.status -Message 'Second install must be no-op'
    Assert-Equal -Expected $backupCount -Actual @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force).Count -Message 'No-op install must not add backup'

    $restoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $emptyHome, '-BackupId', [string]$install.Data.backupId)
    Assert-Equal -Expected 0 -Actual $restoreCheck.ExitCode -Message 'Committed backup must be restorable'
    Assert-Equal -Expected 'RestoreReady' -Actual $restoreCheck.Data.status -Message 'Restore preflight status'

    $unapprovedRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $emptyHome, '-BackupId', [string]$install.Data.backupId, '-PlanDigest', [string]$restoreCheck.Data.planDigest)
    Assert-Equal -Expected 3 -Actual $unapprovedRestore.ExitCode -Message 'Restore without approval must fail'
    $stillHealthy = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'All', '-HomeRoot', $emptyHome)
    Assert-Equal -Expected 'Healthy' -Actual $stillHealthy.Data.status -Message 'Rejected restore must not change targets'

    $restore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $emptyHome, '-BackupId', [string]$install.Data.backupId, '-PlanDigest', [string]$restoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $restore.ExitCode -Message 'Approved restore must pass'
    Assert-Equal -Expected 'Restored' -Actual $restore.Data.status -Message 'Restore status'
    $postRestore = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'All', '-HomeRoot', $emptyHome)
    Assert-Equal -Expected 'Installable' -Actual $postRestore.Data.status -Message 'Absent pre-install state must be restored'
    $secondRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $emptyHome, '-BackupId', [string]$install.Data.backupId)
    Assert-Equal -Expected 0 -Actual $secondRestore.ExitCode -Message 'Second restore must be idempotent'
    Assert-Equal -Expected 'NoOp' -Actual $secondRestore.Data.status -Message 'Second restore no-op status'

    $conflictHome = Join-Path $fixtureRoot 'conflict-home'
    $conflictPath = Join-Path $conflictHome '.claude\skills\goal-cycle'
    $null = New-Item -ItemType Directory -Path $conflictPath -Force
    $conflictFile = Join-Path $conflictPath 'SKILL.md'
    Write-Utf8NoBom -Path $conflictFile -Text "---`nname: goal-cycle`ndescription: drift`n---`n"
    $beforeConflictHash = (Get-FileHash -LiteralPath $conflictFile -Algorithm SHA256).Hash
    $conflict = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $conflictHome)
    Assert-Equal -Expected 3 -Actual $conflict.ExitCode -Message 'Drift must fail Check'
    Assert-Equal -Expected 'Conflict' -Actual $conflict.Data.status -Message 'Drift status'
    Assert-True -Condition (@($conflict.Data.errors | Where-Object { $_ -match 'Manifest mismatch' }).Count -gt 0) -Message 'Drift paths must be reported'
    $blockedInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'goal-cycle', '-HomeRoot', $conflictHome, '-PlanDigest', [string]$conflict.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 3 -Actual $blockedInstall.ExitCode -Message 'Conflict must block Install'
    Assert-Equal -Expected $beforeConflictHash -Actual (Get-FileHash -LiteralPath $conflictFile -Algorithm SHA256).Hash -Message 'Conflict content must remain unchanged'
    Assert-True -Condition (-not [IO.Directory]::Exists((Join-Path $conflictHome '.agents'))) -Message 'Blocked Install must not create other targets'

    $fallbackHome = Join-Path $fixtureRoot 'fallback-home'
    $missingEvidence = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback')
    Assert-Equal -Expected 3 -Actual $missingEvidence.ExitCode -Message 'AGY fallback without evidence must fail'
    Assert-Equal -Expected 'Conflict' -Actual $missingEvidence.Data.status -Message 'Missing evidence status'

    $evidenceDirectory = Join-Path $fixtureRoot 'agy-evidence'
    $null = New-Item -ItemType Directory -Path $evidenceDirectory -Force
    $goalSource = @($check.Data.sources | Where-Object { $_.skill -eq 'goal-cycle' })[0]
    $evidence = [pscustomobject][ordered]@{
        schemaVersion = 1
        host = [string]$env:COMPUTERNAME
        agyVersion = 'test-1.0'
        skill = 'goal-cycle'
        sourceDigest = [string]$goalSource.manifest.digest
        standardPath = Join-Path $fallbackHome '.gemini\config\skills\goal-cycle'
        testedAt = [DateTimeOffset]::Now.ToString('o')
        newSession = $true
        standardDiscovered = $false
    }
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $validFallback = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory)
    Assert-Equal -Expected 2 -Actual $validFallback.ExitCode -Message 'Valid negative evidence permits fallback plan'
    Assert-Equal -Expected 'Installable' -Actual $validFallback.Data.status -Message 'Valid fallback status'
    Assert-Equal -Expected 'CreateJunction' -Actual (@($validFallback.Data.targets | Where-Object { $_.role -eq 'AgyCliFallback' })[0].action) -Message 'Fallback action with valid evidence'

    $legacyHome = Join-Path $fixtureRoot 'legacy-home'
    $legacyParent = Join-Path $legacyHome '.cursor\skills'
    $legacyPath = Join-Path $legacyParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $legacyParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $legacyPath -Recurse
    $legacyCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $legacyHome)
    Assert-Equal -Expected 2 -Actual $legacyCheck.ExitCode -Message 'Identical legacy copy is migratable'
    Assert-Equal -Expected 'BackupOnly' -Actual (@($legacyCheck.Data.targets | Where-Object { $_.role -eq 'CursorLegacy' })[0].action) -Message 'Legacy migration action'
    $legacyInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $legacyHome, '-PlanDigest', [string]$legacyCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $legacyInstall.ExitCode -Message 'Legacy migration install'
    Assert-True -Condition (-not [IO.Directory]::Exists($legacyPath)) -Message 'Legacy active duplicate must leave discovery root'
    $legacyRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $legacyHome, '-BackupId', [string]$legacyInstall.Data.backupId)
    $legacyRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $legacyHome, '-BackupId', [string]$legacyInstall.Data.backupId, '-PlanDigest', [string]$legacyRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $legacyRestore.ExitCode -Message 'Legacy restore'
    Assert-True -Condition ([IO.Directory]::Exists($legacyPath)) -Message 'Legacy directory must be restored byte-for-byte'
    Assert-Equal -Expected (Get-TreeSignature -Directory (Join-Path $repoRoot 'skills\adr-cycle')) -Actual (Get-TreeSignature -Directory $legacyPath) -Message 'Legacy directory manifest after Restore'

    Write-Output "PASS: $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "FAIL after $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 1
}
