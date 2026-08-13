#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$HomeRoot = $env:USERPROFILE,
    [ValidateSet('Json', 'PrettyJson')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($HomeRoot) -or -not (Test-Path -LiteralPath $HomeRoot -PathType Container)) {
    throw 'HomeRoot must be an existing directory'
}
$resolvedHome = (Resolve-Path -LiteralPath $HomeRoot).Path.TrimEnd('\')

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function ConvertTo-HomeUri {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Equals($resolvedHome, [StringComparison]::OrdinalIgnoreCase)) { return 'home://' }
    if ($full.StartsWith($resolvedHome + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return 'home://' + $full.Substring($resolvedHome.Length + 1).Replace('\', '/')
    }
    return 'external://' + [IO.Path]::GetFileName($full.TrimEnd('\'))
}

function Get-SafeTarget {
    param([Parameter(Mandatory = $true)]$Item)
    $targets = @($Item.Target | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($targets.Count -eq 0) { return $null }
    $raw = [string]$targets[0]
    $absolute = if ([IO.Path]::IsPathRooted($raw)) { $raw } else { Join-Path $Item.Parent.FullName $raw }
    return ConvertTo-HomeUri -Path $absolute
}

function Get-ContentDigest {
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)][string]$Kind)
    try {
        $candidate = if ($Item.PSIsContainer -and $Kind -eq 'skill') { Join-Path $Item.FullName 'SKILL.md' } elseif (-not $Item.PSIsContainer) { $Item.FullName } else { $null }
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    catch { return $null }
    return $null
}

$rootSpecs = @(
    @{ Relative = '.agents\skills'; Vendor = 'agent-plugins'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.claude\skills'; Vendor = 'claude-code'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.cursor\skills'; Vendor = 'cursor'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.codex\skills'; Vendor = 'codex'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.gemini\config\skills'; Vendor = 'antigravity'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.gemini\skills'; Vendor = 'antigravity'; Kind = 'skill'; Mode = 'Directory' },
    @{ Relative = '.claude\agents'; Vendor = 'claude-code'; Kind = 'agent'; Mode = 'File' },
    @{ Relative = '.cursor\agents'; Vendor = 'cursor'; Kind = 'agent'; Mode = 'File' },
    @{ Relative = '.codex\agents'; Vendor = 'codex'; Kind = 'agent'; Mode = 'File' },
    @{ Relative = '.gemini\agents'; Vendor = 'antigravity'; Kind = 'agent'; Mode = 'File' },
    @{ Relative = '.claude\commands'; Vendor = 'claude-code'; Kind = 'command'; Mode = 'File' },
    @{ Relative = '.cursor\commands'; Vendor = 'cursor'; Kind = 'command'; Mode = 'File' },
    @{ Relative = '.claude\hooks'; Vendor = 'claude-code'; Kind = 'hook'; Mode = 'File' },
    @{ Relative = '.codex\hooks'; Vendor = 'codex'; Kind = 'hook'; Mode = 'File' },
    @{ Relative = '.cursor\hooks'; Vendor = 'cursor'; Kind = 'hook'; Mode = 'File' },
    @{ Relative = '.gemini\hooks'; Vendor = 'antigravity'; Kind = 'hook'; Mode = 'File' },
    @{ Relative = '.claude\plugins\cache'; Vendor = 'claude-code'; Kind = 'plugin-cache'; Mode = 'Directory' },
    @{ Relative = '.codex\plugins\cache'; Vendor = 'codex'; Kind = 'plugin-cache'; Mode = 'Directory' },
    @{ Relative = '.cursor\plugins\cache'; Vendor = 'cursor'; Kind = 'plugin-cache'; Mode = 'Directory' }
)

$observations = @()
$scannedRoots = @()
foreach ($spec in $rootSpecs) {
    $root = Join-Path $resolvedHome $spec.Relative
    $exists = Test-Path -LiteralPath $root -PathType Container
    $scannedRoots += [pscustomobject]@{ path = 'home://' + $spec.Relative.Replace('\', '/'); exists = [bool]$exists; vendor = $spec.Vendor; kind = $spec.Kind }
    if (-not $exists) { continue }
    $items = if ($spec.Mode -eq 'Directory') { @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop) } else { @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction Stop) }
    foreach ($item in $items) {
        $target = Get-SafeTarget -Item $item
        $targetExists = if ($null -eq $target) { $true } elseif ($target.StartsWith('home://')) {
            $relativeTarget = $target.Substring('home://'.Length).Replace('/', '\')
            Test-Path -LiteralPath (Join-Path $resolvedHome $relativeTarget)
        } else { $true }
        $portability = 'UNKNOWN'
        $lifecycle = 'candidate'
        if ($spec.Kind -eq 'plugin-cache') { $portability = 'LOCAL_ONLY'; $lifecycle = 'released' }
        elseif ($item.Name -eq 'yohan-instagram-cardnews') { $portability = 'PROJECT_SPECIFIC' }
        elseif ($item.Name -in @('competitive-brief', 'interview-me') -and -not $targetExists) { $portability = 'LEGACY'; $lifecycle = 'deprecated' }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) { $portability = if ($targetExists) { 'DUPLICATE' } else { 'LEGACY' }; if (-not $targetExists) { $lifecycle = 'deprecated' } }
        $observations += [pscustomobject]@{
            id = ($spec.Vendor + '-' + $spec.Kind + '-' + [IO.Path]::GetFileNameWithoutExtension($item.Name)).ToLowerInvariant()
            kind = $spec.Kind
            name = $item.Name
            sourcePath = ConvertTo-HomeUri -Path $item.FullName
            portability = $portability
            vendor = $spec.Vendor
            lifecycle = $lifecycle
            linkType = if ($null -eq $item.LinkType) { $null } else { [string]$item.LinkType }
            target = $target
            targetExists = [bool]$targetExists
            contentDigest = Get-ContentDigest -Item $item -Kind $spec.Kind
        }
    }
}

$result = [ordered]@{
    schemaVersion = 1
    readOnly = $true
    homeFingerprint = (Get-Sha256Text -Text $resolvedHome).Substring(0, 12)
    scannedRoots = @($scannedRoots)
    observations = @($observations | Sort-Object sourcePath)
    secretBoundaries = @(
        'home://.claude.json', 'home://.claude/settings.json', 'home://.codex/config.toml',
        'home://.cursor/mcp.json', 'home://.gemini/settings.json'
    )
}

$depth = 8
if ($OutputFormat -eq 'PrettyJson') { $result | ConvertTo-Json -Depth $depth }
else { $result | ConvertTo-Json -Depth $depth -Compress }

