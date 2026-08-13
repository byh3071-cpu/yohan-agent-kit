#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [string]$ContractRepositoryRoot,
    [string]$ContractRef = 'f7615ac2fce83bd93c37801c14640c20dede5980',
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/design-intelligence/events/[a-z0-9][a-z0-9-]*\.jsonl$')][string]$EventLogPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$EventId,
    [Parameter(Mandatory = $true)][datetime]$OccurredAt,
    [Parameter(Mandatory = $true)][ValidateSet('human', 'agent', 'tool')][string]$ActorType,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ActorId,
    [ValidateSet('observed', 'proposed', 'reviewed', 'accepted', 'rejected', 'promoted', 'deprecated')][string]$Action = 'proposed',
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SubjectRef,
    [Parameter(Mandatory = $true)][ValidateSet('reuse', 'adapt', 'remix', 'create')][string]$Decision,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$EvidenceRefs,
    [string]$PreviousEventRef,
    [string]$ApprovalRef,
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:pinnedContractRef = 'f7615ac2fce83bd93c37801c14640c20dede5980'

function Get-NormalizedRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [IO.Directory]::Exists($Path)) { throw 'BrainRoot must be an existing directory' }
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $entry = Get-Item -LiteralPath $root -Force
    if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BrainRoot must be an ordinary directory' }
    return $root
}

function Get-SafeLogPath {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath)

    $candidate = [IO.Path]::GetFullPath((Join-Path $Root ($RelativePath.Replace('/', '\'))))
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Event log escapes BrainRoot' }
    $parent = Split-Path -Parent $candidate
    if (-not [IO.Directory]::Exists($parent)) { throw 'Event log parent must already exist' }
    $parentEntry = Get-Item -LiteralPath $parent -Force
    if (($parentEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Event log parent cannot be a reparse point' }
    if ([IO.File]::Exists($candidate)) {
        $entry = Get-Item -LiteralPath $candidate -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Event log cannot be a reparse point' }
    }
    return $candidate
}

function Assert-PinnedContract {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    if ($ContractRef -cne $script:pinnedContractRef) { throw 'ContractRef must equal the approved pinned contract commit' }
    $git = $null
    foreach ($candidate in @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists([string]$candidate.Source)) { $git = [string]$candidate.Source; break }
    }
    if ([string]::IsNullOrWhiteSpace($git)) { throw 'git.exe is unavailable' }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $commitOutput = @(& $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot rev-parse --verify "$ContractRef^{commit}" 2>&1)
        $commitExit = $LASTEXITCODE
        $indexOutput = @(& $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot show "$ContractRef`:memory/design-intelligence/index.yaml" 2>&1)
        $indexExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($commitExit -ne 0 -or [string]::Join('', $commitOutput).Trim() -cne $script:pinnedContractRef) { throw 'Pinned contract commit cannot be resolved exactly' }
    if ($indexExit -ne 0) { throw 'Pinned design intelligence index is unavailable' }
    $index = [string]::Join("`n", @($indexOutput | ForEach-Object { [string]$_ }))
    foreach ($required in @(
        'resolver_recording_execution: yohan-cc-skills',
        'stable_auto_promotion: false',
        'stable_promotion_requires_human: true',
        'correction_mode: append-only',
        'decision_actions: [observed, proposed, reviewed, accepted, rejected, promoted, deprecated]'
    )) {
        if (-not $index.Contains($required)) { throw "Pinned recording invariant is missing: $required" }
    }
}

function Get-StrictUtf8 {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw 'Event log must be UTF-8 without BOM' }
    try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes) }
    catch [Text.DecoderFallbackException] { throw 'Event log is not valid UTF-8' }
}

try {
    if ([string]::IsNullOrWhiteSpace($ActorId) -or [string]::IsNullOrWhiteSpace($SubjectRef)) { throw 'ActorId and SubjectRef cannot be blank' }
    if ($ActorId -match '[\r\n]' -or $SubjectRef -match '[\r\n]' -or $EvidenceRefs -match '[\r\n]') { throw 'Control characters are forbidden' }
    if ($Action -in @('accepted', 'promoted')) {
        if ($ActorType -ne 'human') { throw "$Action requires a human actor" }
        if ([string]::IsNullOrWhiteSpace($ApprovalRef)) { throw "$Action requires approval_ref" }
    }
    if ($Action -eq 'promoted' -and $ApprovalRef -notmatch '^human-approval:') { throw 'Stable promotion requires an explicit human-approval ref' }
    $evidence = New-Object Collections.Generic.List[string]
    foreach ($reference in @($EvidenceRefs + "decision:$Decision")) {
        $value = [string]$reference
        if ([string]::IsNullOrWhiteSpace($value)) { throw 'Evidence refs cannot be empty' }
        if (-not $evidence.Contains($value)) { $evidence.Add($value) }
    }

    $root = Get-NormalizedRoot -Path $BrainRoot
    if ([string]::IsNullOrWhiteSpace($ContractRepositoryRoot)) { $ContractRepositoryRoot = $BrainRoot }
    $contractRoot = Get-NormalizedRoot -Path $ContractRepositoryRoot
    Assert-PinnedContract -RepositoryRoot $contractRoot
    $target = Get-SafeLogPath -Root $root -RelativePath $EventLogPath
    if (-not [IO.File]::Exists($target) -and -not [string]::IsNullOrWhiteSpace($PreviousEventRef)) { throw 'First event cannot reference an absent previous event' }

    $event = [pscustomobject][ordered]@{
        event_id = $EventId
        occurred_at = $OccurredAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
        actor = [pscustomobject][ordered]@{ type = $ActorType; id = $ActorId }
        action = $Action
        subject_ref = $SubjectRef
    }
    if (-not [string]::IsNullOrWhiteSpace($PreviousEventRef)) { $event | Add-Member -NotePropertyName previous_event_ref -NotePropertyValue $PreviousEventRef }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalRef)) { $event | Add-Member -NotePropertyName approval_ref -NotePropertyValue $ApprovalRef }
    $event | Add-Member -NotePropertyName evidence_refs -NotePropertyValue $evidence.ToArray()
    $event | Add-Member -NotePropertyName append_only -NotePropertyValue $true
    $line = [string]($event | ConvertTo-Json -Depth 8 -Compress)

    $mode = if ([IO.File]::Exists($target)) { [IO.FileMode]::Open } else { [IO.FileMode]::CreateNew }
    $stream = New-Object IO.FileStream($target, $mode, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    try {
        $existingBytes = New-Object byte[] $stream.Length
        $offset = 0
        while ($offset -lt $existingBytes.Length) {
            $read = $stream.Read($existingBytes, $offset, $existingBytes.Length - $offset)
            if ($read -le 0) { throw 'Unable to read the complete event log' }
            $offset += $read
        }
        $existingText = Get-StrictUtf8 -Bytes $existingBytes
        $knownIds = @{}
        foreach ($line in @($existingText -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            try { $existing = $line | ConvertFrom-Json }
            catch { throw 'Existing event log contains invalid JSONL' }
            $knownId = [string]$existing.event_id
            if ($knownId -notmatch '^[a-z0-9][a-z0-9-]*$' -or $knownIds.ContainsKey($knownId)) { throw 'Existing event log has invalid or duplicate event ids' }
            $knownIds[$knownId] = $true
        }
        if ($knownIds.ContainsKey($EventId)) { throw "Duplicate event id: $EventId" }
        if ($knownIds.Count -gt 0) {
            if ([string]::IsNullOrWhiteSpace($PreviousEventRef) -or -not $knownIds.ContainsKey($PreviousEventRef)) { throw 'Append requires an existing previous_event_ref' }
        }
        $prefix = if ($existingBytes.Length -gt 0 -and $existingBytes[$existingBytes.Length - 1] -ne 0x0A) { "`n" } else { '' }
        $appendBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($prefix + $line + "`n")
        $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
        $stream.Write($appendBytes, 0, $appendBytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }

    $result = [pscustomobject][ordered]@{ status = 'appended'; eventId = $EventId; action = $Action; decision = $Decision; path = $EventLogPath; stableAutoPromotion = $false }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Compress)) }
    else { Write-Output "Appended $EventId ($Decision/$Action) to $EventLogPath" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
