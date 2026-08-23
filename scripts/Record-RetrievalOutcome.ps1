#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][string]$ContractRepositoryRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ContractRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractSchemaDigest,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/receipts-\d{4}-\d{2}\.jsonl$')][string]$ReceiptLogPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^memory/retrieval-evidence/events/outcomes-\d{4}-\d{2}\.jsonl$')][string]$EventLogPath,
    [Parameter(Mandatory = $true)][string]$OutcomeId,
    [Parameter(Mandatory = $true)][string]$ReceiptId,
    [Parameter(Mandatory = $true)][ValidateSet('human-explicit', 'golden-eval', 'task-result')][string]$SignalKind,
    [Parameter(Mandatory = $true)][ValidateSet('helpful', 'partial', 'unhelpful', 'unknown')][string]$Verdict,
    [Parameter(Mandatory = $true)][string[]]$EvidenceRefs,
    [Parameter(Mandatory = $true)][ValidateSet('human', 'agent', 'tool')][string]$ActorType,
    [string]$ApprovalRef,
    [Parameter(Mandatory = $true)][datetime]$RecordedAt,
    [string]$Supersedes,
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RetrievalEvidence.Common.ps1')

try {
    Assert-SafeIdentifier -Value $OutcomeId -Label 'OutcomeId'
    Assert-SafeIdentifier -Value $ReceiptId -Label 'ReceiptId'
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) { Assert-SafeIdentifier -Value $Supersedes -Label 'Supersedes' }
    $evidence = New-Object Collections.Generic.List[string]
    foreach ($reference in @($EvidenceRefs)) {
        $value = [string]$reference
        if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch '^(human-approval|golden-eval|task-result):[a-z0-9][a-z0-9._-]{0,127}@git:[0-9a-f]{40}@sha256:[0-9a-f]{64}$') { throw 'EvidenceRefs contains an invalid content-addressed proof reference' }
        if (-not $evidence.Contains($value)) { $evidence.Add($value) }
    }
    if ($evidence.Count -ne 1) { throw 'Exactly one outcome proof reference is required in v1' }
    if ($SignalKind -eq 'human-explicit') {
        if ($ActorType -ne 'human') { throw 'human-explicit outcome requires a human actor' }
        if ([string]::IsNullOrWhiteSpace($ApprovalRef) -or $ApprovalRef -cne $evidence[0]) { throw 'human-explicit outcome requires the exact content-addressed human approval ref' }
    }
    else {
        if ($ActorType -ne 'tool') { throw "$SignalKind outcome requires a tool actor" }
        if (-not [string]::IsNullOrWhiteSpace($ApprovalRef)) { throw 'Non-human outcomes cannot carry ApprovalRef' }
    }

    $snapshot = Get-RetrievalContractSnapshot -ContractRepositoryRoot $ContractRepositoryRoot -ContractRef $ContractRef -ExpectedSchemaDigest $ContractSchemaDigest
    Assert-MonthlyEventPath -RelativePath $EventLogPath -RecordedAt $RecordedAt -Kind outcomes
    Assert-ProductionEventRegistration -BrainRoot $BrainRoot -ContractSnapshot $snapshot -RelativePath $EventLogPath
    $specifiedReceiptLog = Read-JsonLineLog -BrainRoot $BrainRoot -RelativePath $ReceiptLogPath -Kind receipts -IdProperty receipt_id -RequireExisting
    if (-not $specifiedReceiptLog.Ids.ContainsKey($ReceiptId)) { throw 'ReceiptLogPath does not contain ReceiptId' }
    $receipts = Read-AllJsonLineLogs -BrainRoot $BrainRoot -Kind receipts -IdProperty receipt_id
    if (-not $receipts.Ids.ContainsKey($ReceiptId)) { throw 'Outcome receipt_id does not exist' }
    $receipt = @($receipts.Rows | Where-Object { [string]$_.receipt_id -ceq $ReceiptId })[0]
    if ([string]$receipt.contract_ref -cne $ContractRef -or [string]$receipt.contract_schema_digest -cne $ContractSchemaDigest) { throw 'Outcome contract binding does not match the receipt' }
    $outcomes = Read-AllJsonLineLogs -BrainRoot $BrainRoot -Kind outcomes -IdProperty outcome_id
    if ($outcomes.Ids.ContainsKey($OutcomeId)) { throw 'Duplicate outcome_id across outcome logs' }
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) {
        if (-not $outcomes.Ids.ContainsKey($Supersedes)) { throw 'Supersedes must reference an existing prior outcome' }
        $prior = @($outcomes.Rows | Where-Object { [string]$_.outcome_id -ceq $Supersedes })[0]
        if ([string]$prior.receipt_id -cne $ReceiptId) { throw 'Supersedes must stay within the same receipt' }
    }
    $null = Resolve-OutcomeProof -ContractSnapshot $snapshot -Receipt $receipt -Reference $evidence[0] -SignalKind $SignalKind -Verdict $Verdict -ActorType $ActorType

    $outcome = [pscustomobject][ordered]@{
        schema_version = 1
        outcome_id = $OutcomeId
        receipt_id = $ReceiptId
        signal_kind = $SignalKind
        verdict = $Verdict
        evidence_refs = $evidence.ToArray()
        actor_type = $ActorType
    }
    if (-not [string]::IsNullOrWhiteSpace($ApprovalRef)) { $outcome | Add-Member -NotePropertyName approval_ref -NotePropertyValue $ApprovalRef }
    $outcome | Add-Member -NotePropertyName recorded_at -NotePropertyValue $RecordedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
    if (-not [string]::IsNullOrWhiteSpace($Supersedes)) { $outcome | Add-Member -NotePropertyName supersedes -NotePropertyValue $Supersedes }
    $outcome | Add-Member -NotePropertyName append_only -NotePropertyValue $true

    $schemaAllowed = @($snapshot.OutcomeSchema.properties.PSObject.Properties.Name)
    $schemaRequired = @($snapshot.OutcomeSchema.required | ForEach-Object { [string]$_ })
    Assert-AllowedObjectFields -Value $outcome -Allowed $schemaAllowed -Required $schemaRequired -Label 'RetrievalOutcomeEvent'
    $null = Add-JsonLineAppendOnly -BrainRoot $BrainRoot -RelativePath $EventLogPath -Kind outcomes -IdProperty outcome_id -Value $outcome

    $result = [pscustomobject][ordered]@{ status = 'appended'; outcome_id = $OutcomeId; receipt_id = $ReceiptId; verdict = $Verdict; path = $EventLogPath }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Compress)) }
    else { Write-Output "Appended $OutcomeId ($Verdict) to $EventLogPath" }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
