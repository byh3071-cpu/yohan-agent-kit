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
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$ManagerRepositoryRoot = $repoRoot
    )

    $baseArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $toolPath,
        '-RepositoryRoot', $ManagerRepositoryRoot,
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

function Get-TestSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Get-TestTransactionInstallSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = @(
        "schema=$($Transaction.schemaVersion)",
        "backupId=$($Transaction.backupId)",
        "createdAt=$($Transaction.createdAt)",
        "planDigest=$($Transaction.planDigest)",
        "homeRoot=$($Transaction.homeRoot)",
        "repositoryRoot=$($Transaction.repositoryRoot)",
        "selection=$($Transaction.selection)",
        "fallback=$($Transaction.includeAgyCliFallback)",
        "agyVersion=$($Transaction.agyCurrentVersion)"
    )
    foreach ($item in @($Transaction.items)) {
        $lines += "item|$($item.skill)|$($item.role)|$($item.action)|$($item.targetPath)|$($item.sourcePath)|$($item.sourceDigest)|$($item.originalKind)|$($item.originalTarget)|$($item.originalJunctionIdentity)|$($item.originalDigest)|$($item.backupPath)|$($item.junctionStagingPath)"
    }
    return Get-TestSha256Text -Text ([string]::Join("`n", $lines))
}

function Get-TestTransactionCommitSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = @("installSeal=$($Transaction.installSeal)")
    foreach ($item in @($Transaction.items)) {
        $lines += "item|$($item.skill)|$($item.role)|$($item.changed)|$($item.junctionPrepared)|$($item.createdJunction)|$($item.junctionIdentity)"
    }
    return Get-TestSha256Text -Text ([string]::Join("`n", $lines))
}

function Get-TestTransactionRecoverySeal {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$RecoveryKind
    )

    $baseSeal = if ($RecoveryKind -eq 'CommittedRestore') { [string]$Transaction.commitSeal } else { [string]$Transaction.installSeal }
    return Get-TestSha256Text -Text "recovery-v1|$RecoveryKind|$baseSeal"
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
    $agyFixtureBin = Join-Path $fixtureRoot 'agy-bin'
    $null = New-Item -ItemType Directory -Path $evidenceDirectory -Force
    $null = New-Item -ItemType Directory -Path $agyFixtureBin -Force
    $fakeAgyVersion = '9.9.9-test'
    Write-Utf8NoBom -Path (Join-Path $agyFixtureBin 'agy.cmd') -Text "@echo off`r`necho $fakeAgyVersion`r`n"
    $originalProcessPath = $env:PATH
    $env:PATH = "$agyFixtureBin;$originalProcessPath"
    $goalSource = @($check.Data.sources | Where-Object { $_.skill -eq 'goal-cycle' })[0]
    $evidence = [pscustomobject][ordered]@{
        schemaVersion = 1
        host = [string]$env:COMPUTERNAME
        agyVersion = $fakeAgyVersion
        skill = 'goal-cycle'
        sourceDigest = [string]$goalSource.manifest.digest
        standardPath = Join-Path $fallbackHome '.gemini\config\skills\goal-cycle'
        testedAt = [DateTimeOffset]::Now.ToString('o')
        newSession = $true
        standardDiscovered = $false
    }
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $validFallback = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', $fakeAgyVersion)
    Assert-Equal -Expected 2 -Actual $validFallback.ExitCode -Message 'Valid negative evidence permits fallback plan'
    Assert-Equal -Expected 'Installable' -Actual $validFallback.Data.status -Message 'Valid fallback status'
    Assert-Equal -Expected 'CreateJunction' -Actual (@($validFallback.Data.targets | Where-Object { $_.role -eq 'AgyCliFallback' })[0].action) -Message 'Fallback action with valid evidence'

    $evidence.testedAt = [DateTimeOffset]::Now.AddHours(-25).ToString('o')
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $staleEvidence = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', $fakeAgyVersion)
    Assert-Equal -Expected 3 -Actual $staleEvidence.ExitCode -Message 'Stale AGY evidence must fail'
    Assert-True -Condition (@($staleEvidence.Data.errors | Where-Object { $_ -match 'older than 24 hours' }).Count -gt 0) -Message 'Stale evidence reason'

    $evidence.testedAt = [DateTimeOffset]::Now.ToString('o')
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $versionEvidence = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', '9.9.8-test')
    Assert-Equal -Expected 3 -Actual $versionEvidence.ExitCode -Message 'AGY version mismatch must fail'
    Assert-True -Condition (@($versionEvidence.Data.errors | Where-Object { $_ -match 'does not match the installed agy CLI' }).Count -gt 0) -Message 'Installed CLI version mismatch reason'

    $evidence.agyVersion = '9.9.8-test'
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $evidenceVersionMismatch = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', $fakeAgyVersion)
    Assert-Equal -Expected 3 -Actual $evidenceVersionMismatch.ExitCode -Message 'Evidence version mismatch must fail'
    Assert-True -Condition (@($evidenceVersionMismatch.Data.errors | Where-Object { $_ -match 'evidence version' }).Count -gt 0) -Message 'Evidence version mismatch reason'

    $evidence.agyVersion = $fakeAgyVersion
    $evidence.testedAt = [DateTimeOffset]::Now.AddMinutes(6).ToString('o')
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $futureEvidence = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', $fakeAgyVersion)
    Assert-Equal -Expected 3 -Actual $futureEvidence.ExitCode -Message 'Future AGY evidence must fail'
    Assert-True -Condition (@($futureEvidence.Data.errors | Where-Object { $_ -match 'in the future' }).Count -gt 0) -Message 'Future evidence reason'

    $evidence.testedAt = [DateTimeOffset]::Now.ToString('o')
    $evidence.newSession = 'false'
    Write-Utf8NoBom -Path (Join-Path $evidenceDirectory 'goal-cycle.json') -Text ([string]($evidence | ConvertTo-Json -Depth 4))
    $booleanEvidence = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $fallbackHome, '-IncludeAgyCliFallback', '-AgyEvidenceDirectory', $evidenceDirectory, '-AgyCurrentVersion', $fakeAgyVersion)
    Assert-Equal -Expected 3 -Actual $booleanEvidence.ExitCode -Message 'String boolean AGY evidence must fail'
    Assert-True -Condition (@($booleanEvidence.Data.errors | Where-Object { $_ -match 'JSON boolean' }).Count -gt 0) -Message 'String boolean evidence reason'
    $env:PATH = $originalProcessPath

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

    $reparseOutside = Join-Path $fixtureRoot 'reparse-outside'
    $reparseHome = Join-Path $fixtureRoot 'reparse-home'
    $null = New-Item -ItemType Directory -Path $reparseOutside -Force
    $null = New-Item -ItemType Directory -Path $reparseHome -Force
    Write-Utf8NoBom -Path (Join-Path $reparseOutside 'sentinel.txt') -Text 'outside-must-not-change'
    $reparseSignature = Get-TreeSignature -Directory $reparseOutside
    $null = New-Item -ItemType Junction -Path (Join-Path $reparseHome '.agents') -Target $reparseOutside
    $reparseCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $reparseHome)
    Assert-Equal -Expected 3 -Actual $reparseCheck.ExitCode -Message 'Reparse ancestor must fail Check'
    Assert-True -Condition ([string]$reparseCheck.Data.error -match 'reparse point') -Message 'Reparse ancestor reason'
    Assert-Equal -Expected $reparseSignature -Actual (Get-TreeSignature -Directory $reparseOutside) -Message 'Reparse escape must not touch outside tree'

    $backupOutside = Join-Path $fixtureRoot 'backup-reparse-outside'
    $backupReparseHome = Join-Path $fixtureRoot 'backup-reparse-home'
    $null = New-Item -ItemType Directory -Path $backupOutside -Force
    $null = New-Item -ItemType Directory -Path $backupReparseHome -Force
    Write-Utf8NoBom -Path (Join-Path $backupOutside 'sentinel.txt') -Text 'backup-outside-must-not-change'
    $backupOutsideSignature = Get-TreeSignature -Directory $backupOutside
    $null = New-Item -ItemType Junction -Path (Join-Path $backupReparseHome '.yohan-skill-backups') -Target $backupOutside
    $backupReparseCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $backupReparseHome)
    Assert-Equal -Expected 3 -Actual $backupReparseCheck.ExitCode -Message 'Reparse backup root must fail Check'
    Assert-True -Condition ([string]$backupReparseCheck.Data.error -match 'reparse point') -Message 'Reparse backup root reason'
    Assert-Equal -Expected $backupOutsideSignature -Actual (Get-TreeSignature -Directory $backupOutside) -Message 'Backup reparse must not touch outside tree'

    $indexPathText = [string](& git -C $repoRoot rev-parse --git-path index)
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message 'Git index path lookup'
    $indexPath = if ([IO.Path]::IsPathRooted($indexPathText)) { [IO.Path]::GetFullPath($indexPathText) } else { [IO.Path]::GetFullPath((Join-Path $repoRoot $indexPathText)) }
    $indexHashBefore = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash
    $indexTicksBefore = (Get-Item -LiteralPath $indexPath -Force).LastWriteTimeUtc.Ticks
    $indexCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', (Join-Path $fixtureRoot 'index-readonly-home'))
    Assert-Equal -Expected 2 -Actual $indexCheck.ExitCode -Message 'Index read-only fixture is installable'
    Assert-Equal -Expected $indexHashBefore -Actual (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash -Message 'Check must not rewrite Git index bytes'
    Assert-Equal -Expected $indexTicksBefore -Actual (Get-Item -LiteralPath $indexPath -Force).LastWriteTimeUtc.Ticks -Message 'Check must not refresh Git index timestamp'

    $miniRepo = Join-Path $fixtureRoot 'ignored-source-repo'
    $miniSkillParent = Join-Path $miniRepo 'skills'
    $miniManifestParent = Join-Path $miniRepo 'distribution\manifests'
    $null = New-Item -ItemType Directory -Path $miniSkillParent -Force
    $null = New-Item -ItemType Directory -Path $miniManifestParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination (Join-Path $miniSkillParent 'adr-cycle') -Recurse
    Copy-Item -LiteralPath (Join-Path $repoRoot 'distribution\manifests\adr-cycle.json') -Destination (Join-Path $miniManifestParent 'adr-cycle.json')
    Write-Utf8NoBom -Path (Join-Path $miniRepo '.gitignore') -Text "skills/adr-cycle/*.ignored`n"
    $null = & git -C $miniRepo init --quiet 2>&1
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message 'Mini source Git init'
    $null = & git -C $miniRepo -c core.autocrlf=false add . 2>&1
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message 'Mini source Git add'
    $null = & git -C $miniRepo -c core.autocrlf=false -c user.name=fixture -c user.email=fixture@example.invalid commit --quiet -m baseline 2>&1
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message 'Mini source Git commit'
    Write-Utf8NoBom -Path (Join-Path $miniRepo 'skills\adr-cycle\hidden.ignored') -Text 'ignored-but-loaded'
    $ignoredSourceCheck = Invoke-Manager -ManagerRepositoryRoot $miniRepo -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', (Join-Path $fixtureRoot 'ignored-source-home'))
    Assert-Equal -Expected 3 -Actual $ignoredSourceCheck.ExitCode -Message 'Ignored source file must invalidate canonical source'
    Assert-True -Condition (@($ignoredSourceCheck.Data.errors | Where-Object { $_ -match 'untracked or ignored file' }).Count -gt 0) -Message 'Ignored source file reason'

    [IO.File]::Delete((Join-Path $miniRepo 'skills\adr-cycle\hidden.ignored'))
    $sameStatPath = Join-Path $miniRepo 'skills\adr-cycle\SKILL.md'
    $sameStatItem = Get-Item -LiteralPath $sameStatPath -Force
    $sameStatLength = $sameStatItem.Length
    $sameStatWriteTime = $sameStatItem.LastWriteTimeUtc
    $sameStatText = [IO.File]::ReadAllText($sameStatPath, [Text.Encoding]::UTF8)
    if ($sameStatText -notmatch 'ADR') { throw 'Same-stat fixture marker is missing' }
    Write-Utf8NoBom -Path $sameStatPath -Text ($sameStatText -replace 'ADR', 'XDR')
    (Get-Item -LiteralPath $sameStatPath -Force).LastWriteTimeUtc = $sameStatWriteTime
    Assert-Equal -Expected $sameStatLength -Actual (Get-Item -LiteralPath $sameStatPath -Force).Length -Message 'Same-stat fixture preserves byte length'
    Assert-Equal -Expected $sameStatWriteTime.Ticks -Actual (Get-Item -LiteralPath $sameStatPath -Force).LastWriteTimeUtc.Ticks -Message 'Same-stat fixture preserves write time'
    $sameStatCheck = Invoke-Manager -ManagerRepositoryRoot $miniRepo -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', (Join-Path $fixtureRoot 'same-stat-source-home'))
    Assert-Equal -Expected 3 -Actual $sameStatCheck.ExitCode -Message 'Same-size and same-mtime tracked drift must fail'
    Assert-True -Condition (@($sameStatCheck.Data.errors | Where-Object { $_ -match 'differs from Git index' }).Count -gt 0) -Message 'Direct Git index blob comparison reason'

    $tamperHome = Join-Path $fixtureRoot 'transaction-tamper-home'
    $tamperTargetParent = Join-Path $tamperHome '.claude\skills'
    $tamperTarget = Join-Path $tamperTargetParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $tamperTargetParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $tamperTarget -Recurse
    $tamperCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $tamperHome)
    $tamperInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $tamperHome, '-PlanDigest', [string]$tamperCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $tamperInstall.ExitCode -Message 'Transaction tamper fixture install'
    $tamperTransactionPath = [string]$tamperInstall.Data.transactionPath
    $tamperTransaction = [string]([IO.File]::ReadAllText($tamperTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $tamperItem = @($tamperTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    $tamperItem.backupPath = Join-Path $reparseOutside 'forged-backup'
    Write-Utf8NoBom -Path $tamperTransactionPath -Text ([string]($tamperTransaction | ConvertTo-Json -Depth 16))
    $tamperRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $tamperHome, '-BackupId', [string]$tamperInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $tamperRestoreCheck.ExitCode -Message 'Tampered transaction must fail Restore Check'
    Assert-True -Condition ([string]$tamperRestoreCheck.Data.error -match 'install seal mismatch') -Message 'Tampered transaction seal reason'
    Assert-Equal -Expected 'Junction' -Actual ([string](Get-Item -LiteralPath $tamperTarget -Force).LinkType) -Message 'Tampered transaction must not remove current junction'
    Assert-Equal -Expected $reparseSignature -Actual (Get-TreeSignature -Directory $reparseOutside) -Message 'Tampered backup path must not touch outside tree'

    $bindingHome = Join-Path $fixtureRoot 'transaction-binding-home'
    $bindingTargetParent = Join-Path $bindingHome '.claude\skills'
    $bindingTarget = Join-Path $bindingTargetParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $bindingTargetParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $bindingTarget -Recurse
    $bindingCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $bindingHome)
    $bindingInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $bindingHome, '-PlanDigest', [string]$bindingCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $bindingInstall.ExitCode -Message 'Path binding fixture install'
    $bindingTransactionPath = [string]$bindingInstall.Data.transactionPath
    $bindingOriginalJson = [IO.File]::ReadAllText($bindingTransactionPath, [Text.Encoding]::UTF8)
    $bindingTransaction = [string]$bindingOriginalJson | ConvertFrom-Json
    $bindingItem = @($bindingTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    $bindingItem.targetPath = Join-Path $bindingHome '.claude\skills\forged-target'
    $bindingTransaction.installSeal = Get-TestTransactionInstallSeal -Transaction $bindingTransaction
    $bindingTransaction.commitSeal = Get-TestTransactionCommitSeal -Transaction $bindingTransaction
    Write-Utf8NoBom -Path $bindingTransactionPath -Text ([string]($bindingTransaction | ConvertTo-Json -Depth 16))
    $targetBindingCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $bindingHome, '-BackupId', [string]$bindingInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $targetBindingCheck.ExitCode -Message 'Resealed forged target must fail path binding'
    Assert-True -Condition (@($targetBindingCheck.Data.errors | Where-Object { $_ -match 'target binding mismatch' }).Count -gt 0) -Message 'Target path binding reason beyond seals'

    Write-Utf8NoBom -Path $bindingTransactionPath -Text $bindingOriginalJson
    $bindingTransaction = [string]$bindingOriginalJson | ConvertFrom-Json
    $bindingItem = @($bindingTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    $bindingItem.backupPath = Join-Path (Split-Path -Parent $bindingTransactionPath) 'items\forged-backup'
    $bindingTransaction.installSeal = Get-TestTransactionInstallSeal -Transaction $bindingTransaction
    $bindingTransaction.commitSeal = Get-TestTransactionCommitSeal -Transaction $bindingTransaction
    Write-Utf8NoBom -Path $bindingTransactionPath -Text ([string]($bindingTransaction | ConvertTo-Json -Depth 16))
    $backupBindingCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $bindingHome, '-BackupId', [string]$bindingInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $backupBindingCheck.ExitCode -Message 'Resealed forged backup must fail path binding'
    Assert-True -Condition (@($backupBindingCheck.Data.errors | Where-Object { $_ -match 'backup binding mismatch' }).Count -gt 0) -Message 'Backup path binding reason beyond seals'

    $statusHome = Join-Path $fixtureRoot 'restored-status-home'
    $statusCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $statusHome)
    $statusInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $statusHome, '-PlanDigest', [string]$statusCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $statusInstall.ExitCode -Message 'Restored status fixture install'
    $statusTransactionPath = [string]$statusInstall.Data.transactionPath
    $statusTransaction = [string]([IO.File]::ReadAllText($statusTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $statusTransaction.status = 'Restored'
    $statusTransaction.recoverySeal = $null
    Write-Utf8NoBom -Path $statusTransactionPath -Text ([string]($statusTransaction | ConvertTo-Json -Depth 16))
    $unsealedStatusCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $statusHome, '-BackupId', [string]$statusInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $unsealedStatusCheck.ExitCode -Message 'Restored status without recovery seal must fail'
    Assert-True -Condition ([string]$unsealedStatusCheck.Data.error -match 'recovery seal mismatch') -Message 'Restored status seal reason'
    $statusTransaction.recoverySeal = Get-TestTransactionRecoverySeal -Transaction $statusTransaction -RecoveryKind 'CommittedRestore'
    Write-Utf8NoBom -Path $statusTransactionPath -Text ([string]($statusTransaction | ConvertTo-Json -Depth 16))
    $sealedStatusCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $statusHome, '-BackupId', [string]$statusInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $sealedStatusCheck.ExitCode -Message 'Resealed Restored status must verify actual targets'
    Assert-Equal -Expected 'Conflict' -Actual $sealedStatusCheck.Data.status -Message 'Installed targets cannot masquerade as Restored'

    $transactionReparseHome = Join-Path $fixtureRoot 'transaction-file-reparse-home'
    $transactionReparseCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $transactionReparseHome)
    $transactionReparseInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'goal-cycle', '-HomeRoot', $transactionReparseHome, '-PlanDigest', [string]$transactionReparseCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $transactionReparseInstall.ExitCode -Message 'Transaction reparse fixture install'
    $transactionReparseOutside = Join-Path $fixtureRoot 'transaction-file-reparse-outside'
    $null = New-Item -ItemType Directory -Path $transactionReparseOutside -Force
    Write-Utf8NoBom -Path (Join-Path $transactionReparseOutside 'sentinel.txt') -Text 'transaction-reparse-outside-must-not-change'
    $transactionReparseSignature = Get-TreeSignature -Directory $transactionReparseOutside
    [IO.File]::Delete([string]$transactionReparseInstall.Data.transactionPath)
    $null = New-Item -ItemType Junction -Path ([string]$transactionReparseInstall.Data.transactionPath) -Target $transactionReparseOutside
    $transactionReparseResult = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $transactionReparseHome, '-BackupId', [string]$transactionReparseInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $transactionReparseResult.ExitCode -Message 'Transaction file reparse leaf must fail'
    Assert-True -Condition ([string]$transactionReparseResult.Data.error -match 'reparse point') -Message 'Transaction file reparse reason'
    Assert-Equal -Expected $transactionReparseSignature -Actual (Get-TreeSignature -Directory $transactionReparseOutside) -Message 'Transaction reparse must not touch outside tree'

    $backupTamperHome = Join-Path $fixtureRoot 'backup-tamper-home'
    $backupTamperParent = Join-Path $backupTamperHome '.claude\skills'
    $backupTamperTarget = Join-Path $backupTamperParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $backupTamperParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $backupTamperTarget -Recurse
    $backupTamperCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $backupTamperHome)
    $backupTamperInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $backupTamperHome, '-PlanDigest', [string]$backupTamperCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $backupTamperInstall.ExitCode -Message 'Backup tamper fixture install'
    $backupTamperTransaction = [string]([IO.File]::ReadAllText([string]$backupTamperInstall.Data.transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $backupTamperItem = @($backupTamperTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    [IO.File]::AppendAllText((Join-Path ([string]$backupTamperItem.backupPath) 'SKILL.md'), "`n# fixture tamper`n", (New-Object Text.UTF8Encoding($false)))
    $backupTamperRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $backupTamperHome, '-BackupId', [string]$backupTamperInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $backupTamperRestoreCheck.ExitCode -Message 'Modified backup must fail Restore Check'
    Assert-Equal -Expected 'Conflict' -Actual $backupTamperRestoreCheck.Data.status -Message 'Modified backup conflict status'
    Assert-True -Condition (@($backupTamperRestoreCheck.Data.errors | Where-Object { $_ -match 'Backup directory was modified' }).Count -gt 0) -Message 'Modified backup reason'
    Assert-Equal -Expected 'Junction' -Actual ([string](Get-Item -LiteralPath $backupTamperTarget -Force).LinkType) -Message 'Modified backup must not remove current junction'

    $resumeHome = Join-Path $fixtureRoot 'partial-restore-home'
    $resumeCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $resumeHome)
    $resumeInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'goal-cycle', '-HomeRoot', $resumeHome, '-PlanDigest', [string]$resumeCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $resumeInstall.ExitCode -Message 'Partial restore fixture install'
    $resumeTransactionPath = [string]$resumeInstall.Data.transactionPath
    $resumeTransaction = [string]([IO.File]::ReadAllText($resumeTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $alreadyRestoredItem = @($resumeTransaction.items | Where-Object { $_.role -eq 'Agents' })[0]
    [IO.Directory]::Delete([string]$alreadyRestoredItem.targetPath, $false)
    $resumeTransaction.status = 'RecoveryRequired'
    Write-Utf8NoBom -Path $resumeTransactionPath -Text ([string]($resumeTransaction | ConvertTo-Json -Depth 16))
    $resumeRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $resumeHome, '-BackupId', [string]$resumeInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $resumeRestoreCheck.ExitCode -Message 'Partial restore must be resumable'
    Assert-Equal -Expected 'Original' -Actual (@($resumeRestoreCheck.Data.itemStates | Where-Object { $_.targetPath -eq [string]$alreadyRestoredItem.targetPath })[0].state) -Message 'Already restored item state'
    $resumeRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $resumeHome, '-BackupId', [string]$resumeInstall.Data.backupId, '-PlanDigest', [string]$resumeRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $resumeRestore.ExitCode -Message 'Partial Restore resume'
    foreach ($item in @($resumeTransaction.items)) {
        Assert-True -Condition (-not [IO.Directory]::Exists([string]$item.targetPath)) -Message "Partial Restore original missing state:$($item.role)"
    }

    $directoryResumeHome = Join-Path $fixtureRoot 'directory-partial-restore-home'
    $directoryResumeParent = Join-Path $directoryResumeHome '.claude\skills'
    $directoryResumeTarget = Join-Path $directoryResumeParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $directoryResumeParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $directoryResumeTarget -Recurse
    $directoryResumeOriginalSignature = Get-TreeSignature -Directory $directoryResumeTarget
    $directoryResumeCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $directoryResumeHome)
    $directoryResumeInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $directoryResumeHome, '-PlanDigest', [string]$directoryResumeCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $directoryResumeInstall.ExitCode -Message 'Directory partial restore fixture install'
    $directoryResumeTransactionPath = [string]$directoryResumeInstall.Data.transactionPath
    $directoryResumeTransaction = [string]([IO.File]::ReadAllText($directoryResumeTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $directoryResumeItem = @($directoryResumeTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    [IO.Directory]::Delete([string]$directoryResumeItem.targetPath, $false)
    $directoryResumeTransaction.status = 'RecoveryRequired'
    Write-Utf8NoBom -Path $directoryResumeTransactionPath -Text ([string]($directoryResumeTransaction | ConvertTo-Json -Depth 16))
    $directoryResumeRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $directoryResumeHome, '-BackupId', [string]$directoryResumeInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $directoryResumeRestoreCheck.ExitCode -Message 'Directory partial Restore must be resumable'
    Assert-Equal -Expected 'RestorePending' -Actual (@($directoryResumeRestoreCheck.Data.itemStates | Where-Object { $_.targetPath -eq [string]$directoryResumeItem.targetPath })[0].state) -Message 'Missing target with valid backup is RestorePending'
    $directoryResumeRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $directoryResumeHome, '-BackupId', [string]$directoryResumeInstall.Data.backupId, '-PlanDigest', [string]$directoryResumeRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $directoryResumeRestore.ExitCode -Message 'Directory partial Restore resume'
    Assert-Equal -Expected $directoryResumeOriginalSignature -Actual (Get-TreeSignature -Directory $directoryResumeTarget) -Message 'Directory partial Restore manifest'

    $installRecoveryHome = Join-Path $fixtureRoot 'install-recovery-home'
    $installRecoveryCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $installRecoveryHome)
    $installRecoveryInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'goal-cycle', '-HomeRoot', $installRecoveryHome, '-PlanDigest', [string]$installRecoveryCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $installRecoveryInstall.ExitCode -Message 'Install interruption fixture install'
    $installRecoveryTransactionPath = [string]$installRecoveryInstall.Data.transactionPath
    $installRecoveryTransaction = [string]([IO.File]::ReadAllText($installRecoveryTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $installRecoveryTransaction.status = 'Executing'
    $installRecoveryTransaction.commitSeal = $null
    $installRecoveryTransaction.recoverySeal = $null
    foreach ($item in @($installRecoveryTransaction.items)) {
        $item.changed = $true
        $item.junctionPrepared = $true
        $item.createdJunction = $false
    }
    Write-Utf8NoBom -Path $installRecoveryTransactionPath -Text ([string]($installRecoveryTransaction | ConvertTo-Json -Depth 16))
    $installRecoveryRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $installRecoveryHome, '-BackupId', [string]$installRecoveryInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $installRecoveryRestoreCheck.ExitCode -Message 'Executing install without commit seal must have an official recovery plan'
    Assert-Equal -Expected 'InstallRollback' -Actual $installRecoveryRestoreCheck.Data.recoveryKind -Message 'Uncommitted install recovery kind'
    Assert-Equal -Expected 3 -Actual @($installRecoveryRestoreCheck.Data.itemStates | Where-Object { $_.state -eq 'Installed' }).Count -Message 'Journaled staged identities survive an atomic move before active-state journaling'
    $installRecoveryHuman = @(& powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RepositoryRoot $repoRoot -Mode Check -HomeRoot $installRecoveryHome -BackupId ([string]$installRecoveryInstall.Data.backupId) -OutputFormat Human 2>&1)
    $installRecoveryHumanExit = $LASTEXITCODE
    $installRecoveryHumanText = [string]::Join([Environment]::NewLine, @($installRecoveryHuman | ForEach-Object { [string]$_ }))
    Assert-Equal -Expected 0 -Actual $installRecoveryHumanExit -Message 'Human restore Check output exit code'
    Assert-True -Condition ($installRecoveryHumanText -match 'RecoveryKind:\s+InstallRollback') -Message 'Human restore Check shows recovery kind'
    Assert-True -Condition ($installRecoveryHumanText -match '\[Restore/Installed\]') -Message 'Human restore Check shows item states'
    $installRecoveryRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $installRecoveryHome, '-BackupId', [string]$installRecoveryInstall.Data.backupId, '-PlanDigest', [string]$installRecoveryRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $installRecoveryRestore.ExitCode -Message 'Interrupted install rollback'
    Assert-Equal -Expected 'Restored' -Actual $installRecoveryRestore.Data.status -Message 'Interrupted install recovery status'
    $installRecoveryNoOp = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $installRecoveryHome, '-BackupId', [string]$installRecoveryInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $installRecoveryNoOp.ExitCode -Message 'Interrupted install recovery must be idempotent'
    Assert-Equal -Expected 'NoOp' -Actual $installRecoveryNoOp.Data.status -Message 'Interrupted install recovery no-op status'

    $journalOnlyTransaction = [string]([IO.File]::ReadAllText($installRecoveryTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $journalOnlyTransaction.status = 'Executing'
    $journalOnlyTransaction.recoverySeal = $null
    foreach ($item in @($journalOnlyTransaction.items)) {
        $item.changed = $false
        $item.junctionPrepared = $false
        $item.createdJunction = $false
        $item.junctionIdentity = $null
    }
    Write-Utf8NoBom -Path $installRecoveryTransactionPath -Text ([string]($journalOnlyTransaction | ConvertTo-Json -Depth 16))
    $journalOnlyRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $installRecoveryHome, '-BackupId', [string]$installRecoveryInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $journalOnlyRestoreCheck.ExitCode -Message 'Journal-only interruption must have an official recovery plan'
    Assert-Equal -Expected 3 -Actual @($journalOnlyRestoreCheck.Data.itemStates | Where-Object { $_.state -eq 'Original' }).Count -Message 'Journal-only recovery observes untouched original state'
    $journalOnlyRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $installRecoveryHome, '-BackupId', [string]$installRecoveryInstall.Data.backupId, '-PlanDigest', [string]$journalOnlyRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $journalOnlyRestore.ExitCode -Message 'Journal-only interruption recovery'
    Assert-Equal -Expected 'Restored' -Actual $journalOnlyRestore.Data.status -Message 'Journal-only recovery status'

    $unownedRollbackHome = Join-Path $fixtureRoot 'unowned-install-rollback-home'
    $unownedRollbackCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $unownedRollbackHome)
    $unownedRollbackInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $unownedRollbackHome, '-PlanDigest', [string]$unownedRollbackCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $unownedRollbackInstall.ExitCode -Message 'Unowned rollback fixture install'
    $unownedRollbackTransactionPath = [string]$unownedRollbackInstall.Data.transactionPath
    $unownedRollbackTransaction = [string]([IO.File]::ReadAllText($unownedRollbackTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $unownedRollbackTransaction.status = 'Executing'
    $unownedRollbackTransaction.commitSeal = $null
    $unownedRollbackTransaction.recoverySeal = $null
    foreach ($item in @($unownedRollbackTransaction.items)) {
        $item.changed = $true
        $item.junctionPrepared = $true
        $item.createdJunction = $false
        $item.junctionIdentity = $null
    }
    Write-Utf8NoBom -Path $unownedRollbackTransactionPath -Text ([string]($unownedRollbackTransaction | ConvertTo-Json -Depth 16))
    $unownedRollbackTarget = [string](@($unownedRollbackTransaction.items | Where-Object { $_.role -eq 'Agents' })[0].targetPath)
    $unownedRollbackRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $unownedRollbackHome, '-BackupId', [string]$unownedRollbackInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $unownedRollbackRestoreCheck.ExitCode -Message 'InstallRollback without a journaled junction identity must fail closed'
    Assert-Equal -Expected 'Conflict' -Actual $unownedRollbackRestoreCheck.Data.status -Message 'Unowned install rollback conflict status'
    Assert-True -Condition (@($unownedRollbackRestoreCheck.Data.errors | Where-Object { $_ -match 'identity mismatch' }).Count -gt 0) -Message 'Unowned install rollback identity reason'
    $unownedRollbackRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $unownedRollbackHome, '-BackupId', [string]$unownedRollbackInstall.Data.backupId, '-PlanDigest', [string]$unownedRollbackRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 3 -Actual $unownedRollbackRestore.ExitCode -Message 'Blocked InstallRollback must not remove an unowned junction'
    Assert-Equal -Expected 'Junction' -Actual ([string](Get-Item -LiteralPath $unownedRollbackTarget -Force).LinkType) -Message 'Unowned same-source junction remains intact'

    $rollbackRecoveryHome = Join-Path $fixtureRoot 'rollback-recovery-home'
    $rollbackRecoveryParent = Join-Path $rollbackRecoveryHome '.claude\skills'
    $rollbackRecoveryTarget = Join-Path $rollbackRecoveryParent 'goal-cycle'
    $null = New-Item -ItemType Directory -Path $rollbackRecoveryParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\goal-cycle') -Destination $rollbackRecoveryTarget -Recurse
    $rollbackRecoveryOriginalSignature = Get-TreeSignature -Directory $rollbackRecoveryTarget
    $rollbackRecoveryCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'goal-cycle', '-HomeRoot', $rollbackRecoveryHome)
    $rollbackRecoveryInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'goal-cycle', '-HomeRoot', $rollbackRecoveryHome, '-PlanDigest', [string]$rollbackRecoveryCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $rollbackRecoveryInstall.ExitCode -Message 'Rollback recovery fixture install'
    $rollbackRecoveryTransactionPath = [string]$rollbackRecoveryInstall.Data.transactionPath
    $rollbackRecoveryTransaction = [string]([IO.File]::ReadAllText($rollbackRecoveryTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $rollbackRecoveryItem = @($rollbackRecoveryTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    [IO.Directory]::Delete([string]$rollbackRecoveryItem.targetPath, $false)
    $rollbackRecoveryTransaction.status = 'RecoveryRequired'
    $rollbackRecoveryTransaction.commitSeal = $null
    $rollbackRecoveryTransaction.recoverySeal = $null
    $rollbackRecoveryItem.junctionIdentity = $null
    Write-Utf8NoBom -Path $rollbackRecoveryTransactionPath -Text ([string]($rollbackRecoveryTransaction | ConvertTo-Json -Depth 16))
    $rollbackRecoveryRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $rollbackRecoveryHome, '-BackupId', [string]$rollbackRecoveryInstall.Data.backupId)
    Assert-Equal -Expected 0 -Actual $rollbackRecoveryRestoreCheck.ExitCode -Message 'RecoveryRequired without commit seal must be recoverable'
    Assert-Equal -Expected 'InstallRollback' -Actual $rollbackRecoveryRestoreCheck.Data.recoveryKind -Message 'Rollback failure recovery kind'
    Assert-Equal -Expected 'RestorePending' -Actual (@($rollbackRecoveryRestoreCheck.Data.itemStates | Where-Object { $_.targetPath -eq [string]$rollbackRecoveryItem.targetPath })[0].state) -Message 'Rollback failure directory state'
    $rollbackRecoveryRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $rollbackRecoveryHome, '-BackupId', [string]$rollbackRecoveryInstall.Data.backupId, '-PlanDigest', [string]$rollbackRecoveryRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $rollbackRecoveryRestore.ExitCode -Message 'RecoveryRequired install rollback'
    Assert-Equal -Expected $rollbackRecoveryOriginalSignature -Actual (Get-TreeSignature -Directory $rollbackRecoveryTarget) -Message 'RecoveryRequired rollback restores original directory'

    $tamperedRollbackHome = Join-Path $fixtureRoot 'tampered-rollback-home'
    $tamperedRollbackParent = Join-Path $tamperedRollbackHome '.claude\skills'
    $tamperedRollbackTarget = Join-Path $tamperedRollbackParent 'adr-cycle'
    $null = New-Item -ItemType Directory -Path $tamperedRollbackParent -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'skills\adr-cycle') -Destination $tamperedRollbackTarget -Recurse
    $tamperedRollbackCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $tamperedRollbackHome)
    $tamperedRollbackInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $tamperedRollbackHome, '-PlanDigest', [string]$tamperedRollbackCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $tamperedRollbackInstall.ExitCode -Message 'Tampered rollback fixture install'
    $tamperedRollbackTransactionPath = [string]$tamperedRollbackInstall.Data.transactionPath
    $tamperedRollbackTransaction = [string]([IO.File]::ReadAllText($tamperedRollbackTransactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $tamperedRollbackItem = @($tamperedRollbackTransaction.items | Where-Object { $_.role -eq 'Claude' })[0]
    [IO.Directory]::Delete([string]$tamperedRollbackItem.targetPath, $false)
    [IO.File]::AppendAllText((Join-Path ([string]$tamperedRollbackItem.backupPath) 'SKILL.md'), "`n# tampered rollback`n", (New-Object Text.UTF8Encoding($false)))
    $tamperedRollbackTransaction.status = 'RecoveryRequired'
    $tamperedRollbackTransaction.commitSeal = $null
    $tamperedRollbackTransaction.recoverySeal = $null
    Write-Utf8NoBom -Path $tamperedRollbackTransactionPath -Text ([string]($tamperedRollbackTransaction | ConvertTo-Json -Depth 16))
    $tamperedRollbackRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $tamperedRollbackHome, '-BackupId', [string]$tamperedRollbackInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $tamperedRollbackRestoreCheck.ExitCode -Message 'Tampered rollback backup must block recovery'
    Assert-True -Condition (@($tamperedRollbackRestoreCheck.Data.errors | Where-Object { $_ -match 'Backup directory was modified' }).Count -gt 0) -Message 'Tampered rollback backup reason'
    $tamperedRollbackRestore = Invoke-Manager -Arguments @('-Mode', 'Restore', '-HomeRoot', $tamperedRollbackHome, '-BackupId', [string]$tamperedRollbackInstall.Data.backupId, '-PlanDigest', [string]$tamperedRollbackRestoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 3 -Actual $tamperedRollbackRestore.ExitCode -Message 'Tampered rollback directory must never be reactivated'
    Assert-True -Condition (-not [IO.Directory]::Exists($tamperedRollbackTarget)) -Message 'Tampered rollback target remains inactive'
    Assert-True -Condition ([IO.Directory]::Exists([string]$tamperedRollbackItem.backupPath)) -Message 'Tampered rollback backup remains quarantined'

    $identityHome = Join-Path $fixtureRoot 'junction-identity-home'
    $identityCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $identityHome)
    $identityInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $identityHome, '-PlanDigest', [string]$identityCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $identityInstall.ExitCode -Message 'Junction identity fixture install'
    $identityTransaction = [string]([IO.File]::ReadAllText([string]$identityInstall.Data.transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $identityItem = @($identityTransaction.items | Where-Object { $_.role -eq 'Agents' })[0]
    [IO.Directory]::Delete([string]$identityItem.targetPath, $false)
    $null = New-Item -ItemType Junction -Path ([string]$identityItem.targetPath) -Target ([string]$identityItem.sourcePath)
    $identityRestoreCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-HomeRoot', $identityHome, '-BackupId', [string]$identityInstall.Data.backupId)
    Assert-Equal -Expected 3 -Actual $identityRestoreCheck.ExitCode -Message 'Recreated same-target junction must fail ownership check'
    Assert-Equal -Expected 'Conflict' -Actual $identityRestoreCheck.Data.status -Message 'Recreated junction conflict status'
    Assert-True -Condition (@($identityRestoreCheck.Data.errors | Where-Object { $_ -match 'identity mismatch' }).Count -gt 0) -Message 'Recreated junction identity reason'
    Assert-Equal -Expected 'Junction' -Actual ([string](Get-Item -LiteralPath ([string]$identityItem.targetPath) -Force).LinkType) -Message 'Identity conflict must not remove replacement junction'

    $managerTokens = $null
    $managerParseErrors = $null
    $managerAst = [Management.Automation.Language.Parser]::ParseFile($toolPath, [ref]$managerTokens, [ref]$managerParseErrors)
    Assert-Equal -Expected 0 -Actual $managerParseErrors.Count -Message 'Manager AST for primitive safety tests'
    $topLevelFunctions = @($managerAst.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
    foreach ($functionAst in $topLevelFunctions) {
        . ([scriptblock]::Create([string]$functionAst.Extent.Text))
    }
    $moveFunctionAst = @($topLevelFunctions | Where-Object { $_.Name -eq 'Move-DirectoryExact' })[0]
    Assert-True -Condition ([string]$moveFunctionAst.Extent.Text -match '\[IO\.Directory\]::Move') -Message 'Exact directory move uses Directory.Move'
    Assert-True -Condition ([string]$moveFunctionAst.Extent.Text -notmatch 'Move-Item') -Message 'Exact directory move never uses container-style Move-Item'
    $ownedJunctionMoveAst = @($topLevelFunctions | Where-Object { $_.Name -eq 'Move-OwnedJunctionExact' })[0]
    Assert-True -Condition ([string]$ownedJunctionMoveAst.Extent.Text -match '\[IO\.Directory\]::Move') -Message 'Owned staged junction move uses Directory.Move'
    Assert-True -Condition ([string]$ownedJunctionMoveAst.Extent.Text -notmatch 'Move-Item') -Message 'Owned staged junction move never uses container-style Move-Item'
    $atomicJsonAst = @($topLevelFunctions | Where-Object { $_.Name -eq 'Write-JsonAtomic' })[0]
    Assert-True -Condition ([string]$atomicJsonAst.Extent.Text -match '\[IO\.File\]::Replace') -Message 'Existing transaction journal uses File.Replace'
    Assert-True -Condition ([string]$atomicJsonAst.Extent.Text -match '\[IO\.File\]::Move') -Message 'New transaction journal uses File.Move'
    Assert-True -Condition ([string]$atomicJsonAst.Extent.Text -notmatch 'Move-Item') -Message 'Transaction journal never uses Move-Item replacement semantics'

    $atomicJsonRoot = Join-Path $fixtureRoot 'atomic-json-fixture'
    $atomicJsonPath = Join-Path $atomicJsonRoot 'transaction.json'
    $null = New-Item -ItemType Directory -Path $atomicJsonRoot -Force
    Write-JsonAtomic -Path $atomicJsonPath -Value ([pscustomobject][ordered]@{ generation = 1 })
    Write-JsonAtomic -Path $atomicJsonPath -Value ([pscustomobject][ordered]@{ generation = 2 })
    $atomicJsonValue = [string]([IO.File]::ReadAllText($atomicJsonPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal -Expected 2 -Actual $atomicJsonValue.generation -Message 'Atomic transaction replacement preserves the newest complete JSON'
    Assert-Equal -Expected 0 -Actual @(Get-ChildItem -LiteralPath $atomicJsonRoot -Force | Where-Object { $_.Name -ne 'transaction.json' }).Count -Message 'Atomic transaction replacement leaves no temporary or previous file'

    $stagingMoveRoot = Join-Path $fixtureRoot 'staging-move-fixture'
    $stagingTransactionRoot = Join-Path $stagingMoveRoot 'transaction'
    $stagingHomeRoot = Join-Path $stagingMoveRoot 'home'
    $stagedJunction = Join-Path $stagingTransactionRoot 'staging\adr-cycle\Agents'
    $activeJunction = Join-Path $stagingHomeRoot '.agents\skills\adr-cycle'
    $null = New-Item -ItemType Directory -Path $stagingTransactionRoot -Force
    $null = New-Item -ItemType Directory -Path $stagingHomeRoot -Force
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $activeJunction) -Force
    $stagedIdentity = New-CanonicalJunction -Path $stagedJunction -Target (Join-Path $repoRoot 'skills\adr-cycle') -AllowedRoot $stagingTransactionRoot
    Move-OwnedJunctionExact -SourcePath $stagedJunction -SourceAllowedRoot $stagingTransactionRoot -DestinationPath $activeJunction -DestinationAllowedRoot $stagingHomeRoot -ExpectedTarget (Join-Path $repoRoot 'skills\adr-cycle') -ExpectedIdentity $stagedIdentity
    $activeStagedMoveEntry = Get-PathEntryInfo -Path $activeJunction
    Assert-Equal -Expected 'Missing' -Actual (Get-PathEntryInfo -Path $stagedJunction).kind -Message 'Atomic staged junction move empties staging path'
    Assert-Equal -Expected 'Junction' -Actual $activeStagedMoveEntry.kind -Message 'Atomic staged junction move creates the active entry'
    Assert-Equal -Expected $stagedIdentity -Actual $activeStagedMoveEntry.junctionIdentity -Message 'Atomic staged junction move preserves the journaled NTFS identity'

    $mutexHome = Join-Path $fixtureRoot 'mutex-home'
    $mutex = Enter-HomeMutationMutex -UserHome $mutexHome
    try {
        $mutexCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Skill', 'adr-cycle', '-HomeRoot', $mutexHome)
        Assert-Equal -Expected 2 -Actual $mutexCheck.ExitCode -Message 'Read-only Check remains available while mutation mutex is held'
        $mutexBlockedInstall = Invoke-Manager -Arguments @('-Mode', 'Install', '-Skill', 'adr-cycle', '-HomeRoot', $mutexHome, '-PlanDigest', [string]$mutexCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
        Assert-Equal -Expected 3 -Actual $mutexBlockedInstall.ExitCode -Message 'Concurrent HomeRoot mutation is blocked'
        Assert-True -Condition ([string]$mutexBlockedInstall.Data.error -match 'Another skill distribution mutation is active') -Message 'Concurrent HomeRoot mutation reason'
        Assert-True -Condition (-not [IO.Directory]::Exists($mutexHome)) -Message 'Rejected concurrent mutation writes nothing to HomeRoot'
    }
    finally { Exit-HomeMutationMutex -Mutex $mutex }

    $moveOutside = Join-Path $fixtureRoot 'move-leaf-outside'
    $moveFixture = Join-Path $fixtureRoot 'move-leaf-fixture'
    $moveSource = Join-Path $moveFixture 'source'
    $moveDestination = Join-Path $moveFixture 'destination'
    $null = New-Item -ItemType Directory -Path $moveOutside -Force
    $null = New-Item -ItemType Directory -Path $moveSource -Force
    Write-Utf8NoBom -Path (Join-Path $moveOutside 'sentinel.txt') -Text 'move-outside-must-not-change'
    Write-Utf8NoBom -Path (Join-Path $moveSource 'source.txt') -Text 'source-must-stay-put'
    $moveOutsideSignature = Get-TreeSignature -Directory $moveOutside
    $null = New-Item -ItemType Junction -Path $moveDestination -Target $moveOutside
    $moveRejected = $false
    try {
        Move-DirectoryExact -SourcePath $moveSource -SourceAllowedRoot $moveFixture -DestinationPath $moveDestination -DestinationAllowedRoot $moveFixture -Label 'Fixture move'
    }
    catch { $moveRejected = $true }
    Assert-True -Condition $moveRejected -Message 'Existing destination junction must fail exact move'
    Assert-True -Condition ([IO.Directory]::Exists($moveSource)) -Message 'Failed exact move preserves source directory'
    Assert-Equal -Expected $moveOutsideSignature -Actual (Get-TreeSignature -Directory $moveOutside) -Message 'Failed exact move cannot move content through destination junction'

    $replayTarget = Join-Path $fixtureRoot 'identity-replay-target'
    $replayJunction = Join-Path $fixtureRoot 'identity-replay-junction'
    $null = New-Item -ItemType Directory -Path $replayTarget -Force
    $null = New-Item -ItemType Junction -Path $replayJunction -Target $replayTarget
    $replayEntry = Get-Item -LiteralPath $replayJunction -Force
    $firstReplayIdentity = Get-JunctionIdentity -Entry $replayEntry -Target $replayTarget
    [IO.Directory]::Delete($replayJunction, $false)
    $null = New-Item -ItemType Junction -Path $replayJunction -Target $replayTarget
    $replacementReplayEntry = Get-Item -LiteralPath $replayJunction -Force
    $secondReplayIdentity = Get-JunctionIdentity -Entry $replacementReplayEntry -Target $replayTarget
    Assert-True -Condition ($firstReplayIdentity -cne $secondReplayIdentity) -Message 'NTFS file ID detects immediate same-target junction recreation'

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
