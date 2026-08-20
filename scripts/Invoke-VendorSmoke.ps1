#requires -Version 5.1

<#
    File-first vendor smoke runner for Goal 8.

    Contract: every probe record is written to disk BEFORE the vendor CLI starts,
    and every verdict is computed by reading the transcript back from disk.
    A vendor CLI that returns no final summary produces a recorded NO_OUTPUT
    result instead of an unjudgeable session.
#>

# PositionalBinding=$false: a stray argument (e.g. "-Probe a b") would otherwise
# bind silently to -Release and probe the wrong release.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude-code', 'codex', 'cursor', 'antigravity')]
    [string]$Vendor,

    [string]$Release,

    [string]$HomeRoot,

    [string]$RepositoryRoot,

    [string]$OutputRoot,

    [string]$WorkRoot,

    [string[]]$Probe,

    [int]$TimeoutSeconds = 900,

    [string]$CommandOverride,

    [string]$RunId,

    [switch]$ListOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:capabilityKeys = @('explicitSkill', 'implicitSkill', 'negativeRouting', 'sharedScript', 'subagent', 'hookFailureIsolation', 'mcpAuthFailureIsolation')

function Get-Utf8NoBom { return (New-Object System.Text.UTF8Encoding($false)) }

function Write-TextFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Content, (Get-Utf8NoBom))
}

function Write-JsonFile {
    param([string]$Path, $Value)
    Write-TextFile -Path $Path -Content (($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine)
}

function Read-JsonFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label not found: $Path" }
    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    try { return $raw | ConvertFrom-Json } catch { throw "$Label is not valid JSON: $Path" }
}

function Read-TextFileIfPresent {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Resolve-VendorCommand {
    param([string[]]$Candidates, [string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override)) { throw "CommandOverride not found: $Override" }
        return (Resolve-Path -LiteralPath $Override).Path
    }
    foreach ($candidate in $Candidates) {
        $found = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -ne $found) {
            if (-not [string]::IsNullOrWhiteSpace([string]$found.Source)) { return [string]$found.Source }
            return [string]$found.Name
        }
    }
    throw "Vendor command not found. Tried: $([string]::Join(', ', $Candidates))"
}

function Test-PathWithin {
    param([string]$Root, [string]$Candidate)
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath($Candidate).TrimEnd('\', '/')
    return [string]::Equals($base, $path, [StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-DirectorySnapshot {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } | Sort-Object)
}

function Get-ProbeProperty {
    param($Probe, [string]$Name)
    $property = $Probe.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-TranscriptText {
    param([string]$RawStdout)
    if ([string]::IsNullOrWhiteSpace($RawStdout)) { return '' }
    try {
        $parsed = $RawStdout | ConvertFrom-Json
        $resultProperty = $parsed.PSObject.Properties['result']
        if ($null -ne $resultProperty -and -not [string]::IsNullOrWhiteSpace([string]$resultProperty.Value)) {
            return [string]$resultProperty.Value
        }
    }
    catch { }
    return $RawStdout
}

function Expand-Placeholders {
    param([string]$Value, [hashtable]$Map, [string]$Label, [string[]]$Deferred)
    $expanded = $Value
    foreach ($key in $Map.Keys) { $expanded = $expanded.Replace('{{' + $key + '}}', [string]$Map[$key]) }
    # An unexpanded placeholder silently reaches the vendor CLI and produces a
    # meaningless verdict, so fail loudly instead.
    foreach ($match in [regex]::Matches($expanded, '\{\{(?<key>[A-Z_]+)\}\}')) {
        $key = $match.Groups['key'].Value
        if ($null -ne $Deferred -and $Deferred -contains $key) { continue }
        throw "Unresolved placeholder {{$key}} in ${Label}: $Value"
    }
    return $expanded
}

function ConvertTo-CommandLine {
    param([string[]]$Arguments)
    $parts = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') { '"' + $argument.Replace('"', '\"') + '"' } else { $argument }
    }
    return [string]::Join(' ', @($parts))
}

$repoRoot = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path } else { (Resolve-Path -LiteralPath $RepositoryRoot).Path }
$specPath = Join-Path $repoRoot 'registry\vendor-smoke-probes.json'
$spec = Read-JsonFile -Path $specPath -Label 'Vendor smoke probe spec'
if ([int]$spec.schemaVersion -ne 1) { throw 'Vendor smoke probe spec schemaVersion must be 1' }

$vendorProperty = $spec.vendors.PSObject.Properties[$Vendor]
if ($null -eq $vendorProperty) { throw "Vendor smoke probes are not defined yet: $Vendor" }
$vendorSpec = $vendorProperty.Value

# powershell.exe -File passes values verbatim, so "-Probe a,b" arrives as one string.
$requestedProbes = if ($null -eq $Probe -or $Probe.Count -eq 0) { @($script:capabilityKeys) } else {
    @($Probe | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
foreach ($name in $requestedProbes) {
    if ($script:capabilityKeys -notcontains $name) { throw "Unknown probe: $name" }
    if ($null -eq $vendorSpec.probes.PSObject.Properties[$name]) { throw "Probe is not defined for ${Vendor}: $name" }
}

if ([string]::IsNullOrWhiteSpace($HomeRoot)) { $HomeRoot = [Environment]::GetFolderPath('UserProfile') }
$HomeRoot = (Resolve-Path -LiteralPath $HomeRoot).Path
$kitRoot = Join-Path $HomeRoot '.yohan-agent-kit'
if ([string]::IsNullOrWhiteSpace($Release)) {
    $active = Read-JsonFile -Path (Join-Path $kitRoot 'active.json') -Label 'Active release pointer'
    $Release = [string]$active.releaseId
}
$releaseRoot = Join-Path (Join-Path $kitRoot 'releases') $Release
if (-not (Test-Path -LiteralPath $releaseRoot)) { throw "Installed release not found: $releaseRoot" }
$releaseRoot = (Resolve-Path -LiteralPath $releaseRoot).Path
$pluginDir = (Resolve-Path -LiteralPath (Join-Path $releaseRoot ([string]$vendorSpec.pluginPackage).Replace('/', '\'))).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot '.vhk\smoke' }
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-Date -Format 'yyyyMMdd-HHmmss' }
$runRoot = Join-Path (Join-Path $OutputRoot $Vendor) $RunId
$null = New-Item -ItemType Directory -Path $runRoot -Force
$runRoot = (Resolve-Path -LiteralPath $runRoot).Path

# The session working directory must sit outside every checkout: a vendor CLI
# discovers repo-local skills from its cwd and would shadow the release under test.
if ([string]::IsNullOrWhiteSpace($WorkRoot)) { $WorkRoot = Join-Path ([IO.Path]::GetTempPath()) 'yohan-agent-kit-smoke' }
$workDir = [IO.Path]::GetFullPath((Join-Path (Join-Path $WorkRoot $Vendor) $RunId))
# Reject before creating anything, so a bad request leaves no directory behind.
if (Test-PathWithin -Root $repoRoot -Candidate $workDir) { throw "Smoke work directory must be outside the repository: $workDir" }
$null = New-Item -ItemType Directory -Path $workDir -Force
$workDir = (Resolve-Path -LiteralPath $workDir).Path

$command = Resolve-VendorCommand -Candidates @($vendorSpec.commandCandidates) -Override $CommandOverride

$placeholders = @{
    'PLUGIN_DIR'   = $pluginDir
    'WORK_DIR'     = $workDir
    'RELEASE_ROOT' = $releaseRoot
    'REPO_ROOT'    = $repoRoot
}

$runRecordPath = Join-Path $runRoot 'run.json'
Write-JsonFile -Path $runRecordPath -Value ([pscustomobject][ordered]@{
        schemaVersion = 1
        state         = 'STARTED'
        vendor        = $Vendor
        releaseId     = $Release
        releaseRoot   = $releaseRoot
        pluginDir     = $pluginDir
        command       = $command
        probes        = @($requestedProbes)
        runRoot       = $runRoot
        startedUtc    = (Get-Date).ToUniversalTime().ToString('o')
    })

if ($ListOnly) {
    Write-Output (ConvertTo-Json ([pscustomobject][ordered]@{ mode = 'ListOnly'; vendor = $Vendor; command = $command; pluginDir = $pluginDir; probes = @($requestedProbes); runRoot = $runRoot }) -Depth 6)
    exit 0
}

foreach ($name in $requestedProbes) {
    $probeSpec = $vendorSpec.probes.PSObject.Properties[$name].Value
    $probeRoot = Join-Path $runRoot $name
    $null = New-Item -ItemType Directory -Path $probeRoot -Force

    $promptPath = Join-Path $probeRoot 'prompt.txt'
    $stdoutPath = Join-Path $probeRoot 'stdout.txt'
    $stderrPath = Join-Path $probeRoot 'stderr.txt'
    $recordPath = Join-Path $probeRoot 'record.json'

    # SETTINGS and MCP_CONFIG resolve below, once their files are materialized.
    $deferred = @('SETTINGS', 'MCP_CONFIG')
    $arguments = @(foreach ($argument in @($probeSpec.args)) { Expand-Placeholders -Value ([string]$argument) -Map $placeholders -Label "$name args" -Deferred $deferred })
    $promptText = Expand-Placeholders -Value ([string]$probeSpec.prompt) -Map $placeholders -Label "$name prompt"

    $settingsPath = ''
    $materializeSettings = Get-ProbeProperty -Probe $probeSpec -Name 'materializeSettings'
    if ($null -ne $materializeSettings) {
        $settingsPath = Join-Path $probeRoot 'settings.json'
        Write-JsonFile -Path $settingsPath -Value $materializeSettings
        $arguments = @(foreach ($argument in $arguments) { $argument.Replace('{{SETTINGS}}', $settingsPath) })
    }
    $mcpConfigPath = ''
    $materializeMcpConfig = Get-ProbeProperty -Probe $probeSpec -Name 'materializeMcpConfig'
    if ($null -ne $materializeMcpConfig) {
        $mcpConfigPath = Join-Path $probeRoot 'mcp-config.json'
        Write-JsonFile -Path $mcpConfigPath -Value $materializeMcpConfig
        $arguments = @(foreach ($argument in $arguments) { $argument.Replace('{{MCP_CONFIG}}', $mcpConfigPath) })
    }

    foreach ($argument in $arguments) {
        $leftover = [regex]::Match($argument, '\{\{(?<key>[A-Z_]+)\}\}')
        if ($leftover.Success) { throw "Unresolved placeholder {{$($leftover.Groups['key'].Value)}} in $name args after materialization" }
    }

    Write-TextFile -Path $promptPath -Content $promptText

    $assertUnchanged = [bool](Get-ProbeProperty -Probe $probeSpec -Name 'assertWorkDirUnchanged')
    $before = @()
    if ($assertUnchanged) { $before = @(Get-DirectorySnapshot -Path $workDir) }

    # File-first: the record exists before the vendor CLI is launched.
    Write-JsonFile -Path $recordPath -Value ([pscustomobject][ordered]@{
            schemaVersion = 1
            state         = 'RUNNING'
            vendor        = $Vendor
            probe         = $name
            command       = $command
            commandLine   = (ConvertTo-CommandLine -Arguments $arguments)
            promptPath    = $promptPath
            stdoutPath    = $stdoutPath
            stderrPath    = $stderrPath
            workDir       = $workDir
            startedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        })

    Write-TextFile -Path $stdoutPath -Content ''
    Write-TextFile -Path $stderrPath -Content ''

    $exitCode = $null
    $timedOut = $false
    $launchError = ''
    # The child needs its own run location to correlate raw evidence; cwd no
    # longer implies it now that the work directory lives outside the repository.
    $env:YAK_SMOKE_RUN_ROOT = $runRoot
    $env:YAK_SMOKE_PROBE = $name
    try {
        $startArgs = @{
            FilePath               = $command
            ArgumentList           = (ConvertTo-CommandLine -Arguments $arguments)
            WorkingDirectory       = $workDir
            RedirectStandardInput  = $promptPath
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError  = $stderrPath
            NoNewWindow            = $true
            PassThru               = $true
        }
        $process = Start-Process @startArgs
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $process.Kill() } catch { }
            $null = $process.WaitForExit(30000)
        }
        # The parameterless overload flushes exit processing; without it ExitCode stays null.
        try { $process.WaitForExit() } catch { }
        try { $exitCode = [int]$process.ExitCode } catch { $exitCode = $null }
    }
    catch {
        $launchError = [string]$_.Exception.Message
    }

    # Verdict is computed from what is on disk, never from an in-memory summary.
    $rawStdout = Read-TextFileIfPresent -Path $stdoutPath
    $rawStderr = Read-TextFileIfPresent -Path $stderrPath
    $transcript = Get-TranscriptText -RawStdout $rawStdout

    $matched = @()
    $missing = @()
    foreach ($token in @(Get-ProbeProperty -Probe $probeSpec -Name 'expect')) {
        if ($transcript.Contains([string]$token)) { $matched += [string]$token } else { $missing += [string]$token }
    }
    $violated = @()
    foreach ($token in @(Get-ProbeProperty -Probe $probeSpec -Name 'forbid')) {
        if ($transcript.Contains([string]$token)) { $violated += [string]$token }
    }

    $createdPaths = @()
    if ($assertUnchanged) {
        $after = @(Get-DirectorySnapshot -Path $workDir)
        $createdPaths = @($after | Where-Object { $before -notcontains $_ })
    }

    $resolvedPath = ''
    $pathWithinRelease = $null
    $marker = [string](Get-ProbeProperty -Probe $probeSpec -Name 'releasePathMarker')
    if (-not [string]::IsNullOrWhiteSpace($marker)) {
        $pattern = [regex]::Escape($marker) + '\s*(?<value>\S[^\r\n]*)'
        $match = [regex]::Match($transcript, $pattern)
        if ($match.Success) {
            $resolvedPath = $match.Groups['value'].Value.Trim().Trim('"', "'", '`', '*')
            $pathWithinRelease = $resolvedPath.StartsWith($releaseRoot, [StringComparison]::OrdinalIgnoreCase)
        }
    }

    $reasons = @()
    if (-not [string]::IsNullOrWhiteSpace($launchError)) { $reasons += "launch failed: $launchError" }
    if ($timedOut) { $reasons += "timed out after $TimeoutSeconds seconds" }
    if ($missing.Count -gt 0) { $reasons += "missing expected markers: $([string]::Join(', ', $missing))" }
    if ($violated.Count -gt 0) { $reasons += "forbidden markers present: $([string]::Join(', ', $violated))" }
    if ($createdPaths.Count -gt 0) { $reasons += "work directory changed: $($createdPaths.Count) paths" }
    if ($null -ne $pathWithinRelease -and -not $pathWithinRelease) { $reasons += "resolved skill path is outside the release under test: $resolvedPath" }

    $status = 'FAIL'
    if (-not [string]::IsNullOrWhiteSpace($launchError)) { $status = 'LAUNCH_ERROR' }
    elseif ($timedOut) { $status = 'TIMEOUT' }
    elseif ([string]::IsNullOrWhiteSpace($rawStdout)) { $status = 'NO_OUTPUT'; $reasons = @('vendor CLI produced no stdout') }
    elseif ($null -ne $pathWithinRelease -and -not $pathWithinRelease -and $missing.Count -eq 0 -and $violated.Count -eq 0 -and $createdPaths.Count -eq 0) { $status = 'AMBIGUOUS' }
    elseif ($reasons.Count -eq 0) { $status = 'PASS' }

    $exitLabel = if ($null -eq $exitCode) { 'none' } else { [string]$exitCode }
    $evidence = "$Vendor $name via $command exit=$exitLabel transcript=$stdoutPath markers=[$([string]::Join('|', $matched))]"
    if ($reasons.Count -gt 0) { $evidence += " reasons=[$([string]::Join('; ', $reasons))]" }
    if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) { $evidence += " resolvedPath=$resolvedPath" }

    Write-JsonFile -Path $recordPath -Value ([pscustomobject][ordered]@{
            schemaVersion     = 1
            state             = 'COMPLETED'
            vendor            = $Vendor
            probe             = $name
            status            = $status
            command           = $command
            commandLine       = (ConvertTo-CommandLine -Arguments $arguments)
            exitCode          = $exitCode
            timedOut          = $timedOut
            promptPath        = $promptPath
            stdoutPath        = $stdoutPath
            stderrPath        = $stderrPath
            settingsPath      = $settingsPath
            mcpConfigPath     = $mcpConfigPath
            stdoutBytes       = $rawStdout.Length
            stderrBytes       = $rawStderr.Length
            matchedMarkers    = @($matched)
            missingMarkers    = @($missing)
            violatedMarkers   = @($violated)
            createdPaths      = @($createdPaths)
            resolvedPath      = $resolvedPath
            pathWithinRelease = $pathWithinRelease
            reasons           = @($reasons)
            evidence          = $evidence
            completedUtc      = (Get-Date).ToUniversalTime().ToString('o')
        })
}

# Aggregate strictly from the files on disk.
$results = [ordered]@{}
foreach ($name in $script:capabilityKeys) {
    $recordPath = Join-Path (Join-Path $runRoot $name) 'record.json'
    if (Test-Path -LiteralPath $recordPath) {
        $record = Read-JsonFile -Path $recordPath -Label "Probe record $name"
        $results[$name] = [pscustomobject][ordered]@{ status = [string]$record.status; evidence = [string]$record.evidence }
    }
    else {
        $results[$name] = [pscustomobject][ordered]@{ status = 'NOT_RUN'; evidence = '' }
    }
}

$sessionResultsPath = Join-Path $runRoot "session-results.$Vendor.json"
Write-JsonFile -Path $sessionResultsPath -Value ([pscustomobject]@{ $Vendor = [pscustomobject]$results })

Write-JsonFile -Path $runRecordPath -Value ([pscustomobject][ordered]@{
        schemaVersion      = 1
        state              = 'COMPLETED'
        vendor             = $Vendor
        releaseId          = $Release
        releaseRoot        = $releaseRoot
        pluginDir          = $pluginDir
        command            = $command
        probes             = @($requestedProbes)
        runRoot            = $runRoot
        sessionResultsPath = $sessionResultsPath
        completedUtc       = (Get-Date).ToUniversalTime().ToString('o')
    })

$readBack = Read-JsonFile -Path $sessionResultsPath -Label 'Session results'
$vendorResults = $readBack.PSObject.Properties[$Vendor].Value
$summary = [ordered]@{}
foreach ($name in $script:capabilityKeys) { $summary[$name] = [string]$vendorResults.PSObject.Properties[$name].Value.status }
$passCount = @($summary.Values | Where-Object { $_ -ceq 'PASS' }).Count

Write-Output (ConvertTo-Json ([pscustomobject][ordered]@{
            schemaVersion      = 1
            vendor             = $Vendor
            releaseId          = $Release
            runRoot            = $runRoot
            sessionResultsPath = $sessionResultsPath
            passCount          = $passCount
            total              = $script:capabilityKeys.Count
            statuses           = [pscustomobject]$summary
        }) -Depth 6)

if ($passCount -eq $script:capabilityKeys.Count) { exit 0 } else { exit 3 }
