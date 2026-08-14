#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Install', 'Update', 'Restore')]
    [string]$Mode = 'Check',

    [string]$Release,

    [ValidateSet('All', 'AgentPlugins', 'ClaudeCode', 'Codex', 'Cursor', 'Antigravity')]
    [string[]]$Targets = @('All'),

    [string]$RepositoryRoot,

    [string]$ArtifactRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [string]$PlanDigest,

    [string]$BackupId,

    [switch]$ApproveGlobalHomeWrite,

    [switch]$AllowDirtyArtifact,

    [ValidateSet('', 'AfterReleaseCopy', 'AfterFirstTarget', 'AfterActive', 'AfterFirstRestoreTarget')]
    [string]$TestFault = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate
    )
    $base = Get-NormalizedFullPath -Path $Root
    $path = Get-NormalizedFullPath -Path $Candidate
    if ([string]::Equals($base, $path, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-PathWithin -Root $Root -Candidate $Candidate)) { throw "$Label escapes its allowed root: $Candidate" }
}

function Assert-NoReparseAncestors {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [switch]$IncludeLeaf
    )
    $full = Get-NormalizedFullPath -Path $Candidate
    $pathRoot = [IO.Path]::GetPathRoot($full)
    $relative = $full.Substring($pathRoot.Length).TrimStart('\', '/')
    $segments = @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $limit = if ($IncludeLeaf) { $segments.Count } else { [Math]::Max(0, $segments.Count - 1) }
    $current = $pathRoot
    for ($index = 0; $index -lt $limit; $index++) {
        if (-not [IO.Directory]::Exists($current)) { break }
        $leaf = $segments[$index]
        $entries = @(Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $leaf })
        if ($entries.Count -eq 0) { break }
        if ($entries.Count -gt 1) { throw "Case-colliding path entries exist under: $current" }
        $entry = $entries[0]
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Destination ancestor is a reparse point: $($entry.FullName)" }
        if (-not $entry.PSIsContainer) { throw "Destination ancestor is not a directory: $($entry.FullName)" }
        $current = $entry.FullName
    }
}

function Assert-SafeDestinationPath {
    param(
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$IncludeLeaf
    )
    Assert-PathWithin -Root $AllowedRoot -Candidate $Candidate -Label $Label
    Assert-NoReparseAncestors -Candidate $Candidate -IncludeLeaf:$IncludeLeaf
}

function Assert-SafeFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Label
    )
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Candidate -Label $Label
    $full = Get-NormalizedFullPath -Path $Candidate
    $parent = Split-Path -Parent $full
    if (-not [IO.Directory]::Exists($parent)) { return }
    $leaf = Split-Path -Leaf $full
    $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf })
    if ($entries.Count -gt 1) { throw "Case-colliding file entries exist under: $parent" }
    if ($entries.Count -eq 0) { return }
    $entry = $entries[0]
    $linkType = $entry.PSObject.Properties['LinkType']
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value))) {
        throw "$Label is a linked file: $full"
    }
    if ($entry.PSIsContainer) { throw "$Label is a directory: $full" }
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)
    return Get-Sha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-ReleaseManifestDigest {
    param([Parameter(Mandatory = $true)]$Manifest)
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
    param([Parameter(Mandatory = $true)]$Value)
    $json = [string]($Value | ConvertTo-Json -Depth 32)
    return [regex]::Replace($json, '[^\x00-\x7F]', {
        param($Match)
        return ('\u{0:x4}' -f [int][char]$Match.Value)
    })
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )
    Assert-SafeFilePath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'JSON file'
    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Assert-SafeFilePath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'JSON file'
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-AsciiJson -Value $Value) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) {
        $replacementBackup = "$Path.$([Guid]::NewGuid().ToString('N')).previous"
        try {
            [IO.File]::Replace($temporary, $Path, $replacementBackup, $true)
            [IO.File]::Delete($replacementBackup)
        }
        finally {
            if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
            if ([IO.File]::Exists($replacementBackup)) { [IO.File]::Delete($replacementBackup) }
        }
    }
    else { [IO.File]::Move($temporary, $Path) }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )
    Assert-SafeFilePath -AllowedRoot $AllowedRoot -Candidate $Path -Label $Label
    if (-not [IO.File]::Exists($Path)) { throw "$Label is missing: $Path" }
    try { return [string]([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
    catch { throw "$Label is invalid JSON: $($_.Exception.Message)" }
}

function Get-LinkTargetPath {
    param([Parameter(Mandatory = $true)]$Entry)
    $property = $Entry.PSObject.Properties['Target']
    if ($null -eq $property -or $null -eq $property.Value) { return $null }
    $raw = @($property.Value)[0]
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $null }
    $target = [string]$raw
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $Entry.Parent.FullName $target }
    return Get-NormalizedFullPath -Path $target
}

function Get-JunctionIdentity {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $fullPath = Get-NormalizedFullPath -Path $Entry.FullName
    $fsutilPath = Join-Path ([Environment]::GetFolderPath('System')) 'fsutil.exe'
    if (-not [IO.File]::Exists($fsutilPath)) { throw 'System32 fsutil.exe is required to identify Windows junctions' }
    $output = @(& $fsutilPath file queryfileid $fullPath 2>&1)
    $exitCode = $LASTEXITCODE
    $match = [regex]::Match([string]::Join(' ', @($output | ForEach-Object { [string]$_ })), '0x[0-9A-Fa-f]{16,32}')
    if ($exitCode -ne 0 -or -not $match.Success) { throw "Unable to read the junction file ID: $fullPath" }
    return Get-Sha256Text -Text ([string]::Join('|', @('agent-kit-junction-v1', (Get-NormalizedFullPath -Path $Target).ToLowerInvariant(), $match.Value.ToUpperInvariant())))
}

function Get-PathEntryInfo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Get-NormalizedFullPath -Path $Path
    $parent = Split-Path -Parent $full
    $leaf = Split-Path -Leaf $full
    if (-not [IO.Directory]::Exists($parent)) { return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; identity = $null } }
    $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ceq $leaf })
    if ($entries.Count -eq 0) { $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf }) }
    if ($entries.Count -eq 0) { return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; identity = $null } }
    if ($entries.Count -gt 1) { throw "Case-colliding entries exist at: $full" }
    $entry = $entries[0]
    if (-not $entry.PSIsContainer) { return [pscustomobject][ordered]@{ path = $full; kind = 'File'; target = $null; identity = $null } }
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return [pscustomobject][ordered]@{ path = $full; kind = 'Directory'; target = $null; identity = $null } }
    $linkType = [string]$entry.PSObject.Properties['LinkType'].Value
    $target = Get-LinkTargetPath -Entry $entry
    if ($linkType -ne 'Junction' -or $null -eq $target) { return [pscustomobject][ordered]@{ path = $full; kind = 'ReparsePoint'; target = $target; identity = $null } }
    return [pscustomobject][ordered]@{ path = $full; kind = 'Junction'; target = $target; identity = Get-JunctionIdentity -Entry $entry -Target $target }
}

function New-OwnedJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'Junction'
    if ((Get-PathEntryInfo -Path $Path).kind -ne 'Missing') { throw "Junction destination exists: $Path" }
    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'Junction'
    $null = New-Item -ItemType Junction -Path $Path -Target $Target
    $created = Get-PathEntryInfo -Path $Path
    if ($created.kind -ne 'Junction' -or -not [string]::Equals([string]$created.target, (Get-NormalizedFullPath -Path $Target), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Junction verification failed: $Path"
    }
    return [string]$created.identity
}

function Remove-OwnedJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'Owned junction'
    $entry = Get-PathEntryInfo -Path $Path
    if ($entry.kind -eq 'Missing') { return }
    if ($entry.kind -ne 'Junction' -or -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $Target), [StringComparison]::OrdinalIgnoreCase) -or [string]$entry.identity -cne $Identity) {
        throw "Refusing to remove an unowned junction: $Path"
    }
    [IO.Directory]::Delete((Get-NormalizedFullPath -Path $Path), $false)
}

function Move-OwnedJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    Assert-SafeDestinationPath -AllowedRoot $SourceRoot -Candidate $Source -Label 'Junction move source'
    Assert-SafeDestinationPath -AllowedRoot $DestinationRoot -Candidate $Destination -Label 'Junction move destination'
    $entry = Get-PathEntryInfo -Path $Source
    if ($entry.kind -ne 'Junction' -or -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $Target), [StringComparison]::OrdinalIgnoreCase) -or [string]$entry.identity -cne $Identity) {
        throw "Junction ownership mismatch: $Source"
    }
    if ((Get-PathEntryInfo -Path $Destination).kind -ne 'Missing') { throw "Junction move destination exists: $Destination" }
    $parent = Split-Path -Parent $Destination
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.Directory]::Move((Get-NormalizedFullPath -Path $Source), (Get-NormalizedFullPath -Path $Destination))
    $moved = Get-PathEntryInfo -Path $Destination
    if ($moved.kind -ne 'Junction' -or [string]$moved.identity -cne $Identity) { throw "Moved junction verification failed: $Destination" }
}

function Get-SelectedTargets {
    param([string[]]$Selection)
    $requested = if ($Selection -contains 'All') { @('AgentPlugins', 'ClaudeCode', 'Codex', 'Cursor', 'Antigravity') } else { @($Selection | Select-Object -Unique) }
    $expanded = @()
    foreach ($target in $requested) {
        if ($target -eq 'Antigravity') { $expanded += @('AntigravityIde', 'AntigravityCli') }
        else { $expanded += $target }
    }
    return @($expanded | Select-Object -Unique)
}

function Get-TargetDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$ReleaseRoot,
        [Parameter(Mandatory = $true)][string[]]$Selection
    )
    $all = [ordered]@{
        AgentPlugins = [pscustomobject][ordered]@{ name = 'AgentPlugins'; path = Join-Path $UserHome '.agents\plugins\yohan-agent-kit'; source = Join-Path $ReleaseRoot 'packages\agent-plugins\yohan-agent-kit'; deployment = 'Junction' }
        ClaudeCode = [pscustomobject][ordered]@{ name = 'ClaudeCode'; path = $null; source = Join-Path $ReleaseRoot 'packages\claude-code'; deployment = 'MarketplaceManaged' }
        Codex = [pscustomobject][ordered]@{ name = 'Codex'; path = Join-Path $UserHome 'plugins\yohan-agent-kit'; source = Join-Path $ReleaseRoot 'packages\codex\yohan-agent-kit'; deployment = 'Junction' }
        Cursor = [pscustomobject][ordered]@{ name = 'Cursor'; path = Join-Path $UserHome '.cursor\plugins\local\yohan-agent-kit'; source = Join-Path $ReleaseRoot 'packages\cursor\yohan-agent-kit'; deployment = 'Junction' }
        AntigravityIde = [pscustomobject][ordered]@{ name = 'AntigravityIde'; path = Join-Path $UserHome '.gemini\config\plugins\yohan-agent-kit'; source = Join-Path $ReleaseRoot 'packages\antigravity\yohan-agent-kit'; deployment = 'Junction' }
        AntigravityCli = [pscustomobject][ordered]@{ name = 'AntigravityCli'; path = Join-Path $UserHome '.gemini\antigravity-cli\plugins\yohan-agent-kit'; source = Join-Path $ReleaseRoot 'packages\antigravity\yohan-agent-kit'; deployment = 'Junction' }
    }
    return @(Get-SelectedTargets -Selection $Selection | ForEach-Object { $all[$_] })
}

function Test-ReleaseArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ExpectedRelease,
        [switch]$PermitDirty
    )
    $artifact = Get-NormalizedFullPath -Path $Root
    $manifestPath = Join-Path $artifact 'release-manifest.json'
    $manifest = Read-JsonFile -Path $manifestPath -Label 'Release manifest' -AllowedRoot $artifact
    if ([int]$manifest.schemaVersion -ne 1) { throw 'Unsupported release manifest schema' }
    if ([string]$manifest.releaseId -cne $ExpectedRelease) { throw 'Release manifest ID mismatch' }
    if ([string]$manifest.gitCommit -notmatch '^[a-f0-9]{40}$') { throw 'Release manifest Git commit is invalid' }
    if ([string]$manifest.catalogDigest -notmatch '^[a-f0-9]{64}$') { throw 'Release manifest catalog digest is invalid' }
    if ([string]$manifest.manifestDigest -notmatch '^[a-f0-9]{64}$' -or [string]$manifest.manifestDigest -cne (Get-ReleaseManifestDigest -Manifest $manifest)) { throw 'Release manifest metadata digest mismatch' }
    if ([bool]$manifest.dirtyBuild -and -not $PermitDirty) { throw 'Dirty release artifacts are test-only and cannot be installed' }
    $seen = @{}
    foreach ($file in @($manifest.files)) {
        $relativePath = [string]$file.path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or $relativePath.Contains('\') -or $relativePath.StartsWith('/') -or $relativePath -match '(^|/)\.\.(/|$)') { throw "Unsafe release file path: $relativePath" }
        if ($seen.ContainsKey($relativePath)) { throw "Duplicate release file path: $relativePath" }
        $seen[$relativePath] = $true
        $path = Join-Path $artifact ($relativePath.Replace('/', '\'))
        Assert-PathWithin -Root $artifact -Candidate $path -Label 'Release file'
        if (-not [IO.File]::Exists($path)) { throw "Release file is missing: $relativePath" }
        $entry = Get-Item -LiteralPath $path -Force
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Release file is a reparse point: $relativePath" }
        $bytes = [IO.File]::ReadAllBytes($path)
        if ([int64]$file.bytes -ne $bytes.LongLength) { throw "Release file size mismatch: $relativePath" }
        if ([string]$file.sha256 -cne (Get-Sha256Bytes -Bytes $bytes)) { throw "Release file digest mismatch: $relativePath" }
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $artifact -File -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($artifact.Length).TrimStart('\').Replace('\', '/')
    } | Where-Object { $_ -cne 'release-manifest.json' } | Sort-Object)
    $expectedFiles = @($seen.Keys | Sort-Object)
    if ([string]::Join("`n", $actualFiles) -cne [string]::Join("`n", $expectedFiles)) { throw 'Release artifact contains unmanifested or missing payload files' }
    return [pscustomobject][ordered]@{
        root = $artifact
        manifest = $manifest
        manifestSha256 = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($manifestPath))
    }
}

function Get-ActiveState {
    param([Parameter(Mandatory = $true)][string]$KitRoot)
    $path = Join-Path $KitRoot 'active.json'
    if (-not [IO.File]::Exists($path)) { return $null }
    $state = Read-JsonFile -Path $path -Label 'Active release state' -AllowedRoot $KitRoot
    if ([int]$state.schemaVersion -ne 1 -or [string]$state.releaseId -notmatch '^[a-z0-9][a-z0-9._-]{0,127}$' -or [string]$state.manifestSha256 -notmatch '^[a-f0-9]{64}$') {
        throw 'Active release state is invalid'
    }
    return $state
}

function Get-ReleasePlan {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [Parameter(Mandatory = $true)][string]$RequestedRelease,
        [Parameter(Mandatory = $true)][string]$SourceArtifact,
        [Parameter(Mandatory = $true)][string[]]$Selection,
        [switch]$PermitDirty
    )
    $artifact = Test-ReleaseArtifact -Root $SourceArtifact -ExpectedRelease $RequestedRelease -PermitDirty:$PermitDirty
    $releaseRoot = Join-Path $KitRoot "releases\$RequestedRelease"
    $installed = $null
    if ([IO.Directory]::Exists($releaseRoot)) { $installed = Test-ReleaseArtifact -Root $releaseRoot -ExpectedRelease $RequestedRelease -PermitDirty:$PermitDirty }
    $active = Get-ActiveState -KitRoot $KitRoot
    $errors = @()
    if ($null -ne $installed -and [string]$installed.manifestSha256 -cne [string]$artifact.manifestSha256) { $errors += 'Installed immutable release differs from the source artifact' }
    if ($null -ne $active) {
        $activeReleaseRoot = Join-Path $KitRoot "releases\$([string]$active.releaseId)"
        try {
            $activeArtifact = Test-ReleaseArtifact -Root $activeReleaseRoot -ExpectedRelease ([string]$active.releaseId) -PermitDirty:$PermitDirty
            if ([string]$activeArtifact.manifestSha256 -cne [string]$active.manifestSha256) { $errors += 'Active state manifest digest differs from its immutable release' }
        }
        catch { $errors += "Active immutable release is invalid: $($_.Exception.Message)" }
    }

    $targetPlans = @()
    foreach ($target in @(Get-TargetDefinitions -UserHome $UserHome -ReleaseRoot $releaseRoot -Selection $Selection)) {
        if ([string]$target.deployment -eq 'MarketplaceManaged') {
            $targetPlans += [pscustomobject][ordered]@{ name = $target.name; deployment = $target.deployment; path = $null; source = $target.source; state = 'External'; action = 'VerifyMarketplace'; currentTarget = $null; currentIdentity = $null }
            continue
        }
        Assert-PathWithin -Root $UserHome -Candidate ([string]$target.path) -Label "$($target.name) discovery path"
        $entry = Get-PathEntryInfo -Path ([string]$target.path)
        $state = 'Conflict'
        $action = 'None'
        if ($entry.kind -eq 'Missing') { $state = 'Missing'; $action = 'CreateJunction' }
        elseif ($entry.kind -eq 'Junction' -and [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path ([string]$target.source)), [StringComparison]::OrdinalIgnoreCase)) { $state = 'Current'; $action = 'None' }
        elseif ($entry.kind -eq 'Junction' -and (Test-PathWithin -Root (Join-Path $KitRoot 'releases') -Candidate ([string]$entry.target))) { $state = 'PreviousRelease'; $action = 'ReplaceOwnedJunction' }
        else { $errors += "$($target.name) discovery path is not owned by Yohan Agent Kit: $($target.path)" }
        $targetPlans += [pscustomobject][ordered]@{ name = $target.name; deployment = $target.deployment; path = $target.path; source = $target.source; state = $state; action = $action; currentTarget = $entry.target; currentIdentity = $entry.identity }
    }

    $activePath = Join-Path $KitRoot 'active'
    $activeEntry = Get-PathEntryInfo -Path $activePath
    $activeAction = 'None'
    if ($activeEntry.kind -eq 'Missing') { $activeAction = 'CreateJunction' }
    elseif ($activeEntry.kind -eq 'Junction' -and [string]::Equals([string]$activeEntry.target, (Get-NormalizedFullPath -Path $releaseRoot), [StringComparison]::OrdinalIgnoreCase)) { $activeAction = 'None' }
    elseif ($activeEntry.kind -eq 'Junction' -and (Test-PathWithin -Root (Join-Path $KitRoot 'releases') -Candidate ([string]$activeEntry.target))) { $activeAction = 'ReplaceOwnedJunction' }
    else { $errors += 'Active release pointer is not owned by Yohan Agent Kit' }
    if ($null -eq $active -and $activeEntry.kind -ne 'Missing') { $errors += 'Active junction exists without active.json state' }
    if ($null -ne $active) {
        $expectedActiveTarget = Join-Path $KitRoot "releases\$([string]$active.releaseId)"
        if ($activeEntry.kind -ne 'Junction' -or -not [string]::Equals([string]$activeEntry.target, (Get-NormalizedFullPath -Path $expectedActiveTarget), [StringComparison]::OrdinalIgnoreCase)) {
            $errors += 'Active junction and active.json refer to different releases'
        }
    }
    if ($null -eq $active -and @($targetPlans | Where-Object { $_.state -in @('Current', 'PreviousRelease') }).Count -gt 0) { $errors += 'Vendor junctions exist without active.json state' }

    $activeReleaseId = if ($null -eq $active) { $null } else { [string]$active.releaseId }
    $lines = @(
        "release=$RequestedRelease",
        "manifest=$($artifact.manifestSha256)",
        "catalog=$($artifact.manifest.catalogDigest)",
        "active=$activeReleaseId",
        "activeAction=$activeAction",
        "activeTarget=$($activeEntry.target)",
        "selected=$([string]::Join(',', @(Get-SelectedTargets -Selection $Selection)))"
    )
    foreach ($target in $targetPlans) { $lines += "target|$($target.name)|$($target.action)|$($target.path)|$($target.source)|$($target.currentTarget)|$($target.currentIdentity)" }
    $planDigest = Get-Sha256Text -Text ([string]::Join("`n", $lines))
    $needsChange = $null -eq $installed -or $activeAction -ne 'None' -or @($targetPlans | Where-Object { $_.action -ne 'None' -and $_.action -ne 'VerifyMarketplace' }).Count -gt 0 -or $null -eq $active -or [string]$active.releaseId -cne $RequestedRelease -or [string]$active.manifestSha256 -cne [string]$artifact.manifestSha256
    $status = if ($errors.Count) { 'Conflict' } elseif (-not $needsChange) { 'Healthy' } elseif ($null -eq $active) { 'Installable' } else { 'Updatable' }
    $exitCode = if ($status -eq 'Healthy') { 0 } elseif ($status -in @('Installable', 'Updatable')) { 2 } else { 3 }
    return [pscustomobject][ordered]@{
        schemaVersion = 1; mode = 'Check'; status = $status; releaseId = $RequestedRelease
        gitCommit = [string]$artifact.manifest.gitCommit; catalogDigest = [string]$artifact.manifest.catalogDigest
        manifestSha256 = [string]$artifact.manifestSha256; sourceArtifact = [string]$artifact.root
        releaseRoot = $releaseRoot; activeRelease = if ($null -eq $active) { $null } else { [string]$active.releaseId }
        activePath = $activePath; activeAction = $activeAction; activeTarget = $activeEntry.target; activeIdentity = $activeEntry.identity
        targets = $targetPlans; errors = $errors; planDigest = $planDigest; exitCode = $exitCode
    }
}

function Copy-VerifiedRelease {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [switch]$PermitDirty
    )
    if ([IO.Directory]::Exists([string]$Plan.releaseRoot)) {
        $null = Test-ReleaseArtifact -Root ([string]$Plan.releaseRoot) -ExpectedRelease ([string]$Plan.releaseId) -PermitDirty:$PermitDirty
        return $false
    }
    $stagingRoot = Join-Path $KitRoot "releases\.staging-$($Plan.releaseId)-$([Guid]::NewGuid().ToString('N'))"
    Assert-SafeDestinationPath -AllowedRoot $KitRoot -Candidate $stagingRoot -Label 'Release staging root'
    $null = New-Item -ItemType Directory -Path $stagingRoot -Force
    $sourceRoot = [string]$Plan.sourceArtifact
    foreach ($source in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force)) {
        if (($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Artifact source contains a reparse point: $($source.FullName)" }
        $relativePath = $source.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $destination = Join-Path $stagingRoot $relativePath
        Assert-SafeDestinationPath -AllowedRoot $stagingRoot -Candidate $destination -Label 'Release copy file'
        $parent = Split-Path -Parent $destination
        if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        [IO.File]::Copy($source.FullName, $destination, $false)
    }
    $null = Test-ReleaseArtifact -Root $stagingRoot -ExpectedRelease ([string]$Plan.releaseId) -PermitDirty:$PermitDirty
    [IO.Directory]::Move($stagingRoot, [string]$Plan.releaseRoot)
    $null = Test-ReleaseArtifact -Root ([string]$Plan.releaseRoot) -ExpectedRelease ([string]$Plan.releaseId) -PermitDirty:$PermitDirty
    return $true
}

function Enter-AgentKitMutex {
    param([Parameter(Mandatory = $true)][string]$UserHome)
    $name = 'Local\YohanAgentKit-' + (Get-Sha256Text -Text ((Get-NormalizedFullPath -Path $UserHome).ToLowerInvariant())).Substring(0, 24)
    $mutex = New-Object Threading.Mutex($false, $name)
    try {
        if (-not $mutex.WaitOne(0)) { throw "Another Agent Kit mutation is active for HomeRoot:$UserHome" }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

function Exit-AgentKitMutex {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Invoke-ReleaseMutation {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [Parameter(Mandatory = $true)][string]$ApprovedDigest,
        [Parameter(Mandatory = $true)][string]$RequestedMode,
        [switch]$PermitDirty,
        [string]$InjectedFault
    )
    if (-not $ApproveGlobalHomeWrite) { throw "$RequestedMode requires -ApproveGlobalHomeWrite" }
    if ([string]::IsNullOrWhiteSpace($ApprovedDigest) -or [string]$Plan.planDigest -cne $ApprovedDigest) { throw "$RequestedMode PlanDigest does not match the current Check" }
    if ([string]$Plan.status -eq 'Conflict') { throw "$RequestedMode cannot proceed from Conflict" }
    if ($RequestedMode -eq 'Install' -and [string]$Plan.status -eq 'Updatable') { throw 'An active release exists; use -Mode Update' }
    if ([string]$Plan.status -eq 'Healthy') { return [pscustomobject][ordered]@{ schemaVersion = 1; mode = $RequestedMode; status = 'NoChange'; releaseId = $Plan.releaseId; planDigest = $Plan.planDigest; backupId = $null; exitCode = 0 } }

    $backupId = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $transactionRoot = Join-Path $KitRoot "backups\$backupId"
    $transactionPath = Join-Path $transactionRoot 'transaction.json'
    $transaction = [pscustomobject][ordered]@{
        schemaVersion = 1; backupId = $backupId; status = 'Executing'; mode = $RequestedMode
        releaseId = $Plan.releaseId; planDigest = $Plan.planDigest; manifestSha256 = $Plan.manifestSha256
        homeRoot = $UserHome; kitRoot = $KitRoot; previousActiveJson = $null; previousActiveJsonExisted = $false
        releaseCopied = $false; active = $null; targets = @(); error = $null; restoredPlanDigest = $null
    }
    Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $transactionRoot -Label 'Transaction root'
    $null = New-Item -ItemType Directory -Path $transactionRoot -Force
    $activeJsonPath = Join-Path $KitRoot 'active.json'
    if ([IO.File]::Exists($activeJsonPath)) {
        $transaction.previousActiveJsonExisted = $true
        $transaction.previousActiveJson = [Convert]::ToBase64String([IO.File]::ReadAllBytes($activeJsonPath))
    }
    Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot

    try {
        $transaction.releaseCopied = Copy-VerifiedRelease -Plan $Plan -KitRoot $KitRoot -PermitDirty:$PermitDirty
        Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
        if ($InjectedFault -eq 'AfterReleaseCopy') { throw 'Injected test fault after release copy' }

        $processed = 0
        foreach ($target in @($Plan.targets | Where-Object { $_.deployment -eq 'Junction' })) {
            $item = [pscustomobject][ordered]@{
                name = [string]$target.name; path = [string]$target.path; newTarget = [string]$target.source
                newIdentity = $null; priorTarget = [string]$target.currentTarget; priorIdentity = [string]$target.currentIdentity
                priorBackupPath = Join-Path $transactionRoot "items\$($target.name)"; originalKind = if ($target.state -eq 'Missing') { 'Missing' } else { 'Junction' }
                changed = $false
            }
            $transaction.targets += $item
            Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
            if ([string]$target.action -eq 'None') { continue }
            $staging = Join-Path $transactionRoot "staging\$($target.name)"
            $item.newIdentity = New-OwnedJunction -Path $staging -Target ([string]$target.source) -AllowedRoot $KitRoot
            Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
            if ([string]$target.action -eq 'ReplaceOwnedJunction') {
                Move-OwnedJunction -Source ([string]$target.path) -Destination ([string]$item.priorBackupPath) -Target ([string]$target.currentTarget) -Identity ([string]$target.currentIdentity) -SourceRoot $UserHome -DestinationRoot $KitRoot
            }
            Move-OwnedJunction -Source $staging -Destination ([string]$target.path) -Target ([string]$target.source) -Identity ([string]$item.newIdentity) -SourceRoot $KitRoot -DestinationRoot $UserHome
            $item.changed = $true
            Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
            $processed++
            if ($InjectedFault -eq 'AfterFirstTarget' -and $processed -eq 1) { throw 'Injected test fault after first target' }
        }

        $activeItem = [pscustomobject][ordered]@{
            path = [string]$Plan.activePath; newTarget = [string]$Plan.releaseRoot; newIdentity = $null
            priorTarget = [string]$Plan.activeTarget; priorIdentity = [string]$Plan.activeIdentity
            priorBackupPath = Join-Path $transactionRoot 'items\Active'; originalKind = if ([string]::IsNullOrWhiteSpace([string]$Plan.activeTarget)) { 'Missing' } else { 'Junction' }
            changed = $false
        }
        $transaction.active = $activeItem
        if ([string]$Plan.activeAction -ne 'None') {
            $activeStaging = Join-Path $transactionRoot 'staging\Active'
            $activeItem.newIdentity = New-OwnedJunction -Path $activeStaging -Target ([string]$Plan.releaseRoot) -AllowedRoot $KitRoot
            if ([string]$Plan.activeAction -eq 'ReplaceOwnedJunction') {
                Move-OwnedJunction -Source ([string]$Plan.activePath) -Destination ([string]$activeItem.priorBackupPath) -Target ([string]$Plan.activeTarget) -Identity ([string]$Plan.activeIdentity) -SourceRoot $KitRoot -DestinationRoot $KitRoot
            }
            Move-OwnedJunction -Source $activeStaging -Destination ([string]$Plan.activePath) -Target ([string]$Plan.releaseRoot) -Identity ([string]$activeItem.newIdentity) -SourceRoot $KitRoot -DestinationRoot $KitRoot
            $activeItem.changed = $true
        }
        Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
        if ($InjectedFault -eq 'AfterActive') { throw 'Injected test fault after active pointer' }

        $activeState = [pscustomobject][ordered]@{
            schemaVersion = 1; releaseId = $Plan.releaseId; gitCommit = $Plan.gitCommit; catalogDigest = $Plan.catalogDigest
            manifestSha256 = $Plan.manifestSha256; backupId = $backupId; targets = @(Get-SelectedTargets -Selection $Targets)
        }
        Write-JsonAtomic -Path $activeJsonPath -Value $activeState -AllowedRoot $KitRoot
        $transaction.status = 'Committed'
        Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = $RequestedMode; status = 'Committed'; releaseId = $Plan.releaseId; planDigest = $Plan.planDigest; backupId = $backupId; transactionPath = $transactionPath; exitCode = 0 }
    }
    catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        try {
            if ($null -ne $transaction.active -and [bool]$transaction.active.changed) {
                Remove-OwnedJunction -Path ([string]$transaction.active.path) -Target ([string]$transaction.active.newTarget) -Identity ([string]$transaction.active.newIdentity) -AllowedRoot $KitRoot
                if ([string]$transaction.active.originalKind -eq 'Junction') {
                    Move-OwnedJunction -Source ([string]$transaction.active.priorBackupPath) -Destination ([string]$transaction.active.path) -Target ([string]$transaction.active.priorTarget) -Identity ([string]$transaction.active.priorIdentity) -SourceRoot $KitRoot -DestinationRoot $KitRoot
                }
            }
        } catch { $rollbackErrors += $_.Exception.Message }
        $changedTargets = @($transaction.targets | Where-Object { [bool]$_.changed })
        [array]::Reverse($changedTargets)
        foreach ($item in $changedTargets) {
            try {
                Remove-OwnedJunction -Path ([string]$item.path) -Target ([string]$item.newTarget) -Identity ([string]$item.newIdentity) -AllowedRoot $UserHome
                if ([string]$item.originalKind -eq 'Junction') {
                    Move-OwnedJunction -Source ([string]$item.priorBackupPath) -Destination ([string]$item.path) -Target ([string]$item.priorTarget) -Identity ([string]$item.priorIdentity) -SourceRoot $KitRoot -DestinationRoot $UserHome
                }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        try {
            Assert-SafeFilePath -AllowedRoot $KitRoot -Candidate $activeJsonPath -Label 'Active release state'
            if ([bool]$transaction.previousActiveJsonExisted) { [IO.File]::WriteAllBytes($activeJsonPath, [Convert]::FromBase64String([string]$transaction.previousActiveJson)) }
            elseif ([IO.File]::Exists($activeJsonPath)) { [IO.File]::Delete($activeJsonPath) }
        } catch { $rollbackErrors += $_.Exception.Message }
        $transaction.error = $failure
        $transaction.status = if ($rollbackErrors.Count) { 'RecoveryRequired' } else { 'RolledBack' }
        Write-JsonAtomic -Path $transactionPath -Value $transaction -AllowedRoot $KitRoot
        if ($rollbackErrors.Count) { throw "$failure; rollback failed: $([string]::Join('; ', $rollbackErrors)); backupId=$backupId" }
        throw "$failure; mutation rolled back; backupId=$backupId"
    }
}

function Get-RestoreEntryState {
    param([Parameter(Mandatory = $true)]$Item)
    $entry = Get-PathEntryInfo -Path ([string]$Item.path)
    $newTarget = Get-NormalizedFullPath -Path ([string]$Item.newTarget)
    if ($entry.kind -eq 'Junction' -and [string]$entry.identity -ceq [string]$Item.newIdentity -and [string]::Equals([string]$entry.target, $newTarget, [StringComparison]::OrdinalIgnoreCase)) {
        if ([string]$Item.originalKind -eq 'Junction') {
            $backup = Get-PathEntryInfo -Path ([string]$Item.priorBackupPath)
            if ($backup.kind -ne 'Junction' -or [string]$backup.identity -cne [string]$Item.priorIdentity -or -not [string]::Equals([string]$backup.target, (Get-NormalizedFullPath -Path ([string]$Item.priorTarget)), [StringComparison]::OrdinalIgnoreCase)) { return 'Conflict' }
        }
        return 'Installed'
    }
    if ([string]$Item.originalKind -eq 'Missing' -and $entry.kind -eq 'Missing') { return 'Restored' }
    if ([string]$Item.originalKind -eq 'Junction') {
        $priorTarget = Get-NormalizedFullPath -Path ([string]$Item.priorTarget)
        if ($entry.kind -eq 'Junction' -and [string]$entry.identity -ceq [string]$Item.priorIdentity -and [string]::Equals([string]$entry.target, $priorTarget, [StringComparison]::OrdinalIgnoreCase)) { return 'Restored' }
        $backup = Get-PathEntryInfo -Path ([string]$Item.priorBackupPath)
        if ($entry.kind -eq 'Missing' -and $backup.kind -eq 'Junction' -and [string]$backup.identity -ceq [string]$Item.priorIdentity -and [string]::Equals([string]$backup.target, $priorTarget, [StringComparison]::OrdinalIgnoreCase)) { return 'Recoverable' }
    }
    return 'Conflict'
}

function Get-RestorePlan {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [Parameter(Mandatory = $true)][string]$RequestedBackupId
    )
    if ($RequestedBackupId -notmatch '^\d{8}-\d{9}-[a-f0-9]{8}$') { throw 'BackupId format is invalid; latest and path traversal are not supported' }
    $transactionPath = Join-Path $KitRoot "backups\$RequestedBackupId\transaction.json"
    $transaction = Read-JsonFile -Path $transactionPath -Label 'Agent Kit transaction' -AllowedRoot $KitRoot
    if ([int]$transaction.schemaVersion -ne 1 -or [string]$transaction.backupId -cne $RequestedBackupId) { throw 'Agent Kit transaction identity mismatch' }
    if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$transaction.homeRoot)), $UserHome, [StringComparison]::OrdinalIgnoreCase)) { throw 'Transaction HomeRoot mismatch' }
    if ([string]$transaction.status -eq 'Restored') {
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Check'; status = 'AlreadyRestored'; backupId = $RequestedBackupId; transactionPath = $transactionPath; planDigest = Get-Sha256Text -Text "restored|$RequestedBackupId|$($transaction.planDigest)"; transaction = $transaction; errors = @(); exitCode = 0 }
    }
    if ([string]$transaction.status -notin @('Committed', 'Restoring')) { throw "Transaction is not restorable: $($transaction.status)" }
    $errors = @()
    foreach ($item in @($transaction.targets | Where-Object { [bool]$_.changed })) {
        if ((Get-RestoreEntryState -Item $item) -eq 'Conflict') { $errors += "Restore target ownership changed: $($item.name)" }
    }
    if ($null -ne $transaction.active -and [bool]$transaction.active.changed) {
        if ((Get-RestoreEntryState -Item $transaction.active) -eq 'Conflict') { $errors += 'Restore active pointer ownership changed' }
    }
    $digestLines = @("restore=$RequestedBackupId", "transaction=$($transaction.planDigest)")
    foreach ($item in @($transaction.targets)) { $digestLines += "target|$($item.name)|$($item.path)|$($item.newIdentity)|$($item.priorIdentity)" }
    $planDigest = Get-Sha256Text -Text ([string]::Join("`n", $digestLines))
    return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Check'; status = if ($errors.Count) { 'Conflict' } else { 'RestoreReady' }; backupId = $RequestedBackupId; transactionPath = $transactionPath; planDigest = $planDigest; transaction = $transaction; errors = $errors; exitCode = if ($errors.Count) { 3 } else { 2 } }
}

function Invoke-AgentKitRestore {
    param(
        [Parameter(Mandatory = $true)]$RestorePlan,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [Parameter(Mandatory = $true)][string]$ApprovedDigest,
        [string]$InjectedFault
    )
    if (-not $ApproveGlobalHomeWrite) { throw 'Restore requires -ApproveGlobalHomeWrite' }
    if ([string]::IsNullOrWhiteSpace($ApprovedDigest) -or [string]$RestorePlan.planDigest -cne $ApprovedDigest) { throw 'Restore PlanDigest does not match the current Check' }
    if ([string]$RestorePlan.status -eq 'AlreadyRestored') { return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; status = 'NoChange'; backupId = $RestorePlan.backupId; planDigest = $RestorePlan.planDigest; exitCode = 0 } }
    if ([string]$RestorePlan.status -ne 'RestoreReady') { throw 'Restore cannot proceed from Conflict' }
    $transaction = $RestorePlan.transaction
    if ($null -eq $transaction.PSObject.Properties['restoreProgress']) {
        $transaction | Add-Member -NotePropertyName restoreProgress -NotePropertyValue ([pscustomobject][ordered]@{ targets = @(); active = $false; activeJson = $false })
    }
    $transaction.status = 'Restoring'
    Write-JsonAtomic -Path ([string]$RestorePlan.transactionPath) -Value $transaction -AllowedRoot $KitRoot
    $changedTargets = @($transaction.targets | Where-Object { [bool]$_.changed })
    [array]::Reverse($changedTargets)
    $processed = 0
    foreach ($item in $changedTargets) {
        $state = Get-RestoreEntryState -Item $item
        if ($state -eq 'Conflict') { throw "Restore target ownership changed: $($item.name)" }
        if ($state -eq 'Installed') { Remove-OwnedJunction -Path ([string]$item.path) -Target ([string]$item.newTarget) -Identity ([string]$item.newIdentity) -AllowedRoot $UserHome }
        if ($state -in @('Installed', 'Recoverable') -and [string]$item.originalKind -eq 'Junction') {
            Move-OwnedJunction -Source ([string]$item.priorBackupPath) -Destination ([string]$item.path) -Target ([string]$item.priorTarget) -Identity ([string]$item.priorIdentity) -SourceRoot $KitRoot -DestinationRoot $UserHome
        }
        if (@($transaction.restoreProgress.targets) -notcontains [string]$item.name) { $transaction.restoreProgress.targets += [string]$item.name }
        Write-JsonAtomic -Path ([string]$RestorePlan.transactionPath) -Value $transaction -AllowedRoot $KitRoot
        $processed++
        if ($InjectedFault -eq 'AfterFirstRestoreTarget' -and $processed -eq 1) { throw 'Injected test fault after first restore target' }
    }
    if ($null -ne $transaction.active -and [bool]$transaction.active.changed) {
        $activeState = Get-RestoreEntryState -Item $transaction.active
        if ($activeState -eq 'Conflict') { throw 'Restore active pointer ownership changed' }
        if ($activeState -eq 'Installed') { Remove-OwnedJunction -Path ([string]$transaction.active.path) -Target ([string]$transaction.active.newTarget) -Identity ([string]$transaction.active.newIdentity) -AllowedRoot $KitRoot }
        if ($activeState -in @('Installed', 'Recoverable') -and [string]$transaction.active.originalKind -eq 'Junction') {
            Move-OwnedJunction -Source ([string]$transaction.active.priorBackupPath) -Destination ([string]$transaction.active.path) -Target ([string]$transaction.active.priorTarget) -Identity ([string]$transaction.active.priorIdentity) -SourceRoot $KitRoot -DestinationRoot $KitRoot
        }
        $transaction.restoreProgress.active = $true
        Write-JsonAtomic -Path ([string]$RestorePlan.transactionPath) -Value $transaction -AllowedRoot $KitRoot
    }
    $activeJsonPath = Join-Path $KitRoot 'active.json'
    Assert-SafeFilePath -AllowedRoot $KitRoot -Candidate $activeJsonPath -Label 'Active release state'
    if ([bool]$transaction.previousActiveJsonExisted) { [IO.File]::WriteAllBytes($activeJsonPath, [Convert]::FromBase64String([string]$transaction.previousActiveJson)) }
    elseif ([IO.File]::Exists($activeJsonPath)) { [IO.File]::Delete($activeJsonPath) }
    $transaction.restoreProgress.activeJson = $true
    $transaction.status = 'Restored'
    if ($null -eq $transaction.PSObject.Properties['restoredPlanDigest']) { $transaction | Add-Member -NotePropertyName restoredPlanDigest -NotePropertyValue $null }
    $transaction.restoredPlanDigest = $RestorePlan.planDigest
    Write-JsonAtomic -Path ([string]$RestorePlan.transactionPath) -Value $transaction -AllowedRoot $KitRoot
    return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; status = 'Restored'; backupId = $RestorePlan.backupId; planDigest = $RestorePlan.planDigest; exitCode = 0 }
}

function Write-HumanResult {
    param([Parameter(Mandatory = $true)]$Result)
    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['releaseId']) { Write-Output "Release: $($Result.releaseId)" }
    if ($Result.PSObject.Properties['backupId'] -and $null -ne $Result.backupId) { Write-Output "BackupId: $($Result.backupId)" }
    if ($Result.PSObject.Properties['planDigest']) { Write-Output "PlanDigest: $($Result.planDigest)" }
    if ($Result.PSObject.Properties['errors']) { foreach ($message in @($Result.errors)) { Write-Output "ERROR: $message" } }
}

$exitCode = 1
$mutex = $null
try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    $RepositoryRoot = Get-NormalizedFullPath -Path $RepositoryRoot
    if ([IO.File]::Exists((Join-Path $RepositoryRoot '.vhk\HARD_STOP'))) { throw '.vhk/HARD_STOP detected' }
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
    $HomeRoot = Get-NormalizedFullPath -Path $HomeRoot
    if ([string]::Equals($HomeRoot, [IO.Path]::GetPathRoot($HomeRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'HomeRoot cannot be a volume root' }
    $kitRoot = Join-Path $HomeRoot '.yohan-agent-kit'

    if ($AllowDirtyArtifact -or -not [string]::IsNullOrWhiteSpace($TestFault)) {
        $testRoot = Join-Path $RepositoryRoot 'tests\.work'
        $temporaryTestRoot = Join-Path ([IO.Path]::GetTempPath()) 'yohan-agent-kit-tests'
        if (-not (Test-PathWithin -Root $testRoot -Candidate $HomeRoot) -and -not (Test-PathWithin -Root $temporaryTestRoot -Candidate $HomeRoot)) { throw 'Test-only switches require HomeRoot under tests/.work or the bounded Agent Kit temp root' }
    }

    if ($Mode -eq 'Restore' -or ($Mode -eq 'Check' -and -not [string]::IsNullOrWhiteSpace($BackupId))) {
        if ([string]::IsNullOrWhiteSpace($BackupId)) { throw 'Restore requires an exact -BackupId' }
        $result = Get-RestorePlan -UserHome $HomeRoot -KitRoot $kitRoot -RequestedBackupId $BackupId
        if ($Mode -eq 'Restore') {
            $mutex = Enter-AgentKitMutex -UserHome $HomeRoot
            try { $result = Invoke-AgentKitRestore -RestorePlan $result -UserHome $HomeRoot -KitRoot $kitRoot -ApprovedDigest $PlanDigest -InjectedFault $TestFault }
            finally { Exit-AgentKitMutex -Mutex $mutex; $mutex = $null }
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Release)) { throw "$Mode requires -Release" }
        if ($Release -notmatch '^[a-z0-9][a-z0-9._-]{0,127}$' -or $Release.Contains('..')) { throw 'Release ID is invalid' }
        if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = Join-Path $RepositoryRoot "dist\releases\$Release" }
        $plan = Get-ReleasePlan -UserHome $HomeRoot -KitRoot $kitRoot -RequestedRelease $Release -SourceArtifact $ArtifactRoot -Selection $Targets -PermitDirty:$AllowDirtyArtifact
        if ($Mode -eq 'Check') { $result = $plan }
        else {
            $mutex = Enter-AgentKitMutex -UserHome $HomeRoot
            try {
                $plan = Get-ReleasePlan -UserHome $HomeRoot -KitRoot $kitRoot -RequestedRelease $Release -SourceArtifact $ArtifactRoot -Selection $Targets -PermitDirty:$AllowDirtyArtifact
                $result = Invoke-ReleaseMutation -Plan $plan -UserHome $HomeRoot -KitRoot $kitRoot -ApprovedDigest $PlanDigest -RequestedMode $Mode -PermitDirty:$AllowDirtyArtifact -InjectedFault $TestFault
            }
            finally { Exit-AgentKitMutex -Mutex $mutex; $mutex = $null }
        }
    }
    $exitCode = [int]$result.exitCode
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $result) }
    else { Write-HumanResult -Result $result }
}
catch {
    $failure = [pscustomobject][ordered]@{ schemaVersion = 1; mode = $Mode; status = 'Error'; errors = @($_.Exception.Message); exitCode = 1 }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $failure) }
    else { Write-HumanResult -Result $failure }
    $exitCode = 1
}
finally { if ($null -ne $mutex) { Exit-AgentKitMutex -Mutex $mutex } }
exit $exitCode
