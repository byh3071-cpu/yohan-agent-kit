#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Skill,

    [string]$RepositoryRoot,

    [switch]$Write
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Get-GitExecutable {
    $candidates = @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate.Source) -and [IO.File]::Exists([string]$candidate.Source)) {
            return [string]$candidate.Source
        }
    }
    throw 'git.exe is not installed or is not available on PATH'
}

function Invoke-GitReadOnly {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $gitExecutable = Get-GitExecutable
    $previousErrorActionPreference = $ErrorActionPreference
    $previousOptionalLocks = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS', 'Process')
    $ErrorActionPreference = 'Continue'
    try {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0', 'Process')
        $output = @(& $gitExecutable -c 'core.excludesFile=NUL' -C $RepoRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', $previousOptionalLocks, 'Process')
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -notin $AllowedExitCodes) {
        $detail = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
        throw "Git command failed ($exitCode): $detail"
    }
    return [pscustomobject]@{
        exitCode = $exitCode
        lines = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-RelativeSkillPath {
    param(
        [Parameter(Mandatory = $true)][string]$SkillRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $SkillRoot
    $normalizedPath = Get-NormalizedFullPath -Path $Path
    $prefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $normalizedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Skill path escapes its root: $normalizedPath"
    }
    return $normalizedPath.Substring($prefix.Length).Replace('\', '/')
}

function Get-SafeSkillFiles {
    param([Parameter(Mandatory = $true)][string]$SkillRoot)

    $rootEntry = Get-Item -LiteralPath $SkillRoot -Force
    if (($rootEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Skill directory is a reparse point: $SkillRoot"
    }

    $pending = New-Object Collections.Generic.Stack[string]
    $pending.Push($SkillRoot)
    $files = @()
    $seen = @{}
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $relative = Get-RelativeSkillPath -SkillRoot $SkillRoot -Path $entry.FullName
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Skill contains a reparse point: $relative"
            }
            if ($entry.PSIsContainer) {
                $pending.Push($entry.FullName)
                continue
            }

            $caseKey = $relative.ToLowerInvariant()
            if ($seen.ContainsKey($caseKey) -and [string]$seen[$caseKey] -cne $relative) {
                throw "Skill contains a case-colliding path: $relative and $($seen[$caseKey])"
            }
            $seen[$caseKey] = $relative
            $files += [pscustomobject]@{ relativePath = $relative; file = $entry }
        }
    }
    return @($files)
}

function Assert-SkillFileUtf8 {
    param([Parameter(Mandatory = $true)][string]$SkillRoot)

    $skillFile = Join-Path $SkillRoot 'SKILL.md'
    if (-not [IO.File]::Exists($skillFile)) {
        throw "SKILL.md does not exist: $skillFile"
    }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try {
        $null = $strictUtf8.GetString([IO.File]::ReadAllBytes($skillFile))
    }
    catch [Text.DecoderFallbackException] {
        throw "SKILL.md is not valid UTF-8: $skillFile"
    }
}

function Assert-CleanTrackedSkill {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][object[]]$Files
    )

    $inside = Invoke-GitReadOnly -RepoRoot $RepoRoot -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($inside.lines.Count -ne 1 -or $inside.lines[0] -cne 'true') {
        throw 'RepositoryRoot is not a Git worktree'
    }

    $skillRelative = "skills/$SkillName"
    $trackedResult = Invoke-GitReadOnly -RepoRoot $RepoRoot -Arguments @('ls-files', '--', $skillRelative)
    $trackedPaths = @($trackedResult.lines)
    $seenTracked = @{}
    foreach ($path in $trackedPaths) {
        $caseKey = ([string]$path).ToLowerInvariant()
        if ($seenTracked.ContainsKey($caseKey) -and [string]$seenTracked[$caseKey] -cne [string]$path) {
            throw "Skill contains a case-colliding path: $path and $($seenTracked[$caseKey])"
        }
        $seenTracked[$caseKey] = [string]$path
    }

    $actualRepositoryPaths = @($Files | ForEach-Object { "$skillRelative/$($_.relativePath)" })
    foreach ($path in $actualRepositoryPaths) {
        if (@($trackedPaths | Where-Object { [string]$_ -ceq [string]$path }).Count -eq 0) {
            throw "Untracked skill file: $path"
        }
    }
    foreach ($path in $trackedPaths) {
        if (@($actualRepositoryPaths | Where-Object { [string]$_ -ceq [string]$path }).Count -eq 0) {
            throw "Tracked skill file differs from Git index or is missing: $path"
        }
    }

    $stagedResult = Invoke-GitReadOnly -RepoRoot $RepoRoot -Arguments @('ls-files', '--stage', '--', $skillRelative)
    $stagedEntries = @()
    foreach ($line in $stagedResult.lines) {
        if ([string]$line -notmatch '^([0-9]{6})\s+([a-fA-F0-9]{40,64})\s+([0-3])\t(.+)$') {
            throw "Unable to parse skill Git index entry: $line"
        }
        if ([int]$Matches[3] -ne 0) {
            throw "Skill Git index contains an unresolved entry: $($Matches[4])"
        }
        $stagedEntries += [pscustomobject]@{
            blob = ([string]$Matches[2]).ToLowerInvariant()
            path = [string]$Matches[4]
        }
    }

    foreach ($file in $Files) {
        $repositoryPath = "$skillRelative/$($file.relativePath)"
        $indexEntry = @($stagedEntries | Where-Object { [string]$_.path -ceq $repositoryPath })
        if ($indexEntry.Count -ne 1) {
            throw "Skill Git index entry is missing or ambiguous: $repositoryPath"
        }
        $workingHash = Invoke-GitReadOnly -RepoRoot $RepoRoot -Arguments @(
            'hash-object',
            "--path=$repositoryPath",
            '--',
            [string]$file.file.FullName
        )
        if ($workingHash.lines.Count -ne 1 -or [string]$workingHash.lines[0] -notmatch '^[a-fA-F0-9]{40,64}$') {
            throw "Unable to hash tracked skill file: $repositoryPath"
        }
        if ([string]$workingHash.lines[0].ToLowerInvariant() -cne [string]$indexEntry[0].blob) {
            throw "Tracked skill file differs from Git index: $repositoryPath"
        }
    }

    $headDiff = Invoke-GitReadOnly -RepoRoot $RepoRoot -Arguments @('diff', '--cached', '--quiet', '--', $skillRelative) -AllowedExitCodes @(0, 1)
    if ($headDiff.exitCode -eq 1) {
        throw "Skill Git index differs from HEAD: $skillRelative"
    }
}

function Compare-ManifestPath {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $caseInsensitive = [string]::Compare($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
    if ($caseInsensitive -ne 0) { return $caseInsensitive }
    return [string]::CompareOrdinal($Left, $Right)
}

function Sort-ManifestRows {
    param([Parameter(Mandatory = $true)][object[]]$Rows)

    $sorted = New-Object Collections.ArrayList
    foreach ($row in $Rows) {
        $index = 0
        while ($index -lt $sorted.Count -and (Compare-ManifestPath -Left ([string]$sorted[$index].path) -Right ([string]$row.path)) -le 0) {
            $index++
        }
        $sorted.Insert($index, $row)
    }
    return @($sorted)
}

function Initialize-SafeManifestWriteTarget {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $RepoRoot
    $rootEntry = Get-Item -LiteralPath $normalizedRoot -Force
    if (($rootEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "RepositoryRoot is a reparse point: $normalizedRoot"
    }
    if (-not $rootEntry.PSIsContainer) {
        throw "RepositoryRoot is not a directory: $normalizedRoot"
    }

    $current = $normalizedRoot
    foreach ($segment in @('distribution', 'manifests')) {
        $candidate = Join-Path $current $segment
        if (Test-Path -LiteralPath $candidate) {
            $entry = Get-Item -LiteralPath $candidate -Force
        }
        else {
            $null = New-Item -ItemType Directory -Path $candidate
            $entry = Get-Item -LiteralPath $candidate -Force
        }
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Manifest output path contains a reparse point: $candidate"
        }
        if (-not $entry.PSIsContainer) {
            throw "Manifest output path is not a directory: $candidate"
        }

        $normalizedCandidate = Get-NormalizedFullPath -Path $candidate
        $rootPrefix = $normalizedRoot + [IO.Path]::DirectorySeparatorChar
        if (-not $normalizedCandidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest output path escapes RepositoryRoot: $normalizedCandidate"
        }
        $current = $normalizedCandidate
    }

    $target = Join-Path $current "$SkillName.json"
    $normalizedTarget = Get-NormalizedFullPath -Path $target
    $manifestPrefix = $current + [IO.Path]::DirectorySeparatorChar
    if (-not $normalizedTarget.StartsWith($manifestPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest output target escapes its directory: $normalizedTarget"
    }
    if (Test-Path -LiteralPath $normalizedTarget) {
        $targetEntry = Get-Item -LiteralPath $normalizedTarget -Force
        if (($targetEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Manifest output target is a reparse point: $normalizedTarget"
        }
        $linkTypeProperty = $targetEntry.PSObject.Properties['LinkType']
        if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrWhiteSpace([string]$linkTypeProperty.Value)) {
            throw "Manifest output target is a linked target ($($linkTypeProperty.Value)): $normalizedTarget"
        }
        if ($targetEntry.PSIsContainer) {
            throw "Manifest output target is not a file: $normalizedTarget"
        }
    }
    return $normalizedTarget
}

try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = Split-Path -Parent $PSScriptRoot
    }
    $normalizedRepositoryRoot = Get-NormalizedFullPath -Path $RepositoryRoot
    $skillDirectory = Join-Path $normalizedRepositoryRoot "skills\$Skill"
    if (-not [IO.Directory]::Exists($skillDirectory)) {
        throw "Skill directory does not exist: $skillDirectory"
    }

    $safeFiles = Get-SafeSkillFiles -SkillRoot $skillDirectory
    Assert-SkillFileUtf8 -SkillRoot $skillDirectory
    Assert-CleanTrackedSkill -RepoRoot $normalizedRepositoryRoot -SkillName $Skill -Files $safeFiles

    $rows = @()
    foreach ($entry in $safeFiles) {
        $rows += [pscustomobject][ordered]@{
            path = [string]$entry.relativePath
            bytes = [int64]$entry.file.Length
            sha256 = (Get-Sha256File -Path $entry.file.FullName).ToUpperInvariant()
        }
    }
    $rows = @(Sort-ManifestRows -Rows $rows)
    $digestInput = [string]::Join("`n", @($rows | ForEach-Object { "$($_.path)`0$($_.bytes)`0$($_.sha256)" }))
    $manifest = [pscustomobject][ordered]@{
        schemaVersion = 1
        skill = $Skill
        files = $rows
        digest = Get-Sha256Text -Text $digestInput
    }
    $json = [string]($manifest | ConvertTo-Json -Depth 8)

    if ($Write) {
        $manifestTarget = Initialize-SafeManifestWriteTarget -RepoRoot $normalizedRepositoryRoot -SkillName $Skill
        [IO.File]::WriteAllText(
            $manifestTarget,
            $json + [Environment]::NewLine,
            (New-Object Text.UTF8Encoding($false))
        )
    }
    else {
        Write-Output $json
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
