#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Install', 'Restore')]
    [string]$Mode = 'Check',

    [ValidateSet('All', 'adr-cycle', 'design-team', 'design-to-html', 'goal-cycle', 'agent-team-operations', 'restart-safe-handoff', 'runtime-incident-investigator', 'supervised-session-conductor')]
    [string]$Skill = 'All',

    [string]$RepositoryRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [string]$PlanDigest,

    [string]$BackupId,

    [switch]$ApproveGlobalHomeWrite,

    [switch]$IncludeAgyCliFallback,

    [string]$AgyEvidenceDirectory,

    [string]$AgyCurrentVersion
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

    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedCandidate = Get-NormalizedFullPath -Path $Candidate
    if ([string]::Equals($normalizedRoot, $normalizedCandidate, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    return $normalizedCandidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-PathWithin -Root $Root -Candidate $Candidate)) {
        throw "$Label escapes its allowed root: $Candidate"
    }
}

function Assert-NoReparseAncestors {
    param(
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [switch]$IncludeLeaf
    )

    $root = Get-NormalizedFullPath -Path $AllowedRoot
    $full = Get-NormalizedFullPath -Path $Candidate
    Assert-PathWithin -Root $root -Candidate $full -Label 'Reparse-point check'

    if ([IO.Directory]::Exists($root)) {
        $rootEntry = Get-Item -LiteralPath $root -Force
        if (($rootEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Allowed root is a reparse point: $root"
        }
        if (-not $rootEntry.PSIsContainer) { throw "Allowed root is not a directory: $root" }
    }

    $relative = $full.Substring($root.Length).TrimStart('\', '/')
    $segments = @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $limit = if ($IncludeLeaf) { $segments.Count } else { [Math]::Max(0, $segments.Count - 1) }
    $current = $root

    for ($index = 0; $index -lt $limit; $index++) {
        $parent = $current
        $leaf = $segments[$index]
        if (-not [IO.Directory]::Exists($parent)) { break }
        $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf })
        if ($entries.Count -eq 0) { break }
        if ($entries.Count -gt 1) { throw "Case-colliding ancestor entries exist under: $parent" }
        $entry = $entries[0]
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Destination ancestor is a reparse point: $($entry.FullName)"
        }
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
    Assert-NoReparseAncestors -AllowedRoot $AllowedRoot -Candidate $Candidate -IncludeLeaf:$IncludeLeaf
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
    $leaf = Split-Path -Leaf $full
    if (-not [IO.Directory]::Exists($parent)) { return }
    $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf })
    if ($entries.Count -gt 1) { throw "Case-colliding file entries exist under: $parent" }
    if ($entries.Count -eq 0) { return }
    $entry = $entries[0]
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label is a reparse point: $full"
    }
    if ($entry.PSIsContainer) { throw "$Label is a directory: $full" }
}

function Get-RelativePathPortable {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedPath = Get-NormalizedFullPath -Path $Path
    Assert-PathWithin -Root $normalizedRoot -Candidate $normalizedPath -Label 'Relative path'
    if ([string]::Equals($normalizedRoot, $normalizedPath, [StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    return $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function ConvertTo-AsciiJson {
    param([Parameter(Mandatory = $true)]$Value)

    $json = [string]($Value | ConvertTo-Json -Depth 16)
    return [regex]::Replace($json, '[^\x00-\x7F]', {
        param($Match)
        return ('\u{0:x4}' -f [int][char]$Match.Value)
    })
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $json = ConvertTo-AsciiJson -Value $Value
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $replacementBackupPath = "$Path.$([Guid]::NewGuid().ToString('N')).previous"
    [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    try {
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temporaryPath, $Path, $replacementBackupPath, $true)
            [IO.File]::Delete($replacementBackupPath)
        }
        else {
            [IO.File]::Move($temporaryPath, $Path)
        }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
    }
}

function Get-DirectoryManifest {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $root = Get-NormalizedFullPath -Path $Directory
    if (-not [IO.Directory]::Exists($root)) {
        throw "Manifest directory does not exist: $root"
    }
    $rootEntry = Get-Item -LiteralPath $root -Force
    if (($rootEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Manifest root cannot be a reparse point: $root"
    }

    $reparseDirectories = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if ($reparseDirectories.Count -gt 0) {
        throw "Manifest directory contains a nested reparse point: $($reparseDirectories[0].FullName)"
    }

    $seen = @{}
    $rows = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Manifest directory contains a file reparse point: $($file.FullName)"
        }
        $relative = Get-RelativePathPortable -Root $root -Path $file.FullName
        $caseKey = $relative.ToLowerInvariant()
        if ($seen.ContainsKey($caseKey) -and $seen[$caseKey] -cne $relative) {
            throw "Manifest contains a case-colliding path: $relative and $($seen[$caseKey])"
        }
        $seen[$caseKey] = $relative
        $rows += [pscustomobject][ordered]@{
            path = $relative
            bytes = [int64]$file.Length
            sha256 = Get-Sha256File -Path $file.FullName
        }
    }

    $rows = @($rows | Sort-Object -Property @{ Expression = { $_.path.ToLowerInvariant() } }, @{ Expression = { $_.path } })
    $digestInput = [string]::Join("`n", @($rows | ForEach-Object { "$($_.path)`0$($_.bytes)`0$($_.sha256)" }))
    return [pscustomobject][ordered]@{
        files = $rows
        digest = Get-Sha256Text -Text $digestInput
    }
}

function Compare-DirectoryManifest {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual
    )

    $expectedMap = @{}
    foreach ($row in @($Expected.files)) { $expectedMap[[string]$row.path] = $row }
    $actualMap = @{}
    foreach ($row in @($Actual.files)) { $actualMap[[string]$row.path] = $row }
    $differences = @()

    foreach ($path in @($expectedMap.Keys | Sort-Object)) {
        if (-not $actualMap.ContainsKey($path)) {
            $differences += "Missing:$path"
            continue
        }
        $expectedRow = $expectedMap[$path]
        $actualRow = $actualMap[$path]
        if ([int64]$expectedRow.bytes -ne [int64]$actualRow.bytes -or
            -not [string]::Equals([string]$expectedRow.sha256, [string]$actualRow.sha256, [StringComparison]::OrdinalIgnoreCase)) {
            $differences += "Changed:$path"
        }
    }
    foreach ($path in @($actualMap.Keys | Sort-Object)) {
        if (-not $expectedMap.ContainsKey($path)) {
            $differences += "Added:$path"
        }
    }

    return [pscustomobject][ordered]@{
        equal = ($differences.Count -eq 0)
        differences = $differences
    }
}

function Test-SkillFrontmatter {
    param(
        [Parameter(Mandatory = $true)][string]$SkillFile,
        [Parameter(Mandatory = $true)][string]$ExpectedName
    )

    $text = [IO.File]::ReadAllText($SkillFile, [Text.Encoding]::UTF8)
    $lines = [regex]::Split($text, "\r?\n")
    $errors = @()
    if ($lines.Count -lt 4 -or $lines[0] -cne '---') {
        return @('SKILL.md frontmatter opening delimiter is missing')
    }
    $end = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -cne '---') { continue }
        $end = $index
        break
    }
    if ($end -lt 0) {
        return @('SKILL.md frontmatter closing delimiter is missing')
    }

    $keys = @{}
    for ($index = 1; $index -lt $end; $index++) {
        if ($lines[$index] -match '^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$') {
            $key = [string]$Matches[1]
            if ($keys.ContainsKey($key)) { $errors += "Duplicate frontmatter key:$key" }
            $keys[$key] = [string]$Matches[2]
        }
    }
    foreach ($key in @($keys.Keys)) {
        if ($key -notin @('name', 'description')) { $errors += "Unsupported frontmatter key:$key" }
    }
    if (-not $keys.ContainsKey('name')) { $errors += 'Missing frontmatter key:name' }
    if (-not $keys.ContainsKey('description')) { $errors += 'Missing frontmatter key:description' }
    if ($keys.ContainsKey('name')) {
        $actualName = ([string]$keys['name']).Trim().Trim('"').Trim("'")
        if ($actualName -cne $ExpectedName) { $errors += "Frontmatter name mismatch:$actualName" }
    }
    return $errors
}

function Get-AbsoluteReferenceFindings {
    param([Parameter(Mandatory = $true)][string]$SkillDirectory)

    $findings = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $SkillDirectory -File -Recurse -Force | Where-Object {
        $_.Extension -in @('.md', '.yaml', '.yml', '.json')
    })) {
        foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern '(?i)(?:file:///|[A-Z]:[\\/])')) {
            $relative = Get-RelativePathPortable -Root $SkillDirectory -Path $file.FullName
            $findings += "${relative}:$($match.LineNumber)"
        }
    }
    return $findings
}

function Get-GitExecutable {
    $candidates = @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)
    foreach ($candidate in $candidates) {
        $source = [string]$candidate.Source
        if (-not [string]::IsNullOrWhiteSpace($source) -and [IO.File]::Exists($source)) {
            return $source
        }
    }
    throw 'git.exe is not installed or is not available on PATH'
}

function Get-RepositoryCommit {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $gitExecutable = Get-GitExecutable
    $output = @(& $gitExecutable -C $RepoRoot rev-parse HEAD 2>&1)
    $commit = [string]::Join('', @($output | ForEach-Object { ([string]$_).Trim() })).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-fA-F0-9]{40,64}$') {
        throw 'Unable to read canonical repository commit'
    }
    return $commit.ToLowerInvariant()
}

function Test-SourceGitState {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $skillRelative = "skills/$SkillName"
    $baselineRelative = "distribution/manifests/$SkillName.json"
    $errors = @()
    $gitExecutable = $null
    $previousOptionalLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0', 'Process')
        try { $gitExecutable = Get-GitExecutable }
        catch { return @($_.Exception.Message) }
        $inside = & $gitExecutable -C $RepoRoot rev-parse --is-inside-work-tree 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]$inside -notmatch '^true') {
            return @('RepositoryRoot is not a Git worktree')
        }

        $status = @(& $gitExecutable -C $RepoRoot status --porcelain=v1 --untracked-files=all -- $skillRelative $baselineRelative 2>&1)
        if ($LASTEXITCODE -ne 0) { return @('Unable to inspect canonical skill Git state') }
        if ($status.Count -gt 0) { $errors += "Canonical source has uncommitted files:$skillRelative,$baselineRelative" }

        $trackedOutput = @(& $gitExecutable -C $RepoRoot ls-files -- $skillRelative $baselineRelative 2>&1)
        if ($LASTEXITCODE -ne 0) { return @('Unable to enumerate tracked canonical source files') }
        $tracked = @{}
        foreach ($path in $trackedOutput) { $tracked[[string]$path] = $true }

        $stagedOutput = @(& $gitExecutable -C $RepoRoot ls-files --stage -- $skillRelative $baselineRelative 2>&1)
        if ($LASTEXITCODE -ne 0) { return @('Unable to inspect canonical source index blobs') }
        $staged = @{}
        foreach ($line in $stagedOutput) {
            if ([string]$line -notmatch '^[0-9]{6}\s+([a-f0-9]{40,64})\s+0\t(.+)$') {
                $errors += "Unable to parse canonical source index entry:$line"
                continue
            }
            $staged[[string]$Matches[2]] = ([string]$Matches[1]).ToLowerInvariant()
        }

        $actualPaths = @()
        $skillDirectory = Join-Path $RepoRoot ($skillRelative.Replace('/', '\'))
        if ([IO.Directory]::Exists($skillDirectory)) {
            $actualPaths += @(Get-ChildItem -LiteralPath $skillDirectory -File -Recurse -Force | ForEach-Object {
                Get-RelativePathPortable -Root $RepoRoot -Path $_.FullName
            })
        }
        $baselinePath = Join-Path $RepoRoot ($baselineRelative.Replace('/', '\'))
        if ([IO.File]::Exists($baselinePath)) { $actualPaths += $baselineRelative }
        foreach ($path in @($actualPaths | Sort-Object -Unique)) {
            if (-not $tracked.ContainsKey([string]$path)) {
                $errors += "Canonical source contains an untracked or ignored file:$path"
                continue
            }
            if (-not $staged.ContainsKey([string]$path)) {
                $errors += "Canonical source index entry is missing:$path"
                continue
            }
            $absolutePath = Join-Path $RepoRoot ([string]$path).Replace('/', '\')
            $workingBlob = [string](& $gitExecutable -C $RepoRoot hash-object "--path=$path" -- $absolutePath 2>&1)
            if ($LASTEXITCODE -ne 0 -or $workingBlob -notmatch '^[a-f0-9]{40,64}$') {
                $errors += "Unable to hash canonical source file:$path"
                continue
            }
            if ($workingBlob.ToLowerInvariant() -cne [string]$staged[[string]$path]) {
                $errors += "Canonical tracked file differs from Git index:$path"
            }
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $previousOptionalLocks, 'Process')
    }
    return $errors
}

function Get-StrictBooleanProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [bool]) {
        throw "$Label must be a JSON boolean"
    }
    return [bool]$property.Value
}

function Get-OptionalStringProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $null }
    return [string]$property.Value
}

function Enter-HomeMutationMutex {
    param([Parameter(Mandatory = $true)][string]$UserHome)

    $normalizedHome = (Get-NormalizedFullPath -Path $UserHome).ToLowerInvariant()
    $mutexName = "Local\YohanSkillDistribution-$((Get-Sha256Text -Text $normalizedHome).Substring(0, 32))"
    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw "Another skill distribution mutation is active for HomeRoot:$UserHome" }
        return $mutex
    }
    catch {
        $mutex.Dispose()
        throw
    }
}

function Exit-HomeMutationMutex {
    param([Parameter(Mandatory = $true)][Threading.Mutex]$Mutex)

    try { $Mutex.ReleaseMutex() }
    finally { $Mutex.Dispose() }
}

function Get-SourceInfo {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $directory = Join-Path $RepoRoot "skills\$SkillName"
    $baselinePath = Join-Path $RepoRoot "distribution\manifests\$SkillName.json"
    $errors = @()
    $manifest = $null
    $commit = $null

    if (-not [IO.Directory]::Exists($directory)) {
        $errors += "Canonical skill directory is missing:$directory"
    }
    else {
        $skillFile = Join-Path $directory 'SKILL.md'
        if (-not [IO.File]::Exists($skillFile)) {
            $errors += 'Canonical SKILL.md is missing'
        }
        else {
            $errors += @(Test-SkillFrontmatter -SkillFile $skillFile -ExpectedName $SkillName)
        }
        $errors += @(Get-AbsoluteReferenceFindings -SkillDirectory $directory | ForEach-Object { "Absolute reference is not portable:$_" })
        try { $manifest = Get-DirectoryManifest -Directory $directory } catch { $errors += $_.Exception.Message }
    }

    if (-not [IO.File]::Exists($baselinePath)) {
        $errors += "Baseline manifest is missing:$baselinePath"
    }
    elseif ($null -ne $manifest) {
        try {
            $baseline = [string]([IO.File]::ReadAllText($baselinePath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
            if ([int]$baseline.schemaVersion -ne 1 -or [string]$baseline.skill -cne $SkillName) {
                $errors += 'Baseline manifest metadata is invalid'
            }
            $comparison = Compare-DirectoryManifest -Expected $baseline -Actual $manifest
            if (-not $comparison.equal) {
                $errors += @($comparison.differences | ForEach-Object { "Canonical manifest drift:$_" })
            }
            if (-not [string]::Equals([string]$baseline.digest, [string]$manifest.digest, [StringComparison]::OrdinalIgnoreCase)) {
                $errors += 'Canonical manifest digest drift'
            }
        }
        catch {
            $errors += "Unable to read baseline manifest:$($_.Exception.Message)"
        }
    }

    $errors += @(Test-SourceGitState -RepoRoot $RepoRoot -SkillName $SkillName)
    if ($errors.Count -eq 0) {
        try { $commit = Get-RepositoryCommit -RepoRoot $RepoRoot }
        catch { $errors += $_.Exception.Message }
    }
    return [pscustomobject][ordered]@{
        skill = $SkillName
        directory = $directory
        commit = $commit
        manifest = $manifest
        errors = $errors
        valid = ($errors.Count -eq 0)
    }
}

function Get-SealedAdapterInfo {
    param(
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$AdapterKind,
        [Parameter(Mandatory = $true)][string]$DiagnosticLabel,
        [AllowEmptyString()][string]$AgyVersion
    )

    if ([string]::IsNullOrWhiteSpace([string]$Source.commit) -or [string]$Source.commit -notmatch '^[a-fA-F0-9]{40,64}$') {
        throw "Canonical source commit is unavailable:$($Source.skill)"
    }
    if ($PSBoundParameters.ContainsKey('AgyVersion') -and [string]::IsNullOrWhiteSpace($AgyVersion)) { throw "$DiagnosticLabel adapter requires a verified CLI version" }
    $metadataName = '.yohan-adapter.json'
    if (@($Source.manifest.files | Where-Object { [string]$_.path -ieq $metadataName }).Count -gt 0) {
        throw "Canonical source reserves the $DiagnosticLabel adapter metadata path:$metadataName"
    }

    $metadata = [pscustomobject][ordered]@{
        schemaVersion = 1
        adapterKind = $AdapterKind
        skill = [string]$Source.skill
        sourcePath = Get-NormalizedFullPath -Path ([string]$Source.directory)
        sourceCommit = ([string]$Source.commit).ToLowerInvariant()
        sourceDigest = ([string]$Source.manifest.digest).ToUpperInvariant()
    }
    if ($PSBoundParameters.ContainsKey('AgyVersion')) { $metadata | Add-Member -NotePropertyName agyVersion -NotePropertyValue $AgyVersion }
    $metadataText = (ConvertTo-AsciiJson -Value $metadata) + [Environment]::NewLine
    $rows = @($Source.manifest.files | ForEach-Object {
        [pscustomobject][ordered]@{
            path = [string]$_.path
            bytes = [int64]$_.bytes
            sha256 = ([string]$_.sha256).ToUpperInvariant()
        }
    })
    $rows += [pscustomobject][ordered]@{
        path = $metadataName
        bytes = [int64][Text.Encoding]::UTF8.GetByteCount($metadataText)
        sha256 = Get-Sha256Text -Text $metadataText
    }
    $rows = @($rows | Sort-Object -Property @{ Expression = { $_.path.ToLowerInvariant() } }, @{ Expression = { $_.path } })
    $digestInput = [string]::Join("`n", @($rows | ForEach-Object { "$($_.path)`0$($_.bytes)`0$($_.sha256)" }))
    return [pscustomobject][ordered]@{
        metadataName = $metadataName
        metadata = $metadata
        metadataText = $metadataText
        manifest = [pscustomobject][ordered]@{
            files = $rows
            digest = Get-Sha256Text -Text $digestInput
        }
    }
}

function Get-AgyAdapterInfo {
    param(
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$AgyVersion
    )

    return Get-SealedAdapterInfo -Source $Source -AdapterKind 'agy-cli-physical-copy' -AgyVersion $AgyVersion -DiagnosticLabel 'AGY'
}

function New-SealedAdapterDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$DiagnosticLabel
    )

    $destination = Get-NormalizedFullPath -Path $Path
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $destination -Label "$DiagnosticLabel adapter staging directory"
    if ((Get-PathEntryInfo -Path $destination).kind -ne 'Missing') {
        throw "$DiagnosticLabel adapter staging directory already exists:$destination"
    }
    $parent = Split-Path -Parent $destination
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $parent -Label "$DiagnosticLabel adapter staging parent" -IncludeLeaf
    $null = New-Item -ItemType Directory -Path $destination
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $destination -Label "$DiagnosticLabel adapter staging directory" -IncludeLeaf

    foreach ($row in @($Source.manifest.files)) {
        $relative = ([string]$row.path).Replace('/', '\')
        $sourceFile = Join-Path ([string]$Source.directory) $relative
        $destinationFile = Join-Path $destination $relative
        Assert-SafeFilePath -AllowedRoot ([string]$Source.directory) -Candidate $sourceFile -Label "$DiagnosticLabel adapter source file"
        Assert-SafeFilePath -AllowedRoot $destination -Candidate $destinationFile -Label "$DiagnosticLabel adapter destination file"
        $destinationParent = Split-Path -Parent $destinationFile
        if (-not [IO.Directory]::Exists($destinationParent)) { $null = New-Item -ItemType Directory -Path $destinationParent -Force }
        Assert-SafeDestinationPath -AllowedRoot $destination -Candidate $destinationParent -Label "$DiagnosticLabel adapter destination parent" -IncludeLeaf
        [IO.File]::Copy($sourceFile, $destinationFile, $false)
    }
    $metadataPath = Join-Path $destination ([string]$Adapter.metadataName)
    Assert-SafeFilePath -AllowedRoot $destination -Candidate $metadataPath -Label "$DiagnosticLabel adapter metadata file"
    [IO.File]::WriteAllText($metadataPath, [string]$Adapter.metadataText, (New-Object Text.UTF8Encoding($false)))

    $actual = Get-DirectoryManifest -Directory $destination
    $comparison = Compare-DirectoryManifest -Expected $Adapter.manifest -Actual $actual
    if (-not $comparison.equal -or -not [string]::Equals([string]$actual.digest, [string]$Adapter.manifest.digest, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated $DiagnosticLabel adapter verification failed:$([string]::Join(',', @($comparison.differences)))"
    }
}

function New-AgyAdapterDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    New-SealedAdapterDirectory -Path $Path -Source $Source -Adapter $Adapter -AllowedRoot $AllowedRoot -DiagnosticLabel 'AGY'
}

function Get-ClaudeAdapterInfo {
    param([Parameter(Mandatory = $true)]$Source)

    return Get-SealedAdapterInfo -Source $Source -AdapterKind 'claude-code-personal-physical-copy' -DiagnosticLabel 'Claude'
}

function New-ClaudeAdapterDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    New-SealedAdapterDirectory -Path $Path -Source $Source -Adapter $Adapter -AllowedRoot $AllowedRoot -DiagnosticLabel 'Claude'
}

function Get-LinkTargetPath {
    param([Parameter(Mandatory = $true)]$Entry)

    $property = $Entry.PSObject.Properties['Target']
    if ($null -eq $property -or $null -eq $property.Value) { return $null }
    $rawTarget = @($property.Value)[0]
    if ([string]::IsNullOrWhiteSpace([string]$rawTarget)) { return $null }
    $target = [string]$rawTarget
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $Entry.Parent.FullName $target
    }
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
    # fsutil still applies the legacy MAX_PATH limit to ordinary drive paths.
    # Use the Win32 extended-path form so transaction staging remains reliable
    # when the repository or backup identifier makes the junction path long.
    $fileIdPath = if ($fullPath.StartsWith('\\')) {
        '\\?\UNC\' + $fullPath.Substring(2)
    }
    else {
        '\\?\' + $fullPath
    }
    $fileIdOutput = @(& $fsutilPath file queryfileid $fileIdPath 2>&1)
    $fileIdExitCode = $LASTEXITCODE
    $fileIdMatch = [regex]::Match([string]::Join(' ', @($fileIdOutput | ForEach-Object { [string]$_ })), '0x[0-9A-Fa-f]{16,32}')
    if ($fileIdExitCode -ne 0 -or -not $fileIdMatch.Success) {
        throw "Unable to read the junction file ID: $fullPath"
    }

    $identityMaterial = [string]::Join('|', @(
        'junction-v3',
        (Get-NormalizedFullPath -Path $Target).ToLowerInvariant(),
        $fileIdMatch.Value.ToUpperInvariant()
    ))
    return Get-Sha256Text -Text $identityMaterial
}

function Get-PathEntryInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedFullPath -Path $Path
    $parent = Split-Path -Parent $full
    $leaf = Split-Path -Leaf $full
    if (-not [IO.Directory]::Exists($parent)) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; junctionIdentity = $null; manifest = $null }
    }
    $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ceq $leaf })
    if ($entries.Count -eq 0) {
        $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf })
    }
    if ($entries.Count -eq 0) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; junctionIdentity = $null; manifest = $null }
    }
    if ($entries.Count -gt 1) { throw "Multiple case-colliding entries exist at: $full" }
    $entry = $entries[0]
    if (-not $entry.PSIsContainer) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'File'; target = $null; junctionIdentity = $null; manifest = $null }
    }
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $linkType = [string]$entry.PSObject.Properties['LinkType'].Value
        $kind = if ($linkType -eq 'Junction') { 'Junction' } else { 'ReparsePoint' }
        $target = Get-LinkTargetPath -Entry $entry
        $identity = if ($kind -eq 'Junction' -and $null -ne $target) { Get-JunctionIdentity -Entry $entry -Target $target } else { $null }
        return [pscustomobject][ordered]@{ path = $full; kind = $kind; target = $target; junctionIdentity = $identity; manifest = $null }
    }
    return [pscustomobject][ordered]@{ path = $full; kind = 'Directory'; target = $null; junctionIdentity = $null; manifest = Get-DirectoryManifest -Directory $full }
}

function Move-DirectoryExact {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$SourceAllowedRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$DestinationAllowedRoot,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $source = Get-NormalizedFullPath -Path $SourcePath
    $destination = Get-NormalizedFullPath -Path $DestinationPath
    Assert-SafeDestinationPath -AllowedRoot $SourceAllowedRoot -Candidate $source -Label "$Label source" -IncludeLeaf
    Assert-SafeDestinationPath -AllowedRoot $DestinationAllowedRoot -Candidate $destination -Label "$Label destination"
    $sourceEntry = Get-PathEntryInfo -Path $source
    if ($sourceEntry.kind -ne 'Directory') { throw "$Label source is not an ordinary directory: $source" }
    $destinationEntry = Get-PathEntryInfo -Path $destination
    if ($destinationEntry.kind -ne 'Missing') { throw "$Label destination already exists: $destination" }

    try {
        [IO.Directory]::Move($source, $destination)
    }
    catch {
        throw "$Label exact directory move failed: $($_.Exception.Message)"
    }

    Assert-SafeDestinationPath -AllowedRoot $DestinationAllowedRoot -Candidate $destination -Label "$Label destination" -IncludeLeaf
    $movedSource = Get-PathEntryInfo -Path $source
    $movedDestination = Get-PathEntryInfo -Path $destination
    if ($movedSource.kind -ne 'Missing' -or $movedDestination.kind -ne 'Directory') {
        throw "$Label exact directory move verification failed"
    }
}

function Move-OwnedJunctionExact {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$SourceAllowedRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$DestinationAllowedRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentity
    )

    $source = Get-NormalizedFullPath -Path $SourcePath
    $destination = Get-NormalizedFullPath -Path $DestinationPath
    $normalizedTarget = Get-NormalizedFullPath -Path $ExpectedTarget
    Assert-SafeDestinationPath -AllowedRoot $SourceAllowedRoot -Candidate $source -Label 'Staged junction source'
    Assert-SafeDestinationPath -AllowedRoot $DestinationAllowedRoot -Candidate $destination -Label 'Active junction destination'
    $sourceEntry = Get-PathEntryInfo -Path $source
    if ($sourceEntry.kind -ne 'Junction' -or $null -eq $sourceEntry.target -or
        -not [string]::Equals([string]$sourceEntry.target, $normalizedTarget, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$sourceEntry.junctionIdentity -cne $ExpectedIdentity) {
        throw "Staged junction ownership mismatch:$source"
    }
    if ((Get-PathEntryInfo -Path $destination).kind -ne 'Missing') {
        throw "Active junction destination already exists:$destination"
    }

    try { [IO.Directory]::Move($source, $destination) }
    catch { throw "Exact staged junction move failed:$($_.Exception.Message)" }

    $movedSource = Get-PathEntryInfo -Path $source
    $movedDestination = Get-PathEntryInfo -Path $destination
    if ($movedSource.kind -ne 'Missing' -or $movedDestination.kind -ne 'Junction' -or
        $null -eq $movedDestination.target -or
        -not [string]::Equals([string]$movedDestination.target, $normalizedTarget, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$movedDestination.junctionIdentity -cne $ExpectedIdentity) {
        throw "Moved junction verification failed:$destination"
    }
}

function Get-TargetDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][bool]$FallbackEnabled,
        [ValidateSet(3, 4, 5)][int]$ContractVersion = 5
    )

    if ($ContractVersion -eq 3) {
        return @(
            [pscustomobject]@{ role = 'Agents'; category = 'Deploy'; deploymentKind = 'Junction'; path = Join-Path $UserHome ".agents\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'Claude'; category = 'Deploy'; deploymentKind = 'Junction'; path = Join-Path $UserHome ".claude\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'AgyStandard'; category = 'Deploy'; deploymentKind = 'Junction'; path = Join-Path $UserHome ".gemini\config\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'CodexLegacy'; category = 'Migration'; deploymentKind = 'None'; path = Join-Path $UserHome ".codex\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'CursorLegacy'; category = 'Migration'; deploymentKind = 'None'; path = Join-Path $UserHome ".cursor\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'AgyLegacy'; category = 'Migration'; deploymentKind = 'None'; path = Join-Path $UserHome ".gemini\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'AgyCliFallback'; category = 'Fallback'; deploymentKind = 'Junction'; path = Join-Path $UserHome ".gemini\antigravity-cli\skills\$SkillName"; enabled = $FallbackEnabled }
        )
    }

    if ($ContractVersion -eq 4) {
        return @(
            [pscustomobject]@{ role = 'Agents'; category = 'Deploy'; deploymentKind = 'Junction'; adapterKind = $null; path = Join-Path $UserHome ".agents\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'Claude'; category = 'Deploy'; deploymentKind = 'Junction'; adapterKind = $null; path = Join-Path $UserHome ".claude\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'AgyStandard'; category = 'Deploy'; deploymentKind = 'Junction'; adapterKind = $null; path = Join-Path $UserHome ".gemini\config\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'CodexLegacy'; category = 'Migration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".codex\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'CursorLegacy'; category = 'Migration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".cursor\skills\$SkillName"; enabled = $true },
            [pscustomobject]@{ role = 'AgyCliFallback'; category = 'Fallback'; deploymentKind = 'Adapter'; adapterKind = 'agy-cli-physical-copy'; path = Join-Path $UserHome ".gemini\skills\$SkillName"; enabled = $FallbackEnabled },
            [pscustomobject]@{ role = 'AgyCliFallbackLegacy'; category = 'FallbackMigration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".gemini\antigravity-cli\skills\$SkillName"; enabled = $FallbackEnabled }
        )
    }

    return @(
        [pscustomobject]@{ role = 'Agents'; category = 'Deploy'; deploymentKind = 'Junction'; adapterKind = $null; path = Join-Path $UserHome ".agents\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'Claude'; category = 'Deploy'; deploymentKind = 'Adapter'; adapterKind = 'claude-code-personal-physical-copy'; path = Join-Path $UserHome ".claude\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'AgyStandard'; category = 'Deploy'; deploymentKind = 'Junction'; adapterKind = $null; path = Join-Path $UserHome ".gemini\config\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'CodexLegacy'; category = 'Migration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".codex\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'CursorLegacy'; category = 'Migration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".cursor\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'AgyCliFallback'; category = 'Fallback'; deploymentKind = 'Adapter'; adapterKind = 'agy-cli-physical-copy'; path = Join-Path $UserHome ".gemini\skills\$SkillName"; enabled = $FallbackEnabled },
        [pscustomobject]@{ role = 'AgyCliFallbackLegacy'; category = 'FallbackMigration'; deploymentKind = 'None'; adapterKind = $null; path = Join-Path $UserHome ".gemini\antigravity-cli\skills\$SkillName"; enabled = $FallbackEnabled }
    )
}

function Get-AgyCliVersion {
    $agyCommand = Get-Command agy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $agyCommand -or [string]::IsNullOrWhiteSpace([string]$agyCommand.Source)) {
        throw 'agy CLI is not installed or is not available on PATH'
    }
    $versionOutput = @(& $agyCommand.Source --version 2>&1)
    $versionExitCode = $LASTEXITCODE
    $version = [string]::Join('', @($versionOutput | ForEach-Object { ([string]$_).Trim() })).Trim()
    if ($versionExitCode -ne 0 -or $version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
        throw 'Unable to verify the installed agy CLI version'
    }
    return $version
}

function Test-AgyEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$StandardPath,
        [Parameter(Mandatory = $true)][string]$CurrentVersion
    )

    $errors = @()
    $evidencePath = Join-Path $EvidenceDirectory "$($Source.skill).json"
    if (-not [IO.File]::Exists($evidencePath)) {
        return [pscustomobject]@{ valid = $false; errors = @("AGY evidence is missing:$evidencePath"); digest = $null }
    }
    try {
        $evidence = [string]([IO.File]::ReadAllText($evidencePath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
        if ([int]$evidence.schemaVersion -ne 1) { $errors += 'AGY evidence schemaVersion must be 1' }
        if ([string]$evidence.skill -cne [string]$Source.skill) { $errors += 'AGY evidence skill mismatch' }
        if (-not [string]::Equals([string]$evidence.sourceDigest, [string]$Source.manifest.digest, [StringComparison]::OrdinalIgnoreCase)) { $errors += 'AGY evidence source digest mismatch' }
        if ([string]$evidence.host -cne [string]$env:COMPUTERNAME) { $errors += 'AGY evidence host mismatch' }
        if ([string]::IsNullOrWhiteSpace([string]$evidence.agyVersion)) { $errors += 'AGY evidence version is missing' }
        elseif ([string]$evidence.agyVersion -cne $CurrentVersion) { $errors += 'AGY evidence version does not match -AgyCurrentVersion' }
        $newSessionProperty = $evidence.PSObject.Properties['newSession']
        if ($null -eq $newSessionProperty -or $newSessionProperty.Value -isnot [bool]) {
            $errors += 'AGY evidence newSession must be a JSON boolean'
        }
        elseif (-not [bool]$newSessionProperty.Value) { $errors += 'AGY evidence must come from a new session' }
        $standardDiscoveredProperty = $evidence.PSObject.Properties['standardDiscovered']
        if ($null -eq $standardDiscoveredProperty -or $standardDiscoveredProperty.Value -isnot [bool]) {
            $errors += 'AGY evidence standardDiscovered must be a JSON boolean'
        }
        elseif ([bool]$standardDiscoveredProperty.Value) { $errors += 'AGY fallback is forbidden after successful standard discovery' }
        if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$evidence.standardPath)), (Get-NormalizedFullPath -Path $StandardPath), [StringComparison]::OrdinalIgnoreCase)) { $errors += 'AGY evidence standard path mismatch' }
        $parsedTime = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParseExact([string]$evidence.testedAt, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedTime)) {
            $errors += 'AGY evidence testedAt must be an ISO-8601 round-trip timestamp'
        }
        else {
            $now = [DateTimeOffset]::UtcNow
            $testedAt = $parsedTime.ToUniversalTime()
            if ($testedAt -gt $now.AddMinutes(5)) { $errors += 'AGY evidence testedAt is in the future' }
            elseif (($now - $testedAt).TotalHours -gt 24) { $errors += 'AGY evidence is older than 24 hours' }
        }
        return [pscustomobject]@{ valid = ($errors.Count -eq 0); errors = $errors; digest = Get-Sha256File -Path $evidencePath }
    }
    catch {
        return [pscustomobject]@{ valid = $false; errors = @("Unable to read AGY evidence:$($_.Exception.Message)"); digest = $null }
    }
}

function Get-SelectedSkills {
    param([Parameter(Mandatory = $true)][string]$Selection)

    if ($Selection -eq 'All') { return @('adr-cycle', 'design-team', 'design-to-html', 'goal-cycle', 'agent-team-operations', 'restart-safe-handoff', 'runtime-incident-investigator', 'supervised-session-conductor') }
    return @($Selection)
}

function Get-PendingRecoveryIds {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [string]$IgnoreBackupId
    )

    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    if (-not [IO.Directory]::Exists($backupRoot)) { return @() }
    Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $backupRoot -Label 'Recovery backup root' -IncludeLeaf
    $ids = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force)) {
        if (-not [string]::IsNullOrWhiteSpace($IgnoreBackupId) -and $directory.Name -ceq $IgnoreBackupId) { continue }
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $ids += $directory.Name; continue }
        $transactionPath = Join-Path $directory.FullName 'transaction.json'
        if (-not [IO.File]::Exists($transactionPath)) { continue }
        try {
            Assert-SafeFilePath -AllowedRoot $directory.FullName -Candidate $transactionPath -Label 'Recovery transaction file'
            $transaction = [string]([IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
            if ([string]$transaction.status -in @('Executing', 'Restoring', 'RecoveryRequired')) { $ids += $directory.Name }
        }
        catch {
            $ids += $directory.Name
        }
    }
    return @($ids | Sort-Object)
}

function Get-InstallPlan {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$Selection,
        [Parameter(Mandatory = $true)][bool]$FallbackEnabled,
        [string]$EvidenceDirectory,
        [string]$CurrentAgyVersion,
        [string]$IgnoreRecoveryBackupId
    )

    $sources = @()
    $targets = @()
    $errors = @()
    $evidenceDigests = @()
    $verifiedAgyVersion = $CurrentAgyVersion
    $agyVersionReady = -not $FallbackEnabled
    if ($FallbackEnabled) {
        if ([string]::IsNullOrWhiteSpace($CurrentAgyVersion)) {
            $errors += '-AgyCurrentVersion is required for fallback'
        }
        else {
            try {
                $verifiedAgyVersion = Get-AgyCliVersion
                if ([string]$verifiedAgyVersion -cne [string]$CurrentAgyVersion) {
                    $errors += '-AgyCurrentVersion does not match the installed agy CLI'
                }
                else { $agyVersionReady = $true }
            }
            catch { $errors += $_.Exception.Message }
        }
    }
    $recoveryIds = @(Get-PendingRecoveryIds -UserHome $UserHome -IgnoreBackupId $IgnoreRecoveryBackupId)
    if ($recoveryIds.Count -gt 0) { $errors += @($recoveryIds | ForEach-Object { "RecoveryRequired:$_" }) }
    foreach ($skillName in @(Get-SelectedSkills -Selection $Selection)) {
        $source = Get-SourceInfo -RepoRoot $RepoRoot -SkillName $skillName
        $sources += $source
        if (-not $source.valid) {
            $errors += @($source.errors | ForEach-Object { "${skillName}:$_" })
            continue
        }

        $adapters = @{}
        try { $adapters['Claude'] = Get-ClaudeAdapterInfo -Source $source }
        catch { $errors += "${skillName}:$($_.Exception.Message)" }
        if ($FallbackEnabled -and $agyVersionReady) {
            try { $adapters['AgyCliFallback'] = Get-AgyAdapterInfo -Source $source -AgyVersion $verifiedAgyVersion }
            catch { $errors += "${skillName}:$($_.Exception.Message)" }
        }
        $definitions = @(Get-TargetDefinitions -UserHome $UserHome -SkillName $skillName -FallbackEnabled $FallbackEnabled -ContractVersion 5)
        if ($FallbackEnabled) {
            if (-not $agyVersionReady) {
                # The global version error above is sufficient and keeps evidence untrusted.
            }
            elseif ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
                $errors += "${skillName}:AGY evidence directory is required for fallback"
            }
            else {
                $standard = @($definitions | Where-Object { $_.role -eq 'AgyStandard' })[0]
                $evidenceResult = Test-AgyEvidence -EvidenceDirectory $EvidenceDirectory -Source $source -StandardPath $standard.path -CurrentVersion $verifiedAgyVersion
                if (-not $evidenceResult.valid) { $errors += @($evidenceResult.errors | ForEach-Object { "${skillName}:$_" }) }
                elseif ($null -ne $evidenceResult.digest) { $evidenceDigests += "${skillName}:$($evidenceResult.digest)" }
            }
        }

        foreach ($definition in $definitions) {
            Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $definition.path -Label 'Skill target'
            $entryError = $null
            try { $entry = Get-PathEntryInfo -Path $definition.path }
            catch {
                $entryError = $_.Exception.Message
                $entry = [pscustomobject][ordered]@{ path = Get-NormalizedFullPath -Path $definition.path; kind = 'Invalid'; target = $null; junctionIdentity = $null; manifest = $null }
            }
            $deploymentKind = [string]$definition.deploymentKind
            $adapter = if ($deploymentKind -eq 'Adapter' -and $adapters.ContainsKey([string]$definition.role)) { $adapters[[string]$definition.role] } else { $null }
            $expectedManifest = if ($deploymentKind -eq 'Adapter' -and $null -ne $adapter) { $adapter.manifest } else { $source.manifest }
            $action = 'None'
            $reason = ''
            $conflict = $false

            if (-not [string]::IsNullOrWhiteSpace($entryError)) {
                $conflict = $true
                $reason = "Target cannot be inspected:$entryError"
            }
            elseif ($definition.category -in @('Fallback', 'FallbackMigration') -and -not $definition.enabled) {
                if ($entry.kind -ne 'Missing') {
                    $conflict = $true
                    $reason = 'AGY fallback exists without current negative-discovery evidence'
                }
            }
            elseif ($entry.kind -eq 'Missing') {
                if ($deploymentKind -eq 'Adapter') {
                    if ($null -eq $adapter) {
                        $conflict = $true
                        $reason = "$($definition.role) adapter metadata could not be derived"
                    }
                    else {
                        $action = 'CreateAdapter'
                        $reason = "Generated $($definition.role) adapter is missing"
                    }
                }
                elseif ($definition.category -in @('Deploy', 'Fallback')) {
                    $action = 'CreateJunction'
                    $reason = 'Target is missing'
                }
            }
            elseif ($entry.kind -eq 'File') {
                $conflict = $true
                $reason = 'A file blocks the skill directory'
            }
            elseif ($entry.kind -in @('Junction', 'ReparsePoint')) {
                $sameTarget = $null -ne $entry.target -and [string]::Equals([string]$entry.target, [string]$source.directory, [StringComparison]::OrdinalIgnoreCase)
                if (-not $sameTarget -or $entry.kind -ne 'Junction') {
                    $conflict = $true
                    $reason = 'Existing reparse point does not match the canonical source junction'
                }
                elseif ($definition.category -in @('Migration', 'FallbackMigration')) {
                    $action = 'RemoveLegacyJunction'
                    $reason = 'Legacy active duplicate points to the canonical source'
                }
                elseif ($deploymentKind -eq 'Adapter') {
                    if ($null -eq $adapter) {
                        $conflict = $true
                        $reason = "$($definition.role) adapter metadata could not be derived"
                    }
                    else {
                        $action = 'ReplaceJunctionWithAdapter'
                        $reason = "$($definition.role) requires a physical generated adapter"
                    }
                }
                else {
                    $reason = 'Healthy canonical junction'
                }
            }
            elseif ($entry.kind -eq 'Directory') {
                if ($deploymentKind -eq 'Adapter') {
                    if ($null -eq $adapter) {
                        $conflict = $true
                        $reason = "$($definition.role) adapter metadata could not be derived"
                    }
                    else {
                        $adapterComparison = Compare-DirectoryManifest -Expected $adapter.manifest -Actual $entry.manifest
                        if ($adapterComparison.equal) {
                            $reason = "Healthy generated $($definition.role) adapter"
                        }
                        else {
                            $sourceComparison = Compare-DirectoryManifest -Expected $source.manifest -Actual $entry.manifest
                            if ($sourceComparison.equal) {
                                $action = 'BackupAndAdapt'
                                $reason = 'Identical physical copy can be backed up and replaced with a generated adapter'
                            }
                            else {
                                $conflict = $true
                                $reason = "Adapter manifest mismatch:$([string]::Join(',', @($adapterComparison.differences)))"
                            }
                        }
                    }
                }
                else {
                    $comparison = Compare-DirectoryManifest -Expected $source.manifest -Actual $entry.manifest
                    if (-not $comparison.equal) {
                        $conflict = $true
                        $reason = "Manifest mismatch:$([string]::Join(',', @($comparison.differences)))"
                    }
                    elseif ($definition.category -in @('Migration', 'FallbackMigration')) {
                        $action = 'BackupOnly'
                        $reason = 'Identical legacy active duplicate'
                    }
                    else {
                        $action = 'BackupAndLink'
                        $reason = 'Identical directory can be backed up and linked'
                    }
                }
            }
            else {
                $conflict = $true
                $reason = "Unsupported target kind:$($entry.kind)"
            }

            $targets += [pscustomobject][ordered]@{
                skill = $skillName
                role = $definition.role
                category = $definition.category
                deploymentKind = $deploymentKind
                adapterKind = if ($deploymentKind -eq 'Adapter') { [string]$definition.adapterKind } else { $null }
                path = Get-NormalizedFullPath -Path $definition.path
                entryKind = $entry.kind
                currentTarget = $entry.target
                currentJunctionIdentity = $entry.junctionIdentity
                currentDigest = if ($null -ne $entry.manifest) { $entry.manifest.digest } else { $null }
                sourcePath = $source.directory
                sourceDigest = $source.manifest.digest
                sourceCommit = $source.commit
                expectedDigest = if ($null -ne $expectedManifest) { $expectedManifest.digest } else { $null }
                adapterDigest = if ($deploymentKind -eq 'Adapter' -and $null -ne $adapter) { $adapter.manifest.digest } else { $null }
                adapterMetadata = if ($deploymentKind -eq 'Adapter' -and $null -ne $adapter) { $adapter.metadata } else { $null }
                action = $action
                conflict = $conflict
                reason = $reason
            }
            if ($conflict) { $errors += "$skillName/$($definition.role):$reason" }
        }
    }

    $planLines = @('schema=3', 'contract=5', "selection=$Selection", "fallback=$FallbackEnabled", "agyVersion=$verifiedAgyVersion")
    $planLines += @($recoveryIds | ForEach-Object { "recovery|$_" })
    $planLines += @($sources | Sort-Object skill | ForEach-Object { "source|$($_.skill)|$($_.directory)|$($_.commit)|$(if ($null -ne $_.manifest) { $_.manifest.digest } else { 'INVALID' })" })
    $planLines += @($targets | Sort-Object skill, role | ForEach-Object { "target|$($_.skill)|$($_.role)|$($_.deploymentKind)|$($_.adapterKind)|$($_.path)|$($_.sourceCommit)|$($_.sourceDigest)|$($_.entryKind)|$($_.currentTarget)|$($_.currentJunctionIdentity)|$($_.currentDigest)|$($_.expectedDigest)|$($_.action)|$($_.conflict)" })
    $planLines += @($evidenceDigests | Sort-Object | ForEach-Object { "evidence|$_" })
    $digest = Get-Sha256Text -Text ([string]::Join("`n", $planLines))

    $hasInvalidSource = @($sources | Where-Object { -not $_.valid }).Count -gt 0
    $hasConflict = @($targets | Where-Object { $_.conflict }).Count -gt 0 -or $errors.Count -gt 0
    $hasActions = @($targets | Where-Object { $_.action -ne 'None' }).Count -gt 0
    $status = if ($hasInvalidSource) { 'SourceInvalid' } elseif ($recoveryIds.Count -gt 0) { 'RecoveryRequired' } elseif ($hasConflict) { 'Conflict' } elseif ($hasActions) { 'Installable' } else { 'Healthy' }
    $exitCode = if ($status -eq 'Healthy') { 0 } elseif ($status -eq 'Installable') { 2 } else { 3 }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        contractVersion = 5
        mode = 'Check'
        status = $status
        selection = $Selection
        repositoryRoot = $RepoRoot
        homeRoot = $UserHome
        includeAgyCliFallback = $FallbackEnabled
        agyCurrentVersion = $verifiedAgyVersion
        planDigest = $digest
        sources = $sources
        targets = $targets
        errors = $errors
        exitCode = $exitCode
    }
}

function Save-Transaction {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionPath,
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )
    Assert-SafeFilePath -AllowedRoot $AllowedRoot -Candidate $TransactionPath -Label 'Transaction file'
    Write-JsonAtomic -Path $TransactionPath -Value $Transaction
}

function Get-TransactionInstallSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = @(
        "schema=$($Transaction.schemaVersion)",
        "backupId=$($Transaction.backupId)",
        "createdAt=$($Transaction.createdAt)",
        "planDigest=$($Transaction.planDigest)",
        "homeRoot=$($Transaction.homeRoot)",
        "repositoryRoot=$($Transaction.repositoryRoot)",
        "selection=$($Transaction.selection)",
        "fallback=$($Transaction.includeAgyCliFallback)",
        "agyVersion=$($Transaction.agyCurrentVersion)"
    )
    foreach ($item in @($Transaction.items)) {
        if ([int]$Transaction.schemaVersion -eq 3) {
            $lines += "item|$($item.skill)|$($item.role)|$($item.action)|$($item.targetPath)|$($item.sourcePath)|$($item.sourceDigest)|$($item.originalKind)|$($item.originalTarget)|$($item.originalJunctionIdentity)|$($item.originalDigest)|$($item.backupPath)|$($item.junctionStagingPath)"
        }
        elseif ([int]$Transaction.schemaVersion -eq 4) {
            $lines += "item|$($item.skill)|$($item.role)|$($item.deploymentKind)|$($item.action)|$($item.targetPath)|$($item.sourcePath)|$($item.sourceCommit)|$($item.sourceDigest)|$($item.expectedDigest)|$($item.adapterDigest)|$($item.originalKind)|$($item.originalTarget)|$($item.originalJunctionIdentity)|$($item.originalDigest)|$($item.backupPath)|$($item.junctionStagingPath)|$($item.adapterStagingPath)|$($item.adapterRemovalPath)"
        }
        else {
            $lines += "item|$($item.skill)|$($item.role)|$($item.deploymentKind)|$($item.adapterKind)|$($item.action)|$($item.targetPath)|$($item.sourcePath)|$($item.sourceCommit)|$($item.sourceDigest)|$($item.expectedDigest)|$($item.adapterDigest)|$($item.originalKind)|$($item.originalTarget)|$($item.originalJunctionIdentity)|$($item.originalDigest)|$($item.backupPath)|$($item.junctionStagingPath)|$($item.adapterStagingPath)|$($item.adapterRemovalPath)|$($item.preservedJunctionPath)"
        }
    }
    return Get-Sha256Text -Text ([string]::Join("`n", $lines))
}

function Get-TransactionCommitSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = @("installSeal=$($Transaction.installSeal)")
    foreach ($item in @($Transaction.items)) {
        if ([int]$Transaction.schemaVersion -eq 3) {
            $lines += "item|$($item.skill)|$($item.role)|$($item.changed)|$($item.junctionPrepared)|$($item.createdJunction)|$($item.junctionIdentity)"
        }
        elseif ([int]$Transaction.schemaVersion -eq 4) {
            $lines += "item|$($item.skill)|$($item.role)|$($item.changed)|$($item.junctionPrepared)|$($item.createdJunction)|$($item.junctionIdentity)|$($item.adapterPrepared)|$($item.createdAdapter)"
        }
        else {
            $lines += "item|$($item.skill)|$($item.role)|$($item.changed)|$($item.junctionPrepared)|$($item.createdJunction)|$($item.junctionIdentity)|$($item.adapterPrepared)|$($item.createdAdapter)|$($item.junctionPreserved)"
        }
    }
    return Get-Sha256Text -Text ([string]::Join("`n", $lines))
}

function Get-TransactionRecoverySeal {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][ValidateSet('CommittedRestore', 'InstallRollback')][string]$RecoveryKind
    )

    $baseSeal = if ($RecoveryKind -eq 'CommittedRestore') { [string]$Transaction.commitSeal } else { [string]$Transaction.installSeal }
    if ([string]::IsNullOrWhiteSpace($baseSeal)) { throw "Recovery seal base is missing:$RecoveryKind" }
    return Get-Sha256Text -Text "recovery-v1|$RecoveryKind|$baseSeal"
}

function Remove-OwnedJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentity
    )

    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'Owned junction'
    $entry = Get-PathEntryInfo -Path $Path
    if ($entry.kind -eq 'Missing') { return }
    if ($entry.kind -ne 'Junction' -or $null -eq $entry.target -or
        -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $ExpectedTarget), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unowned junction: $Path"
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedIdentity)) { throw "Refusing to remove a junction without its transaction identity: $Path" }
    if ([string]$entry.junctionIdentity -cne $ExpectedIdentity) { throw "Junction transaction identity mismatch: $Path" }
    [IO.Directory]::Delete((Get-NormalizedFullPath -Path $Path), $false)
}

function New-CanonicalJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'New junction'
    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Assert-SafeDestinationPath -AllowedRoot $AllowedRoot -Candidate $Path -Label 'New junction'
    $created = $false
    $createdIdentity = $null
    try {
        $null = New-Item -ItemType Junction -Path $Path -Target $Target
        $created = $true
        $entry = Get-PathEntryInfo -Path $Path
        if ($entry.kind -eq 'Junction' -and [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $Target), [StringComparison]::OrdinalIgnoreCase)) {
            $createdIdentity = [string]$entry.junctionIdentity
        }
        if ([string]::IsNullOrWhiteSpace($createdIdentity)) {
            throw "Junction verification failed: $Path"
        }
        return $createdIdentity
    }
    catch {
        if ($created -and -not [string]::IsNullOrWhiteSpace($createdIdentity)) {
            Remove-OwnedJunction -Path $Path -ExpectedTarget $Target -AllowedRoot $AllowedRoot -ExpectedIdentity $createdIdentity
        }
        throw
    }
}

function Move-OwnedAdapterExact {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$SourceAllowedRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$DestinationAllowedRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedDigest,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $source = Get-NormalizedFullPath -Path $SourcePath
    $destination = Get-NormalizedFullPath -Path $DestinationPath
    Assert-SafeDestinationPath -AllowedRoot $SourceAllowedRoot -Candidate $source -Label "$Label source"
    Assert-SafeDestinationPath -AllowedRoot $DestinationAllowedRoot -Candidate $destination -Label "$Label destination"
    $sourceEntry = Get-PathEntryInfo -Path $source
    $destinationEntry = Get-PathEntryInfo -Path $destination
    if ($sourceEntry.kind -eq 'Missing' -and $destinationEntry.kind -eq 'Directory' -and
        [string]::Equals([string]$destinationEntry.manifest.digest, $ExpectedDigest, [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    if ($sourceEntry.kind -ne 'Directory' -or
        -not [string]::Equals([string]$sourceEntry.manifest.digest, $ExpectedDigest, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label source adapter ownership mismatch:$source"
    }
    if ($destinationEntry.kind -ne 'Missing') { throw "$Label destination is occupied:$destination" }
    $destinationParent = Split-Path -Parent $destination
    if (-not [IO.Directory]::Exists($destinationParent)) { $null = New-Item -ItemType Directory -Path $destinationParent -Force }
    Assert-SafeDestinationPath -AllowedRoot $DestinationAllowedRoot -Candidate $destinationParent -Label "$Label destination parent" -IncludeLeaf
    Move-DirectoryExact -SourcePath $source -SourceAllowedRoot $SourceAllowedRoot -DestinationPath $destination -DestinationAllowedRoot $DestinationAllowedRoot -Label $Label
    $moved = Get-PathEntryInfo -Path $destination
    if ($moved.kind -ne 'Directory' -or -not [string]::Equals([string]$moved.manifest.digest, $ExpectedDigest, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label moved adapter verification failed:$destination"
    }
}

function Invoke-TransactionRollback {
    param(
        [Parameter(Mandatory = $true)]$Transaction,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$TransactionRoot
    )

    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    $items = @($Transaction.items)
    [array]::Reverse($items)
    foreach ($item in $items) {
        $adapterPrepared = $false
        $createdAdapter = $false
        $junctionPreserved = $false
        if ([int]$Transaction.schemaVersion -ge 4) {
            $adapterPrepared = [bool]$item.adapterPrepared
            $createdAdapter = [bool]$item.createdAdapter
        }
        if ([int]$Transaction.schemaVersion -ge 5) { $junctionPreserved = [bool]$item.junctionPreserved }
        if (-not [bool]$item.changed -and -not [bool]$item.junctionPrepared -and -not [bool]$item.createdJunction -and -not $adapterPrepared -and -not $createdAdapter -and -not $junctionPreserved) { continue }
        if ($createdAdapter) {
            Move-OwnedAdapterExact -SourcePath ([string]$item.targetPath) -SourceAllowedRoot $UserHome -DestinationPath ([string]$item.adapterRemovalPath) -DestinationAllowedRoot $TransactionRoot -ExpectedDigest ([string]$item.adapterDigest) -Label 'Rollback installed AGY adapter'
        }
        if ($adapterPrepared) {
            Move-OwnedAdapterExact -SourcePath ([string]$item.adapterStagingPath) -SourceAllowedRoot $TransactionRoot -DestinationPath ([string]$item.adapterRemovalPath) -DestinationAllowedRoot $TransactionRoot -ExpectedDigest ([string]$item.adapterDigest) -Label 'Rollback staged AGY adapter'
        }
        if ([bool]$item.createdJunction) {
            Remove-OwnedJunction -Path ([string]$item.targetPath) -ExpectedTarget ([string]$item.sourcePath) -AllowedRoot $UserHome -ExpectedIdentity ([string]$item.junctionIdentity)
        }
        if ([bool]$item.junctionPrepared) {
            Remove-OwnedJunction -Path ([string]$item.junctionStagingPath) -ExpectedTarget ([string]$item.sourcePath) -AllowedRoot $transactionRoot -ExpectedIdentity ([string]$item.junctionIdentity)
        }
        if ([int]$Transaction.schemaVersion -ge 5 -and [string]$item.action -eq 'ReplaceJunctionWithAdapter') {
            $activeEntry = Get-PathEntryInfo -Path ([string]$item.targetPath)
            $preservedEntry = Get-PathEntryInfo -Path ([string]$item.preservedJunctionPath)
            if ($preservedEntry.kind -eq 'Junction' -and $null -ne $preservedEntry.target -and
                [string]::Equals([string]$preservedEntry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase) -and
                [string]$preservedEntry.junctionIdentity -ceq [string]$item.originalJunctionIdentity) {
                if ($activeEntry.kind -ne 'Missing') { throw "Rollback target is occupied: $($item.targetPath)" }
                Move-OwnedJunctionExact -SourcePath ([string]$item.preservedJunctionPath) -SourceAllowedRoot $TransactionRoot -DestinationPath ([string]$item.targetPath) -DestinationAllowedRoot $UserHome -ExpectedTarget ([string]$item.originalTarget) -ExpectedIdentity ([string]$item.originalJunctionIdentity)
                $item.junctionPreserved = $false
            }
            elseif ($preservedEntry.kind -ne 'Missing') {
                throw "Rollback preserved junction ownership mismatch: $($item.preservedJunctionPath)"
            }
        }
        $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
        if ([string]$item.originalKind -eq 'Directory') {
            if ($entry.kind -eq 'Directory' -and $null -ne $entry.manifest -and
                [string]::Equals([string]$entry.manifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($entry.kind -ne 'Missing') { throw "Rollback target is occupied: $($item.targetPath)" }
            if (-not [IO.Directory]::Exists([string]$item.backupPath)) { throw "Rollback backup is missing: $($item.backupPath)" }
            Assert-SafeDestinationPath -AllowedRoot $backupRoot -Candidate ([string]$item.backupPath) -Label 'Rollback backup' -IncludeLeaf
            $backupManifest = Get-DirectoryManifest -Directory ([string]$item.backupPath)
            if (-not [string]::Equals([string]$backupManifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Rollback backup was modified: $($item.backupPath)"
            }
            Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate ([string]$item.targetPath) -Label 'Rollback target'
            $parent = Split-Path -Parent ([string]$item.targetPath)
            if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
            Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate ([string]$item.targetPath) -Label 'Rollback target'
            Move-DirectoryExact -SourcePath ([string]$item.backupPath) -SourceAllowedRoot $backupRoot -DestinationPath ([string]$item.targetPath) -DestinationAllowedRoot $UserHome -Label 'Rollback'
            $restored = Get-DirectoryManifest -Directory ([string]$item.targetPath)
            if (-not [string]::Equals([string]$restored.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Rollback restored manifest mismatch: $($item.targetPath)"
            }
        }
        elseif ([string]$item.originalKind -eq 'Junction') {
            if ($entry.kind -eq 'Junction' -and $null -ne $entry.target -and
                [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase) -and
                ([int]$Transaction.schemaVersion -lt 5 -or [string]$item.action -ne 'ReplaceJunctionWithAdapter' -or
                    [string]$entry.junctionIdentity -ceq [string]$item.originalJunctionIdentity)) { continue }
            if ($entry.kind -ne 'Missing') { throw "Rollback target is occupied: $($item.targetPath)" }
            if ([int]$Transaction.schemaVersion -ge 5 -and [string]$item.action -eq 'ReplaceJunctionWithAdapter') {
                throw "Rollback preserved junction is missing: $($item.preservedJunctionPath)"
            }
            $null = New-CanonicalJunction -Path ([string]$item.targetPath) -Target ([string]$item.originalTarget) -AllowedRoot $UserHome
        }
        elseif ([string]$item.originalKind -eq 'Missing' -and $entry.kind -ne 'Missing') {
            throw "Rollback absent target is occupied: $($item.targetPath)"
        }
    }
}

function Invoke-SkillInstall {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$ApprovedDigest
    )

    if (-not $ApproveGlobalHomeWrite) { throw 'Install requires -ApproveGlobalHomeWrite' }
    if ([string]::IsNullOrWhiteSpace($ApprovedDigest)) { throw 'Install requires -PlanDigest from Check' }
    if (-not [string]::Equals($ApprovedDigest, [string]$Plan.planDigest, [StringComparison]::OrdinalIgnoreCase)) { throw 'Install plan digest is stale or mismatched' }
    if ($Plan.status -eq 'Healthy') {
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Install'; status = 'NoOp'; planDigest = $Plan.planDigest; backupId = $null; exitCode = 0 }
    }
    if ($Plan.status -ne 'Installable') { throw "Install is blocked by Check status:$($Plan.status)" }

    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $backupRoot -Label 'Backup root'
    if (-not [IO.Directory]::Exists($backupRoot)) { $null = New-Item -ItemType Directory -Path $backupRoot -Force }
    Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $backupRoot -Label 'Backup root' -IncludeLeaf
    $newBackupId = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $transactionRoot = Join-Path $backupRoot $newBackupId
    Assert-SafeDestinationPath -AllowedRoot $backupRoot -Candidate $transactionRoot -Label 'Transaction root'
    $null = New-Item -ItemType Directory -Path $transactionRoot
    Assert-SafeDestinationPath -AllowedRoot $backupRoot -Candidate $transactionRoot -Label 'Transaction root' -IncludeLeaf
    $itemsRoot = Join-Path $transactionRoot 'items'
    $null = New-Item -ItemType Directory -Path $itemsRoot
    Assert-SafeDestinationPath -AllowedRoot $backupRoot -Candidate $itemsRoot -Label 'Transaction items' -IncludeLeaf
    $stagingRoot = Join-Path $transactionRoot 'staging'
    $transactionPath = Join-Path $transactionRoot 'transaction.json'
    Assert-SafeFilePath -AllowedRoot $transactionRoot -Candidate $transactionPath -Label 'Transaction file'

    $items = @()
    foreach ($target in @($Plan.targets | Where-Object { $_.action -ne 'None' })) {
        $relative = Get-RelativePathPortable -Root $UserHome -Path ([string]$target.path)
        $backupPath = Join-Path $itemsRoot ($relative.Replace('/', '\'))
        $stagingPath = Join-Path $stagingRoot ("$($target.skill)\$($target.role)")
        $removalPath = Join-Path (Join-Path $transactionRoot 'removed') ("$($target.skill)\$($target.role)")
        $preservedJunctionPath = Join-Path (Join-Path $transactionRoot 'preserved') ("$($target.skill)\$($target.role)")
        $junctionAction = [string]$target.action -in @('CreateJunction', 'BackupAndLink')
        $adapterAction = [string]$target.action -in @('CreateAdapter', 'BackupAndAdapt', 'ReplaceJunctionWithAdapter')
        $preserveJunctionAction = [string]$target.action -eq 'ReplaceJunctionWithAdapter'
        Assert-SafeDestinationPath -AllowedRoot $itemsRoot -Candidate $backupPath -Label 'Backup item'
        Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $stagingPath -Label 'Deployment staging item'
        Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $removalPath -Label 'Adapter removal item'
        Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $preservedJunctionPath -Label 'Preserved junction item'
        $items += [pscustomobject][ordered]@{
            skill = $target.skill
            role = $target.role
            deploymentKind = $target.deploymentKind
            adapterKind = $target.adapterKind
            action = $target.action
            targetPath = $target.path
            sourcePath = $target.sourcePath
            sourceCommit = $target.sourceCommit
            sourceDigest = $target.sourceDigest
            expectedDigest = $target.expectedDigest
            adapterDigest = $target.adapterDigest
            originalKind = $target.entryKind
            originalTarget = $target.currentTarget
            originalJunctionIdentity = $target.currentJunctionIdentity
            originalDigest = $target.currentDigest
            backupPath = if ($target.entryKind -eq 'Directory') { $backupPath } else { $null }
            junctionStagingPath = if ($junctionAction) { $stagingPath } else { $null }
            adapterStagingPath = if ($adapterAction) { $stagingPath } else { $null }
            adapterRemovalPath = if ($adapterAction) { $removalPath } else { $null }
            preservedJunctionPath = if ($preserveJunctionAction) { $preservedJunctionPath } else { $null }
            changed = $false
            junctionPrepared = $false
            createdJunction = $false
            junctionIdentity = $null
            adapterPrepared = $false
            createdAdapter = $false
            junctionPreserved = $false
        }
    }
    $transaction = [pscustomobject][ordered]@{
        schemaVersion = 5
        backupId = $newBackupId
        status = 'Executing'
        createdAt = [DateTimeOffset]::Now.ToString('o')
        planDigest = $Plan.planDigest
        homeRoot = $UserHome
        repositoryRoot = $Plan.repositoryRoot
        selection = $Plan.selection
        includeAgyCliFallback = $Plan.includeAgyCliFallback
        agyCurrentVersion = $Plan.agyCurrentVersion
        items = $items
        installSeal = $null
        commitSeal = $null
        recoverySeal = $null
        error = $null
    }
    $transaction.installSeal = Get-TransactionInstallSeal -Transaction $transaction
    Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot

    try {
        foreach ($item in @($transaction.items)) {
            $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
            if ([string]$item.originalKind -eq 'Directory' -and
                ($entry.kind -ne 'Directory' -or -not [string]::Equals([string]$entry.manifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase))) {
                throw "Target changed after Check: $($item.targetPath)"
            }
            if ([string]$item.originalKind -eq 'Missing' -and $entry.kind -ne 'Missing') {
                throw "Target changed after Check: $($item.targetPath)"
            }
            if ([string]$item.originalKind -eq 'Junction' -and
                ($entry.kind -ne 'Junction' -or $null -eq $entry.target -or
                    -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase) -or
                    [string]$entry.junctionIdentity -cne [string]$item.originalJunctionIdentity)) {
                throw "Target changed after Check: $($item.targetPath)"
            }

            if ([string]$item.action -in @('CreateJunction', 'BackupAndLink')) {
                $stagingParent = Split-Path -Parent ([string]$item.junctionStagingPath)
                Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $stagingParent -Label 'Junction staging parent'
                if (-not [IO.Directory]::Exists($stagingParent)) { $null = New-Item -ItemType Directory -Path $stagingParent -Force }
                Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $stagingParent -Label 'Junction staging parent' -IncludeLeaf
                $item.junctionIdentity = New-CanonicalJunction -Path ([string]$item.junctionStagingPath) -Target ([string]$item.sourcePath) -AllowedRoot $transactionRoot
                $item.junctionPrepared = $true
                $item.changed = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
            }
            elseif ([string]$item.action -in @('CreateAdapter', 'BackupAndAdapt', 'ReplaceJunctionWithAdapter')) {
                $source = @($Plan.sources | Where-Object { [string]$_.skill -ceq [string]$item.skill })
                if ($source.Count -ne 1) { throw "Adapter source binding is invalid:$($item.skill)" }
                $adapter = if ([string]$item.adapterKind -eq 'claude-code-personal-physical-copy') {
                    Get-ClaudeAdapterInfo -Source $source[0]
                }
                elseif ([string]$item.adapterKind -eq 'agy-cli-physical-copy') {
                    Get-AgyAdapterInfo -Source $source[0] -AgyVersion ([string]$Plan.agyCurrentVersion)
                }
                else { throw "Unsupported adapter kind:$($item.adapterKind)" }
                if (-not [string]::Equals([string]$adapter.manifest.digest, [string]$item.adapterDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Adapter digest changed after Check:$($item.skill)/$($item.role)"
                }
                $item.changed = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
                if ([string]$item.adapterKind -eq 'claude-code-personal-physical-copy') {
                    New-ClaudeAdapterDirectory -Path ([string]$item.adapterStagingPath) -Source $source[0] -Adapter $adapter -AllowedRoot $transactionRoot
                }
                else {
                    New-AgyAdapterDirectory -Path ([string]$item.adapterStagingPath) -Source $source[0] -Adapter $adapter -AllowedRoot $transactionRoot
                }
                $item.adapterPrepared = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
            }

            if ([string]$item.originalKind -eq 'Directory') {
                $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
                if ($entry.kind -ne 'Directory' -or -not [string]::Equals([string]$entry.manifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Target changed after Check: $($item.targetPath)"
                }
                $backupParent = Split-Path -Parent ([string]$item.backupPath)
                Assert-SafeDestinationPath -AllowedRoot $itemsRoot -Candidate $backupParent -Label 'Backup parent'
                if (-not [IO.Directory]::Exists($backupParent)) { $null = New-Item -ItemType Directory -Path $backupParent -Force }
                Assert-SafeDestinationPath -AllowedRoot $itemsRoot -Candidate $backupParent -Label 'Backup parent' -IncludeLeaf
                Assert-SafeDestinationPath -AllowedRoot $itemsRoot -Candidate ([string]$item.backupPath) -Label 'Backup item'
                Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate ([string]$item.targetPath) -Label 'Install target' -IncludeLeaf
                $item.changed = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
                Move-DirectoryExact -SourcePath ([string]$item.targetPath) -SourceAllowedRoot $UserHome -DestinationPath ([string]$item.backupPath) -DestinationAllowedRoot $itemsRoot -Label 'Install backup'
                $backupManifest = Get-DirectoryManifest -Directory ([string]$item.backupPath)
                if (-not [string]::Equals([string]$backupManifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Backup verification failed: $($item.backupPath)"
                }
            }
            elseif ([string]$item.originalKind -eq 'Junction') {
                $item.changed = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
                if ([string]$item.action -eq 'ReplaceJunctionWithAdapter') {
                    $preservedParent = Split-Path -Parent ([string]$item.preservedJunctionPath)
                    if (-not [IO.Directory]::Exists($preservedParent)) { $null = New-Item -ItemType Directory -Path $preservedParent -Force }
                    Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $preservedParent -Label 'Preserved junction parent' -IncludeLeaf
                    Move-OwnedJunctionExact -SourcePath ([string]$item.targetPath) -SourceAllowedRoot $UserHome -DestinationPath ([string]$item.preservedJunctionPath) -DestinationAllowedRoot $transactionRoot -ExpectedTarget ([string]$item.originalTarget) -ExpectedIdentity ([string]$item.originalJunctionIdentity)
                    $item.junctionPreserved = $true
                    Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
                }
                else {
                    Remove-OwnedJunction -Path ([string]$item.targetPath) -ExpectedTarget ([string]$item.sourcePath) -AllowedRoot $UserHome -ExpectedIdentity ([string]$item.originalJunctionIdentity)
                }
            }
            elseif ([string]$item.originalKind -eq 'Missing') {
                if ((Get-PathEntryInfo -Path ([string]$item.targetPath)).kind -ne 'Missing') { throw "Target changed after Check: $($item.targetPath)" }
            }
            else {
                throw "Unsupported original kind during install: $($item.originalKind)"
            }

            if ([string]$item.action -in @('CreateJunction', 'BackupAndLink')) {
                $targetParent = Split-Path -Parent ([string]$item.targetPath)
                Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $targetParent -Label 'Active junction parent'
                if (-not [IO.Directory]::Exists($targetParent)) { $null = New-Item -ItemType Directory -Path $targetParent -Force }
                Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $targetParent -Label 'Active junction parent' -IncludeLeaf
                Move-OwnedJunctionExact -SourcePath ([string]$item.junctionStagingPath) -SourceAllowedRoot $transactionRoot -DestinationPath ([string]$item.targetPath) -DestinationAllowedRoot $UserHome -ExpectedTarget ([string]$item.sourcePath) -ExpectedIdentity ([string]$item.junctionIdentity)
                $item.junctionPrepared = $false
                $item.createdJunction = $true
            }
            elseif ([string]$item.action -in @('CreateAdapter', 'BackupAndAdapt', 'ReplaceJunctionWithAdapter')) {
                Move-OwnedAdapterExact -SourcePath ([string]$item.adapterStagingPath) -SourceAllowedRoot $transactionRoot -DestinationPath ([string]$item.targetPath) -DestinationAllowedRoot $UserHome -ExpectedDigest ([string]$item.adapterDigest) -Label "Activate $($item.role) adapter"
                $item.adapterPrepared = $false
                $item.createdAdapter = $true
            }
            Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        }

        $postPlan = Get-InstallPlan -RepoRoot ([string]$Plan.repositoryRoot) -UserHome $UserHome -Selection ([string]$Plan.selection) -FallbackEnabled ([bool]$Plan.includeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory -CurrentAgyVersion ([string]$Plan.agyCurrentVersion) -IgnoreRecoveryBackupId $newBackupId
        if ($postPlan.status -ne 'Healthy') { throw "Post-install Check failed:$($postPlan.status)" }
        $transaction.commitSeal = Get-TransactionCommitSeal -Transaction $transaction
        $transaction.status = 'Committed'
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Install'; status = 'Committed'; planDigest = $Plan.planDigest; backupId = $newBackupId; transactionPath = $transactionPath; exitCode = 0 }
    }
    catch {
        $installError = $_.Exception.Message
        try {
            Invoke-TransactionRollback -Transaction $transaction -UserHome $UserHome -TransactionRoot $transactionRoot
            $transaction.status = 'RolledBack'
        }
        catch {
            $transaction.status = 'RecoveryRequired'
            $installError = "$installError; rollback failed: $($_.Exception.Message)"
        }
        $transaction.error = $installError
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        throw "Install transaction failed:$installError; backupId=$newBackupId"
    }
}

function Get-RestorePlan {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RequestedBackupId
    )

    if ($RequestedBackupId -notmatch '^\d{8}-\d{9}-[a-f0-9]{8}$') { throw 'BackupId format is invalid; latest and path traversal are not supported' }
    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    $transactionRoot = Join-Path $backupRoot $RequestedBackupId
    Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $backupRoot -Label 'Restore backup root' -IncludeLeaf
    Assert-SafeDestinationPath -AllowedRoot $backupRoot -Candidate $transactionRoot -Label 'Restore transaction' -IncludeLeaf
    $transactionPath = Join-Path $transactionRoot 'transaction.json'
    Assert-SafeFilePath -AllowedRoot $transactionRoot -Candidate $transactionPath -Label 'Restore transaction file'
    if (-not [IO.File]::Exists($transactionPath)) { throw "Transaction does not exist:$RequestedBackupId" }
    $transaction = [string]([IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $transactionSchema = [int]$transaction.schemaVersion
    if ($transactionSchema -notin @(3, 4, 5)) { throw 'Transaction schemaVersion mismatch' }
    if ([string]$transaction.backupId -cne $RequestedBackupId) { throw 'Transaction BackupId mismatch' }
    if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$transaction.homeRoot)), $UserHome, [StringComparison]::OrdinalIgnoreCase)) { throw 'Transaction HomeRoot mismatch' }
    if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$transaction.repositoryRoot)), $RepoRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Transaction RepositoryRoot mismatch' }
    $includeAgyCliFallback = Get-StrictBooleanProperty -Object $transaction -Name 'includeAgyCliFallback' -Label 'Transaction includeAgyCliFallback'
    if ([string]::IsNullOrWhiteSpace([string]$transaction.installSeal) -or
        [string]$transaction.installSeal -cne (Get-TransactionInstallSeal -Transaction $transaction)) { throw 'Transaction install seal mismatch' }

    $transactionStatus = [string]$transaction.status
    $commitSeal = Get-OptionalStringProperty -Object $transaction -Name 'commitSeal'
    $recoverySeal = Get-OptionalStringProperty -Object $transaction -Name 'recoverySeal'
    $hasCommitSeal = -not [string]::IsNullOrWhiteSpace($commitSeal)
    if ($hasCommitSeal) {
        if ($commitSeal -cne (Get-TransactionCommitSeal -Transaction $transaction)) { throw 'Transaction commit seal mismatch' }
        if ($transactionStatus -notin @('Committed', 'Restoring', 'RecoveryRequired', 'Restored')) {
            throw "Committed transaction has an invalid status:$transactionStatus"
        }
        $recoveryKind = 'CommittedRestore'
    }
    else {
        if ($transactionStatus -notin @('Executing', 'Restoring', 'RecoveryRequired', 'Restored')) {
            throw "Uncommitted transaction is not recoverable:$transactionStatus"
        }
        $recoveryKind = 'InstallRollback'
    }
    if ($transactionStatus -eq 'Restored') {
        $expectedRecoverySeal = Get-TransactionRecoverySeal -Transaction $transaction -RecoveryKind $recoveryKind
        if ([string]::IsNullOrWhiteSpace($recoverySeal) -or $recoverySeal -cne $expectedRecoverySeal) {
            throw 'Transaction recovery seal mismatch'
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($recoverySeal)) {
        throw "Unexpected recovery seal for transaction status:$transactionStatus"
    }
    if ([string]$transaction.selection -notin @('All', 'adr-cycle', 'design-team', 'design-to-html', 'goal-cycle', 'agent-team-operations', 'restart-safe-handoff', 'runtime-incident-investigator', 'supervised-session-conductor')) { throw 'Transaction selection is invalid' }
    if (@($transaction.items).Count -eq 0) { throw 'Transaction has no restorable items' }

    $errors = @()
    $states = @()
    $seenTargets = @{}
    $digestLines = @("backupId=$RequestedBackupId", "transactionPlan=$($transaction.planDigest)", "status=$transactionStatus", "recoveryKind=$recoveryKind")
    foreach ($item in @($transaction.items)) {
        $skillName = [string]$item.skill
        $role = [string]$item.role
        $itemChanged = Get-StrictBooleanProperty -Object $item -Name 'changed' -Label "Transaction changed:$skillName/$role"
        $itemJunctionPrepared = Get-StrictBooleanProperty -Object $item -Name 'junctionPrepared' -Label "Transaction junctionPrepared:$skillName/$role"
        $itemCreatedJunction = Get-StrictBooleanProperty -Object $item -Name 'createdJunction' -Label "Transaction createdJunction:$skillName/$role"
        $itemAdapterPrepared = if ($transactionSchema -ge 4) { Get-StrictBooleanProperty -Object $item -Name 'adapterPrepared' -Label "Transaction adapterPrepared:$skillName/$role" } else { $false }
        $itemCreatedAdapter = if ($transactionSchema -ge 4) { Get-StrictBooleanProperty -Object $item -Name 'createdAdapter' -Label "Transaction createdAdapter:$skillName/$role" } else { $false }
        $itemJunctionPreserved = if ($transactionSchema -ge 5) { Get-StrictBooleanProperty -Object $item -Name 'junctionPreserved' -Label "Transaction junctionPreserved:$skillName/$role" } else { $false }
        if ($skillName -notin @('adr-cycle', 'design-team', 'design-to-html', 'goal-cycle', 'agent-team-operations', 'restart-safe-handoff', 'runtime-incident-investigator', 'supervised-session-conductor')) { $errors += "Unsupported transaction skill:$skillName"; continue }
        $definitions = @(Get-TargetDefinitions -UserHome $UserHome -SkillName $skillName -FallbackEnabled $includeAgyCliFallback -ContractVersion $transactionSchema)
        $definition = @($definitions | Where-Object { $_.role -ceq $role })
        if ($definition.Count -ne 1) { $errors += "Unsupported transaction role:$skillName/$role"; continue }
        if ([string]$definition[0].category -in @('Fallback', 'FallbackMigration') -and -not [bool]$definition[0].enabled) { $errors += "Disabled fallback role in transaction:$skillName/$role"; continue }
        if ([string]$transaction.selection -ne 'All' -and [string]$transaction.selection -cne $skillName) { $errors += "Transaction selection binding mismatch:$skillName"; continue }

        $expectedTarget = Get-NormalizedFullPath -Path ([string]$definition[0].path)
        $expectedSource = Get-NormalizedFullPath -Path (Join-Path $RepoRoot "skills\$skillName")
        if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.targetPath)), $expectedTarget, [StringComparison]::OrdinalIgnoreCase)) { $errors += "Transaction target binding mismatch:$skillName/$role"; continue }
        if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.sourcePath)), $expectedSource, [StringComparison]::OrdinalIgnoreCase)) { $errors += "Transaction source binding mismatch:$skillName/$role"; continue }
        $targetKey = $expectedTarget.ToLowerInvariant()
        if ($seenTargets.ContainsKey($targetKey)) { $errors += "Duplicate transaction target:$expectedTarget"; continue }
        $seenTargets[$targetKey] = $true
        Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $expectedTarget -Label 'Restore target'

        $originalKind = [string]$item.originalKind
        if ($originalKind -notin @('Missing', 'Directory', 'Junction')) { $errors += "Unsupported original kind:$originalKind"; continue }
        $deploymentKind = [string]$definition[0].deploymentKind
        if ($transactionSchema -ge 4 -and [string]$item.deploymentKind -cne $deploymentKind) { $errors += "Transaction deployment binding mismatch:$skillName/$role"; continue }
        $adapterKind = if ($deploymentKind -eq 'Adapter' -and $definition[0].PSObject.Properties['adapterKind']) { [string]$definition[0].adapterKind } else { $null }
        if ($transactionSchema -ge 5) {
            if ($deploymentKind -eq 'Adapter' -and [string]$item.adapterKind -cne $adapterKind) { $errors += "Transaction adapter binding mismatch:$skillName/$role"; continue }
            if ($deploymentKind -ne 'Adapter' -and -not [string]::IsNullOrWhiteSpace([string]$item.adapterKind)) { $errors += "Unexpected adapter kind:$skillName/$role"; continue }
        }
        $expectedAction = if ([string]$definition[0].category -in @('Migration', 'FallbackMigration')) {
            if ($originalKind -eq 'Directory') { 'BackupOnly' } elseif ($originalKind -eq 'Junction') { 'RemoveLegacyJunction' } else { $null }
        }
        elseif ($deploymentKind -eq 'Adapter') {
            if ($originalKind -eq 'Missing') { 'CreateAdapter' } elseif ($originalKind -eq 'Directory') { 'BackupAndAdapt' } elseif ($originalKind -eq 'Junction') { 'ReplaceJunctionWithAdapter' } else { $null }
        }
        else {
            if ($originalKind -eq 'Missing') { 'CreateJunction' } elseif ($originalKind -eq 'Directory') { 'BackupAndLink' } else { $null }
        }
        if ([string]::IsNullOrWhiteSpace([string]$expectedAction) -or [string]$item.action -cne $expectedAction) { $errors += "Transaction action binding mismatch:$skillName/$role"; continue }
        $expectedCreatedJunction = $expectedAction -in @('CreateJunction', 'BackupAndLink')
        $expectedCreatedAdapter = $expectedAction -in @('CreateAdapter', 'BackupAndAdapt', 'ReplaceJunctionWithAdapter')
        $expectedStagingPath = $null
        if ($expectedCreatedJunction) {
            $expectedStagingPath = Join-Path (Join-Path (Join-Path $transactionRoot 'staging') $skillName) $role
            if ([string]::IsNullOrWhiteSpace([string]$item.junctionStagingPath) -or
                -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.junctionStagingPath)), (Get-NormalizedFullPath -Path $expectedStagingPath), [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction staging binding mismatch:$skillName/$role"
                continue
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item.junctionStagingPath)) {
            $errors += "Unexpected staging path:$skillName/$role"
            continue
        }
        $expectedAdapterStagingPath = $null
        $expectedAdapterRemovalPath = $null
        $expectedPreservedJunctionPath = $null
        $expectedPreservedJunction = $transactionSchema -ge 5 -and $expectedAction -eq 'ReplaceJunctionWithAdapter'
        if ($expectedCreatedAdapter) {
            $expectedAdapterStagingPath = Join-Path (Join-Path (Join-Path $transactionRoot 'staging') $skillName) $role
            $expectedAdapterRemovalPath = Join-Path (Join-Path (Join-Path $transactionRoot 'removed') $skillName) $role
            if ([string]::IsNullOrWhiteSpace([string]$item.adapterStagingPath) -or
                -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.adapterStagingPath)), (Get-NormalizedFullPath -Path $expectedAdapterStagingPath), [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction adapter staging binding mismatch:$skillName/$role"
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$item.adapterRemovalPath) -or
                -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.adapterRemovalPath)), (Get-NormalizedFullPath -Path $expectedAdapterRemovalPath), [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction adapter removal binding mismatch:$skillName/$role"
                continue
            }
        }
        elseif ($transactionSchema -ge 4 -and (-not [string]::IsNullOrWhiteSpace([string]$item.adapterStagingPath) -or -not [string]::IsNullOrWhiteSpace([string]$item.adapterRemovalPath))) {
            $errors += "Unexpected adapter transaction path:$skillName/$role"
            continue
        }
        if ($expectedPreservedJunction) {
            $expectedPreservedJunctionPath = Join-Path (Join-Path (Join-Path $transactionRoot 'preserved') $skillName) $role
            if ([string]::IsNullOrWhiteSpace([string]$item.preservedJunctionPath) -or
                -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.preservedJunctionPath)), (Get-NormalizedFullPath -Path $expectedPreservedJunctionPath), [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction preserved junction binding mismatch:$skillName/$role"
                continue
            }
        }
        elseif ($transactionSchema -ge 5 -and -not [string]::IsNullOrWhiteSpace([string]$item.preservedJunctionPath)) {
            $errors += "Unexpected preserved junction path:$skillName/$role"
            continue
        }
        $transactionJunctionIdentity = Get-OptionalStringProperty -Object $item -Name 'junctionIdentity'
        if (-not [string]::IsNullOrWhiteSpace($transactionJunctionIdentity) -and $transactionJunctionIdentity -notmatch '^[A-Fa-f0-9]{64}$') {
            $errors += "Transaction junction identity is invalid:$skillName/$role"
            continue
        }
        if ($hasCommitSeal) {
            if (-not $itemChanged) { $errors += "Committed transaction item is not marked changed:$skillName/$role"; continue }
            if ($itemJunctionPrepared) { $errors += "Committed transaction retains a prepared junction:$skillName/$role"; continue }
            if ($itemCreatedJunction -ne $expectedCreatedJunction) { $errors += "Transaction junction flag mismatch:$skillName/$role"; continue }
            if ($expectedCreatedJunction -and [string]::IsNullOrWhiteSpace($transactionJunctionIdentity)) { $errors += "Committed junction identity is missing:$skillName/$role"; continue }
            if (-not $expectedCreatedJunction -and -not [string]::IsNullOrWhiteSpace($transactionJunctionIdentity)) { $errors += "Unexpected committed junction identity:$skillName/$role"; continue }
            if ($itemAdapterPrepared) { $errors += "Committed transaction retains a prepared adapter:$skillName/$role"; continue }
            if ($itemCreatedAdapter -ne $expectedCreatedAdapter) { $errors += "Transaction adapter flag mismatch:$skillName/$role"; continue }
            if ($transactionSchema -ge 5 -and $itemJunctionPreserved -ne $expectedPreservedJunction) { $errors += "Transaction preserved junction flag mismatch:$skillName/$role"; continue }
        }
        if ([string]$item.sourceDigest -notmatch '^[A-Fa-f0-9]{64}$') { $errors += "Transaction source digest is invalid:$skillName/$role"; continue }
        if ($transactionSchema -ge 4) {
            if ([string]$item.sourceCommit -notmatch '^[A-Fa-f0-9]{40,64}$') { $errors += "Transaction source commit is invalid:$skillName/$role"; continue }
            if ([string]$item.expectedDigest -notmatch '^[A-Fa-f0-9]{64}$') { $errors += "Transaction expected digest is invalid:$skillName/$role"; continue }
            if ($expectedCreatedAdapter) {
                if ([string]$item.adapterDigest -notmatch '^[A-Fa-f0-9]{64}$' -or -not [string]::Equals([string]$item.expectedDigest, [string]$item.adapterDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    $errors += "Transaction adapter digest is invalid:$skillName/$role"
                    continue
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$item.adapterDigest) -or -not [string]::Equals([string]$item.expectedDigest, [string]$item.sourceDigest, [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Unexpected adapter digest metadata:$skillName/$role"
                continue
            }
        }
        $expectedBackupPath = $null
        if ($originalKind -eq 'Directory') {
            if ([string]$item.originalDigest -notmatch '^[A-Fa-f0-9]{64}$') { $errors += "Transaction original digest is invalid:$skillName/$role"; continue }
            if (-not [string]::IsNullOrWhiteSpace([string]$item.originalTarget)) { $errors += "Unexpected original target for directory:$skillName/$role"; continue }
            if (-not [string]::IsNullOrWhiteSpace([string]$item.originalJunctionIdentity)) { $errors += "Unexpected original junction identity for directory:$skillName/$role"; continue }
            $relative = Get-RelativePathPortable -Root $UserHome -Path $expectedTarget
            $expectedBackupPath = Join-Path (Join-Path $transactionRoot 'items') ($relative.Replace('/', '\'))
            if ([string]::IsNullOrWhiteSpace([string]$item.backupPath) -or -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.backupPath)), (Get-NormalizedFullPath -Path $expectedBackupPath), [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction backup binding mismatch:$skillName/$role"
                continue
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item.backupPath)) {
            $errors += "Unexpected backup path for non-directory:$skillName/$role"
            continue
        }
        elseif ($originalKind -eq 'Junction') {
            if (-not [string]::IsNullOrWhiteSpace([string]$item.originalDigest)) { $errors += "Unexpected original digest for junction:$skillName/$role"; continue }
            if ([string]$item.originalJunctionIdentity -notmatch '^[A-Fa-f0-9]{64}$') { $errors += "Transaction original junction identity is invalid:$skillName/$role"; continue }
            if ([string]::IsNullOrWhiteSpace([string]$item.originalTarget) -or
                -not [string]::Equals((Get-NormalizedFullPath -Path ([string]$item.originalTarget)), $expectedSource, [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Transaction original junction binding mismatch:$skillName/$role"
                continue
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item.originalDigest) -or -not [string]::IsNullOrWhiteSpace([string]$item.originalTarget) -or
            -not [string]::IsNullOrWhiteSpace([string]$item.originalJunctionIdentity)) {
            $errors += "Unexpected original metadata for missing target:$skillName/$role"
            continue
        }

        $stagingEntry = [pscustomobject][ordered]@{ kind = 'Missing'; target = $null; junctionIdentity = $null }
        $stagingRemovalIdentity = $null
        if ($expectedCreatedJunction) {
            Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $expectedStagingPath -Label 'Restore staging junction'
            $stagingEntry = Get-PathEntryInfo -Path $expectedStagingPath
            if ($stagingEntry.kind -eq 'Junction' -and $null -ne $stagingEntry.target -and
                [string]::Equals([string]$stagingEntry.target, $expectedSource, [StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::IsNullOrWhiteSpace($transactionJunctionIdentity) -and
                    [string]$stagingEntry.junctionIdentity -ceq $transactionJunctionIdentity) {
                    $stagingRemovalIdentity = $transactionJunctionIdentity
                }
                else { $errors += "Staged junction transaction identity mismatch:$expectedStagingPath" }
            }
            elseif ($stagingEntry.kind -ne 'Missing') {
                $errors += "Staging path is occupied by an unowned entry:$expectedStagingPath"
            }
            if ($hasCommitSeal -and $stagingEntry.kind -ne 'Missing') {
                $errors += "Committed transaction staging path is not empty:$expectedStagingPath"
            }
        }
        $adapterStagingEntry = [pscustomobject][ordered]@{ kind = 'Missing'; manifest = $null }
        $adapterRemovalEntry = [pscustomobject][ordered]@{ kind = 'Missing'; manifest = $null }
        if ($expectedCreatedAdapter) {
            Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $expectedAdapterStagingPath -Label 'Restore staged adapter'
            Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $expectedAdapterRemovalPath -Label 'Restore removed adapter'
            $adapterStagingEntry = Get-PathEntryInfo -Path $expectedAdapterStagingPath
            if ($adapterStagingEntry.kind -eq 'Directory') {
                if (-not [string]::Equals([string]$adapterStagingEntry.manifest.digest, [string]$item.adapterDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    $errors += "Staged adapter was modified:$expectedAdapterStagingPath"
                }
            }
            elseif ($adapterStagingEntry.kind -ne 'Missing') {
                $errors += "Staged adapter is not an ordinary directory:$expectedAdapterStagingPath"
            }
            if ($hasCommitSeal -and $adapterStagingEntry.kind -ne 'Missing') {
                $errors += "Committed transaction adapter staging path is not empty:$expectedAdapterStagingPath"
            }

            $adapterRemovalEntry = Get-PathEntryInfo -Path $expectedAdapterRemovalPath
            if ($adapterRemovalEntry.kind -eq 'Directory') {
                if (-not [string]::Equals([string]$adapterRemovalEntry.manifest.digest, [string]$item.adapterDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    $errors += "Removed adapter was modified:$expectedAdapterRemovalPath"
                }
            }
            elseif ($adapterRemovalEntry.kind -ne 'Missing') {
                $errors += "Removed adapter is not an ordinary directory:$expectedAdapterRemovalPath"
            }
            if ($adapterStagingEntry.kind -ne 'Missing' -and $adapterRemovalEntry.kind -ne 'Missing') {
                $errors += "Staged and removed adapters both exist:$expectedTarget"
            }
        }

        $preservedJunctionEntry = [pscustomobject][ordered]@{ kind = 'Missing'; target = $null; junctionIdentity = $null }
        $preservedJunctionValid = $false
        if ($expectedPreservedJunction) {
            Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $expectedPreservedJunctionPath -Label 'Restore preserved junction'
            $preservedJunctionEntry = Get-PathEntryInfo -Path $expectedPreservedJunctionPath
            if ($preservedJunctionEntry.kind -eq 'Junction' -and $null -ne $preservedJunctionEntry.target -and
                [string]::Equals([string]$preservedJunctionEntry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase) -and
                [string]$preservedJunctionEntry.junctionIdentity -ceq [string]$item.originalJunctionIdentity) {
                $preservedJunctionValid = $true
            }
            elseif ($preservedJunctionEntry.kind -ne 'Missing') {
                $errors += "Preserved junction ownership mismatch:$expectedPreservedJunctionPath"
            }
        }

        $entry = Get-PathEntryInfo -Path $expectedTarget
        $sourceJunction = $entry.kind -eq 'Junction' -and $null -ne $entry.target -and [string]::Equals([string]$entry.target, $expectedSource, [StringComparison]::OrdinalIgnoreCase)
        $canonicalInstalled = $false
        $removalIdentity = $null
        if ($expectedCreatedJunction -and $sourceJunction) {
            if (-not [string]::IsNullOrWhiteSpace($transactionJunctionIdentity) -and
                [string]$entry.junctionIdentity -ceq $transactionJunctionIdentity) {
                $canonicalInstalled = $true
                $removalIdentity = $transactionJunctionIdentity
            }
            else { $errors += "Junction transaction identity mismatch:$expectedTarget" }
        }
        elseif ($expectedCreatedAdapter -and $entry.kind -eq 'Directory' -and
            [string]::Equals([string]$entry.manifest.digest, [string]$item.adapterDigest, [StringComparison]::OrdinalIgnoreCase)) {
            $canonicalInstalled = $true
        }
        if ($expectedCreatedAdapter -and $canonicalInstalled -and $adapterRemovalEntry.kind -ne 'Missing') {
            $errors += "Active and removed adapters both exist:$expectedTarget"
        }
        if ($expectedCreatedAdapter -and $canonicalInstalled -and $adapterStagingEntry.kind -ne 'Missing') {
            $errors += "Active and staged adapters both exist:$expectedTarget"
        }
        $state = 'Conflict'
        $backupDigest = ''

        if ($originalKind -eq 'Directory') {
            $originalState = $entry.kind -eq 'Directory' -and $null -ne $entry.manifest -and [string]::Equals([string]$entry.manifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)
            $backupValid = $false
            $backupExists = $false
            try {
                Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $expectedBackupPath -Label 'Restore backup' -IncludeLeaf
                $backupEntry = Get-PathEntryInfo -Path $expectedBackupPath
                if ($backupEntry.kind -eq 'Directory') {
                    $backupExists = $true
                    $backupDigest = [string]$backupEntry.manifest.digest
                    if ([string]::Equals($backupDigest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) { $backupValid = $true }
                    else { $errors += "Backup directory was modified:$expectedBackupPath" }
                }
                elseif ($backupEntry.kind -ne 'Missing') {
                    $errors += "Backup path is not an ordinary directory:$expectedBackupPath"
                }
            }
            catch { $errors += $_.Exception.Message }

            if ($originalState -and -not $backupExists) {
                $state = 'Original'
                $backupDigest = [string]$item.originalDigest
            }
            elseif ($originalState -and $backupExists) {
                $errors += "Original target and backup both exist:$expectedTarget"
            }
            elseif ($expectedAction -in @('BackupAndLink', 'BackupAndAdapt') -and $canonicalInstalled -and $backupValid) { $state = 'Installed' }
            elseif ($entry.kind -eq 'Missing' -and $backupValid) { $state = 'RestorePending' }
            elseif (-not $backupExists) { $errors += "Backup directory is missing:$expectedBackupPath" }
            else { $errors += "Restore target is neither installed, pending, nor original:$expectedTarget" }
        }
        elseif ($originalKind -eq 'Junction') {
            if ([string]::IsNullOrWhiteSpace([string]$item.originalTarget)) {
                $errors += "Original junction target is missing:$expectedTarget"
            }
            elseif ($expectedPreservedJunction) {
                $originalJunctionState = $entry.kind -eq 'Junction' -and $null -ne $entry.target -and
                    [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase) -and
                    [string]$entry.junctionIdentity -ceq [string]$item.originalJunctionIdentity
                if ($originalJunctionState -and $preservedJunctionEntry.kind -eq 'Missing') { $state = 'Original' }
                elseif ($originalJunctionState -and $preservedJunctionEntry.kind -ne 'Missing') { $errors += "Original and preserved junction both exist:$expectedTarget" }
                elseif ($canonicalInstalled -and $preservedJunctionValid) { $state = 'Installed' }
                elseif ($entry.kind -eq 'Missing' -and $preservedJunctionValid) { $state = 'RestorePending' }
                elseif ($entry.kind -eq 'Junction') { $errors += "Original junction identity mismatch:$expectedTarget" }
                else { $errors += "Preserved junction migration is incomplete:$expectedTarget" }
            }
            elseif ($entry.kind -eq 'Junction' -and $null -ne $entry.target -and [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path ([string]$item.originalTarget)), [StringComparison]::OrdinalIgnoreCase)) {
                $state = 'Original'
            }
            elseif ($canonicalInstalled -or $entry.kind -eq 'Missing') { $state = 'Installed' }
            else { $errors += "Restore junction is neither installed nor original:$expectedTarget" }
        }
        else {
            if ($entry.kind -eq 'Missing') { $state = 'Original' }
            elseif ($canonicalInstalled) { $state = 'Installed' }
            else { $errors += "Restore absent target is occupied:$expectedTarget" }
        }

        $states += [pscustomobject][ordered]@{
            targetPath = $expectedTarget
            state = $state
            removalIdentity = $removalIdentity
            stagingPath = $expectedStagingPath
            stagingRemovalIdentity = $stagingRemovalIdentity
            adapterStagingPath = $expectedAdapterStagingPath
            adapterRemovalPath = $expectedAdapterRemovalPath
            adapterStagingState = $adapterStagingEntry.kind
            adapterRemovalState = $adapterRemovalEntry.kind
            preservedJunctionPath = $expectedPreservedJunctionPath
            preservedJunctionState = $preservedJunctionEntry.kind
            preservedJunctionIdentity = $preservedJunctionEntry.junctionIdentity
        }
        $digestLine = "item|$skillName|$role|$expectedTarget|$($entry.kind)|$($entry.target)|$($entry.junctionIdentity)|$transactionJunctionIdentity|$backupDigest|$originalKind|$($item.originalTarget)|$state|$removalIdentity|$expectedStagingPath|$($stagingEntry.kind)|$($stagingEntry.junctionIdentity)|$stagingRemovalIdentity|$expectedAdapterStagingPath|$($adapterStagingEntry.kind)|$(if ($null -ne $adapterStagingEntry.manifest) { $adapterStagingEntry.manifest.digest } else { '' })|$expectedAdapterRemovalPath|$($adapterRemovalEntry.kind)|$(if ($null -ne $adapterRemovalEntry.manifest) { $adapterRemovalEntry.manifest.digest } else { '' })"
        if ($transactionSchema -ge 5) {
            $digestLine += "|$adapterKind|$expectedPreservedJunctionPath|$($preservedJunctionEntry.kind)|$($preservedJunctionEntry.target)|$($preservedJunctionEntry.junctionIdentity)"
        }
        $digestLines += $digestLine
    }
    $digest = Get-Sha256Text -Text ([string]::Join("`n", $digestLines))
    $allOriginal = $states.Count -eq @($transaction.items).Count -and @($states | Where-Object { $_.state -ne 'Original' }).Count -eq 0
    if ($transactionStatus -eq 'Restored') {
        $status = if ($errors.Count -eq 0 -and $allOriginal) { 'Restored' } else { 'Conflict' }
    }
    else {
        $status = if ($errors.Count -eq 0 -and @($states | Where-Object { $_.state -eq 'Conflict' }).Count -eq 0) { 'RestoreReady' } else { 'Conflict' }
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'CheckRestore'
        status = $status
        backupId = $RequestedBackupId
        recoveryKind = $recoveryKind
        planDigest = if ($status -eq 'Restored') { $null } else { $digest }
        transactionPath = $transactionPath
        transaction = $transaction
        itemStates = $states
        errors = $errors
        exitCode = if ($status -in @('RestoreReady', 'Restored')) { 0 } else { 3 }
    }
}

function Invoke-SkillRestore {
    param(
        [Parameter(Mandatory = $true)]$RestorePlan,
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$ApprovedDigest
    )

    if ($RestorePlan.status -eq 'Restored') {
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; status = 'NoOp'; backupId = $RestorePlan.backupId; exitCode = 0 }
    }
    if (-not $ApproveGlobalHomeWrite) { throw 'Restore requires -ApproveGlobalHomeWrite' }
    if ([string]::IsNullOrWhiteSpace($ApprovedDigest)) { throw 'Restore requires -PlanDigest from Check -BackupId' }
    if (-not [string]::Equals($ApprovedDigest, [string]$RestorePlan.planDigest, [StringComparison]::OrdinalIgnoreCase)) { throw 'Restore plan digest is stale or mismatched' }
    if ($RestorePlan.status -ne 'RestoreReady') { throw "Restore is blocked by Check status:$($RestorePlan.status)" }

    $transaction = $RestorePlan.transaction
    $transactionSchema = [int]$transaction.schemaVersion
    $transactionPath = [string]$RestorePlan.transactionPath
    $transactionRoot = Split-Path -Parent $transactionPath
    $stateMap = @{}
    foreach ($state in @($RestorePlan.itemStates)) { $stateMap[[string]$state.targetPath] = $state }
    $transaction.status = 'Restoring'
    $transaction | Add-Member -MemberType NoteProperty -Name recoverySeal -Value $null -Force
    $transaction | Add-Member -MemberType NoteProperty -Name restoreStartedAt -Value ([DateTimeOffset]::Now.ToString('o')) -Force
    $transaction | Add-Member -MemberType NoteProperty -Name restoreError -Value $null -Force
    foreach ($item in @($transaction.items)) { $item | Add-Member -MemberType NoteProperty -Name restoreCompleted -Value $false -Force }
    Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot

    try {
        $items = @($transaction.items)
        [array]::Reverse($items)
        foreach ($item in $items) {
            $targetPath = Get-NormalizedFullPath -Path ([string]$item.targetPath)
            $stateInfo = $stateMap[$targetPath]
            if ($null -eq $stateInfo) { throw "Restore plan state is missing:$targetPath" }
            $itemState = [string]$stateInfo.state
            if (-not [string]::IsNullOrWhiteSpace([string]$stateInfo.stagingRemovalIdentity)) {
                Remove-OwnedJunction -Path ([string]$stateInfo.stagingPath) -ExpectedTarget ([string]$item.sourcePath) -AllowedRoot $transactionRoot -ExpectedIdentity ([string]$stateInfo.stagingRemovalIdentity)
            }
            if ([string]$stateInfo.adapterStagingState -eq 'Directory') {
                Move-OwnedAdapterExact -SourcePath ([string]$stateInfo.adapterStagingPath) -SourceAllowedRoot $transactionRoot -DestinationPath ([string]$stateInfo.adapterRemovalPath) -DestinationAllowedRoot $transactionRoot -ExpectedDigest ([string]$item.adapterDigest) -Label 'Recover staged adapter'
            }
            if ($itemState -eq 'Original') {
                $item.restoreCompleted = $true
                Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
                continue
            }
            if ([string]$item.action -in @('CreateJunction', 'BackupAndLink') -and $itemState -eq 'Installed') {
                Remove-OwnedJunction -Path $targetPath -ExpectedTarget ([string]$item.sourcePath) -AllowedRoot $UserHome -ExpectedIdentity ([string]$stateInfo.removalIdentity)
            }
            elseif ([string]$item.action -in @('CreateAdapter', 'BackupAndAdapt', 'ReplaceJunctionWithAdapter') -and $itemState -eq 'Installed' -and
                (Get-PathEntryInfo -Path $targetPath).kind -eq 'Directory') {
                Move-OwnedAdapterExact -SourcePath $targetPath -SourceAllowedRoot $UserHome -DestinationPath ([string]$stateInfo.adapterRemovalPath) -DestinationAllowedRoot $transactionRoot -ExpectedDigest ([string]$item.adapterDigest) -Label 'Remove installed adapter for Restore'
            }
            $entry = Get-PathEntryInfo -Path $targetPath
            if ([string]$item.originalKind -eq 'Directory') {
                if ($entry.kind -ne 'Missing') { throw "Restore target is occupied:$targetPath" }
                $backupPath = Get-NormalizedFullPath -Path ([string]$item.backupPath)
                Assert-SafeDestinationPath -AllowedRoot $transactionRoot -Candidate $backupPath -Label 'Restore backup' -IncludeLeaf
                Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $targetPath -Label 'Restore target'
                $parent = Split-Path -Parent $targetPath
                if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
                Assert-SafeDestinationPath -AllowedRoot $UserHome -Candidate $targetPath -Label 'Restore target'
                Move-DirectoryExact -SourcePath $backupPath -SourceAllowedRoot $transactionRoot -DestinationPath $targetPath -DestinationAllowedRoot $UserHome -Label 'Restore'
                $restored = Get-DirectoryManifest -Directory $targetPath
                if (-not [string]::Equals([string]$restored.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) { throw "Restored manifest mismatch:$targetPath" }
            }
            elseif ([string]$item.originalKind -eq 'Junction') {
                if ($entry.kind -ne 'Missing') { throw "Restore target is occupied:$targetPath" }
                if ($transactionSchema -ge 5 -and [string]$item.action -eq 'ReplaceJunctionWithAdapter') {
                    Move-OwnedJunctionExact -SourcePath ([string]$stateInfo.preservedJunctionPath) -SourceAllowedRoot $transactionRoot -DestinationPath $targetPath -DestinationAllowedRoot $UserHome -ExpectedTarget ([string]$item.originalTarget) -ExpectedIdentity ([string]$item.originalJunctionIdentity)
                }
                else {
                    $null = New-CanonicalJunction -Path $targetPath -Target ([string]$item.originalTarget) -AllowedRoot $UserHome
                }
            }
            $item.restoreCompleted = $true
            Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        }

        $postRestore = Get-RestorePlan -UserHome $UserHome -RepoRoot $RepoRoot -RequestedBackupId ([string]$transaction.backupId)
        if ($postRestore.status -ne 'RestoreReady' -or @($postRestore.itemStates | Where-Object { $_.state -ne 'Original' }).Count -gt 0) { throw 'Post-restore snapshot verification failed' }
        $transaction.recoverySeal = Get-TransactionRecoverySeal -Transaction $transaction -RecoveryKind ([string]$RestorePlan.recoveryKind)
        $transaction.status = 'Restored'
        $transaction | Add-Member -MemberType NoteProperty -Name restoredAt -Value ([DateTimeOffset]::Now.ToString('o')) -Force
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; status = 'Restored'; backupId = $transaction.backupId; transactionPath = $transactionPath; exitCode = 0 }
    }
    catch {
        $transaction.status = 'RecoveryRequired'
        $transaction.recoverySeal = $null
        $transaction.restoreError = $_.Exception.Message
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction -AllowedRoot $transactionRoot
        throw "Restore transaction requires recovery:$($_.Exception.Message); backupId=$($transaction.backupId)"
    }
}

function Write-HumanResult {
    param([Parameter(Mandatory = $true)]$Result)

    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['planDigest'] -and $null -ne $Result.planDigest) { Write-Output "PlanDigest: $($Result.planDigest)" }
    if ($Result.PSObject.Properties['backupId'] -and $null -ne $Result.backupId) { Write-Output "BackupId: $($Result.backupId)" }
    if ($Result.PSObject.Properties['recoveryKind'] -and $null -ne $Result.recoveryKind) { Write-Output "RecoveryKind: $($Result.recoveryKind)" }
    if ($Result.PSObject.Properties['targets']) {
        foreach ($target in @($Result.targets)) {
            Write-Output ("[{0}/{1}] {2} -> {3} ({4})" -f $target.skill, $target.role, $target.entryKind, $target.action, $target.reason)
        }
    }
    if ($Result.PSObject.Properties['itemStates']) {
        foreach ($state in @($Result.itemStates)) {
            Write-Output ("[Restore/{0}] {1}" -f $state.state, $state.targetPath)
            if (-not [string]::IsNullOrWhiteSpace([string]$state.stagingRemovalIdentity)) { Write-Output ("  staged junction: {0}" -f $state.stagingPath) }
        }
    }
    if ($Result.PSObject.Properties['errors']) {
        foreach ($message in @($Result.errors)) { Write-Output "ERROR: $message" }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
    $RepositoryRoot = Get-NormalizedFullPath -Path $RepositoryRoot
    $HomeRoot = Get-NormalizedFullPath -Path $HomeRoot
    if ([string]::Equals($HomeRoot, [IO.Path]::GetPathRoot($HomeRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'HomeRoot cannot be a volume root' }

    if ($Mode -eq 'Check' -and -not [string]::IsNullOrWhiteSpace($BackupId)) {
        $result = Get-RestorePlan -UserHome $HomeRoot -RepoRoot $RepositoryRoot -RequestedBackupId $BackupId
    }
    elseif ($Mode -eq 'Check') {
        $result = Get-InstallPlan -RepoRoot $RepositoryRoot -UserHome $HomeRoot -Selection $Skill -FallbackEnabled ([bool]$IncludeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory -CurrentAgyVersion $AgyCurrentVersion
    }
    elseif ($Mode -eq 'Install') {
        if (-not [string]::IsNullOrWhiteSpace($BackupId)) { throw 'Install does not accept -BackupId' }
        $mutationMutex = Enter-HomeMutationMutex -UserHome $HomeRoot
        try {
            $check = Get-InstallPlan -RepoRoot $RepositoryRoot -UserHome $HomeRoot -Selection $Skill -FallbackEnabled ([bool]$IncludeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory -CurrentAgyVersion $AgyCurrentVersion
            $result = Invoke-SkillInstall -Plan $check -UserHome $HomeRoot -ApprovedDigest $PlanDigest
        }
        finally { Exit-HomeMutationMutex -Mutex $mutationMutex }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($BackupId)) { throw 'Restore requires an exact -BackupId' }
        $mutationMutex = Enter-HomeMutationMutex -UserHome $HomeRoot
        try {
            $check = Get-RestorePlan -UserHome $HomeRoot -RepoRoot $RepositoryRoot -RequestedBackupId $BackupId
            $result = Invoke-SkillRestore -RestorePlan $check -UserHome $HomeRoot -RepoRoot $RepositoryRoot -ApprovedDigest $PlanDigest
        }
        finally { Exit-HomeMutationMutex -Mutex $mutationMutex }
    }

    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $result) } else { Write-HumanResult -Result $result }
    exit [int]$result.exitCode
}
catch {
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = $Mode
        status = 'Error'
        error = $_.Exception.Message
        exitCode = 3
    }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $failure) } else { Write-HumanResult -Result $failure; Write-Output "ERROR: $($failure.error)" }
    exit 3
}
