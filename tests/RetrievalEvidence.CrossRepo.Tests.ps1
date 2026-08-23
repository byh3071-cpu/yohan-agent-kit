#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$BrainRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractSchemaDigest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$GoldenProofHash,
    [Parameter(Mandatory = $true)][string]$McpRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$McpRef
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$generator = Join-Path $PSScriptRoot 'generate_actual_retrieval_envelope.py'
$fingerprintScript = Join-Path $repoRoot 'scripts\New-RetrievalQueryFingerprint.ps1'
$receiptScript = Join-Path $repoRoot 'scripts\Record-RetrievalReceipt.ps1'
$outcomeScript = Join-Path $repoRoot 'scripts\Record-RetrievalOutcome.ps1'
$candidateScript = Join-Path $repoRoot 'scripts\Get-RetrievalLearningCandidate.ps1'
$fixtureRoot = Join-Path $PSScriptRoot ('.work\retrieval-cross-{0}' -f [Guid]::NewGuid().ToString('N'))
$powerShell = [string](Get-Command powershell.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source)
$python = [string](Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source)
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

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-ProcessWithInput {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [AllowEmptyString()][string]$Stdin = '',
        [hashtable]$Environment = @{}
    )

    $parts = @($Arguments | ForEach-Object { Quote-Argument ([string]$_) })
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $FileName
    $start.Arguments = [string]::Join(' ', $parts)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($entry in $Environment.GetEnumerator()) { $start.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $null = $process.Start()
    if ($Stdin.Length -gt 0) { $process.StandardInput.Write($Stdin) }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    return [pscustomobject]@{ ExitCode = $exitCode; Stdout = $stdout.Trim(); Stderr = $stderr.Trim() }
}

function Invoke-PowerShellScript {
    param([string]$ScriptPath, [string[]]$Arguments, [string]$Stdin = '', [hashtable]$Environment = @{})
    $allArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + @($Arguments)
    return Invoke-ProcessWithInput -FileName $powerShell -Arguments $allArguments -Stdin $Stdin -Environment $Environment
}

function Get-TrackedStateDigest([string]$RepositoryRoot) {
    $status = [string]::Join("`n", @(& git.exe -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot status --porcelain=v1 --untracked-files=all))
    $untrackedHashes = New-Object Collections.Generic.List[string]
    foreach ($relativePath in @(& git.exe -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot ls-files --others --exclude-standard | Sort-Object)) {
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$relativePath)))
        if ([IO.File]::Exists($fullPath)) {
            $fileSha = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($fileSha.ComputeHash([IO.File]::ReadAllBytes($fullPath)))).Replace('-', '').ToLowerInvariant() }
            finally { $fileSha.Dispose() }
            $untrackedHashes.Add(([string]$relativePath) + ':' + $hash)
        }
    }
    $unstaged = [string]::Join("`n", @(& git.exe -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot diff --binary --no-ext-diff))
    $staged = [string]::Join("`n", @(& git.exe -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot diff --cached --binary --no-ext-diff))
    $text = $status + "`n--untracked-hashes--`n" + ([string]::Join("`n", $untrackedHashes.ToArray())) + "`n--unstaged--`n" + $unstaged + "`n--staged--`n" + $staged
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Remove-FixtureSafely {
    if (-not [IO.Directory]::Exists($fixtureRoot)) { return }
    $workRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $target = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $target.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped tests/.work' }
    Remove-Item -LiteralPath $target -Recurse -Force
}

try {
    foreach ($root in @($BrainRoot, $McpRoot, $repoRoot)) { Assert-True ([IO.Directory]::Exists($root)) "repository root exists: $root" }
    Assert-Equal $BrainRef ([string](& git.exe -C $BrainRoot rev-parse HEAD).Trim()) 'BrainRef is the checked-out exact commit'
    Assert-Equal $McpRef ([string](& git.exe -C $McpRoot rev-parse HEAD).Trim()) 'McpRef is the checked-out exact commit'
    $beforeBrain = Get-TrackedStateDigest -RepositoryRoot $BrainRoot
    $beforeMcp = Get-TrackedStateDigest -RepositoryRoot $McpRoot
    $beforeAgentKit = Get-TrackedStateDigest -RepositoryRoot $repoRoot

    $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'evidence\memory\retrieval-evidence\events') -Force
    $evidenceRoot = Join-Path $fixtureRoot 'evidence'
    $query = 'asset location contract ASSETS'
    $generated = Invoke-ProcessWithInput -FileName $python -Arguments @('-E', '-P', '-B', $generator, '--mcp-root', $McpRoot, '--brain-root', $BrainRoot, '--query', $query)
    if ($generated.ExitCode -ne 0) { throw "Actual yohan-mcp envelope generation failed: $($generated.Stderr)" }
    Assert-Equal 0 $generated.ExitCode 'actual yohan-mcp envelope generation succeeds'
    try { $transportEnvelope = $generated.Stdout | ConvertFrom-Json }
    catch { throw "Actual MCP envelope is invalid JSON: $($generated.Stderr)" }
    $transportText = [string]@($transportEnvelope.content)[0].text
    $envelope = $transportText | ConvertFrom-Json
    $diagnostics = $envelope.data.retrieval_diagnostics
    Assert-Equal 'retrieval-diagnostics/v1' ([string]$diagnostics.schema) 'actual diagnostics schema'
    Assert-Equal $true ([bool]$diagnostics.volatile) 'actual diagnostics remain volatile'
    Assert-Equal $false ([bool]$diagnostics.persisted) 'actual diagnostics remain non-persisted'
    Assert-True ([string]$diagnostics.index.generation_id -match '^[0-9a-f]{64}$') 'actual index generation id'
    Assert-Equal '1.1.0' ([string]$diagnostics.index.corpus_contract_version) 'actual corpus contract version'
    Assert-Equal 'yohan-mcp' ([string]$diagnostics.runtime.repository) 'actual MCP runtime repository'
    Assert-True ([string]$diagnostics.runtime.implementation_digest -match '^[0-9a-f]{64}$') 'actual MCP runtime bundle digest'
    Assert-Equal 'sha256-utf8-v1' ([string]$diagnostics.query_binding.scheme) 'actual query binding scheme'
    $assetEvidence = @($diagnostics.evidence | Where-Object { [string]$_.locator -ceq 'ASSETS.md' })
    Assert-Equal 1 $assetEvidence.Count 'actual MCP returns ASSETS evidence exactly once'
    Assert-Equal 'brain:ASSETS.md' ([string]$assetEvidence[0].document_id) 'actual ASSETS document id'
    Assert-True ([string]$assetEvidence[0].content_hash -match '^[0-9a-f]{64}$') 'actual ASSETS content hash'

    $fixtureKey = 'cross-fixture-hmac-material-32-bytes'
    $hmacEnvironment = @{ YOHAN_RETRIEVAL_HMAC_KEY = $fixtureKey }
    $fingerprint = Invoke-PowerShellScript -ScriptPath $fingerprintScript -Arguments @('-FingerprintKeyId', 'cross-fixture-v1') -Stdin $query -Environment $hmacEnvironment
    Assert-Equal 0 $fingerprint.ExitCode 'cross fixture fingerprint succeeds'
    $receiptLog = 'memory/retrieval-evidence/events/receipts-2026-08.jsonl'
    $outcomeLog = 'memory/retrieval-evidence/events/outcomes-2026-08.jsonl'
    $boundInput = [string]([pscustomobject][ordered]@{ query = $query; envelope = $transportEnvelope } | ConvertTo-Json -Depth 30 -Compress)
    $receipt = Invoke-PowerShellScript -ScriptPath $receiptScript -Arguments @(
        '-BrainRoot', $evidenceRoot, '-ContractRepositoryRoot', $BrainRoot, '-McpRepositoryRoot', $McpRoot, '-ContractRef', $BrainRef, '-ContractSchemaDigest', $ContractSchemaDigest,
        '-EventLogPath', $receiptLog, '-ReceiptId', 'receipt-actual-mcp',
        '-FingerprintKeyId', 'cross-fixture-v1', '-ResolverVersion', '1.0.0', '-SourceRevision', $McpRef, '-RecordedAt', '2026-08-24T10:00:00+09:00'
    ) -Stdin $boundInput -Environment $hmacEnvironment
    if ($receipt.ExitCode -ne 0) { throw "Actual MCP receipt append failed: $($receipt.Stderr) $($receipt.Stdout)" }
    Assert-Equal 0 $receipt.ExitCode 'actual MCP receipt append succeeds'
    $receiptData = $receipt.Stdout | ConvertFrom-Json
    Assert-True ([int]$receiptData.included -gt 0) 'actual MCP receipt has included evidence'
    $receiptPath = Join-Path $evidenceRoot $receiptLog.Replace('/', '\')
    $receiptText = [IO.File]::ReadAllText($receiptPath, [Text.Encoding]::UTF8)
    Assert-True (-not $receiptText.Contains($query) -and -not $receiptText.Contains($fixtureKey)) 'actual receipt stores no query or HMAC key'

    $goldenProofRef = "golden-eval:asset-location-contract@git:$BrainRef@sha256:$GoldenProofHash"
    $outcome = Invoke-PowerShellScript -ScriptPath $outcomeScript -Arguments @(
        '-BrainRoot', $evidenceRoot, '-ContractRepositoryRoot', $BrainRoot, '-ContractRef', $BrainRef, '-ContractSchemaDigest', $ContractSchemaDigest,
        '-ReceiptLogPath', $receiptLog, '-EventLogPath', $outcomeLog, '-OutcomeId', 'outcome-actual-golden', '-ReceiptId', 'receipt-actual-mcp',
        '-SignalKind', 'golden-eval', '-Verdict', 'helpful', '-EvidenceRefs', $goldenProofRef, '-ActorType', 'tool', '-RecordedAt', '2026-08-24T10:01:00+09:00'
    ) -Environment $hmacEnvironment
    if ($outcome.ExitCode -ne 0) { throw "Actual golden outcome append failed: $($outcome.Stderr) $($outcome.Stdout)" }
    Assert-Equal 0 $outcome.ExitCode 'actual golden outcome append succeeds'

    $candidateArgs = @(
        '-BrainRoot', $evidenceRoot, '-ContractRepositoryRoot', $BrainRoot, '-ContractRef', $BrainRef, '-ContractSchemaDigest', $ContractSchemaDigest,
        '-ReceiptLogPath', $receiptLog, '-OutcomeLogPath', $outcomeLog, '-ReceiptId', 'receipt-actual-mcp'
    )
    $candidateOne = Invoke-PowerShellScript -ScriptPath $candidateScript -Arguments $candidateArgs -Environment $hmacEnvironment
    $candidateTwo = Invoke-PowerShellScript -ScriptPath $candidateScript -Arguments $candidateArgs -Environment $hmacEnvironment
    Assert-Equal 0 $candidateOne.ExitCode 'actual learning candidate succeeds'
    Assert-Equal $candidateOne.Stdout $candidateTwo.Stdout 'actual learning candidate is byte-stable'
    $candidate = $candidateOne.Stdout | ConvertFrom-Json
    Assert-Equal 'preserve' ([string]$candidate.disposition) 'verified golden outcome yields preserve candidate'
    Assert-Equal 'candidate' ([string]$candidate.status) 'actual result remains candidate-only'
    Assert-Equal $false ([bool]$candidate.stable_auto_promotion) 'actual result cannot auto-promote'

    Assert-Equal $beforeBrain (Get-TrackedStateDigest -RepositoryRoot $BrainRoot) 'actual retrieval leaves Brain tracked state unchanged'
    Assert-Equal $beforeMcp (Get-TrackedStateDigest -RepositoryRoot $McpRoot) 'actual retrieval leaves MCP tracked state unchanged'
    Assert-Equal $beforeAgentKit (Get-TrackedStateDigest -RepositoryRoot $repoRoot) 'cross fixture leaves Agent Kit tracked state unchanged'
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
