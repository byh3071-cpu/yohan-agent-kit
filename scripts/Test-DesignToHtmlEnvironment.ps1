#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BrainRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $volumeRoot, [StringComparison]::OrdinalIgnoreCase)) {
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
    if ([string]::Equals($normalizedRoot, $normalizedCandidate, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $normalizedCandidate.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SafeContractPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Contract path must be relative: $RelativePath"
    }
    $candidate = Get-NormalizedFullPath -Path (Join-Path $Root $RelativePath)
    if (-not (Test-PathWithin -Root $Root -Candidate $candidate)) {
        throw "Contract path escapes its root: $RelativePath"
    }
    return $candidate
}

function Test-ExistingPathChainSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    if (-not (Test-PathWithin -Root $Root -Candidate $Candidate)) { return $false }
    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $normalizedCandidate = Get-NormalizedFullPath -Path $Candidate
    $volumeRoot = [IO.Path]::GetPathRoot($normalizedRoot)
    $paths = New-Object Collections.Generic.List[string]
    $paths.Add($volumeRoot)
    $current = $volumeRoot
    $rootSegments = $normalizedRoot.Substring($volumeRoot.Length).TrimStart('\', '/') -split '[\\/]'
    foreach ($segment in $rootSegments) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $current = Join-Path $current $segment
        $paths.Add($current)
    }
    $candidateSegments = $normalizedCandidate.Substring($normalizedRoot.Length).TrimStart('\', '/') -split '[\\/]'
    foreach ($segment in $candidateSegments) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $current = Join-Path $current $segment
        $paths.Add($current)
    }
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { break }
        $item = Get-Item -LiteralPath $path -Force
        if (([int]$item.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    }
    return $true
}

function Get-FileDigest {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Invoke-ManagerCheck {
    param(
        [Parameter(Mandatory = $true)][string]$ManagerPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RequiredSkill,
        [Parameter(Mandatory = $true)][string]$UserHome
    )

    $powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $ManagerPath,
        '-RepositoryRoot', $RepositoryRoot,
        '-Mode', 'Check',
        '-Skill', $RequiredSkill,
        '-HomeRoot', $UserHome,
        '-OutputFormat', 'Json'
    )
    $previousGitLocks = $env:GIT_OPTIONAL_LOCKS
    $previousXdgConfigHome = $env:XDG_CONFIG_HOME
    try {
        $env:GIT_OPTIONAL_LOCKS = '0'
        $env:XDG_CONFIG_HOME = Join-Path $RepositoryRoot '.git-readonly-xdg'
        $output = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:GIT_OPTIONAL_LOCKS = $previousGitLocks
        $env:XDG_CONFIG_HOME = $previousXdgConfigHome
    }
    $raw = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    try { $data = $raw | ConvertFrom-Json }
    catch { return [pscustomobject]@{ exitCode = $exitCode; status = 'Error'; data = $null } }
    return [pscustomobject]@{ exitCode = $exitCode; status = [string]$data.status; data = $data }
}

function Get-PluginEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$UserHome,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$TestedVersion,
        [Parameter(Mandatory = $true)][string]$CacheRelativePath
    )

    $cachePath = Get-SafeContractPath -Root $UserHome -RelativePath $CacheRelativePath
    if (-not (Test-ExistingPathChainSafe -Root $UserHome -Candidate $cachePath)) {
        return [pscustomobject][ordered]@{
            category = 'plugin'
            name = $Name
            testedVersion = $TestedVersion
            detectedVersions = @()
            state = 'Unsafe'
        }
    }
    $versions = @()
    $hasUnsafeEntry = $false
    if ([IO.Directory]::Exists($cachePath)) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $cachePath -Directory -Force | Sort-Object Name)) {
            if (([int]$entry.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
                $hasUnsafeEntry = $true
                continue
            }
            $versions += [string]$entry.Name
        }
    }
    $versions = @($versions | Sort-Object -Unique)
    if ($hasUnsafeEntry) { $state = 'Unsafe' }
    elseif ($versions.Count -eq 0) { $state = 'MissingCapability' }
    elseif ($versions -ccontains $TestedVersion) {
        $tested = $null
        $testedParsed = [version]::TryParse($TestedVersion, [ref]$tested)
        $hasNewer = $false
        if ($testedParsed) {
            foreach ($candidateText in $versions) {
                $candidate = $null
                if ([version]::TryParse($candidateText, [ref]$candidate) -and $candidate -gt $tested) {
                    $hasNewer = $true
                    break
                }
            }
        }
        $state = if ($hasNewer) { 'TestedWithNewerAvailable' } else { 'Tested' }
    }
    else { $state = 'Drift' }
    return [pscustomobject][ordered]@{
        category = 'plugin'
        name = $Name
        testedVersion = $TestedVersion
        detectedVersions = $versions
        state = $state
    }
}

function ConvertTo-StableJson {
    param([Parameter(Mandatory = $true)]$Value)

    return ($Value | ConvertTo-Json -Depth 8 -Compress)
}

function Write-HumanResult {
    param([Parameter(Mandatory = $true)]$Result)

    Write-Output "Mode: $($Result.mode)"
    Write-Output "Status: $($Result.status)"
    Write-Output ("[skill] {0}: {1} (manager={2}, source={3})" -f $Result.skill.name, $Result.skill.state, $Result.skill.managerStatus, $Result.skill.sourceDigest)
    foreach ($file in @($Result.brainFiles)) {
        $digest = if ([string]::IsNullOrWhiteSpace([string]$file.digest)) { '-' } else { [string]$file.digest }
        Write-Output ("[brain] {0}: {1} (digest={2})" -f $file.path, $file.state, $digest)
    }
    foreach ($plugin in @($Result.plugins)) {
        $detected = if (@($plugin.detectedVersions).Count -eq 0) { '-' } else { [string]::Join(',', @($plugin.detectedVersions)) }
        Write-Output ("[plugin] {0}: {1} (tested={2}, detected={3})" -f $plugin.name, $plugin.state, $plugin.testedVersion, $detected)
    }
    foreach ($item in @($Result.missing)) { Write-Output ("[missing] {0}:{1}" -f $item.category, $item.name) }
    foreach ($item in @($Result.drift)) { Write-Output ("[drift] {0}:{1} ({2})" -f $item.category, $item.name, $item.code) }
    foreach ($item in @($Result.warnings)) { Write-Output ("[warning] {0}:{1} ({2})" -f $item.category, $item.name, $item.code) }
}

try {
    $repositoryRoot = Get-NormalizedFullPath -Path (Split-Path -Parent $PSScriptRoot)
    $BrainRoot = Get-NormalizedFullPath -Path $BrainRoot
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
    $HomeRoot = Get-NormalizedFullPath -Path $HomeRoot
    if ([string]::Equals($HomeRoot, [IO.Path]::GetPathRoot($HomeRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'HomeRoot cannot be a volume root'
    }
    if ([string]::Equals($BrainRoot, [IO.Path]::GetPathRoot($BrainRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BrainRoot cannot be a volume root'
    }

    $contractPath = Join-Path $repositoryRoot 'distribution\design-toolchain.json'
    $manifestPath = Join-Path $repositoryRoot 'distribution\manifests\design-to-html.json'
    $managerPath = Join-Path $repositoryRoot 'scripts\Manage-MultivendorSkills.ps1'
    $contract = [IO.File]::ReadAllText($contractPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([int]$contract.schemaVersion -ne 1) { throw 'Unsupported design toolchain schema' }
    $requiredSkill = [string]$contract.requiredSkill
    $expectedSourceDigest = [string]$manifest.digest

    $missing = New-Object Collections.Generic.List[object]
    $drift = New-Object Collections.Generic.List[object]
    $warnings = New-Object Collections.Generic.List[object]
    $brainFiles = New-Object Collections.Generic.List[object]

    foreach ($relativePathValue in @($contract.requiredBrainFiles)) {
        $relativePath = ([string]$relativePathValue).Replace('\', '/')
        $candidate = Get-SafeContractPath -Root $BrainRoot -RelativePath $relativePath
        if (-not (Test-ExistingPathChainSafe -Root $BrainRoot -Candidate $candidate)) {
            $state = 'Unsafe'
            $digest = $null
            $drift.Add([pscustomobject][ordered]@{ category = 'brain'; name = $relativePath; code = 'UnsafePath' })
        }
        elseif (-not [IO.File]::Exists($candidate)) {
            $state = 'Missing'
            $digest = $null
            $missing.Add([pscustomobject][ordered]@{ category = 'brain'; name = $relativePath })
        }
        else {
            $state = 'Present'
            $digest = Get-FileDigest -Path $candidate
        }
        $brainFiles.Add([pscustomobject][ordered]@{
            category = 'brain'
            path = $relativePath
            state = $state
            digest = $digest
        })
    }

    $manager = Invoke-ManagerCheck -ManagerPath $managerPath -RepositoryRoot $repositoryRoot -RequiredSkill $requiredSkill -UserHome $HomeRoot
    $managerSourceDigest = $expectedSourceDigest
    if ($null -ne $manager.data -and $manager.data.PSObject.Properties['sources']) {
        $source = @($manager.data.sources | Where-Object { [string]$_.skill -ceq $requiredSkill })
        if ($source.Count -eq 1) { $managerSourceDigest = [string]$source[0].manifest.digest }
    }
    if ($manager.status -eq 'Healthy' -and [string]::Equals($managerSourceDigest, $expectedSourceDigest, [StringComparison]::OrdinalIgnoreCase)) {
        $skillState = 'Present'
    }
    elseif ($manager.status -eq 'Installable') {
        $skillState = 'Missing'
        $missing.Add([pscustomobject][ordered]@{ category = 'skill'; name = $requiredSkill })
    }
    else {
        $skillState = 'Drift'
        $drift.Add([pscustomobject][ordered]@{ category = 'skill'; name = $requiredSkill; code = 'ManagerCheckFailed' })
    }
    if (-not [string]::Equals($managerSourceDigest, $expectedSourceDigest, [StringComparison]::OrdinalIgnoreCase)) {
        if ($skillState -ne 'Drift') {
            $skillState = 'Drift'
            $drift.Add([pscustomobject][ordered]@{ category = 'skill'; name = $requiredSkill; code = 'SourceDigestMismatch' })
        }
    }
    $skillEvidence = [pscustomobject][ordered]@{
        category = 'skill'
        name = $requiredSkill
        state = $skillState
        managerStatus = $manager.status
        managerExitCode = [int]$manager.exitCode
        sourceDigest = $managerSourceDigest.ToUpperInvariant()
    }

    $pluginDefinitions = @(
        [pscustomobject][ordered]@{ name = 'product-design'; version = [string]$contract.tested.'product-design'; cache = '.codex/plugins/cache/openai-curated-remote/product-design' },
        [pscustomobject][ordered]@{ name = 'workflow'; version = [string]$contract.tested.workflow; cache = '.codex/plugins/cache/yohan-cc-skills/workflow' },
        [pscustomobject][ordered]@{ name = 'yohan-core'; version = [string]$contract.tested.'yohan-core'; cache = '.codex/plugins/cache/yohan-cc-skills/yohan-core' }
    )
    $plugins = New-Object Collections.Generic.List[object]
    foreach ($definition in $pluginDefinitions) {
        $plugin = Get-PluginEvidence -UserHome $HomeRoot -Name $definition.name -TestedVersion $definition.version -CacheRelativePath $definition.cache
        $plugins.Add($plugin)
        if ($plugin.state -eq 'MissingCapability') {
            $warnings.Add([pscustomobject][ordered]@{ category = 'capability'; name = $plugin.name; code = 'PluginUnavailable' })
        }
        elseif ($plugin.state -eq 'TestedWithNewerAvailable') {
            $warnings.Add([pscustomobject][ordered]@{ category = 'plugin'; name = $plugin.name; code = 'NewerVersionAvailable' })
        }
        elseif ($plugin.state -in @('Drift', 'Unsafe')) {
            $drift.Add([pscustomobject][ordered]@{ category = 'plugin'; name = $plugin.name; code = if ($plugin.state -eq 'Unsafe') { 'UnsafePath' } else { 'TestedVersionMissing' } })
        }
    }

    $status = if ($missing.Count -gt 0) { 'Missing' } elseif ($drift.Count -gt 0) { 'Drift' } else { 'Healthy' }
    $exitCode = if ($status -eq 'Healthy') { 0 } elseif ($status -eq 'Missing') { 2 } else { 3 }
    $result = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'Check'
        status = $status
        skill = $skillEvidence
        brainFiles = $brainFiles.ToArray()
        plugins = $plugins.ToArray()
        missing = $missing.ToArray()
        drift = $drift.ToArray()
        warnings = $warnings.ToArray()
        exitCode = $exitCode
    }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-StableJson -Value $result) }
    else { Write-HumanResult -Result $result }
    exit $exitCode
}
catch {
    $failure = [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'Check'
        status = 'Drift'
        error = 'Environment check could not be completed safely'
        exitCode = 3
    }
    if ($OutputFormat -eq 'Json') { Write-Output (ConvertTo-StableJson -Value $failure) }
    else {
        Write-Output 'Mode: Check'
        Write-Output 'Status: Drift'
        Write-Output '[drift] checker:environment (UnsafeOrInvalidInput)'
    }
    exit 3
}
