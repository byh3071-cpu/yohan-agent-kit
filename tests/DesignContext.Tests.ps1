#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$BrainRoot)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolver = Join-Path $repoRoot 'scripts\Resolve-DesignContext.ps1'
$recorder = Join-Path $repoRoot 'scripts\Record-DesignDecision.ps1'
$fixtureRoot = Join-Path $PSScriptRoot ('.work\design-context-{0}' -f [Guid]::NewGuid().ToString('N'))
$powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$script:assertions = 0
$script:failure = $null

function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" }
}

function Invoke-JsonScript([string]$Path, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    $text = [string]::Join("`n", @($output | ForEach-Object { [string]$_ }))
    $data = $null
    if ($exitCode -eq 0) {
        try { $data = $text | ConvertFrom-Json }
        catch { throw "Successful script returned invalid JSON: $text" }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Text = $text; Data = $data }
}

function Remove-FixtureSafely {
    if (-not [IO.Directory]::Exists($fixtureRoot)) { return }
    $workRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $target.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped tests/.work' }
    Remove-Item -LiteralPath $target -Recurse -Force
}

try {
    Assert-True ([IO.Directory]::Exists($BrainRoot)) 'BrainRoot exists'
    Assert-True ([IO.File]::Exists($resolver)) 'resolver exists'
    Assert-True ([IO.File]::Exists($recorder)) 'recorder exists'

    $beforeStatus = @(& git.exe -c "safe.directory=$BrainRoot" -C $BrainRoot status --porcelain=v1 --untracked-files=no)
    $resolve = Invoke-JsonScript $resolver @(
        '-BrainRoot', $BrainRoot,
        '-ProjectRoot', $repoRoot,
        '-CurrentRequestPath', 'fixtures/design-context-html-slice/context/current-request.json',
        '-ProjectContextPath', 'fixtures/design-context-html-slice/context/project-context.json',
        '-OutputFormat', 'Json'
    )
    Assert-Equal 0 $resolve.ExitCode 'resolver exit code'
    Assert-Equal 'f7615ac2fce83bd93c37801c14640c20dede5980' ([string]$resolve.Data.designContext.contract.ref) 'pinned contract ref'
    Assert-Equal 'current-request,project-git,media,common-taste,golden' ([string]::Join(',', @($resolve.Data.designContext.resolutionOrder))) 'resolution order'
    Assert-Equal 'stage-first-confirmation' ([string]$resolve.Data.designContext.constraints.interactionModel) 'current request wins constraint conflict'
    Assert-Equal 5 @($resolve.Data.designContext.tiers).Count 'all tiers remain explicit'
    Assert-Equal 3 @($resolve.Data.designContext.approvedSources).Count 'approved sources deduplicate deterministically'
    Assert-Equal 'context-trust-navigator-432-verification' ([string]@($resolve.Data.designContext.approvedSources)[0].id) 'current request source order wins'
    Assert-True ([string]$resolve.Data.workContext.goal -match 'DesignContext resolver') 'WorkContext is preserved'
    Assert-True (@($resolve.Data.diagnostics) -contains 'stable-auto-promotion-disabled') 'promotion diagnostic'
    $afterStatus = @(& git.exe -c "safe.directory=$BrainRoot" -C $BrainRoot status --porcelain=v1 --untracked-files=no)
    Assert-Equal ([string]::Join("`n", $beforeStatus)) ([string]::Join("`n", $afterStatus)) 'resolver is read-only against Brain worktree'

    $wrongRef = Invoke-JsonScript $resolver @(
        '-BrainRoot', $BrainRoot, '-ProjectRoot', $repoRoot,
        '-CurrentRequestPath', 'fixtures/design-context-html-slice/context/current-request.json',
        '-ProjectContextPath', 'fixtures/design-context-html-slice/context/project-context.json',
        '-ContractRef', '0000000000000000000000000000000000000000'
    )
    Assert-Equal 3 $wrongRef.ExitCode 'resolver rejects a different contract ref'

    $eventsDirectory = Join-Path $fixtureRoot 'memory\design-intelligence\events'
    $null = New-Item -ItemType Directory -Path $eventsDirectory -Force
    $logRelative = 'memory/design-intelligence/events/2026-08-14-test.jsonl'
    $badContractRelative = 'memory/design-intelligence/events/2026-08-14-bad-contract.jsonl'
    $badContract = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-ContractRef', '0000000000000000000000000000000000000000', '-EventLogPath', $badContractRelative,
        '-EventId', 'bad-contract', '-OccurredAt', '2026-08-14T11:50:00+09:00',
        '-ActorType', 'tool', '-ActorId', 'test', '-Action', 'observed',
        '-SubjectRef', 'invalid-contract', '-Decision', 'reuse', '-EvidenceRefs', 'test:evidence'
    )
    Assert-Equal 3 $badContract.ExitCode 'recorder rejects a different contract ref'
    Assert-True (-not [IO.File]::Exists((Join-Path $fixtureRoot ($badContractRelative.Replace('/', '\'))))) 'rejected contract creates no event log'

    $orphanRelative = 'memory/design-intelligence/events/2026-08-14-orphan.jsonl'
    $orphan = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $orphanRelative,
        '-EventId', 'orphan', '-OccurredAt', '2026-08-14T11:55:00+09:00',
        '-ActorType', 'tool', '-ActorId', 'test', '-Action', 'observed',
        '-SubjectRef', 'invalid-chain', '-Decision', 'reuse', '-EvidenceRefs', 'test:evidence',
        '-PreviousEventRef', 'absent-event'
    )
    Assert-Equal 3 $orphan.ExitCode 'first event cannot reference an absent event'
    Assert-True (-not [IO.File]::Exists((Join-Path $fixtureRoot ($orphanRelative.Replace('/', '\'))))) 'rejected first event creates no event log'

    $first = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $logRelative,
        '-EventId', 'slice-proposed', '-OccurredAt', '2026-08-14T12:00:00+09:00',
        '-ActorType', 'agent', '-ActorId', 'codex', '-Action', 'proposed',
        '-SubjectRef', 'project-git:fixtures/design-context-html-slice/index.html',
        '-Decision', 'adapt', '-EvidenceRefs', 'git:yohan-brain/navigator-432.png@7d82b08720ab4b20bd75dd38b969be37120707fc'
    )
    Assert-Equal 0 $first.ExitCode 'first decision append'
    Assert-Equal 'adapt' ([string]$first.Data.decision) 'decision allowlist value is returned'
    Assert-Equal $false ([bool]$first.Data.stableAutoPromotion) 'stable auto promotion remains false'
    $logPath = Join-Path $fixtureRoot ($logRelative.Replace('/', '\'))
    $firstBytes = [IO.File]::ReadAllBytes($logPath)
    $firstEvent = ([IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8).Trim() | ConvertFrom-Json)
    Assert-True (@($firstEvent.evidence_refs) -contains 'decision:adapt') 'design decision is schema-compatible evidence'
    Assert-Equal $true ([bool]$firstEvent.append_only) 'append-only schema flag'

    $second = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $logRelative,
        '-EventId', 'slice-reviewed', '-OccurredAt', '2026-08-14T12:10:00+09:00',
        '-ActorType', 'tool', '-ActorId', 'design-qa', '-Action', 'reviewed',
        '-SubjectRef', 'project-git:fixtures/design-context-html-slice/index.html',
        '-Decision', 'adapt', '-EvidenceRefs', 'project-git:fixtures/design-context-html-slice/evidence/design-qa.md',
        '-PreviousEventRef', 'slice-proposed'
    )
    Assert-Equal 0 $second.ExitCode 'second decision append'
    $secondBytes = [IO.File]::ReadAllBytes($logPath)
    Assert-True ($secondBytes.Length -gt $firstBytes.Length) 'append grows the log'
    Assert-Equal ([Convert]::ToBase64String($firstBytes)) ([Convert]::ToBase64String($secondBytes[0..($firstBytes.Length - 1)])) 'existing event bytes are unchanged'

    $duplicate = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $logRelative,
        '-EventId', 'slice-reviewed', '-OccurredAt', '2026-08-14T12:20:00+09:00',
        '-ActorType', 'agent', '-ActorId', 'codex', '-Action', 'proposed',
        '-SubjectRef', 'duplicate', '-Decision', 'reuse', '-EvidenceRefs', 'test:evidence',
        '-PreviousEventRef', 'slice-reviewed'
    )
    Assert-Equal 3 $duplicate.ExitCode 'duplicate event id is rejected'
    Assert-Equal ([Convert]::ToBase64String($secondBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($logPath))) 'rejected append leaves the log byte-identical'

    $agentAccept = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $logRelative,
        '-EventId', 'slice-accepted', '-OccurredAt', '2026-08-14T12:30:00+09:00',
        '-ActorType', 'agent', '-ActorId', 'codex', '-Action', 'accepted',
        '-SubjectRef', 'invalid-human-gate', '-Decision', 'create', '-EvidenceRefs', 'test:evidence',
        '-PreviousEventRef', 'slice-reviewed', '-ApprovalRef', 'human-approval:test'
    )
    Assert-Equal 3 $agentAccept.ExitCode 'agent cannot accept or promote'

    $invalidDecision = Invoke-JsonScript $recorder @(
        '-BrainRoot', $fixtureRoot, '-ContractRepositoryRoot', $BrainRoot, '-EventLogPath', $logRelative,
        '-EventId', 'slice-invalid', '-OccurredAt', '2026-08-14T12:40:00+09:00',
        '-ActorType', 'tool', '-ActorId', 'test', '-Action', 'observed',
        '-SubjectRef', 'invalid', '-Decision', 'copy', '-EvidenceRefs', 'test:evidence',
        '-PreviousEventRef', 'slice-reviewed'
    )
    Assert-True ($invalidDecision.ExitCode -ne 0) 'decision outside reuse|adapt|remix|create is rejected'
}
catch { $script:failure = [string]$_.Exception.Message }
finally {
    try { Remove-FixtureSafely }
    catch { if ($null -eq $script:failure) { $script:failure = [string]$_.Exception.Message } }
}

if ($null -eq $script:failure) {
    Write-Output "PASS: $script:assertions assertions"
    exit 0
}
Write-Output "ERROR: $script:failure"
Write-Output "FAIL after $script:assertions assertions"
exit 1
