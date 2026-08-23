#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractSchemaDigest,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/receipts-\d{4}-\d{2}\.jsonl$')][string]$ReceiptLogPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/outcomes-\d{4}-\d{2}\.jsonl$')][string]$OutcomeLogPath,
    [Parameter(Mandatory = $true)][string]$ReceiptId,
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RetrievalEvidence.Common.ps1')

try {
    Assert-SafeIdentifier -Value $ReceiptId -Label 'ReceiptId'
    $snapshot = Get-RetrievalContractSnapshot -ContractRepositoryRoot $ContractRepositoryRoot -ContractRef $ContractRef -ExpectedSchemaDigest $ContractSchemaDigest
    $receipts = Read-JsonLineLog -BrainRoot $BrainRoot -RelativePath $ReceiptLogPath -Kind receipts -IdProperty receipt_id -RequireExisting
    $receipt = @($receipts.Rows | Where-Object { [string]$_.receipt_id -ceq $ReceiptId })
    if ($receipt.Count -ne 1) { throw 'ReceiptId must resolve to exactly one receipt' }
    $receipt = $receipt[0]
    if ([string]$receipt.contract_ref -cne $ContractRef -or [string]$receipt.contract_schema_digest -cne $ContractSchemaDigest) { throw 'Receipt contract binding does not match the requested contract' }

    $outcomeLog = Read-AllJsonLineLogs -BrainRoot $BrainRoot -Kind outcomes -IdProperty outcome_id
    $priorById = @{}
    $supersededIds = @{}
    $matching = New-Object Collections.Generic.List[object]
    foreach ($outcome in @($outcomeLog.Rows)) {
        $outcomeId = [string]$outcome.outcome_id
        if (@('helpful', 'partial', 'unhelpful', 'unknown') -cnotcontains [string]$outcome.verdict) { throw "Outcome verdict is invalid: $outcomeId" }
        if ($null -ne $outcome.PSObject.Properties['supersedes']) {
            $supersedes = [string]$outcome.supersedes
            if (-not $priorById.ContainsKey($supersedes)) { throw "Outcome supersedes does not reference a prior event: $outcomeId" }
            if ([string]$priorById[$supersedes].receipt_id -cne [string]$outcome.receipt_id) { throw "Outcome supersedes crosses receipt boundary: $outcomeId" }
            $supersededIds[$supersedes] = $true
        }
        $priorById[$outcomeId] = $outcome
        if ([string]$outcome.receipt_id -ceq $ReceiptId) {
            if (@($outcome.evidence_refs).Count -ne 1) { throw "Outcome proof cardinality is invalid: $outcomeId" }
            $actor = [string]$outcome.actor_type
            $null = Resolve-OutcomeProof -ContractSnapshot $snapshot -Receipt $receipt -Reference ([string]@($outcome.evidence_refs)[0]) -SignalKind ([string]$outcome.signal_kind) -Verdict ([string]$outcome.verdict) -ActorType $actor
            $matching.Add($outcome)
        }
    }
    $activeById = @{}
    foreach ($outcome in @($matching.ToArray() | Where-Object { -not $supersededIds.ContainsKey([string]$_.outcome_id) })) { $activeById[[string]$outcome.outcome_id] = $outcome }
    $activeIds = [string[]]@($activeById.Keys)
    [Array]::Sort($activeIds, [StringComparer]::Ordinal)
    $activeOutcomes = @($activeIds | ForEach-Object { $activeById[$_] })

    $affected = New-Object Collections.Generic.List[string]
    foreach ($included in @($receipt.included)) {
        foreach ($reference in @($included.evidence_refs)) {
            $documentId = [string]$reference.document_id
            if ($documentId -notmatch '^brain:[^\r\n]+$') { throw 'Receipt contains an invalid affected evidence reference' }
            if (-not $affected.Contains($documentId)) { $affected.Add($documentId) }
        }
    }
    $affectedRefs = [string[]]$affected.ToArray()
    [Array]::Sort($affectedRefs, [StringComparer]::Ordinal)
    if ($affectedRefs.Count -eq 0) { throw 'Receipt has no affected evidence references' }

    $outcomeRefs = [string[]]@($activeOutcomes | ForEach-Object { [string]$_.outcome_id })
    $disposition = 'review'
    $reasonCodes = New-Object Collections.Generic.List[string]
    if ($activeOutcomes.Count -eq 0) {
        $reasonCodes.Add('no-outcome')
    }
    else {
        $verdictSet = @{}
        foreach ($outcome in $activeOutcomes) { $verdictSet[[string]$outcome.verdict] = $true }
        $verdicts = [string[]]@($verdictSet.Keys)
        [Array]::Sort($verdicts, [StringComparer]::Ordinal)
        if ($verdicts.Count -eq 1 -and $verdicts[0] -ceq 'helpful') {
            $disposition = 'preserve'
            $reasonCodes.Add('outcome-helpful')
        }
        else {
            if ($verdicts.Count -gt 1) { $reasonCodes.Add('conflicting-outcomes') }
            foreach ($verdict in $verdicts) {
                $code = "outcome-$verdict"
                if (-not $reasonCodes.Contains($code)) { $reasonCodes.Add($code) }
            }
        }
    }
    $identity = "retrieval-learning-candidate/v1`n$ReceiptId`n" + ([string]::Join("`n", $outcomeRefs))
    $candidateId = 'candidate-' + (Get-Sha256Hex -Text $identity).Substring(0, 24)
    $candidate = [pscustomobject][ordered]@{
        schema_version = 1
        candidate_id = $candidateId
        receipt_id = $ReceiptId
        outcome_refs = $outcomeRefs
        disposition = $disposition
        affected_evidence_refs = $affectedRefs
        reason_codes = $reasonCodes.ToArray()
        status = 'candidate'
        stable_auto_promotion = $false
    }

    $schemaAllowed = @($snapshot.CandidateSchema.properties.PSObject.Properties.Name)
    $schemaRequired = @($snapshot.CandidateSchema.required | ForEach-Object { [string]$_ })
    Assert-AllowedObjectFields -Value $candidate -Allowed $schemaAllowed -Required $schemaRequired -Label 'RetrievalLearningCandidate'
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($candidate | ConvertTo-Json -Depth 20 -Compress)) }
    else { Write-Output "${candidateId}: $disposition ($([string]::Join(',', $reasonCodes.ToArray())))" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
