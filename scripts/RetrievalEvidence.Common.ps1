#requires -Version 5.1

Set-StrictMode -Version 2.0

$script:RetrievalSchemaPaths = @(
    'memory/retrieval-evidence/schemas/retrieval-learning-candidate.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-outcome-event.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-receipt.schema.json'
) | Sort-Object
$script:AgentKitRuntimePaths = @(
    'scripts/Get-RetrievalLearningCandidate.ps1',
    'scripts/New-RetrievalQueryFingerprint.ps1',
    'scripts/Record-RetrievalOutcome.ps1',
    'scripts/Record-RetrievalReceipt.ps1',
    'scripts/RetrievalEvidence.Common.ps1'
) | Sort-Object
$script:McpRuntimePaths = @(
    'adapters/memory_adapter.py',
    'core/context_resolver.py',
    'core/router.py'
) | Sort-Object
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false, $true)

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-HmacQueryFingerprint {
    param([Parameter(Mandatory = $true)][string]$Query, [Parameter(Mandatory = $true)][string]$KeyEnvironmentVariable)

    $key = [Environment]::GetEnvironmentVariable($KeyEnvironmentVariable, [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'Retrieval HMAC key is not configured in the process environment' }
    if ($key.Length -lt 16) { throw 'Retrieval HMAC key is too short' }
    $keyBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($key)
    $queryBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Query)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$keyBytes)
    try { return ([BitConverter]::ToString($hmac.ComputeHash($queryBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hmac.Dispose() }
}

function ConvertTo-NormalizedLf {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n", [StringComparison]::Ordinal)) { $normalized += "`n" }
    return $normalized
}

function Get-OrdinaryRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = 'Root')

    if (-not [IO.Directory]::Exists($Path)) { throw "$Label must be an existing directory" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $current = $full
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $entry = Get-Item -LiteralPath $current -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label path cannot contain a reparse point" }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -ceq $current) { break }
        $current = $parent.FullName
    }
    return $full
}

function Test-RepoRelativePosixPath {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path.Contains('\') -or $Path -match '[\r\n]') { return $false }
    if (@($Path.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) { return $false }
    return $true
}

function Get-SafeEventLogPath {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind
    )

    $root = Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot'
    $pattern = '^memory/retrieval-evidence/events/' + [Regex]::Escape($Kind) + '-\d{4}-\d{2}\.jsonl$'
    if ($RelativePath -notmatch $pattern -or -not (Test-RepoRelativePosixPath -Path $RelativePath)) { throw "$Kind event log path is not allowed" }
    $target = [IO.Path]::GetFullPath((Join-Path $root $RelativePath.Replace('/', '\')))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "$Kind event log escapes BrainRoot" }
    $parent = Split-Path -Parent $target
    if (-not [IO.Directory]::Exists($parent)) { throw "$Kind event log parent must already exist" }
    $null = Get-OrdinaryRoot -Path $parent -Label "$Kind event log parent"
    if ([IO.File]::Exists($target)) {
        $entry = Get-Item -LiteralPath $target -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Kind event log cannot be a reparse point" }
        $fsutil = Get-Command fsutil.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($null -eq $fsutil) { throw 'fsutil.exe is required to verify event log hardlink count on Windows' }
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $links = @(& $fsutil.Source hardlink list $target 2>$null | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $linkExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previous }
        if ($linkExit -ne 0 -or $links.Count -ne 1) { throw "$Kind event log must have exactly one hardlink" }
    }
    return $target
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $git = $null
    foreach ($candidate in @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists([string]$candidate.Source)) { $git = [string]$candidate.Source; break }
    }
    if ([string]::IsNullOrWhiteSpace($git)) { throw 'git.exe is unavailable' }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($exitCode -ne 0) { throw "$Label is unavailable at the requested Git ref" }
    return [string]::Join("`n", @($output | ForEach-Object { [string]$_ }))
}

function Get-ImplementationBundleDigest {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [string]$GitRef
    )

    $root = Get-OrdinaryRoot -Path $RepositoryRoot -Label 'Implementation repository root'
    $bundle = ''
    foreach ($relativePath in @($RelativePaths | Sort-Object)) {
        if (-not (Test-RepoRelativePosixPath -Path $relativePath)) { throw 'Implementation bundle path is invalid' }
        if ([string]::IsNullOrWhiteSpace($GitRef)) {
            $path = [IO.Path]::GetFullPath((Join-Path $root $relativePath.Replace('/', '\')))
            if (-not [IO.File]::Exists($path)) { throw "Implementation bundle file is missing: $relativePath" }
            $text = Get-StrictUtf8Text -Bytes ([IO.File]::ReadAllBytes($path)) -Label $relativePath
        }
        else {
            $text = Invoke-GitText -RepositoryRoot $root -Arguments @('show', "$GitRef`:$relativePath") -Label $relativePath
        }
        $bundle += $relativePath + "`n" + (ConvertTo-NormalizedLf -Text $text)
    }
    return Get-Sha256Hex -Text $bundle
}

function Get-YamlHexValue {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][int]$Length)

    $pattern = '(?m)^\s*' + [Regex]::Escape($Name) + ': "?([0-9a-f]{' + $Length + '})"?\s*$'
    $matches = [Regex]::Matches($Text, $pattern)
    if ($matches.Count -lt 1) { throw "Retrieval contract value is missing: $Name" }
    $values = @($matches | ForEach-Object { [string]$_.Groups[1].Value } | Sort-Object -Unique)
    if ($values.Count -ne 1) { throw "Retrieval contract value is ambiguous: $Name" }
    return $values[0]
}

function Assert-ImplementationBinding {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$PinnedRef,
        [Parameter(Mandatory = $true)][string]$ExpectedBundleDigest,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$RequireExactHead
    )

    $root = Get-OrdinaryRoot -Path $RepositoryRoot -Label "$Label repository root"
    $resolved = (Invoke-GitText -RepositoryRoot $root -Arguments @('rev-parse', '--verify', "$PinnedRef`^{commit}") -Label "$Label implementation ref").Trim()
    if ($resolved -cne $PinnedRef) { throw "$Label implementation ref does not resolve exactly" }
    $head = (Invoke-GitText -RepositoryRoot $root -Arguments @('rev-parse', 'HEAD') -Label "$Label HEAD").Trim()
    if ($RequireExactHead) {
        if ($head -cne $PinnedRef) { throw "$Label HEAD does not equal the activated implementation ref" }
    }
    else {
        $null = Invoke-GitText -RepositoryRoot $root -Arguments @('merge-base', '--is-ancestor', $PinnedRef, $head) -Label "$Label implementation ancestry"
    }
    $pinnedDigest = Get-ImplementationBundleDigest -RepositoryRoot $root -RelativePaths $RelativePaths -GitRef $PinnedRef
    $workingDigest = Get-ImplementationBundleDigest -RepositoryRoot $root -RelativePaths $RelativePaths
    if ($pinnedDigest -cne $ExpectedBundleDigest -or $workingDigest -cne $ExpectedBundleDigest) {
        throw "$Label runtime bundle does not match the activated implementation digest (expected=$ExpectedBundleDigest pinned=$pinnedDigest working=$workingDigest)"
    }
    return [pscustomobject][ordered]@{ Root = $root; Head = $head; BundleDigest = $workingDigest }
}

function Get-RetrievalContractSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedSchemaDigest
    )

    $contractRoot = Get-OrdinaryRoot -Path $ContractRepositoryRoot -Label 'ContractRepositoryRoot'
    $resolved = (Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('rev-parse', '--verify', "$ContractRef`^{commit}") -Label 'Contract commit').Trim()
    if ($resolved -cne $ContractRef) { throw 'ContractRef must resolve to the exact commit' }

    $indexText = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:memory/retrieval-evidence/index.yaml") -Label 'Retrieval evidence index'
    $contractText = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:memory/core/retrieval-contract.yaml") -Label 'Retrieval contract'
    if ($indexText -notmatch '(?m)^status: active\s*$') { throw 'Retrieval evidence index is not active' }
    if (-not $indexText.Contains("schema_bundle_digest: $ExpectedSchemaDigest")) { throw 'Retrieval evidence index schema digest mismatch' }
    if ($contractText -notmatch '(?m)^  status: active\s*$' -or $contractText -notmatch '(?m)^  implementation_status: implemented\s*$') { throw 'Retrieval evidence contract is not active/implemented' }
    if (-not $contractText.Contains("digest: $ExpectedSchemaDigest")) { throw 'Retrieval contract schema digest mismatch' }
    $mcpImplementationRef = Get-YamlHexValue -Text $contractText -Name 'mcp_diagnostics_implementation_ref' -Length 40
    $mcpRuntimeDigest = Get-YamlHexValue -Text $contractText -Name 'mcp_runtime_bundle_digest' -Length 64
    $agentKitImplementationRef = Get-YamlHexValue -Text $contractText -Name 'agent_kit_implementation_ref' -Length 40
    $agentKitRuntimeDigest = Get-YamlHexValue -Text $contractText -Name 'agent_kit_runtime_bundle_digest' -Length 64
    foreach ($binding in @(
        @('mcp_diagnostics_implementation_ref', $mcpImplementationRef, 40),
        @('mcp_runtime_bundle_digest', $mcpRuntimeDigest, 64),
        @('agent_kit_implementation_ref', $agentKitImplementationRef, 40),
        @('agent_kit_runtime_bundle_digest', $agentKitRuntimeDigest, 64)
    )) {
        $indexValue = Get-YamlHexValue -Text $indexText -Name ([string]$binding[0]) -Length ([int]$binding[2])
        if ($indexValue -cne [string]$binding[1]) { throw "Retrieval index/contract handshake mismatch: $($binding[0])" }
    }
    $agentKitRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $null = Assert-ImplementationBinding -RepositoryRoot $agentKitRoot -PinnedRef $agentKitImplementationRef -ExpectedBundleDigest $agentKitRuntimeDigest -RelativePaths $script:AgentKitRuntimePaths -Label 'Agent Kit'
    foreach ($required in @(
        'persistent_writes: []',
        'persistence: forbidden',
        'writer: yohan-agent-kit',
        'fingerprint_scheme: hmac-sha256-v1',
        'correction_mode: append-only',
        'automatic_query_recording: forbidden',
        'stable_auto_promotion: false'
    )) {
        if (-not $contractText.Contains($required) -and -not $indexText.Contains($required)) { throw "Retrieval contract invariant missing: $required" }
    }

    $bundle = ''
    $schemaByName = @{}
    foreach ($relativePath in $script:RetrievalSchemaPaths) {
        $text = Invoke-GitText -RepositoryRoot $contractRoot -Arguments @('show', "$ContractRef`:$relativePath") -Label $relativePath
        $normalized = ConvertTo-NormalizedLf -Text $text
        $bundle += $relativePath + "`n" + $normalized
        try { $schema = $text | ConvertFrom-Json }
        catch { throw "$relativePath is not valid JSON" }
        if ($schema.type -cne 'object' -or [bool]$schema.additionalProperties -ne $false) { throw "$relativePath must be a closed object schema" }
        $schemaByName[[IO.Path]::GetFileName($relativePath)] = $schema
    }
    $actualDigest = Get-Sha256Hex -Text $bundle
    if ($actualDigest -cne $ExpectedSchemaDigest) { throw 'Pinned schema bundle bytes do not match ExpectedSchemaDigest' }

    return [pscustomobject][ordered]@{
        ContractRef = $ContractRef
        SchemaDigest = $actualDigest
        ReceiptSchema = $schemaByName['retrieval-receipt.schema.json']
        OutcomeSchema = $schemaByName['retrieval-outcome-event.schema.json']
        CandidateSchema = $schemaByName['retrieval-learning-candidate.schema.json']
        ContractRepositoryRoot = $contractRoot
        McpImplementationRef = $mcpImplementationRef
        McpRuntimeBundleDigest = $mcpRuntimeDigest
        AgentKitImplementationRef = $agentKitImplementationRef
        AgentKitRuntimeBundleDigest = $agentKitRuntimeDigest
        TrackedEventLogs = @([Regex]::Matches($indexText, '(?m)^    - (memory/retrieval-evidence/events/(?:receipts|outcomes|candidates)-\d{4}-\d{2}\.jsonl)\s*$') | ForEach-Object { [string]$_.Groups[1].Value })
    }
}

function Resolve-OutcomeProof {
    param(
        [Parameter(Mandatory = $true)]$ContractSnapshot,
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$Reference,
        [Parameter(Mandatory = $true)][ValidateSet('human-explicit', 'golden-eval', 'task-result')][string]$SignalKind,
        [Parameter(Mandatory = $true)][ValidateSet('helpful', 'partial', 'unhelpful', 'unknown')][string]$Verdict,
        [Parameter(Mandatory = $true)][ValidateSet('human', 'tool')][string]$ActorType
    )

    $match = [Regex]::Match($Reference, '^(human-approval|golden-eval|task-result):([a-z0-9][a-z0-9._-]{0,127})@git:([0-9a-f]{40})@sha256:([0-9a-f]{64})$')
    if (-not $match.Success) { throw 'Outcome evidence ref must be a content-addressed Brain proof' }
    if ($Reference -match '(?:github_pat_|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|secret|token|password|credential|api[-_]?key)') { throw 'Outcome evidence ref is secret-like' }
    $scheme = [string]$match.Groups[1].Value
    $proofId = [string]$match.Groups[2].Value
    $proofRef = [string]$match.Groups[3].Value
    $contentHash = [string]$match.Groups[4].Value
    $expectedScheme = if ($SignalKind -eq 'human-explicit') { 'human-approval' } else { $SignalKind }
    if ($scheme -cne $expectedScheme) { throw 'Outcome evidence ref scheme does not match SignalKind' }
    $root = [string]$ContractSnapshot.ContractRepositoryRoot
    $null = Invoke-GitText -RepositoryRoot $root -Arguments @('merge-base', '--is-ancestor', [string]$Receipt.contract_ref, $proofRef) -Label 'Outcome proof contract ancestry'
    $null = Invoke-GitText -RepositoryRoot $root -Arguments @('merge-base', '--is-ancestor', $proofRef, 'HEAD') -Label 'Outcome proof Brain ancestry'
    $proofPath = "memory/retrieval-evidence/proofs/$scheme/$proofId.json"
    $proofText = Invoke-GitText -RepositoryRoot $root -Arguments @('show', "$proofRef`:$proofPath") -Label 'Outcome proof artifact'
    if ((Get-Sha256Hex -Text (ConvertTo-NormalizedLf -Text $proofText)) -cne $contentHash) { throw 'Outcome proof content hash mismatch' }
    $proof = ConvertFrom-StrictJsonText -Text $proofText -Label 'Outcome proof artifact'
    if ($scheme -ceq 'golden-eval') {
        Assert-AllowedObjectFields -Value $proof -Allowed @('schema', 'proof_id', 'signal_kind', 'actor_type', 'verdict_rule', 'required_document_ids') -Required @('schema', 'proof_id', 'signal_kind', 'actor_type', 'verdict_rule', 'required_document_ids') -Label 'Golden outcome proof'
        if ([string]$proof.schema -cne 'retrieval-golden-outcome-proof/v1' -or [string]$proof.proof_id -cne $proofId -or [string]$proof.signal_kind -cne 'golden-eval' -or [string]$proof.actor_type -cne 'tool' -or [string]$proof.verdict_rule -cne 'all-required-document-ids') { throw 'Golden outcome proof policy mismatch' }
        $requiredIds = @($proof.required_document_ids | ForEach-Object { [string]$_ })
        if ($requiredIds.Count -eq 0 -or @($requiredIds | Sort-Object -Unique).Count -ne $requiredIds.Count) { throw 'Golden outcome proof required_document_ids are invalid' }
        $includedIds = @($Receipt.included | ForEach-Object { $_.evidence_refs } | ForEach-Object { [string]$_.document_id })
        $matched = @($requiredIds | Where-Object { $includedIds -ccontains $_ }).Count
        $expectedVerdict = if ($matched -eq $requiredIds.Count) { 'helpful' } elseif ($matched -gt 0) { 'partial' } else { 'unhelpful' }
        if ($ActorType -cne 'tool' -or $Verdict -cne $expectedVerdict) { throw 'Golden outcome does not match deterministic proof result' }
    }
    else {
        Assert-AllowedObjectFields -Value $proof -Allowed @('schema', 'proof_id', 'signal_kind', 'receipt_id', 'verdict', 'actor_type') -Required @('schema', 'proof_id', 'signal_kind', 'receipt_id', 'verdict', 'actor_type') -Label 'Outcome attestation'
        if ([string]$proof.schema -cne 'retrieval-outcome-attestation/v1' -or [string]$proof.proof_id -cne $proofId -or [string]$proof.signal_kind -cne $SignalKind -or [string]$proof.receipt_id -cne [string]$Receipt.receipt_id -or [string]$proof.verdict -cne $Verdict -or [string]$proof.actor_type -cne $ActorType) { throw 'Outcome attestation does not bind the event' }
    }
    return [pscustomobject][ordered]@{ Scheme = $scheme; ProofId = $proofId; ProofRef = $proofRef; ContentHash = $contentHash }
}

function Assert-AllowedObjectFields {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string[]]$Required,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($null -eq $Value -or $Value -isnot [psobject]) { throw "$Label must be an object" }
    $names = @($Value.PSObject.Properties.Name)
    foreach ($name in $names) {
        if ($Allowed -cnotcontains [string]$name) { throw "$Label field is not allowed: $name" }
    }
    foreach ($name in $Required) {
        if ($names -cnotcontains $name) { throw "$Label required field is missing: $name" }
    }
}

function ConvertFrom-StrictJsonText {
    param([Parameter(Mandatory = $true)][string]$Text, [string]$Label = 'JSON input')

    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Label cannot be empty" }
    try { return $Text | ConvertFrom-Json }
    catch {
        $firstCodePoint = if ($Text.Length -gt 0) { [int][char]$Text[0] } else { -1 }
        throw "$Label is not valid JSON (length=$($Text.Length), first_codepoint=$firstCodePoint, parser=$($_.Exception.GetType().Name))"
    }
}

function Get-StrictUtf8Text {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [string]$Label = 'JSONL')

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw "$Label must be UTF-8 without BOM" }
    try { return $script:Utf8NoBom.GetString($Bytes) }
    catch [Text.DecoderFallbackException] { throw "$Label is not valid UTF-8" }
}

function ConvertFrom-JsonLinesText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$IdProperty, [string]$Label = 'JSONL')

    $rows = New-Object Collections.Generic.List[object]
    $ids = @{}
    foreach ($line in @($Text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $row = $line | ConvertFrom-Json }
        catch { throw "$Label contains invalid JSONL" }
        $property = $row.PSObject.Properties[$IdProperty]
        if ($null -eq $property) { throw "$Label row is missing $IdProperty" }
        $id = [string]$property.Value
        if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,127}$' -or $ids.ContainsKey($id)) { throw "$Label has invalid or duplicate $IdProperty" }
        $ids[$id] = $true
        $rows.Add($row)
    }
    return [pscustomobject][ordered]@{ Rows = $rows.ToArray(); Ids = $ids }
}

function Read-JsonLineLog {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$IdProperty,
        [switch]$RequireExisting
    )

    $target = Get-SafeEventLogPath -BrainRoot $BrainRoot -RelativePath $RelativePath -Kind $Kind
    if (-not [IO.File]::Exists($target)) {
        if ($RequireExisting) { throw "$Kind event log does not exist" }
        return [pscustomobject][ordered]@{ Path = $target; Rows = @(); Ids = @{} }
    }
    $bytes = [IO.File]::ReadAllBytes($target)
    $parsed = ConvertFrom-JsonLinesText -Text (Get-StrictUtf8Text -Bytes $bytes -Label "$Kind event log") -IdProperty $IdProperty -Label "$Kind event log"
    return [pscustomobject][ordered]@{ Path = $target; Rows = $parsed.Rows; Ids = $parsed.Ids }
}

function Read-AllJsonLineLogs {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$IdProperty
    )

    $root = Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot'
    $eventDirectory = Join-Path $root 'memory\retrieval-evidence\events'
    if (-not [IO.Directory]::Exists($eventDirectory)) { return [pscustomobject][ordered]@{ Rows = @(); Ids = @{}; Paths = @() } }
    $files = @(Get-ChildItem -LiteralPath $eventDirectory -File -Filter "$Kind-*.jsonl" | Sort-Object Name)
    $rows = New-Object Collections.Generic.List[object]
    $ids = @{}
    $paths = New-Object Collections.Generic.List[string]
    foreach ($file in $files) {
        if ($file.Name -notmatch "^$Kind-\d{4}-\d{2}\.jsonl$") { throw "$Kind event directory contains a non-canonical JSONL file" }
        $relativePath = "memory/retrieval-evidence/events/$($file.Name)"
        $log = Read-JsonLineLog -BrainRoot $root -RelativePath $relativePath -Kind $Kind -IdProperty $IdProperty -RequireExisting
        foreach ($row in @($log.Rows)) {
            $id = [string]$row.PSObject.Properties[$IdProperty].Value
            if ($ids.ContainsKey($id)) { throw "Duplicate $IdProperty across $Kind logs: $id" }
            $ids[$id] = $true
            $rows.Add($row)
        }
        $paths.Add($relativePath)
    }
    return [pscustomobject][ordered]@{ Rows = $rows.ToArray(); Ids = $ids; Paths = $paths.ToArray() }
}

function Assert-MonthlyEventPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][datetime]$RecordedAt, [Parameter(Mandatory = $true)][string]$Kind)

    $expected = "$Kind-$($RecordedAt.ToUniversalTime().ToString('yyyy-MM', [Globalization.CultureInfo]::InvariantCulture)).jsonl"
    if ([IO.Path]::GetFileName($RelativePath) -cne $expected) { throw "$Kind event log month does not match RecordedAt" }
}

function Assert-ProductionEventRegistration {
    param([Parameter(Mandatory = $true)][string]$BrainRoot, [Parameter(Mandatory = $true)]$ContractSnapshot, [Parameter(Mandatory = $true)][string]$RelativePath)

    $brain = Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot'
    if ($brain -ceq [string]$ContractSnapshot.ContractRepositoryRoot -and $ContractSnapshot.TrackedEventLogs -cnotcontains $RelativePath) {
        throw 'Canonical Brain event log must be pre-registered in the active contract index'
    }
}

function Add-JsonLineAppendOnly {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][ValidateSet('receipts', 'outcomes', 'candidates')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$IdProperty,
        [Parameter(Mandatory = $true)]$Value
    )

    $target = Get-SafeEventLogPath -BrainRoot $BrainRoot -RelativePath $RelativePath -Kind $Kind
    $id = [string]$Value.PSObject.Properties[$IdProperty].Value
    $line = [string]($Value | ConvertTo-Json -Depth 20 -Compress)
    $mode = if ([IO.File]::Exists($target)) { [IO.FileMode]::Open } else { [IO.FileMode]::CreateNew }
    $stream = New-Object IO.FileStream($target, $mode, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    try {
        $existingBytes = New-Object byte[] $stream.Length
        $offset = 0
        while ($offset -lt $existingBytes.Length) {
            $read = $stream.Read($existingBytes, $offset, $existingBytes.Length - $offset)
            if ($read -le 0) { throw "Unable to read complete $Kind event log" }
            $offset += $read
        }
        $existingText = Get-StrictUtf8Text -Bytes $existingBytes -Label "$Kind event log"
        $existing = ConvertFrom-JsonLinesText -Text $existingText -IdProperty $IdProperty -Label "$Kind event log"
        if ($existing.Ids.ContainsKey($id)) { throw "Duplicate $IdProperty`: $id" }
        $prefix = if ($existingBytes.Length -gt 0 -and $existingBytes[$existingBytes.Length - 1] -ne 0x0A) { "`n" } else { '' }
        $appendBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($prefix + $line + "`n")
        $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
        $stream.Write($appendBytes, 0, $appendBytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    return $RelativePath
}

function Assert-SafeIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Label)

    if ($Value -notmatch '^[a-z0-9][a-z0-9-]{0,127}$') { throw "$Label is invalid" }
}

function Assert-SafeFingerprintKeyId {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$' -or $Value -match '(?i)secret|token|password|credential|api[-_]?key') { throw 'FingerprintKeyId is invalid or secret-like' }
}
