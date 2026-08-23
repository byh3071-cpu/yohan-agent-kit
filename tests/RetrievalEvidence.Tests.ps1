#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainContractRoot,
    [Parameter(Mandatory = $true)][string]$McpRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fingerprintScript = Join-Path $repoRoot 'scripts\New-RetrievalQueryFingerprint.ps1'
$receiptScript = Join-Path $repoRoot 'scripts\Record-RetrievalReceipt.ps1'
$outcomeScript = Join-Path $repoRoot 'scripts\Record-RetrievalOutcome.ps1'
$candidateScript = Join-Path $repoRoot 'scripts\Get-RetrievalLearningCandidate.ps1'
$commonScript = Join-Path $repoRoot 'scripts\RetrievalEvidence.Common.ps1'
. $commonScript
$fixtureRoot = Join-Path $PSScriptRoot ('.work\retrieval-evidence-{0}' -f [Guid]::NewGuid().ToString('N'))
$powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$script:assertions = 0
$script:failure = $null
$script:junctionPath = $null

function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('\', '\').Replace('"', '\"') + '"'
}

function Invoke-Script {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [AllowEmptyString()][string]$Stdin = '',
        [hashtable]$Environment = @{}
    )

    $parts = New-Object Collections.Generic.List[string]
    foreach ($fixed in @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)) { $parts.Add((Quote-Argument $fixed)) }
    foreach ($argument in $Arguments) { $parts.Add((Quote-Argument ([string]$argument))) }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $powerShell
    $start.Arguments = [string]::Join(' ', $parts.ToArray())
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($entry in $Environment.GetEnumerator()) { $start.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $null = $process.Start()
    $process.StandardInput.Write($Stdin)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    $data = $null
    if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdout)) {
        try { $data = $stdout.Trim() | ConvertFrom-Json }
        catch { throw "Successful script returned invalid JSON: $stdout" }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Stdout = $stdout.Trim(); Stderr = $stderr.Trim(); Data = $data }
}

function New-ContractFixture {
    param([string]$Root)

    $contractRoot = Join-Path $Root 'contract'
    & git.exe clone --quiet --shared $BrainContractRoot $contractRoot
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone complete Brain contract fixture' }

    $mcpRef = [string](& git.exe -C $McpRoot rev-parse HEAD).Trim()
    $agentKitRef = [string](& git.exe -C $repoRoot rev-parse HEAD).Trim()
    $mcpDigest = Get-ImplementationBundleDigest -RepositoryRoot $McpRoot -RelativePaths $script:McpRuntimePaths
    $agentKitDigest = Get-ImplementationBundleDigest -RepositoryRoot $repoRoot -RelativePaths $script:AgentKitRuntimePaths

    $indexPath = Join-Path $contractRoot 'memory\retrieval-evidence\index.yaml'
    $index = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)
    $index = $index -replace '(?m)^status: draft\s*$', 'status: active'
    $index = $index -replace '(?m)^  brain_contract_status: draft\s*$', '  brain_contract_status: active'
    $index = $index -replace '(?m)^  agent_kit_implementation_status: not_implemented\s*$', '  agent_kit_implementation_status: implemented'
    $index = $index -replace '(?m)^  mcp_diagnostics_implementation_ref: [0-9a-f]{40}\s*$', ('  mcp_diagnostics_implementation_ref: ' + $mcpRef)
    $index = $index -replace '(?m)^  mcp_runtime_bundle_digest: ["'']?[0-9a-f]{64}["'']?\s*$', ('  mcp_runtime_bundle_digest: ' + $mcpDigest)
    $index = $index -replace '(?m)^  agent_kit_implementation_ref: [0-9a-f]{40}\s*$', ('  agent_kit_implementation_ref: ' + $agentKitRef)
    $index = $index -replace '(?m)^  agent_kit_runtime_bundle_digest: ["'']?[0-9a-f]{64}["'']?\s*$', ('  agent_kit_runtime_bundle_digest: ' + $agentKitDigest)
    Write-Utf8NoBom -Path $indexPath -Text $index

    $contractPath = Join-Path $contractRoot 'memory\core\retrieval-contract.yaml'
    $contract = [IO.File]::ReadAllText($contractPath, [Text.Encoding]::UTF8)
    $contract = $contract -replace '(?m)^  status: draft\s*$', '  status: active'
    $contract = $contract -replace '(?m)^  implementation_status: not_implemented\s*$', '  implementation_status: implemented'
    $contract = $contract -replace '(?m)^    mcp_diagnostics_implementation_ref: [0-9a-f]{40}\s*$', ('    mcp_diagnostics_implementation_ref: ' + $mcpRef)
    $contract = $contract -replace '(?m)^    mcp_runtime_bundle_digest: ["'']?[0-9a-f]{64}["'']?\s*$', ('    mcp_runtime_bundle_digest: ' + $mcpDigest)
    $contract = $contract -replace '(?m)^    agent_kit_implementation_ref: [0-9a-f]{40}\s*$', ('    agent_kit_implementation_ref: ' + $agentKitRef)
    $contract = $contract -replace '(?m)^    agent_kit_runtime_bundle_digest: ["'']?[0-9a-f]{64}["'']?\s*$', ('    agent_kit_runtime_bundle_digest: ' + $agentKitDigest)
    Write-Utf8NoBom -Path $contractPath -Text $contract

    & git.exe -C $contractRoot config user.name fixture
    & git.exe -C $contractRoot config user.email fixture@example.invalid
    & git.exe -C $contractRoot add --all
    & git.exe -C $contractRoot diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        & git.exe -C $contractRoot commit --quiet -m 'fixture active retrieval contract'
        if ($LASTEXITCODE -ne 0) { throw 'Unable to commit contract fixture' }
    }
    elseif ($LASTEXITCODE -ne 0) { throw 'Unable to inspect contract fixture changes' }
    $contractRef = [string](& git.exe -C $contractRoot rev-parse HEAD)
    $indexData = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)
    $digest = [Regex]::Match($indexData, '(?m)^  schema_bundle_digest: ([0-9a-f]{64})\s*$').Groups[1].Value
    $proofText = [IO.File]::ReadAllText((Join-Path $contractRoot 'memory\retrieval-evidence\proofs\golden-eval\asset-location-contract.json'), [Text.Encoding]::UTF8)
    $proofHash = Get-Sha256Hex -Text (ConvertTo-NormalizedLf -Text $proofText)
    return [pscustomobject]@{ Root = $contractRoot; Ref = $contractRef.Trim(); Digest = $digest; McpRef = $mcpRef; McpDigest = $mcpDigest; ProofHash = $proofHash }
}

function Remove-FixtureSafely {
    if (-not [string]::IsNullOrWhiteSpace($script:junctionPath) -and [IO.Directory]::Exists($script:junctionPath)) { [IO.Directory]::Delete($script:junctionPath) }
    if (-not [IO.Directory]::Exists($fixtureRoot)) { return }
    $workRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $target.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped tests/.work' }
    Remove-Item -LiteralPath $target -Recurse -Force
}

try {
    Assert-True ([IO.Directory]::Exists($BrainContractRoot)) 'Brain contract root exists'
    foreach ($path in @($fingerprintScript, $receiptScript, $outcomeScript, $candidateScript)) { Assert-True ([IO.File]::Exists($path)) "script exists: $path" }
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force
    $contract = New-ContractFixture -Root $fixtureRoot
    Assert-True ($contract.Ref -match '^[0-9a-f]{40}$') 'fixture contract exact Git ref'
    Assert-True ($contract.Digest -match '^[0-9a-f]{64}$') 'fixture schema digest'

    $evidenceRoot = Join-Path $fixtureRoot 'evidence'
    $eventsRoot = Join-Path $evidenceRoot 'memory\retrieval-evidence\events'
    $null = New-Item -ItemType Directory -Path $eventsRoot -Force
    $receiptLog = 'memory/retrieval-evidence/events/receipts-2026-08.jsonl'
    $outcomeLog = 'memory/retrieval-evidence/events/outcomes-2026-08.jsonl'
    $query = 'asset location contract ASSETS'
    $fixtureKey = 'fixture-only-hmac-material-32-bytes'
    $hmacEnvironment = @{ YOHAN_RETRIEVAL_HMAC_KEY = $fixtureKey }

    $missingKey = Invoke-Script -ScriptPath $fingerprintScript -Arguments @('-FingerprintKeyId', 'fixture-v1') -Stdin $query
    Assert-Equal 3 $missingKey.ExitCode 'missing HMAC key fails closed'
    Assert-True (-not $missingKey.Stdout.Contains($query)) 'missing-key output omits query'

    $fingerprint = Invoke-Script -ScriptPath $fingerprintScript -Arguments @('-FingerprintKeyId', 'fixture-v1') -Stdin $query -Environment $hmacEnvironment
    Assert-Equal 0 $fingerprint.ExitCode 'fingerprint succeeds with process key'
    Assert-Equal 'hmac-sha256-v1' ([string]$fingerprint.Data.fingerprint_scheme) 'fingerprint scheme'
    Assert-True ([string]$fingerprint.Data.query_fingerprint -match '^[0-9a-f]{64}$') 'fingerprint shape'
    $expectedHmac = New-Object Security.Cryptography.HMACSHA256(,((New-Object Text.UTF8Encoding($false)).GetBytes($fixtureKey)))
    try { $expectedFingerprint = ([BitConverter]::ToString($expectedHmac.ComputeHash((New-Object Text.UTF8Encoding($false)).GetBytes($query)))).Replace('-', '').ToLowerInvariant() }
    finally { $expectedHmac.Dispose() }
    Assert-Equal $expectedFingerprint ([string]$fingerprint.Data.query_fingerprint) 'fingerprint excludes transport BOM bytes'
    Assert-True (-not $fingerprint.Stdout.Contains($query) -and -not $fingerprint.Stdout.Contains($fixtureKey)) 'fingerprint output omits query and key'
    $fingerprintAgain = Invoke-Script -ScriptPath $fingerprintScript -Arguments @('-FingerprintKeyId', 'fixture-v1') -Stdin $query -Environment $hmacEnvironment
    Assert-Equal $fingerprint.Stdout $fingerprintAgain.Stdout 'fingerprint is deterministic'

    $envelope = Invoke-FreshMcpEnvelope -McpRepositoryRoot $McpRoot -BrainRepositoryRoot $contract.Root -Query $query
    $transportPayload = ConvertFrom-StrictJsonText -Text ([string]@($envelope.content)[0].text) -Label 'fixture MCP envelope content'
    $actualDiagnostics = $transportPayload.data.retrieval_diagnostics
    $assetEvidence = @($actualDiagnostics.evidence | Where-Object { [string]$_.document_id -ceq 'brain:ASSETS.md' })
    Assert-Equal 1 $assetEvidence.Count 'actual MCP fixture includes ASSETS lineage'
    $expectedContentHash = [string]$assetEvidence[0].content_hash
    $boundInputJson = [string]([pscustomobject][ordered]@{ query = $query; envelope = $envelope } | ConvertTo-Json -Depth 24 -Compress)
    $receiptArgs = @(
        '-BrainRoot', $evidenceRoot,
        '-ContractRepositoryRoot', $contract.Root,
        '-McpRepositoryRoot', $McpRoot,
        '-ContractRef', $contract.Ref,
        '-ContractSchemaDigest', $contract.Digest,
        '-EventLogPath', $receiptLog,
        '-ReceiptId', 'receipt-fixture',
        '-FingerprintKeyId', 'fixture-v1',
        '-ResolverVersion', '1.0.0',
        '-SourceRevision', $contract.McpRef,
        '-RecordedAt', '2026-08-24T09:00:00+09:00'
    )
    $wrongDigestArgs = @($receiptArgs)
    $digestIndex = [Array]::IndexOf($wrongDigestArgs, '-ContractSchemaDigest') + 1
    $wrongDigestArgs[$digestIndex] = 'f' * 64
    $wrongDigest = Invoke-Script -ScriptPath $receiptScript -Arguments $wrongDigestArgs -Stdin $boundInputJson
    Assert-Equal 3 $wrongDigest.ExitCode 'contract digest drift fails'
    Assert-True (-not [IO.File]::Exists((Join-Path $evidenceRoot $receiptLog.Replace('/', '\')))) 'digest drift writes no log'

    $queryMismatchInput = [string]([pscustomobject][ordered]@{ query = 'different query'; envelope = $envelope } | ConvertTo-Json -Depth 24 -Compress)
    $queryMismatch = Invoke-Script -ScriptPath $receiptScript -Arguments $receiptArgs -Stdin $queryMismatchInput -Environment $hmacEnvironment
    Assert-Equal 3 $queryMismatch.ExitCode 'query fingerprint binding mismatch fails'
    Assert-True (-not [IO.File]::Exists((Join-Path $evidenceRoot $receiptLog.Replace('/', '\')))) 'query binding mismatch writes no log'

    $duplicateKeyInput = $boundInputJson -replace '^\{"query":', '{"query":"shadow duplicate","query":'
    $duplicateKey = Invoke-Script -ScriptPath $receiptScript -Arguments $receiptArgs -Stdin $duplicateKeyInput -Environment $hmacEnvironment
    Assert-Equal 3 $duplicateKey.ExitCode 'duplicate JSON input key fails closed'
    Assert-True (-not [IO.File]::Exists((Join-Path $evidenceRoot $receiptLog.Replace('/', '\')))) 'duplicate JSON key writes no log'

    $receipt = Invoke-Script -ScriptPath $receiptScript -Arguments $receiptArgs -Stdin $boundInputJson -Environment $hmacEnvironment
    Assert-Equal 0 $receipt.ExitCode ("receipt append succeeds; stderr=" + $receipt.Stderr)
    Assert-Equal 1 ([int]$receipt.Data.included) 'receipt includes lineage-complete evidence'
    $receiptPath = Join-Path $evidenceRoot $receiptLog.Replace('/', '\')
    $receiptBytes = [IO.File]::ReadAllBytes($receiptPath)
    $receiptText = [IO.File]::ReadAllText($receiptPath, [Text.Encoding]::UTF8)
    Assert-True (-not $receiptText.Contains($query) -and -not $receiptText.Contains($fixtureKey)) 'receipt stores no query or key'
    Assert-True ($receiptText.Contains('"document_id":"brain:ASSETS.md"') -and $receiptText.Contains('"content_hash":"' + $expectedContentHash + '"')) 'receipt stores exact document lineage'
    Assert-True ($receiptText.Contains('"receipt_attestation_scheme":"hmac-sha256-v1"')) 'receipt carries a full-payload attestation'

    $duplicate = Invoke-Script -ScriptPath $receiptScript -Arguments $receiptArgs -Stdin $boundInputJson -Environment $hmacEnvironment
    Assert-Equal 3 $duplicate.ExitCode 'duplicate receipt id fails'
    Assert-Equal ([Convert]::ToBase64String($receiptBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath))) 'duplicate failure preserves receipt bytes'

    $candidateArgs = @(
        '-BrainRoot', $evidenceRoot,
        '-ContractRepositoryRoot', $contract.Root,
        '-ContractRef', $contract.Ref,
        '-ContractSchemaDigest', $contract.Digest,
        '-ReceiptLogPath', $receiptLog,
        '-OutcomeLogPath', $outcomeLog,
        '-ReceiptId', 'receipt-fixture'
    )
    $candidateMissingKey = Invoke-Script -ScriptPath $candidateScript -Arguments $candidateArgs
    Assert-Equal 3 $candidateMissingKey.ExitCode 'candidate requires receipt attestation key'
    $tamperRoot = Join-Path $fixtureRoot 'tampered-evidence'
    $tamperEventsRoot = Join-Path $tamperRoot 'memory\retrieval-evidence\events'
    $null = New-Item -ItemType Directory -Path $tamperEventsRoot -Force
    $tamperedReceipt = $receiptText.Trim() | ConvertFrom-Json
    $tamperedReceipt.included[0].score = [double]$tamperedReceipt.included[0].score + 0.001
    Write-Utf8NoBom -Path (Join-Path $tamperRoot $receiptLog.Replace('/', '\')) -Text ([string]($tamperedReceipt | ConvertTo-Json -Depth 20 -Compress) + "`n")
    $tamperedCandidateArgs = @($candidateArgs)
    $tamperedCandidateArgs[[Array]::IndexOf($tamperedCandidateArgs, '-BrainRoot') + 1] = $tamperRoot
    $tamperedCandidate = Invoke-Script -ScriptPath $candidateScript -Arguments $tamperedCandidateArgs -Environment $hmacEnvironment
    Assert-Equal 3 $tamperedCandidate.ExitCode 'tampered receipt payload fails attestation verification'
    $withoutOutcome = Invoke-Script -ScriptPath $candidateScript -Arguments $candidateArgs -Environment $hmacEnvironment
    Assert-Equal 0 $withoutOutcome.ExitCode 'candidate without outcome is returned'
    Assert-Equal 'review' ([string]$withoutOutcome.Data.disposition) 'no outcome cannot infer success'
    Assert-True (@($withoutOutcome.Data.reason_codes) -contains 'no-outcome') 'no outcome reason code'
    Assert-Equal $false ([bool]$withoutOutcome.Data.stable_auto_promotion) 'candidate cannot auto-promote'
    $goldenProofRef = "golden-eval:asset-location-contract@git:$($contract.Ref)@sha256:$($contract.ProofHash)"

    $orphanArgs = @(
        '-BrainRoot', $evidenceRoot, '-ContractRepositoryRoot', $contract.Root, '-ContractRef', $contract.Ref, '-ContractSchemaDigest', $contract.Digest,
        '-ReceiptLogPath', $receiptLog, '-EventLogPath', $outcomeLog,
        '-OutcomeId', 'outcome-orphan', '-ReceiptId', 'receipt-missing', '-SignalKind', 'golden-eval', '-Verdict', 'helpful',
        '-EvidenceRefs', $goldenProofRef, '-ActorType', 'tool', '-RecordedAt', '2026-08-24T09:01:00+09:00'
    )
    $orphan = Invoke-Script -ScriptPath $outcomeScript -Arguments $orphanArgs
    Assert-Equal 3 $orphan.ExitCode 'orphan outcome fails'
    Assert-True (-not [IO.File]::Exists((Join-Path $evidenceRoot $outcomeLog.Replace('/', '\')))) 'orphan outcome writes no log'

    $badHumanArgs = @($orphanArgs)
    $badHumanArgs[[Array]::IndexOf($badHumanArgs, '-OutcomeId') + 1] = 'outcome-bad-human'
    $badHumanArgs[[Array]::IndexOf($badHumanArgs, '-ReceiptId') + 1] = 'receipt-fixture'
    $badHumanArgs[[Array]::IndexOf($badHumanArgs, '-SignalKind') + 1] = 'golden-eval'
    $badHumanArgs[[Array]::IndexOf($badHumanArgs, '-ActorType') + 1] = 'agent'
    $badHuman = Invoke-Script -ScriptPath $outcomeScript -Arguments $badHumanArgs -Environment $hmacEnvironment
    Assert-Equal 3 $badHuman.ExitCode 'agent cannot self-score a golden outcome'

    $outcomeArgs = @(
        '-BrainRoot', $evidenceRoot, '-ContractRepositoryRoot', $contract.Root, '-ContractRef', $contract.Ref, '-ContractSchemaDigest', $contract.Digest,
        '-ReceiptLogPath', $receiptLog, '-EventLogPath', $outcomeLog,
        '-OutcomeId', 'outcome-helpful', '-ReceiptId', 'receipt-fixture', '-SignalKind', 'golden-eval', '-Verdict', 'helpful',
        '-EvidenceRefs', $goldenProofRef, '-ActorType', 'tool', '-RecordedAt', '2026-08-24T09:02:00+09:00'
    )
    $outcome = Invoke-Script -ScriptPath $outcomeScript -Arguments $outcomeArgs -Environment $hmacEnvironment
    Assert-Equal 0 $outcome.ExitCode 'explicit helpful outcome append succeeds'
    $outcomePath = Join-Path $evidenceRoot $outcomeLog.Replace('/', '\')
    $outcomeBytes = [IO.File]::ReadAllBytes($outcomePath)
    $outcomeDuplicate = Invoke-Script -ScriptPath $outcomeScript -Arguments $outcomeArgs -Environment $hmacEnvironment
    Assert-Equal 3 $outcomeDuplicate.ExitCode 'duplicate outcome id fails'
    Assert-Equal ([Convert]::ToBase64String($outcomeBytes)) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($outcomePath))) 'duplicate failure preserves outcome bytes'

    $brokenSupersedesArgs = @($outcomeArgs)
    $brokenSupersedesArgs[[Array]::IndexOf($brokenSupersedesArgs, '-OutcomeId') + 1] = 'outcome-broken-supersedes'
    $brokenSupersedesArgs += @('-Supersedes', 'outcome-missing')
    $brokenSupersedes = Invoke-Script -ScriptPath $outcomeScript -Arguments $brokenSupersedesArgs -Environment $hmacEnvironment
    Assert-Equal 3 $brokenSupersedes.ExitCode 'broken outcome supersedes fails globally'

    $secretProofArgs = @($outcomeArgs)
    $secretProofArgs[[Array]::IndexOf($secretProofArgs, '-OutcomeId') + 1] = 'outcome-secret-proof'
    $secretProofId = 'sk-' + ('a' * 20)
    $secretProofArgs[[Array]::IndexOf($secretProofArgs, '-EvidenceRefs') + 1] = "golden-eval:$secretProofId@git:$($contract.Ref)@sha256:$($contract.ProofHash)"
    $secretProof = Invoke-Script -ScriptPath $outcomeScript -Arguments $secretProofArgs -Environment $hmacEnvironment
    Assert-Equal 3 $secretProof.ExitCode 'secret-like outcome proof reference fails'

    $secondReceiptArgs = @($receiptArgs)
    $secondReceiptArgs[[Array]::IndexOf($secondReceiptArgs, '-ReceiptId') + 1] = 'receipt-second'
    $secondReceipt = Invoke-Script -ScriptPath $receiptScript -Arguments $secondReceiptArgs -Stdin $boundInputJson -Environment $hmacEnvironment
    Assert-Equal 0 $secondReceipt.ExitCode 'second receipt append succeeds'
    $crossSupersedesArgs = @($outcomeArgs)
    $crossSupersedesArgs[[Array]::IndexOf($crossSupersedesArgs, '-OutcomeId') + 1] = 'outcome-cross-receipt'
    $crossSupersedesArgs[[Array]::IndexOf($crossSupersedesArgs, '-ReceiptId') + 1] = 'receipt-second'
    $crossSupersedesArgs += @('-Supersedes', 'outcome-helpful')
    $crossSupersedes = Invoke-Script -ScriptPath $outcomeScript -Arguments $crossSupersedesArgs -Environment $hmacEnvironment
    Assert-Equal 3 $crossSupersedes.ExitCode 'cross-receipt supersedes fails before append'

    $septemberOutcomeLog = 'memory/retrieval-evidence/events/outcomes-2026-09.jsonl'
    $partitionMismatchArgs = @($outcomeArgs)
    $partitionMismatchArgs[[Array]::IndexOf($partitionMismatchArgs, '-OutcomeId') + 1] = 'outcome-partition-mismatch'
    $partitionMismatchArgs[[Array]::IndexOf($partitionMismatchArgs, '-EventLogPath') + 1] = $septemberOutcomeLog
    $partitionMismatch = Invoke-Script -ScriptPath $outcomeScript -Arguments $partitionMismatchArgs -Environment $hmacEnvironment
    Assert-Equal 3 $partitionMismatch.ExitCode 'outcome month mismatch fails'

    $septemberOutcomeArgs = @($partitionMismatchArgs)
    $septemberOutcomeArgs[[Array]::IndexOf($septemberOutcomeArgs, '-OutcomeId') + 1] = 'outcome-helpful-september'
    $septemberOutcomeArgs[[Array]::IndexOf($septemberOutcomeArgs, '-RecordedAt') + 1] = '2026-09-01T09:02:00+09:00'
    $septemberOutcomeArgs += @('-Supersedes', 'outcome-helpful')
    $septemberOutcome = Invoke-Script -ScriptPath $outcomeScript -Arguments $septemberOutcomeArgs -Environment $hmacEnvironment
    Assert-Equal 0 $septemberOutcome.ExitCode 'same-receipt cross-month supersedes succeeds'

    $beforeReceipt = [Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath))
    $beforeOutcome = [Convert]::ToBase64String([IO.File]::ReadAllBytes($outcomePath))
    $candidateOne = Invoke-Script -ScriptPath $candidateScript -Arguments $candidateArgs -Environment $hmacEnvironment
    $candidateTwo = Invoke-Script -ScriptPath $candidateScript -Arguments $candidateArgs -Environment $hmacEnvironment
    Assert-Equal 0 $candidateOne.ExitCode 'candidate with outcome succeeds'
    Assert-Equal $candidateOne.Stdout $candidateTwo.Stdout 'candidate JSON is byte-stable'
    Assert-Equal 'preserve' ([string]$candidateOne.Data.disposition) 'explicit helpful outcome permits preserve candidate'
    Assert-Equal 'candidate' ([string]$candidateOne.Data.status) 'candidate status remains candidate'
    Assert-Equal 'outcome-helpful-september' ([string]@($candidateOne.Data.outcome_refs)[0]) 'candidate resolves active outcome across monthly logs'
    Assert-Equal $beforeReceipt ([Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath))) 'evaluator leaves receipt bytes unchanged'
    Assert-Equal $beforeOutcome ([Convert]::ToBase64String([IO.File]::ReadAllBytes($outcomePath))) 'evaluator leaves outcome bytes unchanged'

    $outside = Join-Path $fixtureRoot 'outside'
    $null = New-Item -ItemType Directory -Path (Join-Path $outside 'memory\retrieval-evidence\events') -Force
    $script:junctionPath = Join-Path $fixtureRoot 'junction-evidence'
    $null = New-Item -ItemType Junction -Path $script:junctionPath -Target $outside
    $junctionArgs = @($receiptArgs)
    $junctionArgs[[Array]::IndexOf($junctionArgs, '-BrainRoot') + 1] = $script:junctionPath
    $junction = Invoke-Script -ScriptPath $receiptScript -Arguments $junctionArgs -Stdin $boundInputJson -Environment $hmacEnvironment
    Assert-Equal 3 $junction.ExitCode 'reparse BrainRoot fails closed'
    Assert-True (-not [IO.File]::Exists((Join-Path $outside $receiptLog.Replace('/', '\')))) 'reparse failure leaves external target unchanged'
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
