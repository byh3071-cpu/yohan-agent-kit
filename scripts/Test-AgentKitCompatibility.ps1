#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Probe', 'Finalize', 'Verify', 'Compare')]
    [string]$Mode = 'Probe',

    [string]$Release,

    [string]$ReleaseRoot,

    [string]$HomeRoot,

    [string]$RepositoryRoot,

    [string]$DraftEvidencePath,

    [string]$SessionResultsPath,

    [string]$TransactionResultsPath,

    [string]$EvidencePath,

    [string]$OtherEvidencePath,

    [string]$MachineLabel,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [switch]$ApproveEvidenceWrite,

    [switch]$AllowDirtyArtifact,

    [switch]$AllowSyntheticEvidence
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) { $full = $full.TrimEnd('\', '/') }
    return $full
}

function Test-PathWithin {
    param([string]$Root, [string]$Candidate)
    $base = Get-NormalizedFullPath -Path $Root
    $path = Get-NormalizedFullPath -Path $Candidate
    return [string]::Equals($base, $path, [StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseAncestors {
    param([string]$Root, [string]$Candidate, [switch]$IncludeLeaf)
    if (-not (Test-PathWithin -Root $Root -Candidate $Candidate)) { throw "Evidence path escapes HomeRoot: $Candidate" }
    $base = Get-NormalizedFullPath -Path $Root
    $full = Get-NormalizedFullPath -Path $Candidate
    $segments = @($full.Substring($base.Length).TrimStart('\', '/') -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $limit = if ($IncludeLeaf) { $segments.Count } else { [Math]::Max(0, $segments.Count - 1) }
    $current = $base
    for ($index = 0; $index -lt $limit; $index++) {
        if (-not [IO.Directory]::Exists($current)) { break }
        $entries = @(Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $segments[$index] })
        if ($entries.Count -eq 0) { break }
        if ($entries.Count -gt 1) { throw "Case-colliding evidence path entries exist under: $current" }
        $entry = $entries[0]
        $linkType = $entry.PSObject.Properties['LinkType']
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value))) { throw "Evidence path contains a linked entry: $($entry.FullName)" }
        if (-not $entry.PSIsContainer -and $index -lt ($limit - 1)) { throw "Evidence ancestor is not a directory: $($entry.FullName)" }
        $current = $entry.FullName
    }
}

function Get-Sha256Bytes {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Sha256Text {
    param([string]$Text)
    return Get-Sha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-HomeRootDigest {
    param([Parameter(Mandatory = $true)][string]$Path)
    $canonical = Get-NormalizedFullPath -Path $Path
    $current = $canonical
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if ([IO.File]::Exists($current)) { throw "HomeRoot ancestor is not a directory: $current" }
        if ([IO.Directory]::Exists($current)) {
            $entry = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            $linkType = $entry.PSObject.Properties['LinkType']
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value))) {
                throw "HomeRoot contains a linked ancestor: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $current, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $parent
    }
    return Get-Sha256Text -Text "agent-kit-home-root-v1|$($canonical.ToLowerInvariant())"
}

function Get-ReleaseManifestDigest {
    param($Manifest)
    $lines = @(
        "schema=$([int]$Manifest.schemaVersion)", "release=$([string]$Manifest.releaseId)", "kit=$([string]$Manifest.kitVersion)",
        "commit=$([string]$Manifest.gitCommit)", "dirty=$(([bool]$Manifest.dirtyBuild).ToString().ToLowerInvariant())",
        "catalog=$([string]$Manifest.catalogDigest)", "assetCatalog=$([string]$Manifest.assetCatalogDigest)"
    )
    foreach ($name in @($Manifest.packages | Sort-Object)) { $lines += "package=$([string]$name)" }
    foreach ($property in @($Manifest.compatibility.PSObject.Properties | Sort-Object Name)) {
        $item = $property.Value
        $lines += "compat|$($property.Name)|$([string]$item.testedVersion)|$([string]$item.manifest)|$([string]$item.discoveryPath)|$([string]::Join(',', @($item.discoveryPaths)))|$([string]::Join(',', @($item.components)))"
    }
    foreach ($file in @($Manifest.files | Sort-Object path)) { $lines += "file|$([string]$file.path)|$([int64]$file.bytes)|$([string]$file.sha256)" }
    $lines += "rollback|$([string]$Manifest.rollback.command)|$([string]$Manifest.rollback.backupRoot)"
    return Get-Sha256Text -Text ([string]::Join("`n", $lines))
}

function ConvertTo-AsciiJson {
    param($Value)
    $json = [string]($Value | ConvertTo-Json -Depth 32)
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($Match) return ('\u{0:x4}' -f [int][char]$Match.Value) })
}

function Write-JsonFile {
    param([string]$Path, $Value, [string]$AllowedRoot)
    if (-not (Test-PathWithin -Root $AllowedRoot -Candidate $Path)) { throw "Evidence path escapes HomeRoot: $Path" }
    Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $Path -IncludeLeaf
    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $Path -IncludeLeaf
    if ([IO.File]::Exists($Path)) { throw "Evidence is immutable and already exists: $Path" }
    [IO.File]::WriteAllText($Path, (ConvertTo-AsciiJson -Value $Value) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Read-JsonFile {
    param([string]$Path, [string]$Label)
    if (-not [IO.File]::Exists($Path)) { throw "$Label is missing: $Path" }
    try { return [string]([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

function Get-CliEvidence {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { return [pscustomobject][ordered]@{ state = 'NOT_INSTALLED'; version = $null; path = $null; commandType = $null; sha256 = $null } }
    try {
        $commandPath = if ($command.Path) { [string]$command.Path } else { [string]$command.Source }
        if ([string]::IsNullOrWhiteSpace($commandPath)) { throw "Unable to resolve CLI path: $Name" }
        $commandPath = Get-NormalizedFullPath -Path $commandPath
        $entry = Get-Item -LiteralPath $commandPath -Force -ErrorAction Stop
        if ($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "CLI is not an ordinary file: $commandPath" }
        $commandType = [string]$command.CommandType
        if ($commandType -notin @('Application', 'ExternalScript')) { throw "Unsupported CLI command type: $commandType" }
        if ($Name -ceq 'agy' -and ($commandType -cne 'Application' -or [IO.Path]::GetFileName($commandPath) -cne 'agy.exe')) {
            throw "Antigravity evidence requires the native agy.exe application: $commandPath"
        }
        $sha256 = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($commandPath))
        $output = @(& $commandPath --version 2>&1)
        $exitCode = $LASTEXITCODE
        $version = [string]::Join(' ', @($output | ForEach-Object { ([string]$_).Trim() })).Trim()
        if ((Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($commandPath))) -cne $sha256) { throw "CLI changed while reading its version: $Name" }
        return [pscustomobject][ordered]@{ state = if ($exitCode -eq 0) { 'DETECTED' } else { 'ERROR' }; version = $version; path = $commandPath; commandType = $commandType; sha256 = $sha256 }
    }
    catch { return [pscustomobject][ordered]@{ state = 'UNTRUSTED'; version = $_.Exception.Message; path = $null; commandType = $null; sha256 = $null } }
}

function Test-CliEvidenceEqual {
    param($Expected, $Actual)
    foreach ($field in @('state', 'version', 'path', 'commandType', 'sha256')) {
        if ([string]$Expected.$field -cne [string]$Actual.$field) { return $false }
    }
    return $true
}

function Get-MachineId {
    param([string]$TestLabel)
    $material = if ([string]::IsNullOrWhiteSpace($TestLabel)) { "$([Environment]::MachineName)|$([Environment]::OSVersion.VersionString)|$([Environment]::ProcessorCount)" } else { "test-machine|$TestLabel" }
    return (Get-Sha256Text -Text $material).Substring(0, 24)
}

function Get-CliSnapshot {
    param($Manifest)
    $snapshot = [pscustomobject][ordered]@{
        'claude-code' = Get-CliEvidence -Name 'claude'
        codex = Get-CliEvidence -Name 'codex'
        cursor = Get-CliEvidence -Name 'cursor-agent'
        antigravity = Get-CliEvidence -Name 'agy'
    }
    $compatible = $true
    foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
        $cli = $snapshot.PSObject.Properties[$vendor].Value
        $contract = $Manifest.compatibility.PSObject.Properties[$vendor].Value
        if ($null -eq $cli -or [string]$cli.state -cne 'DETECTED' -or $null -eq $contract -or [string]::IsNullOrWhiteSpace([string]$contract.testedVersion) -or -not ([string]$cli.version).Contains([string]$contract.testedVersion)) { $compatible = $false }
    }
    return [pscustomobject][ordered]@{ cli = $snapshot; compatible = $compatible }
}

function Assert-ReleasePayload {
    param([string]$Root, [string]$ExpectedRelease, [switch]$PermitDirty)
    $manifestPath = Join-Path $Root 'release-manifest.json'
    $manifest = Read-JsonFile -Path $manifestPath -Label 'Release manifest'
    if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.releaseId -cne $ExpectedRelease) { throw 'Release manifest identity mismatch' }
    if ([string]$manifest.manifestDigest -notmatch '^[a-f0-9]{64}$' -or [string]$manifest.manifestDigest -cne (Get-ReleaseManifestDigest -Manifest $manifest)) { throw 'Release manifest metadata digest mismatch' }
    if ([bool]$manifest.dirtyBuild -and -not $PermitDirty) { throw 'Dirty release artifact cannot produce final machine evidence' }
    $listed = @{}
    foreach ($file in @($manifest.files)) {
        $relativePath = [string]$file.path
        if ($relativePath.Contains('\') -or $relativePath -match '(^|/)\.\.(/|$)' -or $listed.ContainsKey($relativePath)) { throw "Unsafe or duplicate release path: $relativePath" }
        $listed[$relativePath] = $true
        $path = Join-Path $Root $relativePath.Replace('/', '\')
        if (-not (Test-PathWithin -Root $Root -Candidate $path) -or -not [IO.File]::Exists($path)) { throw "Release file is missing: $relativePath" }
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.LongLength -ne [int64]$file.bytes -or (Get-Sha256Bytes -Bytes $bytes) -cne [string]$file.sha256) { throw "Release file verification failed: $relativePath" }
    }
    $actual = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/') } | Where-Object { $_ -cne 'release-manifest.json' } | Sort-Object)
    if ([string]::Join("`n", $actual) -cne [string]::Join("`n", @($listed.Keys | Sort-Object))) { throw 'Release contains unmanifested payload files' }
    return [pscustomobject][ordered]@{ data = $manifest; manifestSha256 = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($manifestPath)) }
}

function Test-PackageLayout {
    param([string]$Root)
    $required = @(
        'packages\agent-plugins\yohan-agent-kit\plugin.json',
        'packages\agent-plugins\yohan-agent-kit\mcp.json',
        'packages\claude-code\.claude-plugin\marketplace.json',
        'packages\claude-code\plugins\yohan-agent-kit\hooks\hooks.json',
        'packages\claude-code\plugins\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\codex\yohan-agent-kit\.codex-plugin\plugin.json',
        'packages\codex\yohan-agent-kit\hooks.json',
        'packages\codex\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\cursor\yohan-agent-kit\.cursor-plugin\plugin.json',
        'packages\cursor\yohan-agent-kit\hooks\hooks.json',
        'packages\cursor\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\antigravity\yohan-agent-kit\plugin.json',
        'packages\antigravity\yohan-agent-kit\hooks.json',
        'packages\antigravity\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\antigravity\yohan-agent-kit\agents\explorer.md'
    )
    $missing = @($required | Where-Object { -not [IO.File]::Exists((Join-Path $Root $_)) })
    if ($missing.Count) { throw "Required package manifests are missing: $([string]::Join(', ', $missing))" }
    $portableRoot = Join-Path $Root 'packages\agent-plugins\yohan-agent-kit'
    $unexpected = @(Get-ChildItem -LiteralPath $portableRoot -Force | Where-Object { $_.Name -notin @('plugin.json', 'mcp.json', 'skills') } | ForEach-Object Name)
    if ($unexpected.Count) { throw "Agent Plugins package contains non-v1 components: $([string]::Join(', ', $unexpected))" }
    $portableManifest = Read-JsonFile -Path (Join-Path $portableRoot 'plugin.json') -Label 'Agent Plugins manifest'
    if ([string]$portableManifest.'$schema' -cne 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json') { throw 'Agent Plugins manifest schema mismatch' }
    $portableMcp = Read-JsonFile -Path (Join-Path $portableRoot 'mcp.json') -Label 'Agent Plugins MCP manifest'
    if ([string]$portableMcp.'$schema' -cne 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json') { throw 'Agent Plugins MCP schema mismatch' }
    $codexManifest = Read-JsonFile -Path (Join-Path $Root 'packages\codex\yohan-agent-kit\.codex-plugin\plugin.json') -Label 'Codex plugin manifest'
    if ([string]$codexManifest.hooks -cne './hooks.json') { throw 'Codex hook declaration mismatch' }
    $cursorHooks = Read-JsonFile -Path (Join-Path $Root 'packages\cursor\yohan-agent-kit\hooks\hooks.json') -Label 'Cursor hooks'
    if ([int]$cursorHooks.version -ne 1 -or @($cursorHooks.hooks.sessionEnd).Count -ne 1) { throw 'Cursor hook adapter mismatch' }
    $antigravityHooks = Read-JsonFile -Path (Join-Path $Root 'packages\antigravity\yohan-agent-kit\hooks.json') -Label 'Antigravity hooks'
    if (@($antigravityHooks.'yohan-agent-kit-observer'.PostInvocation).Count -ne 1) { throw 'Antigravity hook adapter mismatch' }
    $antigravityManifest = Read-JsonFile -Path (Join-Path $Root 'packages\antigravity\yohan-agent-kit\plugin.json') -Label 'Antigravity plugin manifest'
    if ([string]$antigravityManifest.'$schema' -cne 'https://antigravity.google/schemas/v1/plugin.json') { throw 'Antigravity plugin schema mismatch' }
    return $true
}

function New-ManualTemplate {
    $keys = @('explicitSkill', 'implicitSkill', 'negativeRouting', 'sharedScript', 'subagent', 'hookFailureIsolation', 'mcpAuthFailureIsolation')
    $vendors = [ordered]@{}
    foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
        $checks = [ordered]@{}
        foreach ($key in $keys) {
            $checks[$key] = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
        }
        $vendors[$vendor] = $checks
    }
    return $vendors
}

function Assert-ResultSet {
    param($Results, [string]$Label, [string[]]$ExpectedKeys, [switch]$PermitSynthetic)
    $actualKeys = @($Results.PSObject.Properties.Name | Sort-Object)
    $requiredKeys = @($ExpectedKeys | Sort-Object)
    if ([string]::Join("`n", $actualKeys) -cne [string]::Join("`n", $requiredKeys)) { throw "$Label result keys do not match the required contract" }
    foreach ($property in @($Results.PSObject.Properties)) {
        $status = [string]$property.Value.status
        $evidence = [string]$property.Value.evidence
        if ($status -cne 'PASS') { throw "$Label.$($property.Name) must be PASS" }
        if ([string]::IsNullOrWhiteSpace($evidence)) { throw "$Label.$($property.Name) requires evidence" }
        if ($evidence -match '(?i)replace with|\bTODO\b|\bTBD\b') { throw "$Label.$($property.Name) still contains placeholder evidence" }
        if ($evidence.StartsWith('TEST_ONLY:', [StringComparison]::Ordinal) -and -not $PermitSynthetic) { throw "$Label.$($property.Name) contains test-only evidence" }
    }
}

function Get-EvidenceSeal {
    param($Evidence)
    $lines = @(
        "schema=$([int]$Evidence.schemaVersion)", "machine=$($Evidence.machineId)", "home=$($Evidence.homeRootDigest)",
        "release=$($Evidence.releaseId)", "commit=$($Evidence.gitCommit)",
        "catalog=$($Evidence.catalogDigest)", "manifest=$($Evidence.manifestSha256)", "status=$($Evidence.status)"
    )
    foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
        $cli = $Evidence.cli.PSObject.Properties[$vendor].Value
        $lines += "cli|$vendor|$($cli.state)|$($cli.version)|$($cli.path)|$($cli.commandType)|$($cli.sha256)"
        foreach ($check in @($Evidence.vendors.$vendor.PSObject.Properties | Sort-Object Name)) { $lines += "$vendor|$($check.Name)|$($check.Value.status)|$($check.Value.evidence)" }
    }
    foreach ($check in @($Evidence.automated.PSObject.Properties | Sort-Object Name)) { $lines += "automated|$($check.Name)|$($check.Value)" }
    foreach ($check in @($Evidence.transactions.PSObject.Properties | Sort-Object Name)) { $lines += "transaction|$($check.Name)|$($check.Value.status)|$($check.Value.evidence)" }
    return Get-Sha256Text -Text ([string]::Join("`n", $lines))
}

function Get-EvidenceValidationErrors {
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$PermitSynthetic
    )

    $errors = @()
    if ([int]$Evidence.schemaVersion -ne 2) { return @("$Label schemaVersion must be 2; regenerate evidence") }
    if ([string]$Evidence.status -cne 'FINAL') { $errors += "$Label evidence must be FINAL" }
    foreach ($field in @('machineId', 'homeRootDigest', 'releaseId', 'gitCommit', 'catalogDigest', 'manifestSha256', 'evidenceDigest')) {
        if ([string]::IsNullOrWhiteSpace([string]$Evidence.$field)) { $errors += "$Label evidence is missing: $field" }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Evidence.homeRootDigest) -and [string]$Evidence.homeRootDigest -notmatch '^[a-f0-9]{64}$') { $errors += "$Label homeRootDigest is invalid" }
    if (-not [string]::IsNullOrWhiteSpace([string]$Evidence.evidenceDigest) -and
        [string]$Evidence.evidenceDigest -cne (Get-EvidenceSeal -Evidence $Evidence)) {
        $errors += "$Label evidence seal is invalid"
    }
    foreach ($check in @('releaseHashes', 'packageLayout', 'cliCompatibility')) {
        if ([string]$Evidence.automated.PSObject.Properties[$check].Value -cne 'PASS') { $errors += "$Label automated check is incomplete: $check" }
    }
    foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
        $cli = $Evidence.cli.PSObject.Properties[$vendor].Value
        if ($null -eq $cli -or [string]$cli.state -cne 'DETECTED' -or [string]::IsNullOrWhiteSpace([string]$cli.version)) {
            $errors += "$Label required CLI is not detected: $vendor"
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$cli.path) -or
            [string]$cli.commandType -notin @('Application', 'ExternalScript') -or
            [string]$cli.sha256 -notmatch '^[a-f0-9]{64}$') {
            $errors += "$Label required CLI identity is invalid: $vendor"
        }
        elseif ($vendor -ceq 'antigravity' -and ([string]$cli.commandType -cne 'Application' -or [IO.Path]::GetFileName([string]$cli.path) -cne 'agy.exe')) {
            $errors += "$Label Antigravity CLI identity is not native agy.exe"
        }
        try { Assert-ResultSet -Results $Evidence.vendors.$vendor -Label "$Label.$vendor" -ExpectedKeys $manualKeys -PermitSynthetic:$PermitSynthetic }
        catch { $errors += $_.Exception.Message }
    }
    try { Assert-ResultSet -Results $Evidence.transactions -Label "$Label.transactions" -ExpectedKeys $transactionKeys -PermitSynthetic:$PermitSynthetic }
    catch { $errors += $_.Exception.Message }
    return @($errors)
}

function Get-SingleMachineStateErrors {
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string]$HomeRoot,
        [string]$ReleaseRoot,
        [string]$MachineLabel,
        [switch]$PermitDirty
    )

    $errors = @()
    $expectedMachineId = Get-MachineId -TestLabel $MachineLabel
    if ([string]$Evidence.machineId -cne $expectedMachineId) {
        $errors += 'House PC evidence machine ID differs from the current machine'
    }
    $currentHomeRootDigest = Get-HomeRootDigest -Path $HomeRoot
    if ([string]$Evidence.homeRootDigest -cne $currentHomeRootDigest) {
        $errors += 'House PC evidence HomeRoot digest differs from the current canonical HomeRoot'
    }

    $kitRoot = Join-Path $HomeRoot '.yohan-agent-kit'
    $expectedReleaseRoot = Join-Path $kitRoot "releases\$([string]$Evidence.releaseId)"
    if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = $expectedReleaseRoot }
    $ReleaseRoot = Get-NormalizedFullPath -Path $ReleaseRoot
    if (-not [string]::Equals($ReleaseRoot, (Get-NormalizedFullPath -Path $expectedReleaseRoot), [StringComparison]::OrdinalIgnoreCase)) {
        $errors += 'House PC evidence release is not the installed release under the current HomeRoot'
        return @($errors)
    }

    $verified = $null
    try {
        Assert-NoReparseAncestors -Root $HomeRoot -Candidate $ReleaseRoot -IncludeLeaf
        $verified = Assert-ReleasePayload -Root $ReleaseRoot -ExpectedRelease ([string]$Evidence.releaseId) -PermitDirty:$PermitDirty
        if ([string]$Evidence.gitCommit -cne [string]$verified.data.gitCommit -or
            [string]$Evidence.catalogDigest -cne [string]$verified.data.catalogDigest -or
            [string]$Evidence.manifestSha256 -cne [string]$verified.manifestSha256) {
            $errors += 'House PC evidence release identity differs from the installed release'
        }
        $null = Test-PackageLayout -Root $ReleaseRoot
        $currentCli = Get-CliSnapshot -Manifest $verified.data
        if (-not $currentCli.compatible) { $errors += 'Current house-PC CLI versions do not satisfy the installed release contract' }
        foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
            $actual = $currentCli.cli.PSObject.Properties[$vendor].Value
            $recorded = $Evidence.cli.PSObject.Properties[$vendor].Value
            if (-not (Test-CliEvidenceEqual -Expected $recorded -Actual $actual)) {
                $errors += "Current house-PC CLI identity differs from the evidence: $vendor"
            }
        }
    }
    catch { $errors += "Installed house-PC release validation failed: $($_.Exception.Message)" }

    try {
        $activeJsonPath = Join-Path $kitRoot 'active.json'
        Assert-NoReparseAncestors -Root $HomeRoot -Candidate $activeJsonPath -IncludeLeaf
        $activeState = Read-JsonFile -Path $activeJsonPath -Label 'Active release state'
        if ([int]$activeState.schemaVersion -ne 1 -or
            [string]$activeState.releaseId -cne [string]$Evidence.releaseId -or
            [string]$activeState.manifestSha256 -cne [string]$Evidence.manifestSha256) {
            $errors += 'House PC active.json differs from the evidence release'
        }

        $activePath = Join-Path $kitRoot 'active'
        Assert-NoReparseAncestors -Root $HomeRoot -Candidate $activePath
        $activeEntry = Get-Item -LiteralPath $activePath -Force -ErrorAction Stop
        $linkType = $activeEntry.PSObject.Properties['LinkType']
        $target = $activeEntry.PSObject.Properties['Target']
        if (($activeEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
            $null -eq $linkType -or [string]$linkType.Value -cne 'Junction' -or $null -eq $target) {
            $errors += 'House PC active pointer is not an owned junction'
        }
        else {
            $targetPath = [string](@($target.Value)[0])
            if (-not [IO.Path]::IsPathRooted($targetPath)) { $targetPath = Join-Path (Split-Path -Parent $activePath) $targetPath }
            if (-not [string]::Equals((Get-NormalizedFullPath -Path $targetPath), $ReleaseRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $errors += 'House PC active junction differs from the evidence release'
            }
        }
    }
    catch { $errors += "House PC active release validation failed: $($_.Exception.Message)" }

    return @($errors)
}

function Write-HumanResult {
    param($Result)
    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['releaseId']) { Write-Output "Release: $($Result.releaseId)" }
    if ($Result.PSObject.Properties['evidencePath']) { Write-Output "Evidence: $($Result.evidencePath)" }
    if ($Result.PSObject.Properties['errors']) { foreach ($message in @($Result.errors)) { Write-Output "ERROR: $message" } }
}

$exitCode = 1
try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    $RepositoryRoot = Get-NormalizedFullPath -Path $RepositoryRoot
    if ([IO.File]::Exists((Join-Path $RepositoryRoot '.vhk\HARD_STOP'))) { throw '.vhk/HARD_STOP detected' }
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
    $HomeRoot = Get-NormalizedFullPath -Path $HomeRoot
    $homeRootDigest = Get-HomeRootDigest -Path $HomeRoot
    $evidenceRoot = Join-Path $HomeRoot '.yohan-agent-kit\evidence'
    $testRoot = Join-Path $RepositoryRoot 'tests\.work'
    $temporaryTestRoot = Join-Path ([IO.Path]::GetTempPath()) 'yohan-agent-kit-tests'
    $isBoundedTestHome = (Test-PathWithin -Root $testRoot -Candidate $HomeRoot) -or (Test-PathWithin -Root $temporaryTestRoot -Candidate $HomeRoot)
    if ($AllowSyntheticEvidence -and -not $isBoundedTestHome) { throw 'Synthetic evidence is permitted only in a bounded Agent Kit test HomeRoot' }
    $manualKeys = @('explicitSkill', 'implicitSkill', 'negativeRouting', 'sharedScript', 'subagent', 'hookFailureIsolation', 'mcpAuthFailureIsolation')
    $transactionKeys = @('install', 'update', 'idempotency', 'rollback', 'partialFailureRollback')
    if (-not [string]::IsNullOrWhiteSpace($MachineLabel)) {
        if (-not $isBoundedTestHome) { throw 'MachineLabel override is test-only and requires a bounded Agent Kit test root' }
    }

    if ($Mode -eq 'Probe') {
        if (-not $ApproveEvidenceWrite) { throw 'Probe requires -ApproveEvidenceWrite' }
        if ([string]::IsNullOrWhiteSpace($Release)) { throw 'Probe requires -Release' }
        if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path $HomeRoot ".yohan-agent-kit\releases\$Release" }
        $ReleaseRoot = Get-NormalizedFullPath -Path $ReleaseRoot
        $verified = Assert-ReleasePayload -Root $ReleaseRoot -ExpectedRelease $Release -PermitDirty:$AllowDirtyArtifact
        $null = Test-PackageLayout -Root $ReleaseRoot
        $cliSnapshot = Get-CliSnapshot -Manifest $verified.data
        $machineId = Get-MachineId -TestLabel $MachineLabel
        if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $evidenceRoot "$Release-$machineId-draft.json" }
        $draft = [pscustomobject][ordered]@{
            schemaVersion = 2; status = 'DRAFT'; machineId = $machineId; homeRootDigest = $homeRootDigest; releaseId = $Release
            gitCommit = [string]$verified.data.gitCommit; catalogDigest = [string]$verified.data.catalogDigest; manifestSha256 = [string]$verified.manifestSha256
            cli = $cliSnapshot.cli
            automated = [pscustomobject][ordered]@{ releaseHashes = 'PASS'; packageLayout = 'PASS'; cliCompatibility = if ($cliSnapshot.compatible) { 'PASS' } else { 'FAIL' } }
            vendors = New-ManualTemplate
            transactions = [pscustomobject][ordered]@{
                install = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
                update = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
                idempotency = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
                rollback = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
                partialFailureRollback = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
            }
            evidenceDigest = $null
        }
        Write-JsonFile -Path $EvidencePath -Value $draft -AllowedRoot $HomeRoot
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Probe'; status = 'DraftEvidenceReady'; releaseId = $Release; evidencePath = $EvidencePath; machineId = $machineId; exitCode = 0 }
    }
    elseif ($Mode -eq 'Finalize') {
        if (-not $ApproveEvidenceWrite) { throw 'Finalize requires -ApproveEvidenceWrite' }
        if (-not (Test-PathWithin -Root $evidenceRoot -Candidate $DraftEvidencePath)) { throw 'Draft evidence must be inside the current HomeRoot evidence directory' }
        Assert-NoReparseAncestors -Root $HomeRoot -Candidate $DraftEvidencePath -IncludeLeaf
        $draft = Read-JsonFile -Path $DraftEvidencePath -Label 'Draft evidence'
        if ([int]$draft.schemaVersion -ne 2) { throw 'Draft evidence schemaVersion must be 2; regenerate evidence' }
        if ([string]$draft.status -cne 'DRAFT') { throw 'Only DRAFT evidence can be finalized' }
        if ([string]$draft.machineId -cne (Get-MachineId -TestLabel $MachineLabel)) { throw 'Draft evidence machine identity differs from the current machine' }
        if ([string]$draft.homeRootDigest -cne $homeRootDigest) { throw 'Draft evidence HomeRoot digest differs from the current canonical HomeRoot' }
        if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path $HomeRoot ".yohan-agent-kit\releases\$([string]$draft.releaseId)" }
        $ReleaseRoot = Get-NormalizedFullPath -Path $ReleaseRoot
        $verified = Assert-ReleasePayload -Root $ReleaseRoot -ExpectedRelease ([string]$draft.releaseId) -PermitDirty:$AllowDirtyArtifact
        $null = Test-PackageLayout -Root $ReleaseRoot
        if ([string]$draft.gitCommit -cne [string]$verified.data.gitCommit -or [string]$draft.catalogDigest -cne [string]$verified.data.catalogDigest -or [string]$draft.manifestSha256 -cne [string]$verified.manifestSha256) { throw 'Draft evidence release identity differs from the verified artifact' }
        $cliSnapshot = Get-CliSnapshot -Manifest $verified.data
        foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
            $recordedCli = $draft.cli.PSObject.Properties[$vendor].Value
            $currentCli = $cliSnapshot.cli.PSObject.Properties[$vendor].Value
            if (-not (Test-CliEvidenceEqual -Expected $recordedCli -Actual $currentCli)) { throw "CLI identity changed since Probe: $vendor" }
        }
        $draft.cli = $cliSnapshot.cli
        $draft.automated.releaseHashes = 'PASS'
        $draft.automated.packageLayout = 'PASS'
        $draft.automated.cliCompatibility = if ($cliSnapshot.compatible) { 'PASS' } else { 'FAIL' }
        foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
            $cli = $draft.cli.PSObject.Properties[$vendor].Value
            if ($null -eq $cli -or [string]$cli.state -cne 'DETECTED' -or [string]::IsNullOrWhiteSpace([string]$cli.version)) { throw "Required vendor CLI is not detected: $vendor" }
        }
        foreach ($check in @('releaseHashes', 'packageLayout', 'cliCompatibility')) { if ([string]$draft.automated.PSObject.Properties[$check].Value -cne 'PASS') { throw "Automated check is not complete: $check" } }
        $sessions = Read-JsonFile -Path $SessionResultsPath -Label 'Session results'
        $transactions = Read-JsonFile -Path $TransactionResultsPath -Label 'Transaction results'
        foreach ($vendor in @('claude-code', 'codex', 'cursor', 'antigravity')) {
            $vendorResults = $sessions.PSObject.Properties[$vendor].Value
            if ($null -eq $vendorResults) { throw "Session results missing vendor: $vendor" }
            Assert-ResultSet -Results $vendorResults -Label $vendor -ExpectedKeys $manualKeys -PermitSynthetic:$AllowSyntheticEvidence
            $draft.vendors.PSObject.Properties[$vendor].Value = $vendorResults
        }
        Assert-ResultSet -Results $transactions -Label 'transactions' -ExpectedKeys $transactionKeys -PermitSynthetic:$AllowSyntheticEvidence
        $draft.transactions = $transactions
        $draft.status = 'FINAL'
        $draft.evidenceDigest = Get-EvidenceSeal -Evidence $draft
        if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $EvidencePath = Join-Path $evidenceRoot "$($draft.releaseId)-$($draft.machineId)-final.json" }
        Write-JsonFile -Path $EvidencePath -Value $draft -AllowedRoot $HomeRoot
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Finalize'; status = 'FinalEvidenceReady'; releaseId = $draft.releaseId; evidencePath = $EvidencePath; evidenceDigest = $draft.evidenceDigest; exitCode = 0 }
    }
    elseif ($Mode -eq 'Verify') {
        if ([string]::IsNullOrWhiteSpace($EvidencePath)) { throw 'Verify requires -EvidencePath' }
        if (-not (Test-PathWithin -Root $evidenceRoot -Candidate $EvidencePath)) { throw 'House PC evidence must be inside the current HomeRoot evidence directory' }
        Assert-NoReparseAncestors -Root $HomeRoot -Candidate $EvidencePath -IncludeLeaf
        $evidence = Read-JsonFile -Path $EvidencePath -Label 'House PC evidence'
        $errors = @(Get-EvidenceValidationErrors -Evidence $evidence -Label 'House PC' -PermitSynthetic:$AllowSyntheticEvidence)
        if ([int]$evidence.schemaVersion -eq 2) {
            $errors += @(Get-SingleMachineStateErrors -Evidence $evidence -HomeRoot $HomeRoot -ReleaseRoot $ReleaseRoot -MachineLabel $MachineLabel -PermitDirty:$AllowDirtyArtifact)
        }
        $result = [pscustomobject][ordered]@{
            schemaVersion = 1
            mode = 'Verify'
            status = if ($errors.Count) { 'Conflict' } else { 'SingleMachineVerified' }
            releaseId = [string]$evidence.releaseId
            machineId = [string]$evidence.machineId
            evidenceDigest = [string]$evidence.evidenceDigest
            errors = $errors
            exitCode = if ($errors.Count) { 3 } else { 0 }
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($EvidencePath) -or [string]::IsNullOrWhiteSpace($OtherEvidencePath)) { throw 'Compare requires -EvidencePath and -OtherEvidencePath' }
        $first = Read-JsonFile -Path $EvidencePath -Label 'First machine evidence'
        $second = Read-JsonFile -Path $OtherEvidencePath -Label 'Second machine evidence'
        $errors = @(
            @(Get-EvidenceValidationErrors -Evidence $first -Label 'First machine' -PermitSynthetic:$AllowSyntheticEvidence)
            @(Get-EvidenceValidationErrors -Evidence $second -Label 'Second machine' -PermitSynthetic:$AllowSyntheticEvidence)
        )
        if ([string]$first.machineId -ceq [string]$second.machineId) { $errors += 'Evidence files must come from different machines' }
        foreach ($field in @('releaseId', 'gitCommit', 'catalogDigest', 'manifestSha256')) { if ([string]$first.$field -cne [string]$second.$field) { $errors += "Evidence mismatch: $field" } }
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Compare'; status = if ($errors.Count) { 'Conflict' } else { 'Compatible' }; releaseId = [string]$first.releaseId; machineIds = @([string]$first.machineId, [string]$second.machineId); errors = $errors; exitCode = if ($errors.Count) { 3 } else { 0 } }
    }
    $exitCode = [int]$result.exitCode
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $result) } else { Write-HumanResult -Result $result }
}
catch {
    $failure = [pscustomobject][ordered]@{ schemaVersion = 1; mode = $Mode; status = 'Error'; errors = @($_.Exception.Message); exitCode = 1 }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $failure) } else { Write-HumanResult -Result $failure }
    $exitCode = 1
}
exit $exitCode
