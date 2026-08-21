#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Check', 'Review', 'ExportDraft')]
    [string]$Mode = 'Check',

    [string]$SourcePath,

    [ValidateSet('skill', 'agent', 'command', 'hook', 'rule', 'mcp', 'script', 'template', 'plugin')]
    [string]$Kind = 'skill',

    [string]$CanonicalId,

    [string]$Owner = 'local-user',

    [string]$Provenance,

    [string]$License = 'UNKNOWN',

    [string[]]$Vendors = @('claude-code', 'codex', 'cursor', 'antigravity'),

    [string]$CandidateId,

    [string]$RepositoryRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [switch]$ApproveInboxWrite
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$allowedVendors = @('agent-plugins', 'claude-code', 'codex', 'cursor', 'antigravity')
$allowedLicenses = @('MIT', 'Apache-2.0', 'BSD-2-Clause', 'BSD-3-Clause', 'CC0-1.0', 'MPL-2.0', 'UNLICENSED')

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
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

function Assert-PathWithin {
    param([string]$Root, [string]$Candidate, [string]$Label)
    if (-not (Test-PathWithin -Root $Root -Candidate $Candidate)) { throw "$Label escapes its allowed root: $Candidate" }
}

function Assert-NoReparseAncestors {
    param([string]$Root, [string]$Candidate, [switch]$IncludeLeaf)
    Assert-PathWithin -Root $Root -Candidate $Candidate -Label 'Inbox path'
    $base = Get-NormalizedFullPath -Path $Root
    $full = Get-NormalizedFullPath -Path $Candidate
    $relative = $full.Substring($base.Length).TrimStart('\', '/')
    $segments = @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $limit = if ($IncludeLeaf) { $segments.Count } else { [Math]::Max(0, $segments.Count - 1) }
    $current = $base
    for ($index = 0; $index -lt $limit; $index++) {
        if (-not [IO.Directory]::Exists($current)) { break }
        $entries = @(Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $segments[$index] })
        if ($entries.Count -eq 0) { break }
        if ($entries.Count -gt 1) { throw "Case-colliding Inbox path entries exist under: $current" }
        $entry = $entries[0]
        $linkType = $entry.PSObject.Properties['LinkType']
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value))) { throw "Inbox path contains a linked entry: $($entry.FullName)" }
        if (-not $entry.PSIsContainer -and $index -lt ($limit - 1)) { throw "Inbox ancestor is not a directory: $($entry.FullName)" }
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

function ConvertTo-AsciiJson {
    param($Value)
    try { $json = [string]($Value | ConvertTo-Json -Depth 24) }
    catch {
        $badFields = @()
        if ($null -ne $Value -and $null -ne $Value.PSObject) {
            foreach ($property in @($Value.PSObject.Properties)) {
                try { $null = $property.Value | ConvertTo-Json -Depth 24 } catch { $badFields += $property.Name }
            }
        }
        throw "JSON serialization failed for fields: $([string]::Join(',', $badFields))"
    }
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($Match) return ('\u{0:x4}' -f [int][char]$Match.Value) })
}

function Write-JsonAtomic {
    param([string]$Path, $Value, [string]$AllowedRoot)
    Assert-PathWithin -Root $AllowedRoot -Candidate $Path -Label 'Inbox JSON'
    Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $Path -IncludeLeaf
    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $Path -IncludeLeaf
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, (ConvertTo-AsciiJson -Value $Value) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($Path)) {
        $backup = "$Path.$([Guid]::NewGuid().ToString('N')).previous"
        try { [IO.File]::Replace($temporary, $Path, $backup, $true); [IO.File]::Delete($backup) }
        finally {
            if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
            if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
        }
    }
    else { [IO.File]::Move($temporary, $Path) }
}

function Get-OrdinaryFiles {
    param([string]$Path)
    $full = Get-NormalizedFullPath -Path $Path
    $entry = Get-Item -LiteralPath $full -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Source cannot be a reparse point: $full" }
    if (-not $entry.PSIsContainer) { return @($entry) }
    $directories = @(Get-ChildItem -LiteralPath $full -Directory -Recurse -Force)
    foreach ($directory in $directories) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Source contains a reparse point: $($directory.FullName)" }
    }
    $files = @(Get-ChildItem -LiteralPath $full -File -Recurse -Force)
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Source contains a reparse point: $($file.FullName)" }
    }
    return $files
}

function Get-TreeInfo {
    param([string]$Path)
    $full = Get-NormalizedFullPath -Path $Path
    $entry = Get-Item -LiteralPath $full -Force
    $base = if ($entry.PSIsContainer) { $full } else { Split-Path -Parent $full }
    $files = @(Get-OrdinaryFiles -Path $full)
    if ($files.Count -eq 0) { throw 'Intake source must contain at least one file' }
    if ($files.Count -gt 500) { throw 'Intake source exceeds the 500-file limit' }
    $total = [int64]0
    $rows = @()
    foreach ($file in @($files | Sort-Object FullName)) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $total += $bytes.LongLength
        if ($total -gt 10485760) { throw 'Intake source exceeds the 10 MiB limit' }
        $relative = if ($entry.PSIsContainer) { $file.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/') } else { $file.Name }
        $rows += "$relative|$($bytes.LongLength)|$(Get-Sha256Bytes -Bytes $bytes)"
    }
    return [pscustomobject][ordered]@{ digest = Get-Sha256Text -Text ([string]::Join("`n", $rows)); files = $files; fileCount = $files.Count; bytes = $total; base = $base; isDirectory = [bool]$entry.PSIsContainer; leaf = $entry.Name }
}

function Get-TextFindings {
    param([object[]]$Files)
    $secretPatterns = @(
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|client[_-]?secret)\b\s*[:=]\s*["'']?[^\s"'']{8,}',
        '\bgh[pousr]_[A-Za-z0-9_]{20,}\b',
        '\bsk-[A-Za-z0-9_-]{20,}\b'
    )
    $absolutePatterns = @('(?i)[A-Z]:\\Users\\', '(?i)\\\\[^\\]+\\[^\\]+', '(?i)file:///', '(?i)(?:^|[\s"''])/home/[^/\s]+/')
    $secret = @()
    $absolute = @()
    foreach ($file in $Files) {
        if ($file.Name -match '^\.env(?:\.|$)' -or $file.Extension -in @('.pem', '.key')) { $secret += $file.Name; continue }
        if ($file.Length -gt 1048576) { continue }
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        if (@($secretPatterns | Where-Object { $text -match $_ }).Count -gt 0) { $secret += $file.Name }
        if (@($absolutePatterns | Where-Object { $text -match $_ }).Count -gt 0) { $absolute += $file.Name }
    }
    return [pscustomobject][ordered]@{ secretFiles = @($secret | Sort-Object -Unique); absolutePathFiles = @($absolute | Sort-Object -Unique) }
}

function Copy-TreeExact {
    param([string]$Source, [string]$Destination, [string]$AllowedRoot)
    $info = Get-TreeInfo -Path $Source
    if ([IO.Directory]::Exists($Destination) -or [IO.File]::Exists($Destination)) { throw "Intake destination already exists: $Destination" }
    foreach ($file in $info.files) {
        $relative = if ($info.isDirectory) { $file.FullName.Substring($info.base.Length).TrimStart('\') } else { $file.Name }
        $target = Join-Path $Destination $relative
        Assert-PathWithin -Root $AllowedRoot -Candidate $target -Label 'Intake copy'
        Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $target
        $parent = Split-Path -Parent $target
        if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        Assert-NoReparseAncestors -Root $AllowedRoot -Candidate $target
        [IO.File]::Copy($file.FullName, $target, $false)
    }
    return $info
}

function Read-Candidate {
    param([string]$InboxRoot, [string]$Id)
    if ($Id -notmatch '^\d{8}-\d{9}-[a-f0-9]{12}$') { throw 'CandidateId format is invalid' }
    $path = Join-Path $InboxRoot "$Id\candidate.json"
    Assert-NoReparseAncestors -Root $InboxRoot -Candidate $path -IncludeLeaf
    if (-not [IO.File]::Exists($path)) { throw "Candidate does not exist: $Id" }
    $candidate = [string]([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    if ([int]$candidate.schemaVersion -ne 1 -or [string]$candidate.candidateId -cne $Id) { throw 'Candidate identity mismatch' }
    return [pscustomobject][ordered]@{ path = $path; root = Split-Path -Parent $path; data = $candidate }
}

function Get-InboxCandidateFiles {
    param([string]$InboxRoot)
    if (-not [IO.Directory]::Exists($InboxRoot)) { return @() }
    $files = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $InboxRoot -Directory -Force)) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Inbox candidate is a reparse point: $($directory.Name)" }
        $candidatePath = Join-Path $directory.FullName 'candidate.json'
        if ([IO.File]::Exists($candidatePath)) {
            Assert-NoReparseAncestors -Root $InboxRoot -Candidate $candidatePath -IncludeLeaf
            $files += Get-Item -LiteralPath $candidatePath -Force
        }
    }
    return $files
}

function Find-Duplicates {
    param([string]$RepoRoot, [string]$InboxRoot, [string]$Id, [string]$Digest, [string]$ExcludeCandidateId)
    $duplicateMatches = @()
    $registryPath = Join-Path $RepoRoot 'registry\assets.yaml'
    $registry = [string]([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    foreach ($asset in @($registry.assets)) {
        if ([string]$asset.id -ceq $Id) { $duplicateMatches += "registry-id:$($asset.id)"; continue }
        if ([string]$asset.sourcePath -match '^(?:home|project|external)://') { continue }
        $path = Join-Path $RepoRoot ([string]$asset.sourcePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try { if ([string](Get-TreeInfo -Path $path).digest -ceq $Digest) { $duplicateMatches += "registry-digest:$($asset.id)" } } catch { }
    }
    if ([IO.Directory]::Exists($InboxRoot)) {
        foreach ($candidateFile in @(Get-InboxCandidateFiles -InboxRoot $InboxRoot)) {
            try {
                $candidate = [string]([IO.File]::ReadAllText($candidateFile.FullName, [Text.Encoding]::UTF8)) | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($ExcludeCandidateId) -and [string]$candidate.candidateId -ceq $ExcludeCandidateId) { continue }
                if ([string]$candidate.canonicalId -ceq $Id) { $duplicateMatches += "inbox-id:$($candidate.candidateId)" }
                elseif ([string]$candidate.contentDigest -ceq $Digest) { $duplicateMatches += "inbox-digest:$($candidate.candidateId)" }
            } catch { }
        }
    }
    return @($duplicateMatches | Sort-Object -Unique)
}

function Get-CandidateIntegrityBlockers {
    param([string]$RepoRoot, [string]$InboxRoot, $Candidate)
    $data = $Candidate.data
    $blockers = @()
    if ([string]$data.rawPath -cne 'raw') { return @('candidate-raw-path') }
    $rawRoot = Join-Path $Candidate.root 'raw'
    Assert-PathWithin -Root $Candidate.root -Candidate $rawRoot -Label 'Candidate raw path'
    Assert-NoReparseAncestors -Root $InboxRoot -Candidate $rawRoot -IncludeLeaf
    if (-not [IO.Directory]::Exists($rawRoot)) { return @('candidate-raw-missing') }
    try {
        $info = Get-TreeInfo -Path $rawRoot
        if ([string]$info.digest -cne [string]$data.contentDigest -or [int]$info.fileCount -ne [int]$data.fileCount -or [int64]$info.bytes -ne [int64]$data.bytes) { $blockers += 'candidate-raw-drift' }
        $findings = Get-TextFindings -Files $info.files
        if (@($findings.secretFiles).Count) { $blockers += "secret-pattern:$([string]::Join(',', @($findings.secretFiles)))" }
        if (@($findings.absolutePathFiles).Count) { $blockers += "absolute-path:$([string]::Join(',', @($findings.absolutePathFiles)))" }
        if ([string]$data.license -notin $allowedLicenses) { $blockers += "license:$($data.license)" }
        $duplicates = @(Find-Duplicates -RepoRoot $RepoRoot -InboxRoot $InboxRoot -Id ([string]$data.canonicalId) -Digest ([string]$info.digest) -ExcludeCandidateId ([string]$data.candidateId))
        if ($duplicates.Count) { $blockers += "duplicate:$([string]::Join(',', $duplicates))" }
    }
    catch { $blockers += "candidate-integrity:$($_.Exception.Message)" }
    return @($blockers | Sort-Object -Unique)
}

function Write-HumanResult {
    param($Result)
    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['candidateId']) { Write-Output "CandidateId: $($Result.candidateId)" }
    if ($Result.PSObject.Properties['lifecycle']) { Write-Output "Lifecycle: $($Result.lifecycle)" }
    if ($Result.PSObject.Properties['blockers']) { foreach ($blocker in @($Result.blockers)) { Write-Output "BLOCKER: $blocker" } }
}

$exitCode = 1
try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    $RepositoryRoot = Get-NormalizedFullPath -Path $RepositoryRoot
    if ([IO.File]::Exists((Join-Path $RepositoryRoot '.vhk\HARD_STOP'))) { throw '.vhk/HARD_STOP detected' }
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
    $HomeRoot = Get-NormalizedFullPath -Path $HomeRoot
    if ([string]::Equals($HomeRoot, [IO.Path]::GetPathRoot($HomeRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'HomeRoot cannot be a volume root' }
    $inboxRoot = Join-Path $HomeRoot '.yohan-agent-kit\inbox'
    Assert-NoReparseAncestors -Root $HomeRoot -Candidate $inboxRoot -IncludeLeaf

    if ($Mode -eq 'Scan') {
        if (-not $ApproveInboxWrite) { throw 'Scan requires -ApproveInboxWrite' }
        if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path -LiteralPath $SourcePath)) { throw 'Scan requires an existing -SourcePath' }
        if ([string]::IsNullOrWhiteSpace($Provenance)) { throw 'Scan requires non-empty provenance' }
        if (@($Vendors | Where-Object { $_ -notin $allowedVendors }).Count -gt 0) { throw 'Scan contains an unsupported vendor' }
        $sourceInfo = Get-TreeInfo -Path $SourcePath
        if ([string]::IsNullOrWhiteSpace($CanonicalId)) { $CanonicalId = "$Kind.$(($sourceInfo.leaf -replace '[^A-Za-z0-9.-]', '-').ToLowerInvariant())" }
        if ($CanonicalId -notmatch '^[a-z0-9][a-z0-9.-]*$') { throw 'CanonicalId is invalid' }
        $duplicates = @(Find-Duplicates -RepoRoot $RepositoryRoot -InboxRoot $inboxRoot -Id $CanonicalId -Digest ([string]$sourceInfo.digest))
        $findings = Get-TextFindings -Files $sourceInfo.files
        $blockers = @()
        if (@($duplicates).Count) { $blockers += "duplicate:$([string]::Join(',', $duplicates))" }
        if (@($findings.secretFiles).Count) { $blockers += "secret-pattern:$([string]::Join(',', @($findings.secretFiles)))" }
        if (@($findings.absolutePathFiles).Count) { $blockers += "absolute-path:$([string]::Join(',', @($findings.absolutePathFiles)))" }
        if ($License -notin $allowedLicenses) { $blockers += "license:$License" }
        $CandidateId = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$(([string]$sourceInfo.digest).Substring(0, 12))"
        $candidateRoot = Join-Path $inboxRoot $CandidateId
        $rawRoot = Join-Path $candidateRoot 'raw'
        $null = Copy-TreeExact -Source $SourcePath -Destination $rawRoot -AllowedRoot $inboxRoot
        $copiedInfo = Get-TreeInfo -Path $rawRoot
        if ([string]$copiedInfo.digest -cne [string]$sourceInfo.digest -or [int]$copiedInfo.fileCount -ne [int]$sourceInfo.fileCount -or [int64]$copiedInfo.bytes -ne [int64]$sourceInfo.bytes) { throw 'Intake source changed while it was copied' }
        $candidate = [pscustomobject][ordered]@{
            schemaVersion = 1; candidateId = $CandidateId; canonicalId = $CanonicalId; kind = $Kind; owner = $Owner
            lifecycle = 'candidate'; provenance = $Provenance; license = $License; vendors = @($Vendors | Sort-Object -Unique)
            contentDigest = [string]$sourceInfo.digest; fileCount = [int]$sourceInfo.fileCount; bytes = [int64]$sourceInfo.bytes
            sourceLabel = [string]$sourceInfo.leaf; rawPath = 'raw'; blockers = $blockers; duplicateRefs = $duplicates
            secretFindings = @($findings.secretFiles); absolutePathFindings = @($findings.absolutePathFiles); pushAuthorized = $false
        }
        Write-JsonAtomic -Path (Join-Path $candidateRoot 'candidate.json') -Value $candidate -AllowedRoot $inboxRoot
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Scan'; status = if ($blockers.Count) { 'BlockedCandidate' } else { 'CandidateReady' }; candidateId = $CandidateId; lifecycle = 'candidate'; blockers = $blockers; inboxPath = $candidateRoot; exitCode = if ($blockers.Count) { 3 } else { 0 } }
    }
    elseif ($Mode -eq 'Check') {
        if ([string]::IsNullOrWhiteSpace($CandidateId)) {
            $items = @()
            if ([IO.Directory]::Exists($inboxRoot)) { $items = @(Get-InboxCandidateFiles -InboxRoot $inboxRoot | ForEach-Object { ([string]([IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)) | ConvertFrom-Json) }) }
            $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Check'; status = 'Inventory'; candidateCount = $items.Count; candidates = $items; exitCode = 0 }
        }
        else {
            $candidate = Read-Candidate -InboxRoot $inboxRoot -Id $CandidateId
            $currentBlockers = @(@($candidate.data.blockers) + @(Get-CandidateIntegrityBlockers -RepoRoot $RepositoryRoot -InboxRoot $inboxRoot -Candidate $candidate))
            $currentBlockers = @($currentBlockers | Sort-Object -Unique)
            $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Check'; status = if ($currentBlockers.Count) { 'BlockedCandidate' } else { 'CandidateReady' }; candidateId = $CandidateId; lifecycle = [string]$candidate.data.lifecycle; blockers = $currentBlockers; candidate = $candidate.data; exitCode = if ($currentBlockers.Count) { 3 } else { 0 } }
        }
    }
    elseif ($Mode -eq 'Review') {
        if (-not $ApproveInboxWrite) { throw 'Review requires -ApproveInboxWrite' }
        $candidate = Read-Candidate -InboxRoot $inboxRoot -Id $CandidateId
        if (@($candidate.data.blockers).Count) { throw 'Blocked candidates cannot become reviewed' }
        $integrityBlockers = @(Get-CandidateIntegrityBlockers -RepoRoot $RepositoryRoot -InboxRoot $inboxRoot -Candidate $candidate)
        if ($integrityBlockers.Count) { throw "Candidate integrity check failed: $([string]::Join(',', $integrityBlockers))" }
        if ([string]$candidate.data.lifecycle -notin @('candidate', 'reviewed')) { throw 'Review cannot change approved or released lifecycle states' }
        $candidate.data.lifecycle = 'reviewed'
        $candidate.data.pushAuthorized = $false
        Write-JsonAtomic -Path $candidate.path -Value $candidate.data -AllowedRoot $inboxRoot
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Review'; status = 'Reviewed'; candidateId = $CandidateId; lifecycle = 'reviewed'; blockers = @(); exitCode = 0 }
    }
    else {
        if (-not $ApproveInboxWrite) { throw 'ExportDraft requires -ApproveInboxWrite' }
        $candidate = Read-Candidate -InboxRoot $inboxRoot -Id $CandidateId
        if ([string]$candidate.data.lifecycle -cne 'reviewed' -or @($candidate.data.blockers).Count) { throw 'Only unblocked reviewed candidates can be exported' }
        $integrityBlockers = @(Get-CandidateIntegrityBlockers -RepoRoot $RepositoryRoot -InboxRoot $inboxRoot -Candidate $candidate)
        if ($integrityBlockers.Count) { throw "Candidate integrity check failed: $([string]::Join(',', $integrityBlockers))" }
        $draftRoot = Join-Path $candidate.root 'draft-pr'
        if ([IO.Directory]::Exists($draftRoot)) { throw 'Draft PR bundle already exists; exports are immutable' }
        $rawRoot = Join-Path $candidate.root ([string]$candidate.data.rawPath)
        $null = Copy-TreeExact -Source $rawRoot -Destination (Join-Path $draftRoot 'asset') -AllowedRoot $inboxRoot
        $proposal = [pscustomobject][ordered]@{
            schemaVersion = 1; candidateId = $CandidateId; canonicalId = [string]$candidate.data.canonicalId
            kind = [string]$candidate.data.kind; owner = [string]$candidate.data.owner; lifecycle = 'reviewed'
            provenance = [string]$candidate.data.provenance; license = [string]$candidate.data.license
            vendors = @($candidate.data.vendors); contentDigest = [string]$candidate.data.contentDigest
            pushAuthorized = $false; nextHumanAction = 'Review files, map destination, then explicitly approve Draft PR push.'
        }
        Write-JsonAtomic -Path (Join-Path $draftRoot 'proposal.json') -Value $proposal -AllowedRoot $inboxRoot
        $result = [pscustomobject][ordered]@{ schemaVersion = 1; mode = 'ExportDraft'; status = 'DraftBundleReady'; candidateId = $CandidateId; lifecycle = 'reviewed'; blockers = @(); draftPath = $draftRoot; pushAuthorized = $false; exitCode = 0 }
    }
    $exitCode = [int]$result.exitCode
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $result) } else { Write-HumanResult -Result $result }
}
catch {
    $line = [int]$_.InvocationInfo.ScriptLineNumber
    $failure = [pscustomobject][ordered]@{ schemaVersion = 1; mode = $Mode; status = 'Error'; blockers = @("$($_.Exception.Message) [line $line]"); exitCode = 1 }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-AsciiJson -Value $failure) } else { Write-HumanResult -Result $failure }
    $exitCode = 1
}
exit $exitCode
