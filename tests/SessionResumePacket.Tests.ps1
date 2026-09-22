#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cli = Join-Path $repoRoot 'scripts\SessionResumePacket.mjs'
$fixturePath = Join-Path $PSScriptRoot 'fixtures\session-resume-packet-cases.json'
$fixture = [IO.File]::ReadAllText($fixturePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("yohan-session-resume-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
$gitRoot = Join-Path $testRoot 'yohan-agent-kit'
$evidenceRoot = Join-Path $testRoot 'yohan-brain'
$contextPath = Join-Path $testRoot 'context.json'
$packetPath = Join-Path $gitRoot '.vhk\receipts\packet.json'
$ackPath = Join-Path $gitRoot '.vhk\receipts\ack.json'
$sourceRef = 'codex/tasks/p2-session-resume'
$ownershipRelative = '.vhk/ownership/current.json'
$ownershipPath = Join-Path $gitRoot '.vhk\ownership\current.json'
$script:assertions = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertions++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertions++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }
function Write-Utf8NoBom { param([string]$Path, [string]$Text); $parent = Split-Path -Parent $Path; if ($parent -and -not [IO.Directory]::Exists($parent)) { $null = [IO.Directory]::CreateDirectory($parent) }; [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false))) }
function Copy-JsonObject { param($Value); return (($Value | ConvertTo-Json -Depth 30 -Compress) | ConvertFrom-Json) }
function Get-NormalizedSha256 {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-TextSha256 {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Write-OwnershipState {
    param(
        [string]$Writer = 'codex-p2', [int]$Epoch = 7, [string]$Liveness = 'active',
        [string]$StateSourceRef = $sourceRef, [string]$Gate = 'implementation',
        [string]$UpdatedAt = '2026-09-22T00:05:00Z', [switch]$TamperDigest
    )
    $canonical = [ordered]@{
        active_writer = $Writer; current_gate = $Gate; liveness = $Liveness; schema = 'session-ownership/v1'
        source_ref = $StateSourceRef; updated_at = $UpdatedAt; writer_epoch = $Epoch
    } | ConvertTo-Json -Compress
    $digest = if ($TamperDigest) { '0' * 64 } else { Get-TextSha256 $canonical }
    $state = [ordered]@{
        schema = 'session-ownership/v1'; active_writer = $Writer; writer_epoch = $Epoch; liveness = $Liveness
        source_ref = $StateSourceRef; current_gate = $Gate; updated_at = $UpdatedAt; content_digest = $digest
    }
    Write-Utf8NoBom $ownershipPath ($state | ConvertTo-Json -Compress)
}

function Invoke-ResumeCli {
    param([string[]]$Arguments, [string]$StdinText = '')
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($StdinText) { $output = @($StdinText | & node $cli @Arguments 2>&1) }
        else { $output = @(& node $cli @Arguments 2>&1) }
        $exit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prior }
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    $data = $null
    if ($text.Trim()) { $data = $text | ConvertFrom-Json }
    return [pscustomobject]@{ ExitCode = $exit; Text = $text; Data = $data }
}

function Get-PacketDigest { param([string]$Path); return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json).receipts.content.digest }

function Invoke-Prepare {
    param([string]$InputPath = $contextPath, [string]$Output = '.vhk/receipts/packet.json', [string]$ResolutionNextAction = '', [string]$PacketSourceRef = $sourceRef)
    $arguments = @(
        'prepare', '--context', $InputPath, '--repo-root', $gitRoot, '--evidence-root', $evidenceRoot, '--ownership-state', $ownershipRelative,
        '--source-ref', $PacketSourceRef, '--current-gate', 'implementation', '--writer', 'codex-p2', '--writer-epoch', '7',
        '--allow', 'Implement the approved P2 packet contract', '--forbid', 'Merge or deploy without a human gate',
        '--human-gate', 'PR Ready and merge', '--now', [string]$fixture.now
    )
    if ($ResolutionNextAction) { $arguments += @('--resolution-next-action', $ResolutionNextAction) }
    if ($Output) { $arguments += @('--output', $Output) }
    return Invoke-ResumeCli -Arguments $arguments
}

function Invoke-Verify {
    param([string]$InputPath = $packetPath, [string]$ContextInput = $contextPath, [string]$Epoch = '7', [string]$PacketDigest = '')
    if (-not $PacketDigest) { $PacketDigest = Get-PacketDigest -Path $InputPath }
    return Invoke-ResumeCli -Arguments @(
        'verify', '--packet', $InputPath, '--context', $ContextInput, '--repo-root', $gitRoot, '--evidence-root', $evidenceRoot, '--ownership-state', $ownershipRelative,
        '--expected-writer', 'codex-p2', '--expected-writer-epoch', $Epoch, '--expected-packet-digest', $PacketDigest,
        '--now', [string]$fixture.now
    )
}

function Get-AckArguments {
    param([string]$Packet = $packetPath, [string]$Context = $contextPath, [string]$Digest = '', [string]$AckSourceRef = $sourceRef, [string]$Action = 'Implement prepare, verify, and acknowledge')
    if (-not $Digest) { $Digest = Get-PacketDigest -Path $Packet }
    return @(
        'ack', '--packet', $Packet, '--context', $Context, '--repo-root', $gitRoot, '--evidence-root', $evidenceRoot, '--ownership-state', $ownershipRelative,
        '--expected-writer', 'codex-p2', '--expected-writer-epoch', '7', '--expected-packet-digest', $Digest,
        '--receiver', 'claude-desktop', '--owner-scope', 'yohan-agent-kit', '--source-ref', $AckSourceRef,
        '--current-gate', 'implementation', '--next-action', $Action, '--now', [string]$fixture.now
    )
}

$exitCode = 1
try {
    $null = New-Item -ItemType Directory -Force -Path $gitRoot, $evidenceRoot
    Write-Utf8NoBom (Join-Path $gitRoot '.gitignore') ".vhk/receipts/`n.vhk/ownership/`n"
    Write-Utf8NoBom (Join-Path $gitRoot 'README.md') "# fixture`n"
    & git -C $gitRoot init --quiet
    & git -C $gitRoot config user.name 'Session Resume Tests'
    & git -C $gitRoot config user.email 'session-resume@example.invalid'
    & git -C $gitRoot add .gitignore README.md
    & git -C $gitRoot commit --quiet -m 'fixture'
    Assert-Equal 0 $LASTEXITCODE 'fixture Git repository initializes'
    $baseSha = [string](& git -C $gitRoot rev-parse HEAD)

    $goalEvidencePath = Join-Path $evidenceRoot 'memory\goals\goal-18.md'
    $partialEvidencePath = Join-Path $evidenceRoot 'memory\decisions\p2-roadmap.md'
    $otherEvidencePath = Join-Path $evidenceRoot 'memory\other.md'
    Write-Utf8NoBom $goalEvidencePath "# Goal 18`n"
    Write-Utf8NoBom $partialEvidencePath "# P2 roadmap`n"
    Write-Utf8NoBom $otherEvidencePath "# Other`n"
    $goalHash = Get-NormalizedSha256 $goalEvidencePath
    $partialHash = Get-NormalizedSha256 $partialEvidencePath
    $otherHash = Get-NormalizedSha256 $otherEvidencePath
    $fixture.context.data.task_context.goals[0].source_ref.content_hash = $goalHash
    $fixture.context.data.task_context.evidence_refs[0].content_hash = $goalHash
    $fixture.actual_partial_task_context.evidence_refs[0].content_hash = $partialHash
    Write-Utf8NoBom $contextPath ($fixture.context | ConvertTo-Json -Depth 30 -Compress)
    Write-OwnershipState

    $dirtyPrepareProbe = Join-Path $gitRoot 'dirty-before-prepare.txt'
    Write-Utf8NoBom $dirtyPrepareProbe "dirty`n"
    $dirtyPrepare = Invoke-Prepare -Output ''
    Assert-Equal 'dirty_repository' $dirtyPrepare.Data.reason_code 'prepare rejects dirty repository'
    Remove-Item -LiteralPath $dirtyPrepareProbe -Force

    $prepared = Invoke-Prepare
    Assert-Equal 0 $prepared.ExitCode 'valid prepare succeeds'
    Assert-Equal 'session-resume-packet/v1' $prepared.Data.schema 'prepare success schema'
    Assert-Equal $sourceRef $prepared.Data.source_ref 'prepare binds explicit source ref'
    Assert-True ([IO.File]::Exists($packetPath)) 'prepare writes project-owned receipt'
    Assert-Equal $baseSha $prepared.Data.repository.git.sha 'prepare binds exact live Git SHA'
    Assert-Equal $false $prepared.Data.repository.git.dirty 'packets require clean Git state'
    Assert-Equal $ownershipRelative $prepared.Data.ownership.source_path 'packet stores relative ownership state path'
    Assert-Equal 'active' $prepared.Data.ownership.liveness 'packet binds active ownership liveness'
    Assert-Equal 3600 $prepared.Data.ownership.max_age_seconds 'packet binds fixed ownership maximum age'
    Assert-Equal 300 $prepared.Data.ownership.future_skew_seconds 'packet binds fixed ownership future skew'
    Assert-Equal $true $prepared.Data.lineage.context_envelope.volatile 'volatile provenance is preserved'
    Assert-Equal $false $prepared.Data.lineage.context_envelope.persisted 'non-persisted provenance is preserved'
    Assert-True ([string]$prepared.Data.lineage.context_envelope.digest -match '^[a-f0-9]{64}$') 'canonical context digest is present'
    Assert-Equal 'REAL_MACHINE_UNVERIFIED' $prepared.Data.validation.machine_status 'real-machine boundary remains explicit'
    $packetDigest = [string]$prepared.Data.receipts.content.digest

    Assert-Equal 'VERIFIED' (Invoke-Verify).Data.classification 'valid packet verifies'

    Move-Item -LiteralPath $ownershipPath -Destination "$ownershipPath.missing"
    Assert-Equal 'ownership_state_missing' (Invoke-Verify).Data.reason_code 'missing ownership state fails closed'
    Assert-Equal 'ownership_state_missing' (Invoke-Prepare -Output '').Data.reason_code 'prepare requires live ownership state'
    Move-Item -LiteralPath "$ownershipPath.missing" -Destination $ownershipPath
    Write-OwnershipState -TamperDigest
    Assert-Equal 'ownership_digest_mismatch' (Invoke-Verify).Data.reason_code 'tampered ownership digest is rejected'
    Write-OwnershipState -Writer 'other-writer'
    Assert-Equal 'ownership_state_changed' (Invoke-Verify).Data.reason_code 'changed ownership writer conflicts'
    Write-OwnershipState -Epoch 8
    Assert-Equal 'ownership_state_changed' (Invoke-Verify).Data.reason_code 'changed ownership epoch conflicts'
    Write-OwnershipState -Liveness 'yielded'
    Assert-Equal 'ownership_state_changed' (Invoke-Verify).Data.reason_code 'changed ownership liveness conflicts'
    Write-OwnershipState -Gate 'review'
    Assert-Equal 'ownership_state_changed' (Invoke-Verify).Data.reason_code 'changed ownership gate conflicts'
    Write-OwnershipState -StateSourceRef 'codex/tasks/other'
    Assert-Equal 'ownership_state_changed' (Invoke-Verify).Data.reason_code 'changed ownership source ref conflicts'
    Write-OwnershipState -Liveness 'unknown'
    Assert-Equal 'ownership_liveness_unknown' (Invoke-Verify).Data.reason_code 'unknown ownership liveness is indeterminate'
    Assert-Equal 'ownership_liveness_unknown' (Invoke-Prepare -Output '').Data.reason_code 'prepare also rejects unknown ownership liveness'
    Write-OwnershipState -UpdatedAt '2026-09-21T22:00:00Z'
    $staleOwnershipVerify = Invoke-Verify
    Assert-Equal 'INDETERMINATE' $staleOwnershipVerify.Data.classification 'stale active ownership is indeterminate'
    Assert-Equal 'ownership_stale' $staleOwnershipVerify.Data.reason_code 'verify rejects ownership older than one hour'
    Assert-Equal 'ownership_stale' (Invoke-Prepare -Output '').Data.reason_code 'prepare rejects ownership older than one hour'
    Write-OwnershipState -UpdatedAt '2026-09-22T00:20:01Z'
    $futureOwnershipVerify = Invoke-Verify
    Assert-Equal 'INDETERMINATE' $futureOwnershipVerify.Data.classification 'far-future active ownership is indeterminate'
    Assert-Equal 'ownership_from_future' $futureOwnershipVerify.Data.reason_code 'verify rejects ownership beyond five-minute future skew'
    Assert-Equal 'ownership_from_future' (Invoke-Prepare -Output '').Data.reason_code 'prepare rejects ownership beyond five-minute future skew'
    Write-OwnershipState

    $baseBranch = [string](& git -C $gitRoot branch --show-current)
    & git -C $gitRoot switch --quiet -c same-sha-drift
    Assert-Equal 'branch_changed' (Invoke-Verify).Data.reason_code 'same-SHA branch drift conflicts'
    & git -C $gitRoot switch --quiet $baseBranch
    & git -C $gitRoot branch -D same-sha-drift | Out-Null

    $omittedOwnership = Invoke-ResumeCli -Arguments @('verify', '--packet', $packetPath, '--context', $contextPath, '--repo-root', $gitRoot, '--evidence-root', $evidenceRoot, '--ownership-state', $ownershipRelative, '--expected-packet-digest', $packetDigest, '--now', [string]$fixture.now)
    Assert-Equal 'missing_argument' $omittedOwnership.Data.reason_code 'verify requires ownership expectations'
    $wrongDigest = Invoke-Verify -PacketDigest ('0' * 64)
    Assert-Equal 'expected_packet_digest_mismatch' $wrongDigest.Data.reason_code 'wrong expected packet digest conflicts'

    $ackArguments = Get-AckArguments
    $ackArguments += @('--output', '.vhk/receipts/ack.json')
    $acknowledged = Invoke-ResumeCli -Arguments $ackArguments
    Assert-Equal 'ACKNOWLEDGED' $acknowledged.Data.status 'exact ACK succeeds'
    Assert-Equal $false $acknowledged.Data.takeover 'ACK never performs takeover'
    Assert-True ([IO.File]::Exists($ackPath)) 'ACK writes independent delivery receipt'
    $wrongSourceAck = Invoke-ResumeCli -Arguments (Get-AckArguments -AckSourceRef 'codex/tasks/arbitrary')
    Assert-Equal 'source_ref_mismatch' $wrongSourceAck.Data.reason_code 'arbitrary ACK source ref is rejected'
    $missingAckOwnershipArgs = @(Get-AckArguments)
    $missingWriterIndex = [Array]::IndexOf($missingAckOwnershipArgs, '--expected-writer')
    $missingAckOwnershipArgs = @($missingAckOwnershipArgs[0..($missingWriterIndex - 1)] + $missingAckOwnershipArgs[($missingWriterIndex + 2)..($missingAckOwnershipArgs.Count - 1)])
    Assert-Equal 'missing_argument' (Invoke-ResumeCli -Arguments $missingAckOwnershipArgs).Data.reason_code 'ACK requires explicit ownership expectations'

    $packetText = [IO.File]::ReadAllText($packetPath, [Text.Encoding]::UTF8)
    $stdinAckArgs = Get-AckArguments
    $packetIndex = [Array]::IndexOf($stdinAckArgs, $packetPath)
    $stdinAckArgs[$packetIndex] = '-'
    $stdinAck = Invoke-ResumeCli -Arguments $stdinAckArgs -StdinText $packetText
    Assert-Equal 'ACKNOWLEDGED' $stdinAck.Data.status 'ACK uses one immutable stdin packet read'

    Write-OwnershipState -Liveness 'yielded'
    $yieldedPacketPath = Join-Path $gitRoot '.vhk\receipts\yielded-packet.json'
    $yieldedPrepared = Invoke-Prepare -Output '.vhk/receipts/yielded-packet.json'
    Assert-Equal 'read_only_pending_ownership' $yieldedPrepared.Data.policy.execution_mode 'yielded ownership cannot produce scoped-write packet'
    Assert-True (@($yieldedPrepared.Data.policy.forbidden_work) -contains 'repository_writes') 'yielded packet prohibits repository writes'
    Assert-Equal 'VERIFIED' (Invoke-Verify -InputPath $yieldedPacketPath).Data.classification 'yielded packet verifies only as read-only pending ownership'
    $yieldedAck = Invoke-ResumeCli -Arguments (Get-AckArguments -Packet $yieldedPacketPath)
    Assert-Equal 'read_only_pending_ownership' $yieldedAck.Data.execution_mode 'yielded ACK remains read-only pending ownership'
    Assert-Equal $false $yieldedAck.Data.takeover 'yielded ACK does not take ownership'
    Write-OwnershipState

    $partialContext = Copy-JsonObject $fixture.context
    $partialContext.data.task_context = Copy-JsonObject $fixture.actual_partial_task_context
    $partialContextPath = Join-Path $testRoot 'partial-context.json'
    $partialPacketPath = Join-Path $gitRoot '.vhk\receipts\partial-packet.json'
    Write-Utf8NoBom $partialContextPath ($partialContext | ConvertTo-Json -Depth 30 -Compress)
    $resolutionAction = 'Select and record one active project goal before any implementation'
    Assert-Equal 'resolution_next_action_missing' (Invoke-Prepare -InputPath $partialContextPath -Output '').Data.reason_code 'partial context requires exact resolution action'
    $partialPrepared = Invoke-Prepare -InputPath $partialContextPath -Output '.vhk/receipts/partial-packet.json' -ResolutionNextAction $resolutionAction
    Assert-Equal 0 $partialPrepared.ExitCode 'actual P1 partial context prepares read-only packet'
    Assert-Equal 'shared_repository_evidence_included,other_repository_evidence_excluded,missing_project_goal,missing_next_action' ([string]::Join(',', @($partialPrepared.Data.lineage.task_context.reason_codes))) 'partial reason codes are preserved'
    Assert-Equal 'missing_project_goal,missing_next_action' ([string]::Join(',', @($partialPrepared.Data.task.blockers))) 'only blocking reasons become blockers'
    Assert-True (-not (@($partialPrepared.Data.task.blockers) -contains 'shared_repository_evidence_included')) 'shared evidence reason is not a blocker'
    Assert-Equal 'read_only_until_goal_selected' $partialPrepared.Data.policy.execution_mode 'partial packet is read-only'
    Assert-Equal 'VERIFIED' (Invoke-Verify -InputPath $partialPacketPath -ContextInput $partialContextPath).Data.classification 'partial integrity verifies with explicit blockers'
    $partialAck = Invoke-ResumeCli -Arguments (Get-AckArguments -Packet $partialPacketPath -Context $partialContextPath -Action $resolutionAction)
    Assert-Equal 'read_only_until_goal_selected' $partialAck.Data.execution_mode 'partial ACK cannot grant writes'
    Assert-Equal $false $partialAck.Data.takeover 'partial ACK cannot grant takeover'

    $unsupportedPartial = Copy-JsonObject $partialContext
    $unsupportedPartial.data.task_context.reason_codes += 'stale_index:changed'
    $unsupportedPath = Join-Path $testRoot 'unsupported-partial.json'
    Write-Utf8NoBom $unsupportedPath ($unsupportedPartial | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'unsupported_partial_reason' (Invoke-Prepare -InputPath $unsupportedPath -Output '' -ResolutionNextAction $resolutionAction).Data.reason_code 'unsupported partial reasons fail closed'

    Write-Utf8NoBom (Join-Path $gitRoot 'second.txt') "second`n"
    & git -C $gitRoot add second.txt
    & git -C $gitRoot commit --quiet -m 'advance fixture'
    $stale = Invoke-Verify
    Assert-Equal 'git_sha_changed' $stale.Data.reason_code 'stale SHA fails closed'
    & git -C $gitRoot reset --hard --quiet $baseSha

    $tamperedPacket = Copy-JsonObject $prepared.Data
    $tamperedPacket.lineage.evidence[0].content_hash = ('2' * 64)
    $tamperedPath = Join-Path $testRoot 'tampered-packet.json'
    Write-Utf8NoBom $tamperedPath ($tamperedPacket | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'goal_evidence_missing' (Invoke-Verify -InputPath $tamperedPath -PacketDigest $packetDigest).Data.reason_code 'evidence mutation violates packet integrity'

    $originalGoalEvidence = [IO.File]::ReadAllText($goalEvidencePath, [Text.Encoding]::UTF8)
    Write-Utf8NoBom $goalEvidencePath "# changed evidence`n"
    Assert-Equal 'evidence_content_changed' (Invoke-Verify).Data.reason_code 'changed evidence fails verification'
    Write-Utf8NoBom $goalEvidencePath $originalGoalEvidence
    Move-Item -LiteralPath $goalEvidencePath -Destination "$goalEvidencePath.missing"
    Assert-Equal 'evidence_missing' (Invoke-Verify).Data.reason_code 'missing evidence fails verification'
    Move-Item -LiteralPath "$goalEvidencePath.missing" -Destination $goalEvidencePath

    $duplicateContext = Copy-JsonObject $fixture.context
    $duplicateContext.data.task_context.evidence_refs += Copy-JsonObject $duplicateContext.data.task_context.evidence_refs[0]
    $duplicateEvidencePath = Join-Path $testRoot 'duplicate-evidence.json'
    Write-Utf8NoBom $duplicateEvidencePath ($duplicateContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'duplicate_evidence_tuple' (Invoke-Prepare -InputPath $duplicateEvidencePath -Output '').Data.reason_code 'duplicate evidence tuple is rejected'
    $conflictingContext = Copy-JsonObject $fixture.context
    $conflictingContext.data.task_context.evidence_refs += [pscustomobject]@{ type = 'brain:goal'; id = 'other'; backend = 'memory'; locator = 'memory/other.md'; document_id = 'brain:memory/goals/goal-18.md'; content_hash = $otherHash }
    $conflictingEvidencePath = Join-Path $testRoot 'conflicting-evidence.json'
    Write-Utf8NoBom $conflictingEvidencePath ($conflictingContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'conflicting_evidence_document' (Invoke-Prepare -InputPath $conflictingEvidencePath -Output '').Data.reason_code 'conflicting document id is rejected'

    $dirtyProbe = Join-Path $gitRoot 'untracked.txt'
    Write-Utf8NoBom $dirtyProbe "dirty`n"
    Assert-Equal 'dirty_repository' (Invoke-Verify).Data.reason_code 'dirty mutation conflicts'
    Remove-Item -LiteralPath $dirtyProbe -Force
    $mutatedContext = Copy-JsonObject $fixture.context
    $mutatedContext.data.task_context.reason_codes = @('changed')
    $mutatedContextPath = Join-Path $testRoot 'mutated-context.json'
    Write-Utf8NoBom $mutatedContextPath ($mutatedContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'context_envelope_changed' (Invoke-Verify -ContextInput $mutatedContextPath).Data.reason_code 'verify binds exact context envelope'

    $invalidProvenance = Copy-JsonObject $fixture.context
    $invalidProvenance.data.retrieval_diagnostics.persisted = $true
    $invalidProvenancePath = Join-Path $testRoot 'invalid-provenance.json'
    Write-Utf8NoBom $invalidProvenancePath ($invalidProvenance | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'context_provenance_invalid' (Invoke-Prepare -InputPath $invalidProvenancePath -Output '').Data.reason_code 'volatile provenance is mandatory'
    $duplicateJsonPath = Join-Path $testRoot 'duplicate.json'
    Write-Utf8NoBom $duplicateJsonPath '{"data":{"task_context":{},"task_context":{}}}'
    Assert-Equal 'duplicate_json_key' (Invoke-Prepare -InputPath $duplicateJsonPath -Output '').Data.reason_code 'duplicate JSON key is rejected'
    $corruptPath = Join-Path $testRoot 'corrupt.json'
    Write-Utf8NoBom $corruptPath '{"data":'
    Assert-Equal 'invalid_json' (Invoke-Prepare -InputPath $corruptPath -Output '').Data.reason_code 'corrupt JSON is rejected'
    $secretContext = Copy-JsonObject $fixture.context
    $secretContext.data.task_context.next_actions[0] = ('Use Bear' + 'er ' + ('x' * 32))
    $secretPath = Join-Path $testRoot 'secret.json'
    Write-Utf8NoBom $secretPath ($secretContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'secret_like_value' (Invoke-Prepare -InputPath $secretPath -Output '').Data.reason_code 'secret material is rejected'
    $absoluteContext = Copy-JsonObject $fixture.context
    $absoluteContext.data.task_context.repository.canonical_path = '/absolute/project'
    $absolutePath = Join-Path $testRoot 'absolute.json'
    Write-Utf8NoBom $absolutePath ($absoluteContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'absolute_or_native_path' (Invoke-Prepare -InputPath $absolutePath -Output '').Data.reason_code 'absolute path is rejected'

    Assert-Equal 'writer_epoch_changed' (Invoke-Verify -Epoch '8').Data.reason_code 'writer epoch mismatch conflicts'
    Assert-Equal 'unknown_option' (Invoke-ResumeCli -Arguments @('verify', '--bogus', 'value')).Data.reason_code 'unknown options are rejected'
    Assert-Equal 'unsafe_path_characters' (Invoke-Prepare -Output '.vhk/receipts/bad:name.json').Data.reason_code 'ADS colon is rejected'
    $linkTarget = Join-Path $testRoot 'linked-output-target'
    $linkPath = Join-Path $gitRoot '.vhk\receipts\linked'
    $null = New-Item -ItemType Directory -Force -Path $linkTarget
    $linkCreated = $false
    try { $null = New-Item -ItemType SymbolicLink -Path $linkPath -Target $linkTarget -ErrorAction Stop; $linkCreated = $true } catch { $linkCreated = $false }
    if ($linkCreated) {
        Assert-Equal 'linked_path_component' (Invoke-Prepare -Output '.vhk/receipts/linked/packet.json').Data.reason_code 'linked output path is rejected'
        Remove-Item -LiteralPath $linkPath -Force
    }

    $unregisteredContext = Copy-JsonObject $fixture.context
    $unregisteredContext.data.task_context.status = 'unresolved'
    $unregisteredContext.data.task_context.repository = $null
    $unregisteredPath = Join-Path $testRoot 'unregistered.json'
    Write-Utf8NoBom $unregisteredPath ($unregisteredContext | ConvertTo-Json -Depth 30 -Compress)
    Assert-Equal 'INDETERMINATE' (Invoke-Prepare -InputPath $unregisteredPath -Output '').Data.classification 'unregistered repository is indeterminate'

    Write-Output "PASS: $script:assertions assertions"
    $exitCode = 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "FAIL after $script:assertions assertions"
    Write-Output "Fixture retained: $testRoot"
}

exit $exitCode
