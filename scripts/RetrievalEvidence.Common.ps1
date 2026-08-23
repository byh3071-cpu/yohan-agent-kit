#requires -Version 5.1

Set-StrictMode -Version 2.0

$script:RetrievalSchemaPaths = @(
    'memory/retrieval-evidence/schemas/retrieval-learning-candidate.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-outcome-event.schema.json',
    'memory/retrieval-evidence/schemas/retrieval-receipt.schema.json'
) | Sort-Object
$script:AgentKitRuntimePaths = @(
    'scripts/Assert-UniqueJsonKeys.py',
    'scripts/Get-VerifiedMcpEnvelope.py',
    'scripts/Get-RetrievalLearningCandidate.ps1',
    'scripts/New-RetrievalQueryFingerprint.ps1',
    'scripts/Record-RetrievalOutcome.ps1',
    'scripts/Record-RetrievalReceipt.ps1',
    'scripts/RetrievalEvidence.Common.ps1'
) | Sort-Object
$script:McpRuntimePaths = @(
    'adapters/base.py',
    'adapters/memory_adapter.py',
    'core/context_resolver.py',
    'core/paths.py',
    'core/router.py',
    'core/tools.py',
    'server.py'
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

function Get-HmacSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$KeyEnvironmentVariable)

    $key = [Environment]::GetEnvironmentVariable($KeyEnvironmentVariable, [EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'Retrieval HMAC key is not configured in the process environment' }
    if ($key.Length -lt 16) { throw 'Retrieval HMAC key is too short' }
    $keyBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($key)
    $textBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$keyBytes)
    try { return ([BitConverter]::ToString($hmac.ComputeHash($textBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hmac.Dispose() }
}

function Get-HmacQueryFingerprint {
    param([Parameter(Mandatory = $true)][string]$Query, [Parameter(Mandatory = $true)][string]$KeyEnvironmentVariable)

    return Get-HmacSha256Hex -Text $Query -KeyEnvironmentVariable $KeyEnvironmentVariable
}

function Get-RetrievalReceiptAttestationPayload {
    param([Parameter(Mandatory = $true)]$Receipt)

    $included = @($Receipt.included | ForEach-Object {
        $item = [ordered]@{
            candidate_id = [string]$_.candidate_id
            evidence_refs = @($_.evidence_refs | ForEach-Object { [ordered]@{ document_id = [string]$_.document_id; content_hash = [string]$_.content_hash; locator = [string]$_.locator } })
            score = [double]$_.score
            reasons = @($_.reasons | ForEach-Object { [string]$_ })
        }
        if ($null -ne $_.PSObject.Properties['canonical_entity_id']) { $item['canonical_entity_id'] = [string]$_.canonical_entity_id }
        [pscustomobject]$item
    })
    $excluded = @($Receipt.excluded | ForEach-Object { [pscustomobject][ordered]@{ candidate_id = [string]$_.candidate_id; reason = [string]$_.reason } })
    $projection = [ordered]@{
        schema_version = [int]$Receipt.schema_version
        receipt_id = [string]$Receipt.receipt_id
        query_fingerprint = [string]$Receipt.query_fingerprint
        fingerprint_scheme = [string]$Receipt.fingerprint_scheme
        fingerprint_key_id = [string]$Receipt.fingerprint_key_id
        resolver_version = [string]$Receipt.resolver_version
        contract_ref = [string]$Receipt.contract_ref
        contract_schema_digest = [string]$Receipt.contract_schema_digest
        source_repository = [string]$Receipt.source_repository
        source_revision = [string]$Receipt.source_revision
        source_implementation_digest = [string]$Receipt.source_implementation_digest
        capture_mode = [string]$Receipt.capture_mode
        corpus_contract_version = [string]$Receipt.corpus_contract_version
        corpus_revision = [string]$Receipt.corpus_revision
        index_generation_id = [string]$Receipt.index_generation_id
        index_revision = [string]$Receipt.index_revision
        backend_states = [ordered]@{ lexical = [string]$Receipt.backend_states.lexical; vector = [string]$Receipt.backend_states.vector; graph = [string]$Receipt.backend_states.graph }
        included = $included
        excluded = $excluded
        recorded_at = [string]$Receipt.recorded_at
    }
    if ($null -ne $Receipt.PSObject.Properties['supersedes']) { $projection['supersedes'] = [string]$Receipt.supersedes }
    if ($null -ne $Receipt.PSObject.Properties['outcome_ref']) { $projection['outcome_ref'] = [string]$Receipt.outcome_ref }
    $projection['append_only'] = [bool]$Receipt.append_only
    return "retrieval-receipt-attestation/v1`n" + [string]([pscustomobject]$projection | ConvertTo-Json -Depth 20 -Compress)
}

function Get-RetrievalReceiptAttestation {
    param([Parameter(Mandatory = $true)]$Receipt, [Parameter(Mandatory = $true)][string]$KeyEnvironmentVariable)

    return Get-HmacSha256Hex -Text (Get-RetrievalReceiptAttestationPayload -Receipt $Receipt) -KeyEnvironmentVariable $KeyEnvironmentVariable
}

function Assert-RetrievalReceiptAttestation {
    param([Parameter(Mandatory = $true)]$Receipt, [Parameter(Mandatory = $true)][string]$KeyEnvironmentVariable)

    if ([string]$Receipt.receipt_attestation_scheme -cne 'hmac-sha256-v1' -or [string]$Receipt.receipt_attestation -notmatch '^[0-9a-f]{64}$') { throw 'Receipt attestation is missing or invalid' }
    $expected = Get-RetrievalReceiptAttestation -Receipt $Receipt -KeyEnvironmentVariable $KeyEnvironmentVariable
    if ([string]$Receipt.receipt_attestation -cne $expected) { throw 'Receipt attestation does not match the canonical payload' }
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
    $quotedArguments = New-Object Collections.Generic.List[string]
    foreach ($argument in @('-c', "safe.directory=$RepositoryRoot", '-C', $RepositoryRoot) + $Arguments) {
        $quotedArguments.Add('"' + ([string]$argument).Replace('"', '\"') + '"')
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $git
    $start.Arguments = [string]::Join(' ', $quotedArguments.ToArray())
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $stdout = New-Object IO.MemoryStream
    try {
        $null = $process.Start()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($stdout)
        $process.WaitForExit()
        $stderr = $stderrTask.Result
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
        $stdout.Dispose()
    }
    if ($exitCode -ne 0) { throw "$Label is unavailable at the requested Git ref: $($stderr.Trim())" }
    return Get-StrictUtf8Text -Bytes $stdout.ToArray() -Label "$Label Git output"
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
        [switch]$RequireExactHead,
        [switch]$RequireClean
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
    if ($RequireClean) {
        $status = Invoke-GitText -RepositoryRoot $root -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -Label "$Label repository status"
        if (-not [string]::IsNullOrWhiteSpace($status)) { throw "$Label repository must be clean before retrieval evidence capture" }
    }
    return [pscustomobject][ordered]@{ Root = $root; Head = $head; BundleDigest = $workingDigest }
}

function Assert-ExactCleanGitCheckout {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedRef,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $root = Get-OrdinaryRoot -Path $RepositoryRoot -Label "$Label repository root"
    $head = (Invoke-GitText -RepositoryRoot $root -Arguments @('rev-parse', 'HEAD') -Label "$Label HEAD").Trim()
    if ($head -cne $ExpectedRef) { throw "$Label HEAD must equal the requested contract ref for fresh retrieval capture" }
    $status = Invoke-GitText -RepositoryRoot $root -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -Label "$Label repository status"
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw "$Label repository must be clean for fresh retrieval capture" }
    return $root
}

function Invoke-FreshMcpEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$McpRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$BrainRepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Query
    )

    $python = Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $helper = Join-Path $PSScriptRoot 'Get-VerifiedMcpEnvelope.py'
    if (-not [IO.File]::Exists($helper)) { throw 'Verified MCP envelope helper is missing' }
    # -E ignores inherited PYTHON* injection, while -P keeps the helper directory
    # and current directory off sys.path without disabling the installed user site.
    $arguments = @('-E', '-P', '-B', $helper, '--mcp-root', $McpRepositoryRoot, '--brain-root', $BrainRepositoryRoot)
    $quoted = @($arguments | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' })
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [string]$python.Source
    $start.Arguments = [string]::Join(' ', $quoted)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $queryBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Query)
        $process.StandardInput.BaseStream.Write($queryBytes, 0, $queryBytes.Length)
        $process.StandardInput.BaseStream.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $stderr = $stderrTask.Result
        $exitCode = $process.ExitCode
    }
    finally { $process.Dispose() }
    if ($exitCode -ne 0) { throw "Fresh MCP stdio retrieval failed (exit=$exitCode): $($stderr.Trim())" }
    return ConvertFrom-StrictJsonText -Text $stdout -Label 'Fresh MCP stdio envelope'
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
    $null = Assert-ImplementationBinding -RepositoryRoot $agentKitRoot -PinnedRef $agentKitImplementationRef -ExpectedBundleDigest $agentKitRuntimeDigest -RelativePaths $script:AgentKitRuntimePaths -Label 'Agent Kit' -RequireClean
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
        try { $schema = ConvertFrom-StrictJsonText -Text $text -Label $relativePath }
        catch { throw "$relativePath is not valid strict JSON" }
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
        RegisteredGoldenProofs = @([Regex]::Matches($indexText, '(?m)^    - id: ([a-z0-9][a-z0-9-]{0,127})\r?\n      path: (memory/retrieval-evidence/proofs/golden-eval/[a-z0-9._-]+\.json)\r?\n      content_hash: ([0-9a-f]{64})\s*$') | ForEach-Object {
            [pscustomobject][ordered]@{ Id = [string]$_.Groups[1].Value; Path = [string]$_.Groups[2].Value; ContentHash = [string]$_.Groups[3].Value }
        })
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
    if ($scheme -cne 'golden-eval') { throw "$scheme outcome proofs are inactive until a trusted issuer is configured" }
    $root = [string]$ContractSnapshot.ContractRepositoryRoot
    $null = Invoke-GitText -RepositoryRoot $root -Arguments @('merge-base', '--is-ancestor', [string]$Receipt.contract_ref, $proofRef) -Label 'Outcome proof contract ancestry'
    $null = Invoke-GitText -RepositoryRoot $root -Arguments @('merge-base', '--is-ancestor', $proofRef, 'HEAD') -Label 'Outcome proof Brain ancestry'
    $proofPath = "memory/retrieval-evidence/proofs/$scheme/$proofId.json"
    $registered = @($ContractSnapshot.RegisteredGoldenProofs | Where-Object { [string]$_.Id -ceq $proofId })
    if ($registered.Count -ne 1 -or [string]$registered[0].Path -cne $proofPath -or [string]$registered[0].ContentHash -cne $contentHash) { throw 'Golden outcome proof is not registered in the pinned contract' }
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

function Assert-UniqueJsonObjectKeys {
    param([Parameter(Mandatory = $true)][string]$Text, [switch]$JsonLines, [string]$Label = 'JSON input')

    $python = Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $helper = Join-Path $PSScriptRoot 'Assert-UniqueJsonKeys.py'
    if (-not [IO.File]::Exists($helper)) { throw 'Strict JSON key helper is missing' }
    $arguments = @('-I', '"' + $helper.Replace('"', '\"') + '"')
    if ($JsonLines) { $arguments += '--json-lines' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [string]$python.Source
    $start.Arguments = [string]::Join(' ', $arguments)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.BaseStream.Close()
        $null = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $stderr = $stderrTask.Result
        $exitCode = $process.ExitCode
    }
    finally { $process.Dispose() }
    if ($exitCode -ne 0) { throw "$Label is invalid or contains duplicate object keys: $($stderr.Trim())" }
}

function ConvertFrom-StrictJsonText {
    param([Parameter(Mandatory = $true)][string]$Text, [string]$Label = 'JSON input')

    if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Label cannot be empty" }
    Assert-UniqueJsonObjectKeys -Text $Text -Label $Label
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

    Assert-UniqueJsonObjectKeys -Text $Text -JsonLines -Label $Label
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
    $entries = @(Get-ChildItem -LiteralPath $eventDirectory -Force | Sort-Object Name)
    foreach ($entry in $entries) {
        if (-not [IO.File]::Exists([string]$entry.FullName) -or (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $entry.Name -notmatch '^(receipts|outcomes)-\d{4}-\d{2}\.jsonl$') {
            throw "Retrieval event directory contains an unexpected or unsafe entry: $($entry.Name)"
        }
    }
    $files = @($entries | Where-Object { $_.Name -match "^$Kind-\d{4}-\d{2}\.jsonl$" })
    $rows = New-Object Collections.Generic.List[object]
    $ids = @{}
    $paths = New-Object Collections.Generic.List[string]
    foreach ($file in $files) {
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
    if ([string]::Equals($brain, [string]$ContractSnapshot.ContractRepositoryRoot, [StringComparison]::OrdinalIgnoreCase) -and $ContractSnapshot.TrackedEventLogs -cnotcontains $RelativePath) {
        throw 'Canonical Brain event log must be pre-registered in the active contract index'
    }
}

function Assert-CanonicalEventRegistration {
    param([Parameter(Mandatory = $true)][string]$BrainRoot, [Parameter(Mandatory = $true)]$ContractSnapshot)

    $brain = Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot'
    if (-not [string]::Equals($brain, [string]$ContractSnapshot.ContractRepositoryRoot, [StringComparison]::OrdinalIgnoreCase)) { return }
    $eventDirectory = Join-Path $brain 'memory\retrieval-evidence\events'
    $physical = New-Object Collections.Generic.List[string]
    if ([IO.Directory]::Exists($eventDirectory)) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $eventDirectory -Force | Sort-Object Name)) {
            if (-not [IO.File]::Exists([string]$entry.FullName) -or (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $entry.Name -notmatch '^(receipts|outcomes)-\d{4}-\d{2}\.jsonl$') {
                throw "Canonical retrieval event directory contains an unexpected or unsafe entry: $($entry.Name)"
            }
            $physical.Add("memory/retrieval-evidence/events/$($entry.Name)")
        }
    }
    $registered = @($ContractSnapshot.TrackedEventLogs | Sort-Object)
    if ([string]::Join("`n", $physical.ToArray()) -cne [string]::Join("`n", $registered)) { throw 'Canonical retrieval event files must exactly match the pinned contract registration' }
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
    $stream = New-Object IO.FileStream($target, $mode, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
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

function Enter-RetrievalEvidenceMutex {
    param([Parameter(Mandatory = $true)][string]$BrainRoot)

    $root = (Get-OrdinaryRoot -Path $BrainRoot -Label 'BrainRoot').ToLowerInvariant()
    $name = 'Local\YohanRetrievalEvidence-' + (Get-Sha256Hex -Text $root)
    $mutex = New-Object Threading.Mutex($false, $name)
    try {
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(120)) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Timed out waiting for the retrieval evidence transaction lock' }
        return $mutex
    }
    catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-RetrievalEvidenceMutex {
    param($Mutex)

    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() }
    finally { $Mutex.Dispose() }
}
