#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$hookPath = Join-Path $repoRoot 'plugins\yohan-core\hooks\context-hint.ps1'
$testRoot = Join-Path $scriptRoot '.work\context-hint'
$policyRoot = Join-Path $testRoot 'policy'
$fakeHome = Join-Path $testRoot 'home'
$fakeBrain = Join-Path $testRoot 'feature-brain'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source

function Assert-True {
    param([bool]$Condition, [string]$Message)

    $script:Assertions++
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function ConvertTo-NormalizedText {
    param([string]$Text)

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n", [StringComparison]::Ordinal)) { $normalized += "`n" }
    return $normalized
}

function Get-TextSha256 {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)

    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function New-TestPolicy {
    param([string]$SourceRef = 'origin/master')

    if ([IO.Directory]::Exists($policyRoot)) { Remove-Item -LiteralPath $policyRoot -Recurse -Force }
    [IO.Directory]::CreateDirectory($policyRoot) | Out-Null
    $unicodeMarker = [string]([char]0xB77C) + [char]0xC6B0 + [char]0xD305
    $card = ConvertTo-NormalizedText (@'
# Stable test routing policy

execution_provider: orca-ready | native-approved | plan-only | blocked
automatic_fallback=false
TEST_STABLE_CARD
'@ + $unicodeMarker)
    $cardHash = Get-TextSha256 $card
    $manifest = [ordered]@{
        schema = 'orca-routing-policy-manifest'
        schema_version = 1
        policy_version = '0.5.99-test'
        source_roster_version = '0.5.99-test'
        status = 'active'
        hash_contract = 'sha256-lf-utf8'
        source_files = @()
        card = [ordered]@{ path = 'card.md'; sha256 = $cardHash }
    }
    $manifestText = ConvertTo-NormalizedText ($manifest | ConvertTo-Json -Depth 6)
    $deployment = [ordered]@{
        schema = 'orca-routing-policy-deployment'
        schema_version = 1
        policy_version = '0.5.99-test'
        manifest_sha256 = Get-TextSha256 $manifestText
        source_commit = ('a' * 40)
        source_ref = $SourceRef
        fetch_performed = $true
        deployed_at_utc = '2026-08-05T00:00:00.0000000Z'
    }
    $deploymentText = ConvertTo-NormalizedText ($deployment | ConvertTo-Json -Depth 4)
    Write-Utf8NoBom (Join-Path $policyRoot 'card.md') $card
    Write-Utf8NoBom (Join-Path $policyRoot 'manifest.json') $manifestText
    Write-Utf8NoBom (Join-Path $policyRoot 'deployment.json') $deploymentText
}

function Invoke-ContextHint {
    param(
        [switch]$RouteOnly,
        [AllowEmptyString()][string]$Payload = '{"session_id":"route-canary"}'
    )

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $hookPath)
    if ($RouteOnly) { $psArgs += '-RouteOnly' }
    $raw = $Payload | & $powershellExe @psArgs
    if ($LASTEXITCODE -ne 0) { throw "context-hint exited with $LASTEXITCODE" }
    return ($raw | ConvertFrom-Json).hookSpecificOutput.additionalContext
}

$oldPolicyRoot = $env:YOHAN_ORCA_ROUTING_POLICY_ROOT
$oldBrainRoot = $env:YOHAN_BRAIN_ROOT
$oldUserProfile = $env:USERPROFILE
$oldCanary = $env:YOHAN_ROUTE_ONLY_CANARY

try {
    if ([IO.Directory]::Exists($testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    [IO.Directory]::CreateDirectory($fakeHome) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $fakeBrain 'memory\core\templates')) | Out-Null
    Write-Utf8NoBom (Join-Path $fakeBrain 'memory\core\templates\roster-routing-card.md') "UNTRUSTED_FEATURE_CARD`n"
    $env:USERPROFILE = $fakeHome
    $env:YOHAN_BRAIN_ROOT = $fakeBrain
    $env:YOHAN_ORCA_ROUTING_POLICY_ROOT = $policyRoot
    $env:YOHAN_ROUTE_ONLY_CANARY = $null

    New-TestPolicy
    $stable = Invoke-ContextHint -RouteOnly
    $unicodeMarker = [string]([char]0xB77C) + [char]0xC6B0 + [char]0xD305
    Assert-True ($stable.Contains('policy_status=stable policy_version=0.5.99-test')) 'verified policy version is injected'
    Assert-True ($stable.Contains('TEST_STABLE_CARD')) 'verified policy card is injected'
    Assert-True ($stable.Contains($unicodeMarker)) 'PAT-002 escaped JSON round-trips Unicode policy text'
    Assert-True (-not $stable.Contains('UNTRUSTED_FEATURE_CARD')) 'feature checkout card is never injected'
    Assert-True (-not [IO.Directory]::Exists((Join-Path $fakeHome '.claude'))) 'route-only switch performs no cache write'

    Write-Utf8NoBom (Join-Path $policyRoot 'card.md') "tampered orca-ready native-approved plan-only blocked automatic_fallback=false`n"
    $tampered = Invoke-ContextHint -RouteOnly
    Assert-True ($tampered.Contains('policy_status=safe-fallback')) 'tampered card is rejected'
    Assert-True ($tampered.Contains('policy_reason=integrity-failed')) 'tampered card reports a bounded integrity reason'
    Assert-True (-not $tampered.Contains('tampered')) 'tampered card content is not injected'
    Assert-True (-not $tampered.Contains('UNTRUSTED_FEATURE_CARD')) 'legacy feature fallback remains disabled after rejection'

    New-TestPolicy -SourceRef 'feature/unreviewed'
    $untrustedRef = Invoke-ContextHint -RouteOnly
    Assert-True ($untrustedRef.Contains('policy_status=safe-fallback')) 'non-stable source ref is rejected'
    Assert-True ($untrustedRef.Contains('policy_reason=untrusted-provenance')) 'non-stable source reports a bounded provenance reason'
    Assert-True (-not $untrustedRef.Contains('TEST_STABLE_CARD')) 'card from non-stable source ref is not injected'

    $env:YOHAN_ORCA_ROUTING_POLICY_ROOT = Join-Path $testRoot 'missing-policy'
    $missing = Invoke-ContextHint -RouteOnly
    Assert-True ($missing.Contains('policy_status=safe-fallback')) 'missing stable policy uses bounded safe fallback'
    Assert-True ($missing.Contains('policy_reason=unavailable')) 'missing stable policy reports a bounded availability reason'
    Assert-True (-not $missing.Contains($testRoot)) 'safe fallback does not expose the local policy path'
    Assert-True ($missing.Contains('automatic_fallback=false')) 'safe fallback preserves no-fallback contract'

    New-TestPolicy
    $env:YOHAN_ORCA_ROUTING_POLICY_ROOT = $policyRoot
    $noStdin = Invoke-ContextHint -RouteOnly -Payload ''
    Assert-True ($noStdin.Contains('policy_status=stable')) 'missing stdin does not change route-only policy resolution'
    $brokenStdin = Invoke-ContextHint -RouteOnly -Payload '{broken-json'
    Assert-True ($brokenStdin.Contains('policy_status=stable')) 'broken stdin does not change route-only policy resolution'

    $manifestPath = Join-Path $policyRoot 'manifest.json'
    $unsupportedManifest = ([IO.File]::ReadAllText($manifestPath)).Replace('0.5.99-test', '0.6.0')
    Write-Utf8NoBom $manifestPath $unsupportedManifest
    $unsupported = Invoke-ContextHint -RouteOnly
    Assert-True ($unsupported.Contains('policy_status=safe-fallback')) 'unsupported policy version is rejected'
    Assert-True ($unsupported.Contains('policy_reason=unsupported-version')) 'unsupported policy reports a bounded version reason'

    New-TestPolicy
    $env:YOHAN_ORCA_ROUTING_POLICY_ROOT = $policyRoot
    $env:YOHAN_ROUTE_ONLY_CANARY = '1'
    $canary = Invoke-ContextHint
    Assert-True ($canary.Contains('policy_status=stable')) 'environment route-only canary reads the stable policy'
    Assert-True (-not [IO.Directory]::Exists((Join-Path $fakeHome '.claude'))) 'environment route-only canary performs no cache write'

    $env:YOHAN_ROUTE_ONLY_CANARY = $null
    $normal = Invoke-ContextHint
    $baseline = Join-Path $fakeHome '.claude\.cache\routing-route-canary.start'
    Assert-True ($normal.Contains('policy_status=stable')) 'normal hook reads the stable policy'
    Assert-True ([IO.File]::Exists($baseline)) 'normal hook preserves the routing baseline write'

    Write-Output "PASS: ContextHint.Tests.ps1 ($script:Assertions assertions)"
}
finally {
    $env:YOHAN_ORCA_ROUTING_POLICY_ROOT = $oldPolicyRoot
    $env:YOHAN_BRAIN_ROOT = $oldBrainRoot
    $env:USERPROFILE = $oldUserProfile
    $env:YOHAN_ROUTE_ONLY_CANARY = $oldCanary
    if ([IO.Directory]::Exists($testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
