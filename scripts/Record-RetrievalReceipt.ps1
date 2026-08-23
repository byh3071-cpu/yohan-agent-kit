#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
    [Parameter(Mandatory = $true)][string]$McpRepositoryRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractSchemaDigest,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/receipts-\d{4}-\d{2}\.jsonl$')][string]$EventLogPath,
    [Parameter(Mandatory = $true)][string]$ReceiptId,
    [Parameter(Mandatory = $true)][string]$FingerprintKeyId,
    [ValidatePattern('^[A-Z][A-Z0-9_]{2,63}$')][string]$KeyEnvironmentVariable = 'YOHAN_RETRIEVAL_HMAC_KEY',
    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$')][string]$ResolverVersion = '1.0.0',
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceRevision,
    [Parameter(Mandatory = $true)][datetime]$RecordedAt,
    [string]$Supersedes,
    [string]$OutcomeRef,
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RetrievalEvidence.Common.ps1')
$transactionMutex = $null

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
}

function Get-RetrievalDiagnosticsFromEnvelope {
    param([Parameter(Mandatory = $true)]$TransportEnvelope, [Parameter(Mandatory = $true)][string]$Label)

    $envelope = $TransportEnvelope
    if ($null -ne $envelope.PSObject.Properties['content'] -and @($envelope.content).Count -gt 0) {
        $first = @($envelope.content)[0]
        if ($null -ne $first.PSObject.Properties['text']) { $envelope = ConvertFrom-StrictJsonText -Text ([string]$first.text) -Label "$Label content text" }
    }
    if ($null -eq $envelope.PSObject.Properties['data'] -or $null -eq $envelope.data.PSObject.Properties['retrieval_diagnostics']) { throw "$Label retrieval_diagnostics are missing" }
    return $envelope.data.retrieval_diagnostics
}

function Get-StableRetrievalDiagnosticsJson {
    param([Parameter(Mandatory = $true)]$Diagnostics)

    $clone = ConvertFrom-StrictJsonText -Text ([string]($Diagnostics | ConvertTo-Json -Depth 24 -Compress)) -Label 'Retrieval diagnostics projection'
    $clone.PSObject.Properties.Remove('latency_ms')
    return [string]($clone | ConvertTo-Json -Depth 24 -Compress)
}

try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    Assert-SafeIdentifier -Value $ReceiptId -Label 'ReceiptId'
    Assert-SafeFingerprintKeyId -Value $FingerprintKeyId
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) { Assert-SafeIdentifier -Value $Supersedes -Label 'Supersedes' }
    if (-not [string]::IsNullOrWhiteSpace($OutcomeRef)) { Assert-SafeIdentifier -Value $OutcomeRef -Label 'OutcomeRef' }
    $transactionMutex = Enter-RetrievalEvidenceMutex -BrainRoot $BrainRoot
    $snapshot = Get-RetrievalContractSnapshot -ContractRepositoryRoot $ContractRepositoryRoot -ContractRef $ContractRef -ExpectedSchemaDigest $ContractSchemaDigest
    if ($SourceRevision -cne $snapshot.McpImplementationRef) { throw 'SourceRevision does not match the activated MCP implementation ref' }
    $contractRoot = Assert-ExactCleanGitCheckout -RepositoryRoot $ContractRepositoryRoot -ExpectedRef $ContractRef -Label 'Brain contract'
    $null = Assert-ImplementationBinding -RepositoryRoot $McpRepositoryRoot -PinnedRef $snapshot.McpImplementationRef -ExpectedBundleDigest $snapshot.McpRuntimeBundleDigest -RelativePaths $script:McpRuntimePaths -Label 'MCP' -RequireExactHead -RequireClean
    Assert-MonthlyEventPath -RelativePath $EventLogPath -RecordedAt $RecordedAt -Kind receipts
    Assert-CanonicalEventRegistration -BrainRoot $BrainRoot -ContractSnapshot $snapshot
    Assert-ProductionEventRegistration -BrainRoot $BrainRoot -ContractSnapshot $snapshot -RelativePath $EventLogPath

    $inputText = [Console]::In.ReadToEnd()
    if ($inputText.Length -gt 0 -and [int][char]$inputText[0] -eq 0xFEFF) { $inputText = $inputText.Substring(1) }
    $boundInput = ConvertFrom-StrictJsonText -Text $inputText -Label 'Bound query and MCP envelope stdin'
    Assert-AllowedObjectFields -Value $boundInput -Allowed @('query', 'envelope') -Required @('query', 'envelope') -Label 'Bound receipt input'
    $query = [string]$boundInput.query
    if ([string]::IsNullOrEmpty($query) -or $query.IndexOf([char]0) -ge 0) { throw 'Bound receipt query is invalid' }
    $diagnostics = Get-RetrievalDiagnosticsFromEnvelope -TransportEnvelope $boundInput.envelope -Label 'Supplied MCP envelope'
    $freshEnvelope = Invoke-FreshMcpEnvelope -McpRepositoryRoot $McpRepositoryRoot -BrainRepositoryRoot $contractRoot -Query $query
    $freshDiagnostics = Get-RetrievalDiagnosticsFromEnvelope -TransportEnvelope $freshEnvelope -Label 'Fresh MCP stdio envelope'
    $suppliedCanonical = Get-StableRetrievalDiagnosticsJson -Diagnostics $diagnostics
    $freshCanonical = Get-StableRetrievalDiagnosticsJson -Diagnostics $freshDiagnostics
    if ($suppliedCanonical -cne $freshCanonical) { throw 'Supplied MCP diagnostics do not match a fresh clean pinned stdio retrieval' }
    $diagnostics = $freshDiagnostics
    $null = Assert-ExactCleanGitCheckout -RepositoryRoot $ContractRepositoryRoot -ExpectedRef $ContractRef -Label 'Brain contract'
    $null = Assert-ImplementationBinding -RepositoryRoot $McpRepositoryRoot -PinnedRef $snapshot.McpImplementationRef -ExpectedBundleDigest $snapshot.McpRuntimeBundleDigest -RelativePaths $script:McpRuntimePaths -Label 'MCP' -RequireExactHead -RequireClean
    if ([string]$diagnostics.schema -cne 'retrieval-diagnostics/v1' -or [bool]$diagnostics.volatile -ne $true -or [bool]$diagnostics.persisted -ne $false) { throw 'MCP diagnostics must be volatile retrieval-diagnostics/v1 and not persisted' }
    if ($null -eq $diagnostics.index -or [bool]$diagnostics.index.fresh -ne $true) { throw 'MCP index must be fresh before recording a receipt' }
    foreach ($value in @($diagnostics.index.revision, $diagnostics.index.generation_id)) {
        if ([string]$value -notmatch '^[0-9a-f]{64}$') { throw 'MCP index lineage is incomplete' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$diagnostics.index.corpus_contract_version)) { throw 'MCP corpus contract version is missing' }
    if ([string]$diagnostics.runtime.repository -cne 'yohan-mcp' -or [string]$diagnostics.runtime.implementation_digest -cne $snapshot.McpRuntimeBundleDigest) { throw 'MCP runtime attestation does not match the active contract' }
    if ([string]$diagnostics.query_binding.scheme -cne 'sha256-utf8-v1' -or [string]$diagnostics.query_binding.digest -cne (Get-Sha256Hex -Text $query)) { throw 'MCP query binding does not match the receipt query' }
    $queryFingerprint = Get-HmacQueryFingerprint -Query $query -KeyEnvironmentVariable $KeyEnvironmentVariable

    $included = New-Object Collections.Generic.List[object]
    $excluded = New-Object Collections.Generic.List[object]
    $candidateIds = @{}
    foreach ($item in @($diagnostics.evidence)) {
        $candidateType = [string]$item.type
        $candidateValue = [string]$item.id
        $candidateId = $candidateType + ':' + $candidateValue
        if ([string]::IsNullOrWhiteSpace($candidateType) -or [string]::IsNullOrWhiteSpace($candidateValue) -or $candidateId.Length -gt 256 -or $candidateId -match '[\r\n]') { throw 'MCP evidence candidate id is invalid' }
        if ($candidateIds.ContainsKey($candidateId)) { throw "MCP diagnostics contain a duplicate candidate id: $candidateId" }
        $candidateIds[$candidateId] = $true
        $locator = [string]$item.locator
        $documentId = [string]$item.document_id
        $contentHash = [string]$item.content_hash
        $score = $item.score
        $numericScore = 0.0
        $scoreReady = $null -ne $score -and [double]::TryParse([string]$score, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$numericScore) -and -not [double]::IsNaN($numericScore) -and -not [double]::IsInfinity($numericScore)
        $lineageReady = (Test-RepoRelativePosixPath -Path $locator) -and $locator.Length -le 512 -and $documentId -ceq "brain:$locator" -and $contentHash -match '^[0-9a-f]{64}$' -and $scoreReady
        if ($lineageReady) {
            $included.Add([pscustomobject][ordered]@{
                candidate_id = $candidateId
                evidence_refs = @([pscustomobject][ordered]@{
                    document_id = $documentId
                    content_hash = $contentHash
                    locator = $locator
                })
                score = $numericScore
                reasons = @('retrieval-match')
            })
        }
        else {
            $excluded.Add([pscustomobject][ordered]@{ candidate_id = $candidateId; reason = 'unavailable_backend' })
        }
    }
    if ($included.Count -eq 0) { throw 'MCP envelope has no evidence with complete document lineage' }

    $attempted = Get-StringArray -Value $diagnostics.sources.attempted
    $availableCollections = @($diagnostics.collections.available)
    $unavailableCollections = @($diagnostics.collections.unavailable)
    $vectorState = 'skipped'
    if ($attempted -contains 'qdrant') {
        if ($availableCollections.Count -gt 0) { $vectorState = 'ready' }
        elseif ($unavailableCollections.Count -gt 0) { $vectorState = 'degraded' }
        else { $vectorState = 'unavailable' }
    }
    $graphState = if ([int]$diagnostics.graph_edge_count -gt 0) { 'ready' } else { 'skipped' }

    $receipt = [pscustomobject][ordered]@{
        schema_version = 1
        receipt_id = $ReceiptId
        query_fingerprint = $queryFingerprint
        fingerprint_scheme = 'hmac-sha256-v1'
        fingerprint_key_id = $FingerprintKeyId
        resolver_version = $ResolverVersion
        contract_ref = $snapshot.ContractRef
        contract_schema_digest = $snapshot.SchemaDigest
        source_repository = 'yohan-mcp'
        source_revision = $SourceRevision
        source_implementation_digest = $snapshot.McpRuntimeBundleDigest
        capture_mode = 'fresh-verified-mcp-stdio-v1'
        corpus_contract_version = [string]$diagnostics.index.corpus_contract_version
        corpus_revision = [string]$diagnostics.index.revision
        index_generation_id = [string]$diagnostics.index.generation_id
        index_revision = [string]$diagnostics.index.revision
        backend_states = [pscustomobject][ordered]@{ lexical = 'ready'; vector = $vectorState; graph = $graphState }
        included = $included.ToArray()
        excluded = $excluded.ToArray()
        recorded_at = $RecordedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) { $receipt | Add-Member -NotePropertyName supersedes -NotePropertyValue $Supersedes }
    if (-not [string]::IsNullOrWhiteSpace($OutcomeRef)) { $receipt | Add-Member -NotePropertyName outcome_ref -NotePropertyValue $OutcomeRef }
    $receipt | Add-Member -NotePropertyName append_only -NotePropertyValue $true
    $receipt | Add-Member -NotePropertyName receipt_attestation_scheme -NotePropertyValue 'hmac-sha256-v1'
    $receipt | Add-Member -NotePropertyName receipt_attestation -NotePropertyValue (Get-RetrievalReceiptAttestation -Receipt $receipt -KeyEnvironmentVariable $KeyEnvironmentVariable)

    $schemaAllowed = @($snapshot.ReceiptSchema.properties.PSObject.Properties.Name)
    $schemaRequired = @($snapshot.ReceiptSchema.required | ForEach-Object { [string]$_ })
    Assert-AllowedObjectFields -Value $receipt -Allowed $schemaAllowed -Required $schemaRequired -Label 'RetrievalReceipt'
    if ([string]$receipt.corpus_contract_version -eq '' -or ([string]$receipt.corpus_contract_version).Length -gt 64) { throw 'Receipt corpus contract version is invalid' }
    $existing = Read-AllJsonLineLogs -BrainRoot $BrainRoot -Kind receipts -IdProperty receipt_id
    if ($existing.Ids.ContainsKey($ReceiptId)) { throw 'Duplicate receipt_id across receipt logs' }
    if (-not [string]::IsNullOrWhiteSpace($Supersedes) -and -not $existing.Ids.ContainsKey($Supersedes)) { throw 'Supersedes must reference an existing prior receipt' }
    $null = Add-JsonLineAppendOnly -BrainRoot $BrainRoot -RelativePath $EventLogPath -Kind receipts -IdProperty receipt_id -Value $receipt

    $result = [pscustomobject][ordered]@{
        status = 'appended'
        receipt_id = $ReceiptId
        path = $EventLogPath
        included = $included.Count
        excluded = $excluded.Count
        persistent_query_copy = $false
        query_binding_verified = $true
        fresh_mcp_stdio_verified = $true
        receipt_attestation_verified = $true
    }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Compress)) }
    else { Write-Output "Appended $ReceiptId to $EventLogPath" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
finally { Exit-RetrievalEvidenceMutex -Mutex $transactionMutex }
