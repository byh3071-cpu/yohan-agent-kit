#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tool = Join-Path $repoRoot 'scripts\Test-AgentKitCompatibility.ps1'
$builder = Join-Path $repoRoot 'scripts\Build-AgentKit.mjs'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "yohan-agent-kit-tests\compatibility-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$artifactRoot = Join-Path $fixtureRoot 'artifacts'
$release = 'test-compatibility-r1'
$null = New-Item -ItemType Directory -Path $artifactRoot -Force
$script:assertionCount = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertionCount++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertionCount++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }
function Get-TestSha256File {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-Compatibility {
    param([string[]]$Arguments, [string]$FixtureHome, [bool]$PermitSynthetic = $true)
    $base = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-RepositoryRoot', $repoRoot, '-HomeRoot', $FixtureHome, '-OutputFormat', 'Json')
    if ($PermitSynthetic) { $base += '-AllowSyntheticEvidence' }
    $output = @(& powershell @base @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    try { $data = $text | ConvertFrom-Json } catch { throw "Compatibility tool returned invalid JSON (exit=$exitCode): $text" }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Text = $text }
}

try {
    $buildOutput = @(& node $builder --release $release --output-root $artifactRoot --source-commit ('3' * 40) --allow-dirty --allow-test-output --json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Builder failed: $([string]::Join([Environment]::NewLine, $buildOutput))" }
    $releaseRoot = Join-Path $artifactRoot $release
    $home1 = Join-Path $fixtureRoot 'machine-a'
    $home2 = Join-Path $fixtureRoot 'machine-b'

    $deniedHome = Join-Path $fixtureRoot 'denied-home'
    $denied = Invoke-Compatibility -FixtureHome $deniedHome -Arguments @('-Mode', 'Probe', '-Release', $release, '-ReleaseRoot', $releaseRoot, '-AllowDirtyArtifact', '-MachineLabel', 'denied')
    Assert-Equal 1 $denied.ExitCode 'Probe requires evidence write approval'
    Assert-True (-not [IO.Directory]::Exists($deniedHome)) 'denied Probe does not create HomeRoot'

    $probe1 = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Probe', '-Release', $release, '-ReleaseRoot', $releaseRoot, '-AllowDirtyArtifact', '-MachineLabel', 'machine-a', '-ApproveEvidenceWrite')
    Assert-Equal 0 $probe1.ExitCode 'first machine Probe succeeds'
    Assert-Equal 'DraftEvidenceReady' $probe1.Data.status 'first draft status'
    $draft1 = [string]$probe1.Data.evidencePath
    $draftData = Get-Content -LiteralPath $draft1 -Raw | ConvertFrom-Json
    Assert-Equal 2 $draftData.schemaVersion 'new evidence uses the fail-closed v2 schema'
    Assert-Equal 'DRAFT' $draftData.status 'draft evidence cannot claim completion'
    Assert-Equal 'NOT_RUN' $draftData.vendors.'claude-code'.explicitSkill.status 'manual session starts NOT_RUN'
    Assert-Equal 'NOT_RUN' $draftData.vendors.antigravity.subagent.status 'Antigravity CLI subagent requires a real session'
    Assert-Equal 'PASS' $draftData.automated.releaseHashes 'release hashes automated'
    Assert-Equal 'PASS' $draftData.automated.packageLayout 'package layout automated'
    Assert-Equal 'PASS' $draftData.automated.cliCompatibility 'vendor CLI versions match the release contract'

    # The contract binds a version series, because vendor CLIs auto-update faster than a
    # sealing window. It must still reject a different series and a false prefix match.
    $toolSource = [IO.File]::ReadAllText($tool, [Text.Encoding]::UTF8)
    $ruleMatch = [regex]::Match($toolSource, '(?s)function Test-VendorVersionCompatible \{.*?\r?\n\}')
    Assert-True $ruleMatch.Success 'version compatibility rule is defined in the tool'
    . ([ScriptBlock]::Create($ruleMatch.Value))
    $seriesContract = [pscustomobject]@{ testedVersion = '2.1.233'; compatibleVersionPrefix = '2.1.' }
    $exactContract = [pscustomobject]@{ testedVersion = '2.1.233' }
    Assert-Equal $true (Test-VendorVersionCompatible -Reported '2.1.233 (Claude Code)' -Contract $seriesContract) 'the exercised patch stays compatible'
    Assert-Equal $true (Test-VendorVersionCompatible -Reported '2.1.238 (Claude Code)' -Contract $seriesContract) 'a newer patch in the same series stays compatible'
    Assert-Equal $false (Test-VendorVersionCompatible -Reported '2.2.0 (Claude Code)' -Contract $seriesContract) 'a different minor series is rejected'
    Assert-Equal $false (Test-VendorVersionCompatible -Reported '12.1.4 (Claude Code)' -Contract $seriesContract) 'a prefix match inside another number is rejected'
    Assert-Equal $false (Test-VendorVersionCompatible -Reported '' -Contract $seriesContract) 'an unreported version is rejected'
    Assert-Equal $false (Test-VendorVersionCompatible -Reported '2.1.238 (Claude Code)' -Contract $exactContract) 'without a prefix the contract still demands the exercised version'

    $draftHardLinkOutside = Join-Path $fixtureRoot 'draft-hardlink-outside.json'
    [IO.File]::WriteAllBytes($draftHardLinkOutside, [IO.File]::ReadAllBytes($draft1))
    $draftHardLinkPath = Join-Path $home1 '.yohan-agent-kit\evidence\hardlink-draft.json'
    $null = New-Item -ItemType HardLink -Path $draftHardLinkPath -Target $draftHardLinkOutside
    $hardLinkFinal = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', $draftHardLinkPath, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact', '-SessionResultsPath', (Join-Path $repoRoot 'fixtures\agent-kit-session-results.example.json'), '-TransactionResultsPath', (Join-Path $repoRoot 'fixtures\agent-kit-transaction-results.example.json'), '-ApproveEvidenceWrite')
    Assert-Equal 1 $hardLinkFinal.ExitCode 'Finalize rejects a hard-linked draft evidence file'
    Assert-True (@($hardLinkFinal.Data.errors | Where-Object { $_ -match 'linked entry' }).Count -eq 1) 'draft hard-link rejection reason'

    $invalidSessions = Join-Path $fixtureRoot 'invalid-sessions.json'
    [IO.File]::WriteAllText($invalidSessions, (ConvertTo-Json @{ 'claude-code' = @{ explicitSkill = @{ status = 'NOT_RUN'; evidence = '' } } } -Depth 8))
    $invalidFinal = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', $draft1, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact', '-SessionResultsPath', $invalidSessions, '-TransactionResultsPath', (Join-Path $repoRoot 'fixtures\agent-kit-transaction-results.example.json'), '-ApproveEvidenceWrite')
    Assert-Equal 1 $invalidFinal.ExitCode 'Finalize rejects incomplete manual sessions'

    $sessions = Join-Path $repoRoot 'fixtures\agent-kit-session-results.example.json'
    $transactions = Join-Path $repoRoot 'fixtures\agent-kit-transaction-results.example.json'
    $syntheticDenied = Invoke-Compatibility -FixtureHome $home1 -PermitSynthetic:$false -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', $draft1, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact', '-SessionResultsPath', $sessions, '-TransactionResultsPath', $transactions, '-ApproveEvidenceWrite', '-EvidencePath', (Join-Path $home1 '.yohan-agent-kit\evidence\synthetic-denied.json'))
    Assert-Equal 1 $syntheticDenied.ExitCode 'production finalization rejects test-only evidence'
    Assert-True (@($syntheticDenied.Data.errors | Where-Object { $_ -match 'test-only evidence' }).Count -eq 1) 'test-only rejection reason'
    $tamperedDraftPath = Join-Path $home1 '.yohan-agent-kit\evidence\tampered-draft.json'
    $tamperedDraft = Get-Content -LiteralPath $draft1 -Raw | ConvertFrom-Json
    $tamperedDraft.catalogDigest = ('e' * 64)
    [IO.File]::WriteAllText($tamperedDraftPath, (ConvertTo-Json $tamperedDraft -Depth 32), (New-Object Text.UTF8Encoding($false)))
    $tamperedDraftFinal = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', $tamperedDraftPath, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact', '-SessionResultsPath', $sessions, '-TransactionResultsPath', $transactions, '-ApproveEvidenceWrite')
    Assert-Equal 1 $tamperedDraftFinal.ExitCode 'Finalize revalidates draft release identity'
    Assert-True (@($tamperedDraftFinal.Data.errors | Where-Object { $_ -match 'verified artifact' }).Count -eq 1) 'draft identity tamper reason'

    $final1 = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', $draft1, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact', '-SessionResultsPath', $sessions, '-TransactionResultsPath', $transactions, '-ApproveEvidenceWrite')
    Assert-Equal 0 $final1.ExitCode 'first evidence finalizes with complete results'
    Assert-Equal 'FinalEvidenceReady' $final1.Data.status 'first final evidence status'
    Assert-True ([string]$final1.Data.evidenceDigest -match '^[a-f0-9]{64}$') 'first evidence has a SHA-256 seal'

    $kitRoot1 = Join-Path $home1 '.yohan-agent-kit'
    $installedReleaseRoot1 = Join-Path $kitRoot1 "releases\$release"
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $installedReleaseRoot1) -Force
    Copy-Item -LiteralPath $releaseRoot -Destination $installedReleaseRoot1 -Recurse
    $manifestSha256 = Get-TestSha256File -Path (Join-Path $installedReleaseRoot1 'release-manifest.json')
    $activeStatePath = Join-Path $kitRoot1 'active.json'
    [IO.File]::WriteAllText($activeStatePath, (ConvertTo-Json ([ordered]@{ schemaVersion = 1; releaseId = $release; manifestSha256 = $manifestSha256 })), (New-Object Text.UTF8Encoding($false)))
    $null = New-Item -ItemType Junction -Path (Join-Path $kitRoot1 'active') -Target $installedReleaseRoot1

    $singleMachine = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', [string]$final1.Data.evidencePath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    Assert-Equal 0 $singleMachine.ExitCode 'single-machine evidence verification succeeds'
    Assert-Equal 'SingleMachineVerified' $singleMachine.Data.status 'house PC evidence can satisfy the release gate by itself'
    Assert-Equal $release $singleMachine.Data.releaseId 'single-machine verification preserves release identity'

    $replayHome = Join-Path $fixtureRoot 'machine-a-replay'
    $replayKitRoot = Join-Path $replayHome '.yohan-agent-kit'
    $replayReleaseRoot = Join-Path $replayKitRoot "releases\$release"
    $replayEvidenceRoot = Join-Path $replayKitRoot 'evidence'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $replayReleaseRoot),$replayEvidenceRoot -Force
    Copy-Item -LiteralPath $installedReleaseRoot1 -Destination $replayReleaseRoot -Recurse
    $replayEvidencePath = Join-Path $replayEvidenceRoot 'replayed-final.json'
    [IO.File]::Copy([string]$final1.Data.evidencePath, $replayEvidencePath, $false)
    [IO.File]::Copy($activeStatePath, (Join-Path $replayKitRoot 'active.json'), $false)
    $null = New-Item -ItemType Junction -Path (Join-Path $replayKitRoot 'active') -Target $replayReleaseRoot
    $replayedHome = Invoke-Compatibility -FixtureHome $replayHome -Arguments @('-Mode', 'Verify', '-EvidencePath', $replayEvidencePath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    Assert-Equal 3 $replayedHome.ExitCode 'single-machine verification rejects a cloned HomeRoot replay'
    Assert-True (@($replayedHome.Data.errors | Where-Object { $_ -match 'HomeRoot digest' }).Count -eq 1) 'cloned HomeRoot replay rejection reason'

    $legacyEvidencePath = Join-Path $home1 '.yohan-agent-kit\evidence\legacy-v1-final.json'
    $legacyEvidence = Get-Content -LiteralPath ([string]$final1.Data.evidencePath) -Raw | ConvertFrom-Json
    $legacyEvidence.schemaVersion = 1
    $legacyEvidence.PSObject.Properties.Remove('homeRootDigest')
    foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
        $legacyCli = $legacyEvidence.cli.PSObject.Properties[$vendor].Value
        $legacyCli.PSObject.Properties.Remove('path')
        $legacyCli.PSObject.Properties.Remove('commandType')
        $legacyCli.PSObject.Properties.Remove('sha256')
    }
    [IO.File]::WriteAllText($legacyEvidencePath, (ConvertTo-Json $legacyEvidence -Depth 32), (New-Object Text.UTF8Encoding($false)))
    $legacyVerify = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', $legacyEvidencePath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    Assert-Equal 3 $legacyVerify.ExitCode 'single-machine verification rejects legacy evidence schema'
    Assert-True (@($legacyVerify.Data.errors | Where-Object { $_ -match 'schemaVersion must be 2' }).Count -eq 1) 'legacy evidence regeneration reason'

    $fakeCliBin = Join-Path $fixtureRoot 'fake-cli-bin'
    $null = New-Item -ItemType Directory -Path $fakeCliBin -Force
    $fakeAgy = Join-Path $fakeCliBin 'agy.cmd'
    $finalEvidence = Get-Content -LiteralPath ([string]$final1.Data.evidencePath) -Raw | ConvertFrom-Json
    [IO.File]::WriteAllText($fakeAgy, "@echo off`r`necho $([string]$finalEvidence.cli.antigravity.version)`r`n", (New-Object Text.ASCIIEncoding))
    $priorPath = $env:PATH
    try {
        $env:PATH = "$fakeCliBin;$priorPath"
        $shadowedCli = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', [string]$final1.Data.evidencePath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    }
    finally { $env:PATH = $priorPath }
    Assert-Equal 3 $shadowedCli.ExitCode 'single-machine verification rejects same-version PATH shadow CLI'
    Assert-True (@($shadowedCli.Data.errors | Where-Object { $_ -match 'CLI' }).Count -ge 1) 'PATH shadow CLI rejection reason'

    $wrongMachine = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', [string]$final1.Data.evidencePath, '-MachineLabel', 'machine-b', '-AllowDirtyArtifact')
    Assert-Equal 3 $wrongMachine.ExitCode 'single-machine verification rejects evidence from another machine identity'
    Assert-True (@($wrongMachine.Data.errors | Where-Object { $_ -match 'current machine' }).Count -eq 1) 'wrong-machine rejection reason'

    $activeStateBytes = [IO.File]::ReadAllBytes($activeStatePath)
    [IO.File]::WriteAllText($activeStatePath, (ConvertTo-Json ([ordered]@{ schemaVersion = 1; releaseId = 'stale-release'; manifestSha256 = $manifestSha256 })), (New-Object Text.UTF8Encoding($false)))
    $staleActive = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', [string]$final1.Data.evidencePath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    Assert-Equal 3 $staleActive.ExitCode 'single-machine verification rejects a stale active release state'
    Assert-True (@($staleActive.Data.errors | Where-Object { $_ -match 'active.json' }).Count -eq 1) 'stale active release rejection reason'
    [IO.File]::WriteAllBytes($activeStatePath, $activeStateBytes)

    $probe2 = Invoke-Compatibility -FixtureHome $home2 -Arguments @('-Mode', 'Probe', '-Release', $release, '-ReleaseRoot', $releaseRoot, '-AllowDirtyArtifact', '-MachineLabel', 'machine-b', '-ApproveEvidenceWrite')
    $final2 = Invoke-Compatibility -FixtureHome $home2 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', [string]$probe2.Data.evidencePath, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-b', '-AllowDirtyArtifact', '-SessionResultsPath', $sessions, '-TransactionResultsPath', $transactions, '-ApproveEvidenceWrite')
    Assert-Equal 0 $final2.ExitCode 'second evidence finalizes'

    $compare = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Compare', '-EvidencePath', [string]$final1.Data.evidencePath, '-OtherEvidencePath', [string]$final2.Data.evidencePath)
    Assert-Equal 0 $compare.ExitCode 'two-machine evidence comparison succeeds'
    Assert-Equal 'Compatible' $compare.Data.status 'two-machine compatible status'
    Assert-True ([string]$compare.Data.machineIds[0] -cne [string]$compare.Data.machineIds[1]) 'machine IDs differ'
    Assert-Equal $release $compare.Data.releaseId 'same release identity required'

    $tamperedPath = Join-Path $home1 '.yohan-agent-kit\evidence\tampered-final.json'
    $tampered = Get-Content -LiteralPath ([string]$final2.Data.evidencePath) -Raw | ConvertFrom-Json
    $tampered.catalogDigest = ('f' * 64)
    [IO.File]::WriteAllText($tamperedPath, (ConvertTo-Json $tampered -Depth 32), (New-Object Text.UTF8Encoding($false)))
    $tamperedVerify = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Verify', '-EvidencePath', $tamperedPath, '-MachineLabel', 'machine-a', '-AllowDirtyArtifact')
    Assert-Equal 3 $tamperedVerify.ExitCode 'single-machine verification rejects a tampered seal'
    Assert-True (@($tamperedVerify.Data.errors | Where-Object { $_ -match 'seal' }).Count -eq 1) 'single-machine tamper reason'
    $tamperedCompare = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Compare', '-EvidencePath', [string]$final1.Data.evidencePath, '-OtherEvidencePath', $tamperedPath)
    Assert-Equal 3 $tamperedCompare.ExitCode 'tampered evidence comparison conflicts'
    Assert-True (@($tamperedCompare.Data.errors | Where-Object { $_ -match 'catalogDigest|seal' }).Count -ge 1) 'tampered evidence reason'

    $sameMachine = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Compare', '-EvidencePath', [string]$final1.Data.evidencePath, '-OtherEvidencePath', [string]$final1.Data.evidencePath)
    Assert-Equal 3 $sameMachine.ExitCode 'same-machine evidence cannot satisfy two-PC gate'
    Assert-True (@($sameMachine.Data.errors | Where-Object { $_ -match 'different machines' }).Count -eq 1) 'same machine rejection reason'

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
