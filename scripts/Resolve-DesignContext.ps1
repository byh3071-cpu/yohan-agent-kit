#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BrainRoot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$CurrentRequestPath,
    [Parameter(Mandatory = $true)][string]$ProjectContextPath,
    [string]$ContractRef = 'f7615ac2fce83bd93c37801c14640c20dede5980',
    [ValidateSet('Json', 'Human')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:pinnedContractRef = 'f7615ac2fce83bd93c37801c14640c20dede5980'
$script:indexPath = 'memory/design-intelligence/index.yaml'
$script:resolutionOrder = @('current-request', 'project-git', 'media', 'common-taste', 'golden')

function Get-NormalizedRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Directory]::Exists($Path)) { throw "$Label must be an existing directory" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $entry = Get-Item -LiteralPath $full -Force
    if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label must be an ordinary directory"
    }
    return $full
}

function Get-SafeProjectFile {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)' -or $RelativePath -match '[:\x00-\x1f]') {
        throw 'Context input must be a project-relative path'
    }
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Context input escapes ProjectRoot' }
    if (-not [IO.File]::Exists($candidate)) { throw "Context input is missing: $RelativePath" }
    $entry = Get-Item -LiteralPath $candidate -Force
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Context input cannot be a reparse point' }
    return $candidate
}

function Get-GitExecutable {
    foreach ($candidate in @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        if ([IO.File]::Exists([string]$candidate.Source)) { return [string]$candidate.Source }
    }
    throw 'git.exe is unavailable'
}

function ConvertTo-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '["\x00-\x1f]') { throw 'Unsafe native argument rejected' }
    return '"' + $Value + '"'
}

function Invoke-GitBytes {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $git = Get-GitExecutable
    $all = @('-c', "safe.directory=$RepositoryRoot", '-C', $RepositoryRoot) + $Arguments
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $git
    $start.Arguments = [string]::Join(' ', @($all | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }))
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $null = $process.Start()
    $memory = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Git object read failed: $errorText" }
        return $memory.ToArray()
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-StrictUtf8 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes, [Parameter(Mandatory = $true)][string]$Label)

    try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes) }
    catch [Text.DecoderFallbackException] { throw "$Label is not valid UTF-8" }
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Get-StrictUtf8 -Bytes ([IO.File]::ReadAllBytes($Path)) -Label 'Context input'
    try { return $text | ConvertFrom-Json }
    catch { throw "Context input is not valid JSON: $Path" }
}

function Get-IndexItems {
    param([Parameter(Mandatory = $true)][string]$IndexText)

    $items = @{}
    $pattern = '(?ms)^  - id:\s*(?<id>[a-z0-9][a-z0-9-]*)\s*\r?\n(?<body>(?:    .*?(?:\r?\n|$))+?)?(?=^  - id:|^[a-z][a-z0-9_-]*:|\z)'
    foreach ($match in [regex]::Matches($IndexText, $pattern)) {
        $id = [string]$match.Groups['id'].Value
        $body = [string]$match.Groups['body'].Value
        if ($items.ContainsKey($id)) { throw "Duplicate design intelligence item: $id" }
        $fields = @{}
        foreach ($name in @('kind', 'title', 'owner', 'status')) {
            $field = [regex]::Match($body, "(?m)^    $name`:\s*(.+?)\s*$")
            if ($field.Success) { $fields[$name] = [string]$field.Groups[1].Value }
        }
        $source = [regex]::Match($body, '(?ms)^    source_ref:\s*\r?\n      repo:\s*(?<repo>\S+)\s*\r?\n      path:\s*(?<path>\S+)\s*\r?\n      git_ref:\s*(?<ref>[a-f0-9]{40})\s*\r?\n      sha256:\s*(?<sha>[a-f0-9]{64})\s*$')
        if (-not $source.Success) { throw "Item lacks a valid source_ref: $id" }
        $items[$id] = [pscustomobject][ordered]@{
            id = $id
            kind = [string]$fields['kind']
            title = [string]$fields['title']
            owner = [string]$fields['owner']
            status = [string]$fields['status']
            sourceRef = [pscustomobject][ordered]@{
                repo = [string]$source.Groups['repo'].Value
                path = [string]$source.Groups['path'].Value
                gitRef = [string]$source.Groups['ref'].Value
                sha256 = [string]$source.Groups['sha'].Value
            }
        }
    }
    if ($items.Count -eq 0) { throw 'Design intelligence index has no parseable items' }
    return $items
}

function Add-Constraints {
    param([Parameter(Mandatory = $true)][Collections.Specialized.OrderedDictionary]$Target, [AllowNull()]$Constraints)

    if ($null -eq $Constraints) { return }
    foreach ($property in @($Constraints.PSObject.Properties)) {
        if ($property.Name -notmatch '^[a-z][a-zA-Z0-9]*$') { throw "Invalid constraint key: $($property.Name)" }
        if (-not $Target.Contains($property.Name)) { $Target.Add($property.Name, $property.Value) }
    }
}

try {
    if ($ContractRef -cne $script:pinnedContractRef) { throw 'ContractRef must equal the approved pinned contract commit' }
    $brain = Get-NormalizedRoot -Path $BrainRoot -Label 'BrainRoot'
    $project = Get-NormalizedRoot -Path $ProjectRoot -Label 'ProjectRoot'
    $currentFile = Get-SafeProjectFile -Root $project -RelativePath $CurrentRequestPath
    $projectFile = Get-SafeProjectFile -Root $project -RelativePath $ProjectContextPath

    $resolvedCommit = (Get-StrictUtf8 -Bytes (Invoke-GitBytes -RepositoryRoot $brain -Arguments @('rev-parse', '--verify', "$ContractRef^{commit}")) -Label 'Git commit').Trim()
    if ($resolvedCommit -cne $script:pinnedContractRef) { throw 'Pinned contract commit does not resolve exactly' }
    $indexText = Get-StrictUtf8 -Bytes (Invoke-GitBytes -RepositoryRoot $brain -Arguments @('show', "$ContractRef`:$script:indexPath")) -Label 'Design intelligence index'
    foreach ($required in @(
        'metadata_schema_index_evidence: yohan-brain',
        'resolver_recording_execution: yohan-cc-skills',
        'artifact_and_verification_assets: project-git',
        'stable_auto_promotion: false',
        'stable_promotion_requires_human: true',
        'correction_mode: append-only'
    )) {
        if (-not $indexText.Contains($required)) { throw "Pinned contract invariant is missing: $required" }
    }
    $items = Get-IndexItems -IndexText $indexText
    $current = Read-JsonFile -Path $currentFile
    $projectContext = Read-JsonFile -Path $projectFile
    if ([int]$current.schemaVersion -ne 1 -or [int]$projectContext.schemaVersion -ne 1) { throw 'Context inputs must use schemaVersion 1' }
    if ($null -eq $current.workContext) { throw 'Current request must preserve WorkContext' }

    $constraints = New-Object Collections.Specialized.OrderedDictionary
    Add-Constraints -Target $constraints -Constraints $current.constraints
    Add-Constraints -Target $constraints -Constraints $projectContext.constraints

    $selectedIds = New-Object Collections.Generic.List[string]
    foreach ($candidate in @(@($current.approvedReferenceIds) + @($projectContext.approvedReferenceIds))) {
        $id = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $selectedIds.Contains($id)) { $selectedIds.Add($id) }
    }
    $selectedSources = @()
    foreach ($id in $selectedIds) {
        if (-not $items.ContainsKey($id)) { throw "Approved reference is absent from pinned index: $id" }
        $item = $items[$id]
        if ([string]$item.status -cne 'approved') { throw "Reference is not approved: $id" }
        $sourcePath = [string]$item.sourceRef.path
        if ($sourcePath -notmatch '^[a-zA-Z0-9._/-]+$' -or $sourcePath -match '(^|/)\.\.(/|$)') { throw "Unsafe source path: $sourcePath" }
        $blob = Invoke-GitBytes -RepositoryRoot $brain -Arguments @('show', "$($item.sourceRef.gitRef):$sourcePath")
        $actualHash = Get-Sha256Bytes -Bytes $blob
        $hashMode = 'git-blob'
        if ($actualHash -cne [string]$item.sourceRef.sha256 -and $sourcePath -match '\.(?:md|json|ya?ml|txt)$') {
            $text = Get-StrictUtf8 -Bytes $blob -Label "Source $id"
            $checkoutBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($text -replace '(?<!\r)\n', "`r`n"))
            $actualHash = Get-Sha256Bytes -Bytes $checkoutBytes
            $hashMode = 'git-checkout-crlf'
        }
        if ($actualHash -cne [string]$item.sourceRef.sha256) { throw "Source hash mismatch: $id" }
        $item | Add-Member -NotePropertyName hashVerification -NotePropertyValue $hashMode
        $selectedSources += $item
    }

    $tiers = @(
        [pscustomobject][ordered]@{ name = 'current-request'; sourceCount = 1; applied = $true },
        [pscustomobject][ordered]@{ name = 'project-git'; sourceCount = 1; applied = $true },
        [pscustomobject][ordered]@{ name = 'media'; sourceCount = @($selectedSources | Where-Object { $_.kind -eq 'media' }).Count; applied = $true },
        [pscustomobject][ordered]@{ name = 'common-taste'; sourceCount = @($selectedSources | Where-Object { $_.kind -in @('taste', 'anti-pattern') }).Count; applied = $true },
        [pscustomobject][ordered]@{ name = 'golden'; sourceCount = @($selectedSources | Where-Object { $_.kind -eq 'golden' }).Count; applied = $true }
    )
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1
        designContext = [pscustomobject][ordered]@{
            contract = [pscustomobject][ordered]@{ repo = 'yohan-brain'; ref = $script:pinnedContractRef; path = $script:indexPath }
            resolutionOrder = $script:resolutionOrder
            tiers = $tiers
            constraints = [pscustomobject]$constraints
            approvedSources = $selectedSources
        }
        workContext = $current.workContext
        diagnostics = @('pinned-contract-verified', 'selected-source-hashes-verified', 'stable-auto-promotion-disabled')
    }
    if ($OutputFormat -eq 'Json') { Write-Output ([string]($result | ConvertTo-Json -Depth 12 -Compress)) }
    else {
        Write-Output "Contract: yohan-brain@$script:pinnedContractRef"
        Write-Output "Resolution: $([string]::Join(' -> ', $script:resolutionOrder))"
        Write-Output "Approved sources: $($selectedSources.Count)"
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))")
    exit 3
}
