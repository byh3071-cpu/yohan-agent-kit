#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Check', 'Install', 'Restore')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BrainRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HomeRoot,

    [string]$PlanDigest,

    [switch]$ApproveGlobalHomeWrite,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$targetRelativePath = '.codex/state/plugins/product-design/user-context.md'
$transactionRelativePath = '.yohan-product-design-context.transaction.json'
$allowedContextDirectories = @('.codex', '.codex/state', '.codex/state/plugins', '.codex/state/plugins/product-design')
$sourceDefinitions = @(
    [pscustomobject][ordered]@{ name = 'html-artifact-design'; path = 'memory/rules/html-artifact-design.md' },
    [pscustomobject][ordered]@{ name = 'context-trust-navigator'; path = 'docs/reference/websites/ai-workspace-context-trust-navigator.md' }
)

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Assert-SafeRootInput {
    param(
        [Parameter(Mandatory = $true)][string]$Original,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not [IO.Path]::IsPathRooted($Original)) { throw "$Label must be absolute" }
    foreach ($segment in @($Original.Replace('/', '\').Split('\'))) {
        if ($segment -ceq '..') { throw "$Label contains traversal" }
    }
    $normalized = Get-NormalizedFullPath -Path $Original
    if ([string]::Equals($normalized, [IO.Path]::GetPathRoot($normalized), [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label cannot be a volume root"
    }
    return $normalized
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedCandidate = Get-NormalizedFullPath -Path $Candidate
    if ([string]::Equals($normalizedRoot, $normalizedCandidate, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $normalizedCandidate.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SafeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'Relative path contract is invalid'
    }
    foreach ($segment in @($RelativePath.Replace('/', '\').Split('\'))) {
        if ($segment -ceq '..') { throw 'Relative path contract contains traversal' }
    }
    $candidate = Get-NormalizedFullPath -Path (Join-Path $Root $RelativePath.Replace('/', '\'))
    if (-not (Test-PathWithin -Root $Root -Candidate $candidate)) { throw 'Relative path escapes its root' }
    return $candidate
}

function Assert-ExistingPathChainSafe {
    param([Parameter(Mandatory = $true)][string]$Candidate)

    $normalized = Get-NormalizedFullPath -Path $Candidate
    $volumeRoot = [IO.Path]::GetPathRoot($normalized)
    $paths = New-Object Collections.Generic.List[string]
    $paths.Add($volumeRoot)
    $current = $volumeRoot
    foreach ($segment in @($normalized.Substring($volumeRoot.Length).TrimStart('\', '/') -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $current = Join-Path $current $segment
        $paths.Add($current)
    }
    foreach ($path in $paths) {
        try { $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop }
        catch [Management.Automation.ItemNotFoundException] { break }
        if (([int]$entry.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Path chain contains a reparse point'
        }
        $linkType = $entry.PSObject.Properties['LinkType']
        if ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value)) {
            throw 'Path chain contains a linked entry'
        }
        $isCandidateLeaf = [string]::Equals((Get-NormalizedFullPath -Path $path), $normalized, [StringComparison]::OrdinalIgnoreCase)
        if (-not $isCandidateLeaf -and -not $entry.PSIsContainer) {
            throw 'Path chain contains a non-directory ancestor'
        }
    }
}

function Assert-OrdinaryDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-ExistingPathChainSafe -Candidate $Path
    if (-not [IO.Directory]::Exists($Path)) { throw 'Required root directory does not exist' }
    $entry = Get-Item -LiteralPath $Path -Force
    if (-not $entry.PSIsContainer) { throw 'Required root is not a directory' }
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Get-FileDigest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-OrdinaryFileState {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-ExistingPathChainSafe -Candidate $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ kind = 'Missing'; digest = '' }
    }
    $entry = Get-Item -LiteralPath $Path -Force
    if ($entry.PSIsContainer) { throw 'Expected file path is a directory' }
    return [pscustomobject]@{ kind = 'File'; digest = Get-FileDigest -Path $Path }
}

function Get-GeneratedContext {
    param([Parameter(Mandatory = $true)][object[]]$Sources)

    $designRules = [string](@($Sources | Where-Object { $_.name -ceq 'html-artifact-design' })[0].absolutePath)
    $reference = [string](@($Sources | Where-Object { $_.name -ceq 'context-trust-navigator' })[0].absolutePath)
    return [string]::Join("`n", @(
        '# Codebase References',
        '',
        '- Description: Git-backed product layout, evidence, and trust references for Product Design work',
        '## Saved Links And Context',
        '',
        $reference,
        '- Useful Context: Approved AI workspace context and trust reference',
        '- Future Use: Use as the product layout, evidence, and trust reference before Product Design work',
        '',
        '# Design Tokens And Theme Sources',
        '',
        '- Description: Git-backed typography, layout, and validation rules for HTML artifacts',
        '## Saved Links And Context',
        '',
        $designRules,
        '- Useful Context: Approved typography, layout, evidence, and validation rules',
        '- Future Use: Apply these rules to every Product Design HTML artifact unless the current request overrides them',
        ''
    ))
}

function Get-TransactionSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("schema|$([int]$Transaction.schemaVersion)")
    $lines.Add("owner|$([string]$Transaction.owner)")
    $lines.Add("target|$([string]$Transaction.targetRelativePath)|$([string]$Transaction.targetDigest)")
    $lines.Add("plan|$([string]$Transaction.installPlanDigest)")
    $lines.Add("brain|$([string]$Transaction.brainRootKey)")
    $lines.Add("home|$([string]$Transaction.homeRootKey)")
    foreach ($source in @($Transaction.sources)) {
        $lines.Add("source|$([string]$source.name)|$([string]$source.path)|$([string]$source.sha256)")
    }
    foreach ($relativePath in @($Transaction.createdDirectories)) { $lines.Add("directory|$([string]$relativePath)") }
    return Get-Sha256Text -Text ([string]::Join("`n", $lines.ToArray()))
}

function Get-TransactionEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionPath,
        [Parameter(Mandatory = $true)][string]$BrainRootKey,
        [Parameter(Mandatory = $true)][string]$HomeRootKey,
        [Parameter(Mandatory = $true)][string]$ExpectedTargetDigest,
        [Parameter(Mandatory = $true)][object[]]$Sources
    )

    $state = Get-OrdinaryFileState -Path $TransactionPath
    if ($state.kind -eq 'Missing') {
        return [pscustomobject]@{ state = 'Missing'; digest = ''; owned = $false; data = $null; targetDigest = '' }
    }
    try {
        $data = [IO.File]::ReadAllText($TransactionPath, (New-Object Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
        $valid = [int]$data.schemaVersion -eq 1 -and
            [string]$data.owner -ceq 'yohan-product-design-context' -and
            [string]$data.targetRelativePath -ceq $targetRelativePath -and
            [string]$data.brainRootKey -ceq $BrainRootKey -and
            [string]$data.homeRootKey -ceq $HomeRootKey -and
            [string]$data.targetDigest -match '^[A-Fa-f0-9]{64}$' -and
            [string]::Equals([string]$data.targetDigest, $ExpectedTargetDigest, [StringComparison]::OrdinalIgnoreCase) -and
            [string]$data.installPlanDigest -match '^[A-Fa-f0-9]{64}$'
        $recordedSources = @($data.sources)
        if ($recordedSources.Count -ne $Sources.Count) { $valid = $false }
        $seenSourceNames = @{}
        $seenSourcePaths = @{}
        foreach ($recordedSource in $recordedSources) {
            $recordedName = [string]$recordedSource.name
            $recordedPath = [string]$recordedSource.path
            if ($seenSourceNames.ContainsKey($recordedName) -or $seenSourcePaths.ContainsKey($recordedPath)) { $valid = $false }
            $seenSourceNames[$recordedName] = $true
            $seenSourcePaths[$recordedPath] = $true
        }
        foreach ($source in $Sources) {
            $match = @($recordedSources | Where-Object {
                [string]$_.name -ceq [string]$source.name -and [string]$_.path -ceq [string]$source.path
            })
            if ($match.Count -ne 1 -or [string]$match[0].sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
                $valid = $false
            }
        }
        $recordedDirectories = @($data.createdDirectories | ForEach-Object { [string]$_ })
        $seenDirectories = @{}
        foreach ($relativePath in $recordedDirectories) {
            if ($relativePath -cnotin $allowedContextDirectories -or $seenDirectories.ContainsKey($relativePath)) { $valid = $false }
            $seenDirectories[$relativePath] = $true
        }
        if ([string]$data.evidenceDigest -notmatch '^[A-Fa-f0-9]{64}$' -or
            -not [string]::Equals([string]$data.evidenceDigest, (Get-TransactionSeal -Transaction $data), [StringComparison]::OrdinalIgnoreCase)) {
            $valid = $false
        }
        return [pscustomobject]@{ state = if ($valid) { 'Owned' } else { 'Unowned' }; digest = $state.digest; owned = $valid; data = $data; targetDigest = [string]$data.targetDigest }
    }
    catch {
        return [pscustomobject]@{ state = 'Unowned'; digest = $state.digest; owned = $false; data = $null; targetDigest = '' }
    }
}

function Get-ContextPlan {
    param(
        [Parameter(Mandatory = $true)][string]$NormalizedBrainRoot,
        [Parameter(Mandatory = $true)][string]$NormalizedHomeRoot,
        [string]$ResultMode = 'Check'
    )

    Assert-OrdinaryDirectory -Path $NormalizedBrainRoot
    Assert-OrdinaryDirectory -Path $NormalizedHomeRoot
    $brainRootKey = $NormalizedBrainRoot.ToLowerInvariant()
    $homeRootKey = $NormalizedHomeRoot.ToLowerInvariant()
    $sources = New-Object Collections.Generic.List[object]
    foreach ($definition in $sourceDefinitions) {
        $absolutePath = Get-SafeChildPath -Root $NormalizedBrainRoot -RelativePath ([string]$definition.path)
        $state = Get-OrdinaryFileState -Path $absolutePath
        if ($state.kind -ne 'File') { throw 'Required Product Design source is missing' }
        $sources.Add([pscustomobject][ordered]@{
            name = [string]$definition.name
            path = [string]$definition.path
            sha256 = [string]$state.digest
            absolutePath = $absolutePath
        })
    }

    $generatedContext = Get-GeneratedContext -Sources $sources.ToArray()
    $generatedDigest = Get-Sha256Text -Text $generatedContext
    $targetPath = Get-SafeChildPath -Root $NormalizedHomeRoot -RelativePath $targetRelativePath
    $transactionPath = Get-SafeChildPath -Root $NormalizedHomeRoot -RelativePath $transactionRelativePath
    $targetFile = Get-OrdinaryFileState -Path $targetPath
    $targetState = if ($targetFile.kind -eq 'Missing') { 'Missing' } elseif ([string]::Equals($targetFile.digest, $generatedDigest, [StringComparison]::OrdinalIgnoreCase)) { 'Exact' } else { 'Different' }
    $transaction = Get-TransactionEvidence -TransactionPath $transactionPath -BrainRootKey $brainRootKey -HomeRootKey $homeRootKey -ExpectedTargetDigest $generatedDigest -Sources $sources.ToArray()

    if ($targetState -eq 'Missing' -and $transaction.state -eq 'Missing') { $status = 'Installable'; $exitCode = 2 }
    elseif ($targetState -eq 'Exact' -and $transaction.state -eq 'Owned') { $status = 'Healthy'; $exitCode = 0 }
    else { $status = 'Conflict'; $exitCode = 3 }

    $digestLines = New-Object Collections.Generic.List[string]
    $digestLines.Add("brain|$brainRootKey")
    $digestLines.Add("home|$homeRootKey")
    foreach ($source in $sources) { $digestLines.Add("source|$($source.path)|$($source.sha256)") }
    $digestLines.Add("generated|$generatedDigest")
    $digestLines.Add("target|$targetState|$($targetFile.digest)")
    $digestLines.Add("transaction|$($transaction.state)|$($transaction.digest)")
    $planDigestValue = Get-Sha256Text -Text ([string]::Join("`n", $digestLines.ToArray()))

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = $ResultMode
        status = $status
        planDigest = $planDigestValue
        target = $targetRelativePath
        targetState = $targetState
        generatedDigest = $generatedDigest
        owned = [bool]$transaction.owned
        transactionState = [string]$transaction.state
        sources = @($sources | ForEach-Object { [pscustomobject][ordered]@{ name = $_.name; path = $_.path; sha256 = $_.sha256 } })
        exitCode = $exitCode
        _targetPath = $targetPath
        _transactionPath = $transactionPath
        _generatedContext = $generatedContext
        _transaction = $transaction.data
        _transactionTargetDigest = [string]$transaction.targetDigest
    }
}

function ConvertTo-PublicResult {
    param([Parameter(Mandatory = $true)]$Result)

    return [pscustomobject][ordered]@{
        schemaVersion = [int]$Result.schemaVersion
        mode = [string]$Result.mode
        status = [string]$Result.status
        planDigest = if ($Result.PSObject.Properties['planDigest']) { $Result.planDigest } else { $null }
        target = $targetRelativePath
        targetState = if ($Result.PSObject.Properties['targetState']) { $Result.targetState } else { $null }
        generatedDigest = if ($Result.PSObject.Properties['generatedDigest']) { $Result.generatedDigest } else { $null }
        owned = if ($Result.PSObject.Properties['owned']) { [bool]$Result.owned } else { $false }
        transactionState = if ($Result.PSObject.Properties['transactionState']) { $Result.transactionState } else { $null }
        sources = if ($Result.PSObject.Properties['sources']) { @($Result.sources) } else { @() }
        code = if ($Result.PSObject.Properties['code']) { $Result.code } else { $null }
        exitCode = [int]$Result.exitCode
    }
}

function Get-MissingContextDirectories {
    param([Parameter(Mandatory = $true)][string]$NormalizedHomeRoot)

    $created = New-Object Collections.Generic.List[string]
    $current = $NormalizedHomeRoot
    $relative = ''
    foreach ($segment in @('.codex', 'state', 'plugins', 'product-design')) {
        $relative = if ([string]::IsNullOrWhiteSpace($relative)) { $segment } else { "$relative/$segment" }
        $current = Get-SafeChildPath -Root $NormalizedHomeRoot -RelativePath $relative
        Assert-ExistingPathChainSafe -Candidate $current
        if (Test-Path -LiteralPath $current) {
            $entry = Get-Item -LiteralPath $current -Force
            if (-not $entry.PSIsContainer) { throw 'Context directory path is occupied by a file' }
        }
        else { $created.Add($relative) }
    }
    return $created.ToArray()
}

function New-ContextDirectories {
    param(
        [Parameter(Mandatory = $true)][string]$NormalizedHomeRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    foreach ($relativePath in $RelativePaths) {
        $path = Get-SafeChildPath -Root $NormalizedHomeRoot -RelativePath $relativePath
        Assert-ExistingPathChainSafe -Candidate $path
        $null = New-Item -ItemType Directory -Path $path
        Assert-ExistingPathChainSafe -Candidate $path
    }
}

function Write-NewUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    Assert-ExistingPathChainSafe -Candidate $Path
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Remove-EmptyOwnedDirectories {
    param(
        [Parameter(Mandatory = $true)][string]$NormalizedHomeRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths,
        [switch]$RequireRemoval
    )

    foreach ($relativePath in @($RelativePaths | Sort-Object { $_.Length } -Descending)) {
        $path = Get-SafeChildPath -Root $NormalizedHomeRoot -RelativePath $relativePath
        Assert-ExistingPathChainSafe -Candidate $path
        if ([IO.File]::Exists($path)) {
            if ($RequireRemoval) { throw 'Owned directory cleanup path is occupied by an unowned file' }
        }
        elseif ([IO.Directory]::Exists($path)) {
            if (@(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
                [IO.Directory]::Delete($path, $false)
            }
            elseif ($RequireRemoval) { throw 'Owned directory cleanup is blocked by unowned content' }
        }
    }
}

function Invoke-ContextInstall {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$NormalizedBrainRoot,
        [Parameter(Mandatory = $true)][string]$NormalizedHomeRoot
    )

    if (-not $ApproveGlobalHomeWrite) { throw 'Install requires explicit approval' }
    if ([string]::IsNullOrWhiteSpace($PlanDigest) -or -not [string]::Equals($PlanDigest, [string]$Plan.planDigest, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Install plan digest is stale or mismatched'
    }
    if ($Plan.status -ne 'Installable') { throw 'Install is blocked by the current target state' }
    $createdDirectories = @(Get-MissingContextDirectories -NormalizedHomeRoot $NormalizedHomeRoot)
    $targetCreated = $false
    $transactionCreated = $false
    try {
        New-ContextDirectories -NormalizedHomeRoot $NormalizedHomeRoot -RelativePaths $createdDirectories
        $transaction = [pscustomobject][ordered]@{
            schemaVersion = 1
            owner = 'yohan-product-design-context'
            targetRelativePath = $targetRelativePath
            targetDigest = [string]$Plan.generatedDigest
            installPlanDigest = [string]$Plan.planDigest
            brainRootKey = $NormalizedBrainRoot.ToLowerInvariant()
            homeRootKey = $NormalizedHomeRoot.ToLowerInvariant()
            sources = @($Plan.sources)
            createdDirectories = $createdDirectories
        }
        $transaction | Add-Member -MemberType NoteProperty -Name evidenceDigest -Value (Get-TransactionSeal -Transaction $transaction)
        $transactionJson = [string]($transaction | ConvertTo-Json -Depth 8 -Compress)
        Write-NewUtf8File -Path ([string]$Plan._transactionPath) -Text $transactionJson
        $transactionCreated = $true
        Write-NewUtf8File -Path ([string]$Plan._targetPath) -Text ([string]$Plan._generatedContext)
        $targetCreated = $true
        $post = Get-ContextPlan -NormalizedBrainRoot $NormalizedBrainRoot -NormalizedHomeRoot $NormalizedHomeRoot -ResultMode Install
        if ($post.status -ne 'Healthy' -or -not $post.owned) { throw 'Post-install verification failed' }
        return $post
    }
    catch {
        if ($targetCreated -and [IO.File]::Exists([string]$Plan._targetPath) -and
            [string]::Equals((Get-FileDigest -Path ([string]$Plan._targetPath)), [string]$Plan.generatedDigest, [StringComparison]::OrdinalIgnoreCase)) {
            [IO.File]::Delete([string]$Plan._targetPath)
        }
        if ($transactionCreated -and [IO.File]::Exists([string]$Plan._transactionPath)) {
            [IO.File]::Delete([string]$Plan._transactionPath)
        }
        Remove-EmptyOwnedDirectories -NormalizedHomeRoot $NormalizedHomeRoot -RelativePaths $createdDirectories
        throw
    }
}

function Invoke-ContextRestore {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$NormalizedHomeRoot
    )

    if (-not $ApproveGlobalHomeWrite) { throw 'Restore requires explicit approval' }
    if ([string]::IsNullOrWhiteSpace($PlanDigest) -or -not [string]::Equals($PlanDigest, [string]$Plan.planDigest, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Restore plan digest is stale or mismatched'
    }
    if ($Plan.status -notin @('Healthy', 'Conflict') -or -not $Plan.owned -or $null -eq $Plan._transaction) {
        throw 'Restore requires exact owned transaction evidence'
    }
    $targetState = Get-OrdinaryFileState -Path ([string]$Plan._targetPath)
    if ($targetState.kind -eq 'File' -and -not [string]::Equals($targetState.digest, [string]$Plan._transactionTargetDigest, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Restore target changed after Check'
    }
    if ($targetState.kind -notin @('File', 'Missing')) { throw 'Restore target is unsafe' }
    $transactionState = Get-OrdinaryFileState -Path ([string]$Plan._transactionPath)
    if ($transactionState.kind -ne 'File') { throw 'Restore transaction changed after Check' }

    $createdDirectories = @($Plan._transaction.createdDirectories | ForEach-Object { [string]$_ })
    foreach ($relativePath in $createdDirectories) {
        if ($relativePath -cnotin $allowedContextDirectories) { throw 'Restore transaction contains an unsafe directory claim' }
    }
    if ($targetState.kind -eq 'File') { [IO.File]::Delete([string]$Plan._targetPath) }
    Remove-EmptyOwnedDirectories -NormalizedHomeRoot $NormalizedHomeRoot -RelativePaths $createdDirectories -RequireRemoval
    [IO.File]::Delete([string]$Plan._transactionPath)
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'Restore'
        status = 'Restored'
        planDigest = $null
        targetState = 'Missing'
        generatedDigest = [string]$Plan.generatedDigest
        owned = $false
        transactionState = 'Missing'
        sources = @($Plan.sources)
        exitCode = 0
    }
}

function Write-HumanResult {
    param([Parameter(Mandatory = $true)]$Result)

    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    if ($Result.PSObject.Properties['planDigest'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.planDigest)) {
        Write-Output "PlanDigest: $($Result.planDigest)"
    }
    Write-Output "Target: $targetRelativePath"
    if ($Result.PSObject.Properties['sources']) {
        foreach ($source in @($Result.sources)) { Write-Output ("[source] {0}: {1}" -f $source.path, $source.sha256) }
    }
    if ($Result.PSObject.Properties['code'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.code)) { Write-Output "Code: $($Result.code)" }
}

try {
    $normalizedBrainRoot = Assert-SafeRootInput -Original $BrainRoot -Label 'BrainRoot'
    $normalizedHomeRoot = Assert-SafeRootInput -Original $HomeRoot -Label 'HomeRoot'
    $check = Get-ContextPlan -NormalizedBrainRoot $normalizedBrainRoot -NormalizedHomeRoot $normalizedHomeRoot -ResultMode $Mode
    if ($Mode -eq 'Check') { $result = $check }
    elseif ($Mode -eq 'Install') { $result = Invoke-ContextInstall -Plan $check -NormalizedBrainRoot $normalizedBrainRoot -NormalizedHomeRoot $normalizedHomeRoot }
    else { $result = Invoke-ContextRestore -Plan $check -NormalizedHomeRoot $normalizedHomeRoot }
    $publicResult = ConvertTo-PublicResult -Result $result
}
catch {
    $publicResult = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = $Mode
        status = if ($Mode -eq 'Check') { 'Unsafe' } else { 'Rejected' }
        planDigest = $null
        target = $targetRelativePath
        targetState = $null
        generatedDigest = $null
        owned = $false
        transactionState = $null
        sources = @()
        code = if ($Mode -eq 'Check') { 'UnsafeOrInvalidInput' } else { 'MutationRejected' }
        exitCode = 3
    }
}

if ($OutputFormat -eq 'Json') { Write-Output ([string]($publicResult | ConvertTo-Json -Depth 8 -Compress)) }
else { Write-HumanResult -Result $publicResult }
exit [int]$publicResult.exitCode
