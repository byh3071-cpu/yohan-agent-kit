#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manager = Join-Path $repoRoot 'scripts\Manage-AgentKit.ps1'
$builder = Join-Path $repoRoot 'scripts\Build-AgentKit.mjs'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "yohan-agent-kit-tests\manager-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$artifactRoot = Join-Path $fixtureRoot 'artifacts'
$homeRoot = Join-Path $fixtureRoot 'home'
$null = New-Item -ItemType Directory -Path $artifactRoot -Force
$script:assertionCount = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertionCount++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertionCount++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }

function Build-TestRelease {
    param([string]$Release)
    $output = @(& node $builder --release $Release --output-root $artifactRoot --source-commit ('2' * 40) --allow-dirty --allow-test-output --json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Builder failed: $([string]::Join([Environment]::NewLine, $output))" }
    return Join-Path $artifactRoot $Release
}

function Invoke-Manager {
    param([string[]]$Arguments, [string]$FixtureHome = $homeRoot)
    $base = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $manager, '-RepositoryRoot', $repoRoot, '-HomeRoot', $FixtureHome, '-OutputFormat', 'Json', '-AllowDirtyArtifact')
    $output = @(& powershell @base @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    try { $data = $text | ConvertFrom-Json } catch { throw "Manager returned invalid JSON (exit=$exitCode): $text" }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Text = $text }
}

try {
    $release1 = 'test-manager-r1'
    $release2 = 'test-manager-r2'
    $release3 = 'test-manager-r3'
    $artifact1 = Build-TestRelease -Release $release1
    $artifact2 = Build-TestRelease -Release $release2
    $artifact3 = Build-TestRelease -Release $release3

    $check1 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 2 $check1.ExitCode 'first release is installable'
    Assert-Equal 'Installable' $check1.Data.status 'first release Check status'
    Assert-True (-not [IO.Directory]::Exists($homeRoot)) 'Check does not create HomeRoot'
    Assert-Equal 6 @($check1.Data.targets).Count 'five packages expand to six discovery targets because Antigravity IDE and CLI differ'
    Assert-Equal 1 @($check1.Data.targets | Where-Object deployment -eq 'MarketplaceManaged').Count 'Claude remains Marketplace-managed'

    $denied = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All', '-PlanDigest', [string]$check1.Data.planDigest)
    Assert-Equal 1 $denied.ExitCode 'Install requires global home approval'
    Assert-True (@($denied.Data.errors | Where-Object { $_ -match 'ApproveGlobalHomeWrite' }).Count -eq 1) 'missing approval reason'
    Assert-True (-not [IO.Directory]::Exists($homeRoot)) 'denied Install leaves HomeRoot absent'

    $wrongDigest = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All', '-PlanDigest', ('0' * 64), '-ApproveGlobalHomeWrite')
    Assert-Equal 1 $wrongDigest.ExitCode 'Install rejects stale PlanDigest'
    Assert-True (@($wrongDigest.Data.errors | Where-Object { $_ -match 'PlanDigest' }).Count -eq 1) 'stale digest reason'

    $install1 = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All', '-PlanDigest', [string]$check1.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 0 $install1.ExitCode 'approved Install succeeds'
    Assert-Equal 'Committed' $install1.Data.status 'Install transaction committed'
    Assert-True ([IO.Directory]::Exists((Join-Path $homeRoot ".yohan-agent-kit\releases\$release1"))) 'immutable release copied'
    foreach ($relativePath in @('.agents\plugins\yohan-agent-kit', 'plugins\yohan-agent-kit', '.cursor\plugins\local\yohan-agent-kit', '.gemini\config\plugins\yohan-agent-kit', '.gemini\antigravity-cli\plugins\yohan-agent-kit', '.yohan-agent-kit\active')) {
        $entry = Get-Item -LiteralPath (Join-Path $homeRoot $relativePath) -Force
        Assert-Equal 'Junction' $entry.LinkType "discovery junction $relativePath"
    }

    $healthy1 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 0 $healthy1.ExitCode 'post-install Check healthy'
    Assert-Equal 'Healthy' $healthy1.Data.status 'post-install state'
    $activeStatePath = Join-Path $homeRoot '.yohan-agent-kit\active.json'
    $activeStateBytes = [IO.File]::ReadAllBytes($activeStatePath)
    $activeState = [Text.Encoding]::UTF8.GetString($activeStateBytes) | ConvertFrom-Json
    $activeState.manifestSha256 = ('f' * 64)
    [IO.File]::WriteAllText($activeStatePath, (ConvertTo-Json $activeState -Depth 16), (New-Object Text.UTF8Encoding($false)))
    $activeTamper = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 'Conflict' $activeTamper.Data.status 'active state manifest tamper conflicts'
    Assert-True (@($activeTamper.Data.errors | Where-Object { $_ -match 'Active state manifest digest' }).Count -eq 1) 'active state tamper reason'
    [IO.File]::WriteAllBytes($activeStatePath, $activeStateBytes)
    $activeHardLinkOutside = Join-Path $fixtureRoot 'active-hardlink-outside.json'
    [IO.File]::WriteAllBytes($activeHardLinkOutside, $activeStateBytes)
    $activeHardLinkOutsideHash = (Get-FileHash -LiteralPath $activeHardLinkOutside -Algorithm SHA256).Hash
    [IO.File]::Delete($activeStatePath)
    $null = New-Item -ItemType HardLink -Path $activeStatePath -Target $activeHardLinkOutside
    $activeHardLinkCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 1 $activeHardLinkCheck.ExitCode 'active state hard link is rejected'
    Assert-True (@($activeHardLinkCheck.Data.errors | Where-Object { $_ -match 'linked file' }).Count -eq 1) 'active state hard-link rejection reason'
    Assert-Equal $activeHardLinkOutsideHash (Get-FileHash -LiteralPath $activeHardLinkOutside -Algorithm SHA256).Hash 'active state hard link cannot modify outside bytes'
    [IO.File]::Delete($activeStatePath)
    [IO.File]::WriteAllBytes($activeStatePath, $activeStateBytes)
    $noChange = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All', '-PlanDigest', [string]$healthy1.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 'NoChange' $noChange.Data.status 'repeated Install is idempotent'
    Assert-True ($null -eq $noChange.Data.backupId) 'idempotent Install creates no backup'

    $check2 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release2, '-ArtifactRoot', $artifact2, '-Targets', 'All')
    Assert-Equal 'Updatable' $check2.Data.status 'second release is an update'
    $wrongMode = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release2, '-ArtifactRoot', $artifact2, '-Targets', 'All', '-PlanDigest', [string]$check2.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 1 $wrongMode.ExitCode 'Install cannot replace an active release'
    Assert-True (@($wrongMode.Data.errors | Where-Object { $_ -match 'use -Mode Update' }).Count -eq 1) 'wrong mutation mode reason'
    $update2 = Invoke-Manager -Arguments @('-Mode', 'Update', '-Release', $release2, '-ArtifactRoot', $artifact2, '-Targets', 'All', '-PlanDigest', [string]$check2.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 'Committed' $update2.Data.status 'Update committed'
    $healthy2 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release2, '-ArtifactRoot', $artifact2, '-Targets', 'All')
    Assert-Equal 'Healthy' $healthy2.Data.status 'second release healthy'

    $restore2Check = Invoke-Manager -Arguments @('-Mode', 'Check', '-BackupId', [string]$update2.Data.backupId)
    Assert-Equal 2 $restore2Check.ExitCode 'update backup restore preflight'
    Assert-Equal 'RestoreReady' $restore2Check.Data.status 'update restore ready'
    $restoreFault = Invoke-Manager -Arguments @('-Mode', 'Restore', '-BackupId', [string]$update2.Data.backupId, '-PlanDigest', [string]$restore2Check.Data.planDigest, '-ApproveGlobalHomeWrite', '-TestFault', 'AfterFirstRestoreTarget')
    Assert-Equal 1 $restoreFault.ExitCode 'interrupted restore reports error'
    $restoreResumeCheck = Invoke-Manager -Arguments @('-Mode', 'Check', '-BackupId', [string]$update2.Data.backupId)
    Assert-Equal 'RestoreReady' $restoreResumeCheck.Data.status 'interrupted restore is resumable'
    Assert-Equal $restore2Check.Data.planDigest $restoreResumeCheck.Data.planDigest 'restore digest remains stable while resuming'
    $restore2 = Invoke-Manager -Arguments @('-Mode', 'Restore', '-BackupId', [string]$update2.Data.backupId, '-PlanDigest', [string]$restoreResumeCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 'Restored' $restore2.Data.status 'resumed update rollback succeeds'
    $backTo1 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 'Healthy' $backTo1.Data.status 'rollback restores first release exactly'
    $restore2Again = Invoke-Manager -Arguments @('-Mode', 'Check', '-BackupId', [string]$update2.Data.backupId)
    Assert-Equal 'AlreadyRestored' $restore2Again.Data.status 'restore is idempotent'

    $restore1Check = Invoke-Manager -Arguments @('-Mode', 'Check', '-BackupId', [string]$install1.Data.backupId)
    Assert-Equal 'RestoreReady' $restore1Check.Data.status 'initial install remains exactly restorable after update rollback'
    $restore1 = Invoke-Manager -Arguments @('-Mode', 'Restore', '-BackupId', [string]$install1.Data.backupId, '-PlanDigest', [string]$restore1Check.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal 'Restored' $restore1.Data.status 'initial install restore succeeds'
    foreach ($relativePath in @('.agents\plugins\yohan-agent-kit', 'plugins\yohan-agent-kit', '.cursor\plugins\local\yohan-agent-kit', '.gemini\config\plugins\yohan-agent-kit', '.gemini\antigravity-cli\plugins\yohan-agent-kit', '.yohan-agent-kit\active')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $homeRoot $relativePath))) "restore returns $relativePath to missing"
    }

    $check3 = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release3, '-ArtifactRoot', $artifact3, '-Targets', 'All')
    $fault = Invoke-Manager -Arguments @('-Mode', 'Install', '-Release', $release3, '-ArtifactRoot', $artifact3, '-Targets', 'All', '-PlanDigest', [string]$check3.Data.planDigest, '-ApproveGlobalHomeWrite', '-TestFault', 'AfterFirstTarget')
    Assert-Equal 1 $fault.ExitCode 'injected partial failure reports error'
    Assert-True (@($fault.Data.errors | Where-Object { $_ -match 'mutation rolled back' }).Count -eq 1) 'partial failure reports rollback'
    $postFault = Invoke-Manager -Arguments @('-Mode', 'Check', '-Release', $release3, '-ArtifactRoot', $artifact3, '-Targets', 'All')
    Assert-Equal 'Installable' $postFault.Data.status 'partial failure leaves no active mutation'

    $conflictHome = Join-Path $fixtureRoot 'conflict-home'
    $null = New-Item -ItemType Directory -Path (Join-Path $conflictHome 'plugins\yohan-agent-kit') -Force
    [IO.File]::WriteAllText((Join-Path $conflictHome 'plugins\yohan-agent-kit\user.txt'), 'preserve me')
    $conflict = Invoke-Manager -FixtureHome $conflictHome -Arguments @('-Mode', 'Check', '-Release', $release1, '-ArtifactRoot', $artifact1, '-Targets', 'All')
    Assert-Equal 3 $conflict.ExitCode 'unowned discovery directory conflicts'
    Assert-Equal 'Conflict' $conflict.Data.status 'unowned discovery state'
    Assert-True ([IO.File]::Exists((Join-Path $conflictHome 'plugins\yohan-agent-kit\user.txt'))) 'Conflict preserves user directory'

    $artifact3ManifestPath = Join-Path $artifact3 'release-manifest.json'
    $artifact3ManifestBytes = [IO.File]::ReadAllBytes($artifact3ManifestPath)
    $metadataTamper = [Text.Encoding]::UTF8.GetString($artifact3ManifestBytes) | ConvertFrom-Json
    $metadataTamper.kitVersion = '999.0.0'
    [IO.File]::WriteAllText($artifact3ManifestPath, (ConvertTo-Json $metadataTamper -Depth 32), (New-Object Text.UTF8Encoding($false)))
    $metadataTampered = Invoke-Manager -FixtureHome (Join-Path $fixtureRoot 'metadata-tamper-home') -Arguments @('-Mode', 'Check', '-Release', $release3, '-ArtifactRoot', $artifact3, '-Targets', 'All')
    Assert-Equal 1 $metadataTampered.ExitCode 'tampered release metadata is rejected'
    Assert-True (@($metadataTampered.Data.errors | Where-Object { $_ -match 'metadata digest mismatch' }).Count -eq 1) 'metadata tamper rejection reason'
    [IO.File]::WriteAllBytes($artifact3ManifestPath, $artifact3ManifestBytes)

    $tamperFile = @((Get-Content -LiteralPath $artifact3ManifestPath -Raw | ConvertFrom-Json).files)[0].path
    [IO.File]::AppendAllText((Join-Path $artifact3 ([string]$tamperFile).Replace('/', '\')), 'tamper')
    $tampered = Invoke-Manager -FixtureHome (Join-Path $fixtureRoot 'tamper-home') -Arguments @('-Mode', 'Check', '-Release', $release3, '-ArtifactRoot', $artifact3, '-Targets', 'All')
    Assert-Equal 1 $tampered.ExitCode 'tampered artifact is rejected'
    Assert-True (@($tampered.Data.errors | Where-Object { $_ -match 'digest mismatch|size mismatch' }).Count -eq 1) 'tamper rejection reason'

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
