#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Check', 'Install', 'Restore')]
    [string]$Mode = 'Check',

    [ValidateSet('All', 'adr-cycle', 'goal-cycle')]
    [string]$Skill = 'All',

    [string]$RepositoryRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [string]$PlanDigest,

    [string]$BackupId,

    [switch]$ApproveGlobalHomeWrite,

    [switch]$IncludeAgyCliFallback,

    [string]$AgyEvidenceDirectory
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
    [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-DirectoryManifest {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $root = Get-NormalizedFullPath -Path $Directory
    if (-not [IO.Directory]::Exists($root)) {
        throw "Manifest directory does not exist: $root"
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
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
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

function Test-SourceGitState {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $relative = "skills/$SkillName"
    $inside = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]$inside -notmatch '^true') {
        return @('RepositoryRoot is not a Git worktree')
    }
    $status = @(& git -C $RepoRoot status --porcelain=v1 --untracked-files=all -- $relative 2>&1)
    if ($LASTEXITCODE -ne 0) { return @('Unable to inspect canonical skill Git state') }
    if ($status.Count -gt 0) { return @("Canonical skill has uncommitted files:$relative") }
    return @()
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
    return [pscustomobject][ordered]@{
        skill = $SkillName
        directory = $directory
        manifest = $manifest
        errors = $errors
        valid = ($errors.Count -eq 0)
    }
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

function Get-PathEntryInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedFullPath -Path $Path
    $parent = Split-Path -Parent $full
    $leaf = Split-Path -Leaf $full
    if (-not [IO.Directory]::Exists($parent)) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; manifest = $null }
    }
    $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ceq $leaf })
    if ($entries.Count -eq 0) {
        $entries = @(Get-ChildItem -LiteralPath $parent -Force | Where-Object { $_.Name -ieq $leaf })
    }
    if ($entries.Count -eq 0) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'Missing'; target = $null; manifest = $null }
    }
    if ($entries.Count -gt 1) { throw "Multiple case-colliding entries exist at: $full" }
    $entry = $entries[0]
    if (-not $entry.PSIsContainer) {
        return [pscustomobject][ordered]@{ path = $full; kind = 'File'; target = $null; manifest = $null }
    }
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $linkType = [string]$entry.PSObject.Properties['LinkType'].Value
        $kind = if ($linkType -eq 'Junction') { 'Junction' } else { 'ReparsePoint' }
        return [pscustomobject][ordered]@{ path = $full; kind = $kind; target = Get-LinkTargetPath -Entry $entry; manifest = $null }
    }
    return [pscustomobject][ordered]@{ path = $full; kind = 'Directory'; target = $null; manifest = Get-DirectoryManifest -Directory $full }
}

function Get-TargetDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][bool]$FallbackEnabled
    )

    return @(
        [pscustomobject]@{ role = 'Agents'; category = 'Deploy'; path = Join-Path $UserHome ".agents\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'Claude'; category = 'Deploy'; path = Join-Path $UserHome ".claude\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'AgyStandard'; category = 'Deploy'; path = Join-Path $UserHome ".gemini\config\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'CodexLegacy'; category = 'Migration'; path = Join-Path $UserHome ".codex\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'CursorLegacy'; category = 'Migration'; path = Join-Path $UserHome ".cursor\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'AgyLegacy'; category = 'Migration'; path = Join-Path $UserHome ".gemini\skills\$SkillName"; enabled = $true },
        [pscustomobject]@{ role = 'AgyCliFallback'; category = 'Fallback'; path = Join-Path $UserHome ".gemini\antigravity-cli\skills\$SkillName"; enabled = $FallbackEnabled }
    )
}

function Test-AgyEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)]$Source,
        [Parameter(Mandatory = $true)][string]$StandardPath
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
        if (-not [bool]$evidence.newSession) { $errors += 'AGY evidence must come from a new session' }
        if ([bool]$evidence.standardDiscovered) { $errors += 'AGY fallback is forbidden after successful standard discovery' }
        if (-not [string]::Equals((Get-NormalizedFullPath -Path ([string]$evidence.standardPath)), (Get-NormalizedFullPath -Path $StandardPath), [StringComparison]::OrdinalIgnoreCase)) { $errors += 'AGY evidence standard path mismatch' }
        $parsedTime = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$evidence.testedAt, [ref]$parsedTime)) { $errors += 'AGY evidence testedAt is invalid' }
        return [pscustomobject]@{ valid = ($errors.Count -eq 0); errors = $errors; digest = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash }
    }
    catch {
        return [pscustomobject]@{ valid = $false; errors = @("Unable to read AGY evidence:$($_.Exception.Message)"); digest = $null }
    }
}

function Get-SelectedSkills {
    param([Parameter(Mandatory = $true)][string]$Selection)

    if ($Selection -eq 'All') { return @('adr-cycle', 'goal-cycle') }
    return @($Selection)
}

function Get-PendingRecoveryIds {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [string]$IgnoreBackupId
    )

    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    if (-not [IO.Directory]::Exists($backupRoot)) { return @() }
    $ids = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force)) {
        if (-not [string]::IsNullOrWhiteSpace($IgnoreBackupId) -and $directory.Name -ceq $IgnoreBackupId) { continue }
        $transactionPath = Join-Path $directory.FullName 'transaction.json'
        if (-not [IO.File]::Exists($transactionPath)) { continue }
        try {
            $transaction = [string]([IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
            if ([string]$transaction.status -in @('Executing', 'RecoveryRequired')) { $ids += $directory.Name }
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
        [string]$IgnoreRecoveryBackupId
    )

    $sources = @()
    $targets = @()
    $errors = @()
    $evidenceDigests = @()
    $recoveryIds = @(Get-PendingRecoveryIds -UserHome $UserHome -IgnoreBackupId $IgnoreRecoveryBackupId)
    if ($recoveryIds.Count -gt 0) { $errors += @($recoveryIds | ForEach-Object { "RecoveryRequired:$_" }) }
    foreach ($skillName in @(Get-SelectedSkills -Selection $Selection)) {
        $source = Get-SourceInfo -RepoRoot $RepoRoot -SkillName $skillName
        $sources += $source
        if (-not $source.valid) {
            $errors += @($source.errors | ForEach-Object { "${skillName}:$_" })
            continue
        }

        $definitions = @(Get-TargetDefinitions -UserHome $UserHome -SkillName $skillName -FallbackEnabled $FallbackEnabled)
        if ($FallbackEnabled) {
            if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
                $errors += "$skillName:AGY evidence directory is required for fallback"
            }
            else {
                $standard = @($definitions | Where-Object { $_.role -eq 'AgyStandard' })[0]
                $evidenceResult = Test-AgyEvidence -EvidenceDirectory $EvidenceDirectory -Source $source -StandardPath $standard.path
                if (-not $evidenceResult.valid) { $errors += @($evidenceResult.errors | ForEach-Object { "${skillName}:$_" }) }
                elseif ($null -ne $evidenceResult.digest) { $evidenceDigests += "${skillName}:$($evidenceResult.digest)" }
            }
        }

        foreach ($definition in $definitions) {
            Assert-PathWithin -Root $UserHome -Candidate $definition.path -Label 'Skill target'
            $entry = Get-PathEntryInfo -Path $definition.path
            $action = 'None'
            $reason = ''
            $conflict = $false

            if ($definition.category -eq 'Fallback' -and -not $definition.enabled) {
                if ($entry.kind -ne 'Missing') {
                    $conflict = $true
                    $reason = 'AGY fallback exists without current negative-discovery evidence'
                }
            }
            elseif ($entry.kind -eq 'Missing') {
                if ($definition.category -in @('Deploy', 'Fallback')) {
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
                elseif ($definition.category -eq 'Migration') {
                    $action = 'RemoveLegacyJunction'
                    $reason = 'Legacy active duplicate points to the canonical source'
                }
                else {
                    $reason = 'Healthy canonical junction'
                }
            }
            elseif ($entry.kind -eq 'Directory') {
                $comparison = Compare-DirectoryManifest -Expected $source.manifest -Actual $entry.manifest
                if (-not $comparison.equal) {
                    $conflict = $true
                    $reason = "Manifest mismatch:$([string]::Join(',', @($comparison.differences)))"
                }
                elseif ($definition.category -eq 'Migration') {
                    $action = 'BackupOnly'
                    $reason = 'Identical legacy active duplicate'
                }
                else {
                    $action = 'BackupAndLink'
                    $reason = 'Identical directory can be backed up and linked'
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
                path = Get-NormalizedFullPath -Path $definition.path
                entryKind = $entry.kind
                currentTarget = $entry.target
                currentDigest = if ($null -ne $entry.manifest) { $entry.manifest.digest } else { $null }
                sourcePath = $source.directory
                sourceDigest = $source.manifest.digest
                action = $action
                conflict = $conflict
                reason = $reason
            }
            if ($conflict) { $errors += "$skillName/$($definition.role):$reason" }
        }
    }

    $planLines = @('schema=1', "selection=$Selection", "fallback=$FallbackEnabled")
    $planLines += @($recoveryIds | ForEach-Object { "recovery|$_" })
    $planLines += @($sources | Sort-Object skill | ForEach-Object { "source|$($_.skill)|$($_.directory)|$(if ($null -ne $_.manifest) { $_.manifest.digest } else { 'INVALID' })" })
    $planLines += @($targets | Sort-Object skill, role | ForEach-Object { "target|$($_.skill)|$($_.role)|$($_.path)|$($_.entryKind)|$($_.currentTarget)|$($_.currentDigest)|$($_.action)|$($_.conflict)" })
    $planLines += @($evidenceDigests | Sort-Object | ForEach-Object { "evidence|$_" })
    $digest = Get-Sha256Text -Text ([string]::Join("`n", $planLines))

    $hasInvalidSource = @($sources | Where-Object { -not $_.valid }).Count -gt 0
    $hasConflict = @($targets | Where-Object { $_.conflict }).Count -gt 0 -or $errors.Count -gt 0
    $hasActions = @($targets | Where-Object { $_.action -ne 'None' }).Count -gt 0
    $status = if ($hasInvalidSource) { 'SourceInvalid' } elseif ($recoveryIds.Count -gt 0) { 'RecoveryRequired' } elseif ($hasConflict) { 'Conflict' } elseif ($hasActions) { 'Installable' } else { 'Healthy' }
    $exitCode = if ($status -eq 'Healthy') { 0 } elseif ($status -eq 'Installable') { 2 } else { 3 }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'Check'
        status = $status
        selection = $Selection
        repositoryRoot = $RepoRoot
        homeRoot = $UserHome
        includeAgyCliFallback = $FallbackEnabled
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
        [Parameter(Mandatory = $true)]$Transaction
    )
    Write-JsonAtomic -Path $TransactionPath -Value $Transaction
}

function Remove-OwnedJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget
    )

    $entry = Get-PathEntryInfo -Path $Path
    if ($entry.kind -eq 'Missing') { return }
    if ($entry.kind -ne 'Junction' -or $null -eq $entry.target -or
        -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $ExpectedTarget), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unowned junction: $Path"
    }
    [IO.Directory]::Delete((Get-NormalizedFullPath -Path $Path), $false)
}

function New-CanonicalJunction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $null = New-Item -ItemType Junction -Path $Path -Target $Target
    $entry = Get-PathEntryInfo -Path $Path
    if ($entry.kind -ne 'Junction' -or -not [string]::Equals([string]$entry.target, (Get-NormalizedFullPath -Path $Target), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Junction verification failed: $Path"
    }
}

function Invoke-TransactionRollback {
    param([Parameter(Mandatory = $true)]$Transaction)

    $items = @($Transaction.items)
    [array]::Reverse($items)
    foreach ($item in $items) {
        if (-not [bool]$item.changed) { continue }
        if ([bool]$item.createdJunction) {
            Remove-OwnedJunction -Path ([string]$item.targetPath) -ExpectedTarget ([string]$item.sourcePath)
        }
        $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
        if ([string]$item.originalKind -eq 'Directory') {
            if ($entry.kind -ne 'Missing') { throw "Rollback target is occupied: $($item.targetPath)" }
            if (-not [IO.Directory]::Exists([string]$item.backupPath)) { throw "Rollback backup is missing: $($item.backupPath)" }
            $parent = Split-Path -Parent ([string]$item.targetPath)
            if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
            Move-Item -LiteralPath ([string]$item.backupPath) -Destination ([string]$item.targetPath)
        }
        elseif ([string]$item.originalKind -eq 'Junction') {
            if ($entry.kind -ne 'Missing') { throw "Rollback target is occupied: $($item.targetPath)" }
            New-CanonicalJunction -Path ([string]$item.targetPath) -Target ([string]$item.originalTarget)
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
    Assert-PathWithin -Root $UserHome -Candidate $backupRoot -Label 'Backup root'
    if (-not [IO.Directory]::Exists($backupRoot)) { $null = New-Item -ItemType Directory -Path $backupRoot -Force }
    $newBackupId = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $transactionRoot = Join-Path $backupRoot $newBackupId
    Assert-PathWithin -Root $backupRoot -Candidate $transactionRoot -Label 'Transaction root'
    $itemsRoot = Join-Path $transactionRoot 'items'
    $null = New-Item -ItemType Directory -Path $itemsRoot -Force
    $transactionPath = Join-Path $transactionRoot 'transaction.json'

    $items = @()
    foreach ($target in @($Plan.targets | Where-Object { $_.action -ne 'None' })) {
        $relative = Get-RelativePathPortable -Root $UserHome -Path ([string]$target.path)
        $backupPath = Join-Path $itemsRoot ($relative.Replace('/', '\'))
        Assert-PathWithin -Root $itemsRoot -Candidate $backupPath -Label 'Backup item'
        $items += [pscustomobject][ordered]@{
            skill = $target.skill
            role = $target.role
            action = $target.action
            targetPath = $target.path
            sourcePath = $target.sourcePath
            originalKind = $target.entryKind
            originalTarget = $target.currentTarget
            originalDigest = $target.currentDigest
            backupPath = if ($target.entryKind -eq 'Directory') { $backupPath } else { $null }
            changed = $false
            createdJunction = $false
        }
    }
    $transaction = [pscustomobject][ordered]@{
        schemaVersion = 1
        backupId = $newBackupId
        status = 'Executing'
        createdAt = [DateTimeOffset]::Now.ToString('o')
        planDigest = $Plan.planDigest
        homeRoot = $UserHome
        repositoryRoot = $Plan.repositoryRoot
        selection = $Plan.selection
        includeAgyCliFallback = $Plan.includeAgyCliFallback
        items = $items
        error = $null
    }
    Save-Transaction -TransactionPath $transactionPath -Transaction $transaction

    try {
        foreach ($item in @($transaction.items)) {
            $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
            if ([string]$item.originalKind -eq 'Directory') {
                if ($entry.kind -ne 'Directory' -or -not [string]::Equals([string]$entry.manifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Target changed after Check: $($item.targetPath)"
                }
                $backupParent = Split-Path -Parent ([string]$item.backupPath)
                if (-not [IO.Directory]::Exists($backupParent)) { $null = New-Item -ItemType Directory -Path $backupParent -Force }
                Move-Item -LiteralPath ([string]$item.targetPath) -Destination ([string]$item.backupPath)
                $backupManifest = Get-DirectoryManifest -Directory ([string]$item.backupPath)
                if (-not [string]::Equals([string]$backupManifest.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Backup verification failed: $($item.backupPath)"
                }
                $item.changed = $true
            }
            elseif ([string]$item.originalKind -eq 'Junction') {
                Remove-OwnedJunction -Path ([string]$item.targetPath) -ExpectedTarget ([string]$item.sourcePath)
                $item.changed = $true
            }
            elseif ([string]$item.originalKind -ne 'Missing') {
                throw "Unsupported original kind during install: $($item.originalKind)"
            }

            if ([string]$item.action -in @('CreateJunction', 'BackupAndLink')) {
                New-CanonicalJunction -Path ([string]$item.targetPath) -Target ([string]$item.sourcePath)
                $item.createdJunction = $true
                $item.changed = $true
            }
            Save-Transaction -TransactionPath $transactionPath -Transaction $transaction
        }

        $postPlan = Get-InstallPlan -RepoRoot ([string]$Plan.repositoryRoot) -UserHome $UserHome -Selection ([string]$Plan.selection) -FallbackEnabled ([bool]$Plan.includeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory -IgnoreRecoveryBackupId $newBackupId
        if ($postPlan.status -ne 'Healthy') { throw "Post-install Check failed:$($postPlan.status)" }
        $transaction.status = 'Committed'
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Install'; status = 'Committed'; planDigest = $Plan.planDigest; backupId = $newBackupId; transactionPath = $transactionPath; exitCode = 0 }
    }
    catch {
        $installError = $_.Exception.Message
        try {
            Invoke-TransactionRollback -Transaction $transaction
            $transaction.status = 'RolledBack'
        }
        catch {
            $transaction.status = 'RecoveryRequired'
            $installError = "$installError; rollback failed: $($_.Exception.Message)"
        }
        $transaction.error = $installError
        Save-Transaction -TransactionPath $transactionPath -Transaction $transaction
        throw "Install transaction failed:$installError; backupId=$newBackupId"
    }
}

function Get-RestorePlan {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$RequestedBackupId
    )

    if ($RequestedBackupId -notmatch '^\d{8}-\d{9}-[a-f0-9]{8}$') { throw 'BackupId format is invalid; latest and path traversal are not supported' }
    $backupRoot = Join-Path $UserHome '.yohan-skill-backups'
    $transactionRoot = Join-Path $backupRoot $RequestedBackupId
    Assert-PathWithin -Root $backupRoot -Candidate $transactionRoot -Label 'Restore transaction'
    $transactionPath = Join-Path $transactionRoot 'transaction.json'
    if (-not [IO.File]::Exists($transactionPath)) { throw "Transaction does not exist:$RequestedBackupId" }
    $transaction = [string]([IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    if ([string]$transaction.backupId -cne $RequestedBackupId) { throw 'Transaction BackupId mismatch' }
    if ([string]$transaction.status -eq 'Restored') {
        return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'CheckRestore'; status = 'Restored'; backupId = $RequestedBackupId; planDigest = $null; transaction = $transaction; errors = @(); exitCode = 0 }
    }
    if ([string]$transaction.status -ne 'Committed') { throw "Transaction is not restorable:$($transaction.status)" }

    $errors = @()
    $digestLines = @("backupId=$RequestedBackupId", "transactionPlan=$($transaction.planDigest)")
    foreach ($item in @($transaction.items)) {
        Assert-PathWithin -Root $UserHome -Candidate ([string]$item.targetPath) -Label 'Restore target'
        $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
        if ([bool]$item.createdJunction) {
            if ($entry.kind -ne 'Junction' -or $null -eq $entry.target -or -not [string]::Equals([string]$entry.target, [string]$item.sourcePath, [StringComparison]::OrdinalIgnoreCase)) {
                $errors += "Current target is not the transaction junction:$($item.targetPath)"
            }
        }
        elseif ($entry.kind -ne 'Missing') {
            $errors += "Migration target was recreated outside Restore:$($item.targetPath)"
        }

        $backupDigest = ''
        if ([string]$item.originalKind -eq 'Directory') {
            if (-not [IO.Directory]::Exists([string]$item.backupPath)) {
                $errors += "Backup directory is missing:$($item.backupPath)"
            }
            else {
                try {
                    $backupManifest = Get-DirectoryManifest -Directory ([string]$item.backupPath)
                    $backupDigest = [string]$backupManifest.digest
                    if (-not [string]::Equals($backupDigest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                        $errors += "Backup directory was modified:$($item.backupPath)"
                    }
                }
                catch { $errors += $_.Exception.Message }
            }
        }
        $digestLines += "item|$($item.targetPath)|$($entry.kind)|$($entry.target)|$backupDigest|$($item.originalKind)|$($item.originalTarget)"
    }
    $digest = Get-Sha256Text -Text ([string]::Join("`n", $digestLines))
    $status = if ($errors.Count -eq 0) { 'RestoreReady' } else { 'Conflict' }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'CheckRestore'
        status = $status
        backupId = $RequestedBackupId
        planDigest = $digest
        transaction = $transaction
        errors = $errors
        exitCode = if ($status -eq 'RestoreReady') { 0 } else { 3 }
    }
}

function Invoke-SkillRestore {
    param(
        [Parameter(Mandatory = $true)]$RestorePlan,
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
    $items = @($transaction.items)
    [array]::Reverse($items)
    foreach ($item in $items) {
        if ([bool]$item.createdJunction) {
            Remove-OwnedJunction -Path ([string]$item.targetPath) -ExpectedTarget ([string]$item.sourcePath)
        }
        $entry = Get-PathEntryInfo -Path ([string]$item.targetPath)
        if ([string]$item.originalKind -eq 'Directory') {
            if ($entry.kind -ne 'Missing') { throw "Restore target is occupied:$($item.targetPath)" }
            $parent = Split-Path -Parent ([string]$item.targetPath)
            if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
            Move-Item -LiteralPath ([string]$item.backupPath) -Destination ([string]$item.targetPath)
            $restored = Get-DirectoryManifest -Directory ([string]$item.targetPath)
            if (-not [string]::Equals([string]$restored.digest, [string]$item.originalDigest, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Restored manifest mismatch:$($item.targetPath)"
            }
        }
        elseif ([string]$item.originalKind -eq 'Junction') {
            if ($entry.kind -ne 'Missing') { throw "Restore target is occupied:$($item.targetPath)" }
            New-CanonicalJunction -Path ([string]$item.targetPath) -Target ([string]$item.originalTarget)
        }
    }
    $transaction.status = 'Restored'
    $transaction | Add-Member -MemberType NoteProperty -Name restoredAt -Value ([DateTimeOffset]::Now.ToString('o')) -Force
    $transactionPath = Join-Path (Join-Path (Join-Path ([string]$transaction.homeRoot) '.yohan-skill-backups') ([string]$transaction.backupId)) 'transaction.json'
    Save-Transaction -TransactionPath $transactionPath -Transaction $transaction
    return [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; status = 'Restored'; backupId = $transaction.backupId; transactionPath = $transactionPath; exitCode = 0 }
}

function Write-HumanResult {
    param([Parameter(Mandatory = $true)]$Result)

    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['planDigest'] -and $null -ne $Result.planDigest) { Write-Output "PlanDigest: $($Result.planDigest)" }
    if ($Result.PSObject.Properties['backupId'] -and $null -ne $Result.backupId) { Write-Output "BackupId: $($Result.backupId)" }
    if ($Result.PSObject.Properties['targets']) {
        foreach ($target in @($Result.targets)) {
            Write-Output ("[{0}/{1}] {2} -> {3} ({4})" -f $target.skill, $target.role, $target.entryKind, $target.action, $target.reason)
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

    if ($Mode -eq 'Check' -and -not [string]::IsNullOrWhiteSpace($BackupId)) {
        $result = Get-RestorePlan -UserHome $HomeRoot -RequestedBackupId $BackupId
    }
    elseif ($Mode -eq 'Check') {
        $result = Get-InstallPlan -RepoRoot $RepositoryRoot -UserHome $HomeRoot -Selection $Skill -FallbackEnabled ([bool]$IncludeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory
    }
    elseif ($Mode -eq 'Install') {
        if (-not [string]::IsNullOrWhiteSpace($BackupId)) { throw 'Install does not accept -BackupId' }
        $check = Get-InstallPlan -RepoRoot $RepositoryRoot -UserHome $HomeRoot -Selection $Skill -FallbackEnabled ([bool]$IncludeAgyCliFallback) -EvidenceDirectory $AgyEvidenceDirectory
        $result = Invoke-SkillInstall -Plan $check -UserHome $HomeRoot -ApprovedDigest $PlanDigest
    }
    else {
        if ([string]::IsNullOrWhiteSpace($BackupId)) { throw 'Restore requires an exact -BackupId' }
        $check = Get-RestorePlan -UserHome $HomeRoot -RequestedBackupId $BackupId
        $result = Invoke-SkillRestore -RestorePlan $check -ApprovedDigest $PlanDigest
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
