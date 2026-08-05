#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$RouteOnly
)

# SessionStart hook. The executable source stays ASCII so Windows PowerShell 5.1
# parses it consistently regardless of the host's legacy code page.
$ErrorActionPreference = 'Continue'
$script:SupportedPolicyVersionPattern = '^0\.5\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$'

function Get-RoutingPolicyFailureCode {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    switch -Regex ([string]$Exception.Message) {
        '^Stable routing policy is unavailable$|^Required policy file is missing$' { return 'unavailable' }
        '^Routing policy version is unsupported or inconsistent$' { return 'unsupported-version' }
        '^Routing policy deployment version does not match the manifest$' { return 'version-mismatch' }
        '^Routing policy deployment provenance is not trusted$' { return 'untrusted-provenance' }
        'fingerprint' { return 'integrity-failed' }
        'schema' { return 'invalid-schema' }
        'inactive|hash contract' { return 'inactive-policy' }
        'card path|missing required contract token' { return 'invalid-card' }
        default { return 'invalid-policy' }
    }
}

function ConvertTo-NormalizedText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n", [StringComparison]::Ordinal)) {
        $normalized += "`n"
    }
    return $normalized
}

function Get-NormalizedFileText {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [IO.File]::Exists($Path)) { throw "Required policy file is missing" }
    return (ConvertTo-NormalizedText -Text ([IO.File]::ReadAllText($Path)))
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $encoding = New-Object Text.UTF8Encoding($false)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($encoding.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-PolicyRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:YOHAN_ORCA_ROUTING_POLICY_ROOT)) {
        return [IO.Path]::GetFullPath($env:YOHAN_ORCA_ROUTING_POLICY_ROOT)
    }

    $devRoot = $env:YOHAN_PUBLIC_DEV_ROOT
    if ([string]::IsNullOrWhiteSpace($devRoot) -and -not [string]::IsNullOrWhiteSpace($env:PUBLIC)) {
        $devRoot = Join-Path $env:PUBLIC 'dev'
    }
    if ([string]::IsNullOrWhiteSpace($devRoot)) { return $null }
    return (Join-Path ([IO.Path]::GetFullPath($devRoot)) '.agents\runtime\orca-routing-policy')
}

function Get-VerifiedRoutingPolicy {
    param([string]$PolicyRoot)

    if ([string]::IsNullOrWhiteSpace($PolicyRoot) -or -not [IO.Directory]::Exists($PolicyRoot)) {
        throw 'Stable routing policy is unavailable'
    }

    $cardText = Get-NormalizedFileText -Path (Join-Path $PolicyRoot 'card.md')
    $manifestText = Get-NormalizedFileText -Path (Join-Path $PolicyRoot 'manifest.json')
    $deploymentText = Get-NormalizedFileText -Path (Join-Path $PolicyRoot 'deployment.json')
    $manifest = $manifestText | ConvertFrom-Json
    $deployment = $deploymentText | ConvertFrom-Json

    if ([string]$manifest.schema -cne 'orca-routing-policy-manifest' -or [int]$manifest.schema_version -ne 1) {
        throw 'Routing policy manifest schema is invalid'
    }
    if ([string]$manifest.status -cne 'active' -or [string]$manifest.hash_contract -cne 'sha256-lf-utf8') {
        throw 'Routing policy manifest is inactive or uses an unsupported hash contract'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.policy_version)) {
        throw 'Routing policy version is missing'
    }
    if ([string]$manifest.policy_version -notmatch $script:SupportedPolicyVersionPattern -or
        [string]$manifest.source_roster_version -cne [string]$manifest.policy_version) {
        throw 'Routing policy version is unsupported or inconsistent'
    }
    if ([string]$deployment.schema -cne 'orca-routing-policy-deployment' -or [int]$deployment.schema_version -ne 1) {
        throw 'Routing policy deployment schema is invalid'
    }
    if ([string]$deployment.policy_version -cne [string]$manifest.policy_version) {
        throw 'Routing policy deployment version does not match the manifest'
    }
    if ([string]$deployment.source_ref -cne 'origin/master' -or [string]$deployment.source_commit -notmatch '^[a-fA-F0-9]{40}$') {
        throw 'Routing policy deployment provenance is not trusted'
    }
    if ($deployment.fetch_performed -isnot [bool] -or -not [bool]$deployment.fetch_performed) {
        throw 'Routing policy deployment does not prove a source fetch'
    }

    $manifestHash = Get-TextSha256 -Text $manifestText
    $cardHash = Get-TextSha256 -Text $cardText
    if (-not [string]::Equals([string]$deployment.manifest_sha256, $manifestHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Routing policy manifest fingerprint does not match deployment provenance'
    }
    if (-not [string]::Equals([string]$manifest.card.sha256, $cardHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Routing policy card fingerprint does not match the manifest'
    }
    if ([string]$manifest.card.path -cne 'card.md') {
        throw 'Routing policy card path is invalid'
    }

    foreach ($token in @('orca-ready', 'native-approved', 'plan-only', 'blocked', 'automatic_fallback=false')) {
        if (-not $cardText.Contains($token)) {
            throw "Routing policy card is missing required contract token: $token"
        }
    }

    return [pscustomobject][ordered]@{
        version = [string]$manifest.policy_version
        card = $cardText.TrimEnd("`r", "`n")
    }
}

try { $evt = ([Console]::In.ReadToEnd() | ConvertFrom-Json) } catch { $evt = $null }
$cwd = (Get-Location).Path
$repo = Split-Path $cwd -Leaf
$branch = (git rev-parse --abbrev-ref HEAD 2>$null)
$lines = @()
$lines += "repository=$repo branch=$branch"
if (Test-Path -LiteralPath (Join-Path $cwd 'CLAUDE.md')) { $lines += 'project_claude_md=present' }
if (Test-Path -LiteralPath (Join-Path $cwd '.claude\rules')) { $lines += 'project_claude_rules=present' }
$ctx = '[yohan-core] ' + ($lines -join ' | ')

try {
    $policy = Get-VerifiedRoutingPolicy -PolicyRoot (Get-PolicyRoot)
    $ctx += "`n`n[yohan-core routing-policy] policy_status=stable policy_version=$($policy.version)`n$($policy.card)"
}
catch {
    # Deliberately do not read a feature checkout or an unverified routing card.
    $policyReason = Get-RoutingPolicyFailureCode -Exception $_.Exception
    $ctx += "`n`n[yohan-core routing-policy] policy_status=safe-fallback policy_reason=$policyReason`nClassify every task as S, M, or L and state the route. L is a task class, not proof that Orca is ready. Use only an explicitly approved execution provider: orca-ready, native-approved, plan-only, or blocked. Preserve ADR, Plan, global-write, deploy, and merge gates. automatic_fallback=false"
}

$out = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx } } | ConvertTo-Json -Depth 5 -Compress
$out = [regex]::Replace($out, '[^\x00-\x7F]', { param($match) '\u{0:x4}' -f [int][char]($match.Value[0]) })
Write-Output $out

$routeOnlyRequested = $RouteOnly -or [string]::Equals($env:YOHAN_ROUTE_ONLY_CANARY, '1', [StringComparison]::Ordinal)
if (-not $routeOnlyRequested) {
    try {
        if ($evt -and $evt.session_id) {
            $cacheDir = Join-Path $env:USERPROFILE '.claude\.cache'
            if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            $sha = (git -C $cwd rev-parse HEAD 2>$null)
            if ($sha) { Set-Content -LiteralPath (Join-Path $cacheDir "routing-$($evt.session_id).start") -Value "$sha".Trim() -Encoding ASCII }
        }
    }
    catch {}
}
exit 0
