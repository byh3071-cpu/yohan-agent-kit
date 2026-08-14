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
    Assert-Equal 'DRAFT' $draftData.status 'draft evidence cannot claim completion'
    Assert-Equal 'NOT_RUN' $draftData.vendors.'claude-code'.explicitSkill.status 'manual session starts NOT_RUN'
    Assert-Equal 'NOT_RUN' $draftData.vendors.antigravity.subagent.status 'Antigravity CLI subagent requires a real session'
    Assert-Equal 'PASS' $draftData.automated.releaseHashes 'release hashes automated'
    Assert-Equal 'PASS' $draftData.automated.packageLayout 'package layout automated'
    Assert-Equal 'PASS' $draftData.automated.cliCompatibility 'vendor CLI versions match the release contract'

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

    $probe2 = Invoke-Compatibility -FixtureHome $home2 -Arguments @('-Mode', 'Probe', '-Release', $release, '-ReleaseRoot', $releaseRoot, '-AllowDirtyArtifact', '-MachineLabel', 'machine-b', '-ApproveEvidenceWrite')
    $final2 = Invoke-Compatibility -FixtureHome $home2 -Arguments @('-Mode', 'Finalize', '-DraftEvidencePath', [string]$probe2.Data.evidencePath, '-ReleaseRoot', $releaseRoot, '-MachineLabel', 'machine-b', '-AllowDirtyArtifact', '-SessionResultsPath', $sessions, '-TransactionResultsPath', $transactions, '-ApproveEvidenceWrite')
    Assert-Equal 0 $final2.ExitCode 'second evidence finalizes'

    $compare = Invoke-Compatibility -FixtureHome $home1 -Arguments @('-Mode', 'Compare', '-EvidencePath', [string]$final1.Data.evidencePath, '-OtherEvidencePath', [string]$final2.Data.evidencePath)
    Assert-Equal 0 $compare.ExitCode 'two-machine evidence comparison succeeds'
    Assert-Equal 'Compatible' $compare.Data.status 'two-machine compatible status'
    Assert-True ([string]$compare.Data.machineIds[0] -cne [string]$compare.Data.machineIds[1]) 'machine IDs differ'
    Assert-Equal $release $compare.Data.releaseId 'same release identity required'

    $tamperedPath = Join-Path $home2 '.yohan-agent-kit\evidence\tampered-final.json'
    $tampered = Get-Content -LiteralPath ([string]$final2.Data.evidencePath) -Raw | ConvertFrom-Json
    $tampered.catalogDigest = ('f' * 64)
    [IO.File]::WriteAllText($tamperedPath, (ConvertTo-Json $tampered -Depth 32), (New-Object Text.UTF8Encoding($false)))
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
