#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractSchemaDigest,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/receipts-\d{4}-\d{2}\.jsonl$')][string]$EventLogPath,
    [Parameter(Mandatory = $true)][string]$ReceiptId,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$QueryFingerprint,
    [Parameter(Mandatory = $true)][string]$FingerprintKeyId,
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

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
}

try {
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    Assert-SafeIdentifier -Value $ReceiptId -Label 'ReceiptId'
    Assert-SafeFingerprintKeyId -Value $FingerprintKeyId
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) { Assert-SafeIdentifier -Value $Supersedes -Label 'Supersedes' }
    if (-not [string]::IsNullOrWhiteSpace($OutcomeRef)) { Assert-SafeIdentifier -Value $OutcomeRef -Label 'OutcomeRef' }
    $snapshot = Get-RetrievalContractSnapshot -ContractRepositoryRoot $ContractRepositoryRoot -ContractRef $ContractRef -ExpectedSchemaDigest $ContractSchemaDigest

    $inputText = [Console]::In.ReadToEnd()
    if ($inputText.Length -gt 0 -and [int][char]$inputText[0] -eq 0xFEFF) { $inputText = $inputText.Substring(1) }
    $envelope = ConvertFrom-StrictJsonText -Text $inputText -Label 'MCP envelope stdin'
    if ($null -ne $envelope.PSObject.Properties['content'] -and @($envelope.content).Count -gt 0) {
        $first = @($envelope.content)[0]
        if ($null -ne $first.PSObject.Properties['text']) { $envelope = ConvertFrom-StrictJsonText -Text ([string]$first.text) -Label 'MCP envelope content text' }
    }
    if ($null -eq $envelope.PSObject.Properties['data']) { throw 'MCP envelope data is missing' }
    $data = $envelope.data
    if ($null -eq $data.PSObject.Properties['retrieval_diagnostics']) { throw 'MCP retrieval_diagnostics are missing' }
    $diagnostics = $data.retrieval_diagnostics
    if ([string]$diagnostics.schema -cne 'retrieval-diagnostics/v1' -or [bool]$diagnostics.volatile -ne $true -or [bool]$diagnostics.persisted -ne $false) { throw 'MCP diagnostics must be volatile retrieval-diagnostics/v1 and not persisted' }
    if ($null -eq $diagnostics.index -or [bool]$diagnostics.index.fresh -ne $true) { throw 'MCP index must be fresh before recording a receipt' }
    foreach ($value in @($diagnostics.index.revision, $diagnostics.index.generation_id)) {
        if ([string]$value -notmatch '^[0-9a-f]{64}$') { throw 'MCP index lineage is incomplete' }
    }
    if ([string]::IsNullOrWhiteSpace([string]$diagnostics.index.corpus_contract_version)) { throw 'MCP corpus contract version is missing' }

    $included = New-Object Collections.Generic.List[object]
    $excluded = New-Object Collections.Generic.List[object]
    $candidateIds = @{}
    foreach ($item in @($diagnostics.evidence)) {
        $candidateId = ([string]$item.type) + ':' + ([string]$item.id)
        if ([string]::IsNullOrWhiteSpace($candidateId) -or $candidateId -match '[\r\n]') { throw 'MCP evidence candidate id is invalid' }
        if ($candidateIds.ContainsKey($candidateId)) { throw "MCP diagnostics contain a duplicate candidate id: $candidateId" }
        $candidateIds[$candidateId] = $true
        $locator = [string]$item.locator
        $documentId = [string]$item.document_id
        $contentHash = [string]$item.content_hash
        $score = $item.score
        $lineageReady = (Test-RepoRelativePosixPath -Path $locator) -and $documentId -ceq "brain:$locator" -and $contentHash -match '^[0-9a-f]{64}$' -and $null -ne $score
        if ($lineageReady) {
            $included.Add([pscustomobject][ordered]@{
                candidate_id = $candidateId
                evidence_refs = @([pscustomobject][ordered]@{
                    document_id = $documentId
                    content_hash = $contentHash
                    locator = $locator
                })
                score = [double]$score
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
        query_fingerprint = $QueryFingerprint
        fingerprint_scheme = 'hmac-sha256-v1'
        fingerprint_key_id = $FingerprintKeyId
        resolver_version = $ResolverVersion
        contract_ref = $snapshot.ContractRef
        contract_schema_digest = $snapshot.SchemaDigest
        source_repository = 'yohan-mcp'
        source_revision = $SourceRevision
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

    $schemaAllowed = @($snapshot.ReceiptSchema.properties.PSObject.Properties.Name)
    $schemaRequired = @($snapshot.ReceiptSchema.required | ForEach-Object { [string]$_ })
    Assert-AllowedObjectFields -Value $receipt -Allowed $schemaAllowed -Required $schemaRequired -Label 'RetrievalReceipt'
    $existing = Read-JsonLineLog -BrainRoot $BrainRoot -RelativePath $EventLogPath -Kind receipts -IdProperty receipt_id
    if (-not [string]::IsNullOrWhiteSpace($Supersedes) -and -not $existing.Ids.ContainsKey($Supersedes)) { throw 'Supersedes must reference an existing receipt in the same log' }
    $null = Add-JsonLineAppendOnly -BrainRoot $BrainRoot -RelativePath $EventLogPath -Kind receipts -IdProperty receipt_id -Value $receipt

    $result = [pscustomobject][ordered]@{
        status = 'appended'
        receipt_id = $ReceiptId
        path = $EventLogPath
        included = $included.Count
        excluded = $excluded.Count
        persistent_query_copy = $false
    }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Compress)) }
    else { Write-Output "Appended $ReceiptId to $EventLogPath" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
