#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manager = Join-Path $repoRoot 'scripts\Manage-AgentIntake.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "yohan-agent-kit-tests\intake-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$homeRoot = Join-Path $fixtureRoot 'home'
$sourceRoot = Join-Path $fixtureRoot 'sources'
$null = New-Item -ItemType Directory -Path $sourceRoot -Force
$script:assertionCount = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertionCount++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertionCount++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }
function Get-TestSha256File { param([string]$Path); $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($Path); try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() } finally { $stream.Dispose(); $sha.Dispose() } }

function Invoke-Intake {
    param([string[]]$Arguments)
    $base = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $manager, '-RepositoryRoot', $repoRoot, '-HomeRoot', $homeRoot, '-OutputFormat', 'Json')
    $output = @(& powershell @base @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    try { $data = $text | ConvertFrom-Json } catch { throw "Intake returned invalid JSON (exit=$exitCode): $text" }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Text = $text }
}

try {
    $safeSkill = Join-Path $sourceRoot 'yohan-html-taste'
    $null = New-Item -ItemType Directory -Path (Join-Path $safeSkill 'references') -Force
    [IO.File]::WriteAllText((Join-Path $safeSkill 'SKILL.md'), "---`nname: yohan-html-taste`ndescription: Preserve Yohan HTML taste.`n---`n`nUse the reference.`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $safeSkill 'references\taste.md'), "# Taste`nAvoid generic AI gradients.`n", (New-Object Text.UTF8Encoding($false)))

    $denied = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $safeSkill, '-Kind', 'skill', '-CanonicalId', 'skill.yohan-html-taste', '-Provenance', 'local-authored:test', '-License', 'MIT')
    Assert-Equal 1 $denied.ExitCode 'Scan requires explicit inbox approval'
    Assert-True (@($denied.Data.blockers | Where-Object { $_ -match 'ApproveInboxWrite' }).Count -eq 1) 'missing inbox approval reason'
    Assert-True (-not [IO.Directory]::Exists($homeRoot)) 'denied Scan does not create HomeRoot'

    $scan = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $safeSkill, '-Kind', 'skill', '-CanonicalId', 'skill.yohan-html-taste', '-Provenance', 'local-authored:test', '-License', 'MIT', '-ApproveInboxWrite')
    Assert-Equal 0 $scan.ExitCode 'safe candidate scan succeeds'
    Assert-Equal 'CandidateReady' $scan.Data.status 'safe candidate status'
    Assert-Equal 'candidate' $scan.Data.lifecycle 'initial lifecycle'
    $candidateId = [string]$scan.Data.candidateId
    $candidatePath = Join-Path $homeRoot ".yohan-agent-kit\inbox\$candidateId\candidate.json"
    Assert-True ([IO.File]::Exists($candidatePath)) 'candidate metadata stored in local inbox'
    $candidateText = [IO.File]::ReadAllText($candidatePath, [Text.Encoding]::UTF8)
    Assert-True ($candidateText -notmatch [regex]::Escape($fixtureRoot)) 'candidate metadata omits local absolute source path'
    $candidate = $candidateText | ConvertFrom-Json
    Assert-Equal $false $candidate.pushAuthorized 'candidate cannot authorize push'
    Assert-True ([IO.File]::Exists((Join-Path $homeRoot ".yohan-agent-kit\inbox\$candidateId\raw\SKILL.md"))) 'raw source preserved locally'

    $candidateHardLinkOutside = Join-Path $fixtureRoot 'candidate-hardlink-outside.json'
    [IO.File]::WriteAllBytes($candidateHardLinkOutside, [IO.File]::ReadAllBytes($candidatePath))
    $candidateHardLinkOutsideHash = Get-TestSha256File -Path $candidateHardLinkOutside
    [IO.File]::Delete($candidatePath)
    $null = New-Item -ItemType HardLink -Path $candidatePath -Target $candidateHardLinkOutside
    $hardLinkCheck = Invoke-Intake -Arguments @('-Mode', 'Check', '-CandidateId', $candidateId)
    Assert-Equal 1 $hardLinkCheck.ExitCode 'candidate metadata hard link is rejected'
    Assert-True (@($hardLinkCheck.Data.blockers | Where-Object { $_ -match 'linked entry' }).Count -eq 1) 'candidate hard-link rejection reason'
    Assert-Equal $candidateHardLinkOutsideHash (Get-TestSha256File -Path $candidateHardLinkOutside) 'candidate hard link cannot modify outside bytes'
    [IO.File]::Delete($candidatePath)
    [IO.File]::WriteAllBytes($candidatePath, [IO.File]::ReadAllBytes($candidateHardLinkOutside))

    $check = Invoke-Intake -Arguments @('-Mode', 'Check', '-CandidateId', $candidateId)
    Assert-Equal 'CandidateReady' $check.Data.status 'candidate Check'
    $review = Invoke-Intake -Arguments @('-Mode', 'Review', '-CandidateId', $candidateId, '-ApproveInboxWrite')
    Assert-Equal 'Reviewed' $review.Data.status 'human-gated review advances once'
    Assert-Equal 'reviewed' $review.Data.lifecycle 'reviewed lifecycle ceiling'
    $export = Invoke-Intake -Arguments @('-Mode', 'ExportDraft', '-CandidateId', $candidateId, '-ApproveInboxWrite')
    Assert-Equal 'DraftBundleReady' $export.Data.status 'reviewed candidate exports a Draft PR bundle'
    Assert-Equal $false $export.Data.pushAuthorized 'Draft bundle never authorizes push'
    $proposal = Get-Content -LiteralPath (Join-Path ([string]$export.Data.draftPath) 'proposal.json') -Raw | ConvertFrom-Json
    Assert-Equal 'reviewed' $proposal.lifecycle 'Draft proposal cannot auto-approve'
    Assert-True ([string]$proposal.nextHumanAction -match 'explicitly approve') 'Draft proposal requires explicit push approval'
    $secondExport = Invoke-Intake -Arguments @('-Mode', 'ExportDraft', '-CandidateId', $candidateId, '-ApproveInboxWrite')
    Assert-Equal 1 $secondExport.ExitCode 'Draft bundle is immutable'

    Start-Sleep -Milliseconds 2
    $duplicate = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $safeSkill, '-Kind', 'skill', '-CanonicalId', 'skill.yohan-html-taste', '-Provenance', 'local-authored:test-duplicate', '-License', 'MIT', '-ApproveInboxWrite')
    Assert-Equal 3 $duplicate.ExitCode 'duplicate candidate is blocked'
    Assert-Equal 'BlockedCandidate' $duplicate.Data.status 'duplicate status'
    Assert-True (@($duplicate.Data.blockers | Where-Object { $_ -match '^duplicate:' }).Count -eq 1) 'duplicate blocker recorded'

    $secretSkill = Join-Path $sourceRoot 'secret-skill'
    $null = New-Item -ItemType Directory -Path $secretSkill -Force
    [IO.File]::WriteAllText((Join-Path $secretSkill 'SKILL.md'), "---`nname: secret-skill`ndescription: test`n---`npassword = 'DUMMY_TEST_VALUE_00000000'`n")
    $secret = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $secretSkill, '-Kind', 'skill', '-CanonicalId', 'skill.secret-test', '-Provenance', 'external:https://example.invalid', '-License', 'UNKNOWN', '-ApproveInboxWrite')
    Assert-Equal 3 $secret.ExitCode 'secret and unknown license candidate is blocked'
    Assert-True (@($secret.Data.blockers | Where-Object { $_ -match '^secret-pattern:' }).Count -eq 1) 'secret blocker recorded without value'
    Assert-True (@($secret.Data.blockers | Where-Object { $_ -match '^license:UNKNOWN' }).Count -eq 1) 'unknown license blocker recorded'
    $blockedReview = Invoke-Intake -Arguments @('-Mode', 'Review', '-CandidateId', [string]$secret.Data.candidateId, '-ApproveInboxWrite')
    Assert-Equal 1 $blockedReview.ExitCode 'blocked candidate cannot become reviewed'
    $secretCandidatePath = Join-Path $homeRoot ".yohan-agent-kit\inbox\$([string]$secret.Data.candidateId)\candidate.json"
    $secretCandidate = Get-Content -LiteralPath $secretCandidatePath -Raw | ConvertFrom-Json
    $secretCandidate.blockers = @()
    $secretCandidate.secretFindings = @()
    $secretCandidate.license = 'MIT'
    [IO.File]::WriteAllText($secretCandidatePath, (ConvertTo-Json $secretCandidate -Depth 24), (New-Object Text.UTF8Encoding($false)))
    $tamperedSecretReview = Invoke-Intake -Arguments @('-Mode', 'Review', '-CandidateId', [string]$secret.Data.candidateId, '-ApproveInboxWrite')
    Assert-Equal 1 $tamperedSecretReview.ExitCode 'editing candidate metadata cannot bypass raw secret inspection'
    Assert-True (@($tamperedSecretReview.Data.blockers | Where-Object { $_ -match 'secret-pattern' }).Count -eq 1) 'raw secret is re-detected during review'

    $driftSkill = Join-Path $sourceRoot 'drift-skill'
    $null = New-Item -ItemType Directory -Path $driftSkill -Force
    [IO.File]::WriteAllText((Join-Path $driftSkill 'SKILL.md'), "---`nname: drift-skill`ndescription: drift test`n---`n")
    $driftScan = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $driftSkill, '-Kind', 'skill', '-CanonicalId', 'skill.drift-test', '-Provenance', 'local-authored:drift', '-License', 'MIT', '-ApproveInboxWrite')
    Assert-Equal 0 $driftScan.ExitCode 'drift fixture candidate is accepted initially'
    $driftRaw = Join-Path $homeRoot ".yohan-agent-kit\inbox\$([string]$driftScan.Data.candidateId)\raw\SKILL.md"
    [IO.File]::AppendAllText($driftRaw, "tampered`n")
    $driftCheck = Invoke-Intake -Arguments @('-Mode', 'Check', '-CandidateId', [string]$driftScan.Data.candidateId)
    Assert-Equal 'BlockedCandidate' $driftCheck.Data.status 'raw candidate drift changes Check status'
    Assert-True (@($driftCheck.Data.blockers | Where-Object { $_ -match 'candidate-raw-drift' }).Count -eq 1) 'raw drift blocker recorded'
    $driftReview = Invoke-Intake -Arguments @('-Mode', 'Review', '-CandidateId', [string]$driftScan.Data.candidateId, '-ApproveInboxWrite')
    Assert-Equal 1 $driftReview.ExitCode 'raw drift cannot become reviewed'

    $pathRule = Join-Path $sourceRoot 'path-rule.md'
    [IO.File]::WriteAllText($pathRule, 'Use C:\Users\someone\private\tool.exe')
    $absolute = Invoke-Intake -Arguments @('-Mode', 'Scan', '-SourcePath', $pathRule, '-Kind', 'rule', '-CanonicalId', 'rule.absolute-test', '-Provenance', 'local-authored:test', '-License', 'UNLICENSED', '-ApproveInboxWrite')
    Assert-Equal 3 $absolute.ExitCode 'machine absolute path candidate is blocked'
    Assert-True (@($absolute.Data.blockers | Where-Object { $_ -match '^absolute-path:' }).Count -eq 1) 'absolute path blocker recorded'

    $inventory = Invoke-Intake -Arguments @('-Mode', 'Check')
    Assert-Equal 0 $inventory.ExitCode 'inbox inventory is readable'
    Assert-True ([int]$inventory.Data.candidateCount -ge 5) 'inbox retains safe and blocked candidates'
    foreach ($item in @($inventory.Data.candidates)) { Assert-True ([string]$item.lifecycle -notin @('approved', 'released')) 'AI intake never creates approved or released lifecycle' }

    $gitStatus = @(& git.exe -C $repoRoot status --short)
    Assert-True (@($gitStatus | Where-Object { $_ -match '\.yohan-agent-kit|inbox' }).Count -eq 0) 'raw inbox never enters repository status'

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
