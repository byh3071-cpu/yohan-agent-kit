#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tool = Join-Path $repoRoot 'scripts\Invoke-VendorSmoke.ps1'
$specPath = Join-Path $repoRoot 'registry\vendor-smoke-probes.json'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "yohan-agent-kit-tests\vendor-smoke-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$script:assertionCount = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertionCount++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertionCount++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }
function Remove-Whitespace { param([string]$Value); return ($Value -replace '\s', '') }

function New-Utf8NoBomFile {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-Smoke {
    param([string[]]$Arguments)
    $base = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-RepositoryRoot', $repoRoot)
    # Native stderr becomes an ErrorRecord under 2>&1; keep it non-terminating so failure paths stay testable.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& powershell @base @Arguments 2>&1) } finally { $ErrorActionPreference = $previous }
    $exitCode = $LASTEXITCODE
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    $data = $null
    try { $data = $text | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Text = $text }
}

try {
    $spec = ([IO.File]::ReadAllText($specPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 1 ([int]$spec.schemaVersion) 'probe spec schema version'
    $capabilities = @($spec.capabilities)
    Assert-Equal 7 $capabilities.Count 'probe spec covers seven capabilities'
    $claudeProbes = $spec.vendors.'claude-code'.probes
    foreach ($capability in $capabilities) {
        Assert-True ($null -ne $claudeProbes.PSObject.Properties[$capability]) "claude-code probe defined: $capability"
    }

    # Disposable HomeRoot with a synthetic release payload.
    $homeRoot = Join-Path $fixtureRoot 'home'
    $releaseId = 'test-smoke-r1'
    $kitRoot = Join-Path $homeRoot '.yohan-agent-kit'
    $releaseRoot = Join-Path (Join-Path $kitRoot 'releases') $releaseId
    $pluginDir = Join-Path $releaseRoot 'packages\claude-code\plugins\yohan-agent-kit'
    $null = New-Item -ItemType Directory -Path (Join-Path $pluginDir 'skills\adr-cycle') -Force
    New-Utf8NoBomFile -Path (Join-Path $pluginDir 'skills\adr-cycle\SKILL.md') -Content "# adr-cycle stub`n"
    New-Utf8NoBomFile -Path (Join-Path $kitRoot 'active.json') -Content (@{ schemaVersion = 1; releaseId = $releaseId } | ConvertTo-Json)

    # Stub vendor CLI. It fails unless the runner already wrote the probe record to disk.
    $stubScript = Join-Path $fixtureRoot 'stub-vendor.ps1'
    New-Utf8NoBomFile -Path $stubScript -Content @'
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$stdin = [Console]::In.ReadToEnd()
$match = [regex]::Match($stdin, 'YAK-PROBE::(?<probe>[A-Za-z]+)::(?<token>[A-Za-z_]+)')
if (-not $match.Success) { [Console]::Error.Write('stub could not identify the probe'); exit 2 }
$probe = $match.Groups['probe'].Value
$token = $match.Groups['token'].Value
$runRoot = [string]$env:YAK_SMOKE_RUN_ROOT
if ([string]::IsNullOrWhiteSpace($runRoot)) { [Console]::Error.Write('runner did not publish YAK_SMOKE_RUN_ROOT'); exit 5 }
if ([string]$env:YAK_SMOKE_PROBE -cne $probe) { [Console]::Error.Write("probe env mismatch: $($env:YAK_SMOKE_PROBE) vs $probe"); exit 6 }
if ((Get-Location).Path.StartsWith($runRoot, [StringComparison]::OrdinalIgnoreCase)) { [Console]::Error.Write('work directory must not live inside the run root'); exit 7 }
$recordPath = Join-Path (Join-Path $runRoot $probe) 'record.json'
if (-not (Test-Path -LiteralPath $recordPath)) {
    [Console]::Error.Write("file-first violation: record.json missing for $probe")
    exit 3
}
$record = ([IO.File]::ReadAllText($recordPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
if ([string]$record.state -cne 'RUNNING') {
    [Console]::Error.Write("file-first violation: record state was $($record.state)")
    exit 4
}
$mode = [string]$env:YAK_SMOKE_STUB_MODE
if ($mode -ceq 'noout') { exit 0 }
$skillPath = if ($mode -ceq 'ambiguous') { 'C:\Users\user\.claude\skills\adr-cycle\SKILL.md' } else { Join-Path $env:YAK_SMOKE_STUB_PLUGIN_DIR 'skills\adr-cycle\SKILL.md' }
$lines = @()
if ($probe -cne 'negativeRouting') {
    $lines += "SKILL_PATH=$skillPath"
    $lines += 'ROUTED_SKILL=adr-cycle'
    $lines += 'EXITCODE=0'
    $lines += 'SCRIPT_STDOUT={"schemaVersion":1,"mode":"Check","status":"Healthy"}'
    $lines += 'SUBAGENT_RESULT=AGENT-OK'
}
$lines += "YAK-PROBE::$probe::$token"
$payload = [pscustomobject]@{ result = [string]::Join("`n", $lines) }
[Console]::Out.Write(($payload | ConvertTo-Json -Depth 4))
exit 0
'@
    $stubCmd = Join-Path $fixtureRoot 'stub-vendor.cmd'
    New-Utf8NoBomFile -Path $stubCmd -Content "@echo off`r`npowershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$stubScript`"`r`n"

    $env:YAK_SMOKE_STUB_PLUGIN_DIR = $pluginDir
    $outputRoot = Join-Path $fixtureRoot 'smoke'
    $workRoot = Join-Path $fixtureRoot 'work'
    $commonArgs = @('-Vendor', 'claude-code', '-HomeRoot', $homeRoot, '-OutputRoot', $outputRoot, '-WorkRoot', $workRoot, '-CommandOverride', $stubCmd, '-TimeoutSeconds', '120')

    $listOnly = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'list', '-ListOnly'))
    Assert-Equal 0 $listOnly.ExitCode 'list-only run succeeds'
    Assert-Equal 7 (@($listOnly.Data.probes).Count) 'list-only reports every probe'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'list') 'run.json')) 'list-only writes the run record before returning'

    $env:YAK_SMOKE_STUB_MODE = 'pass'
    $passRun = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'pass'))
    Assert-Equal 0 $passRun.ExitCode 'all-pass run exits zero'
    Assert-Equal 7 ([int]$passRun.Data.passCount) 'all seven probes pass'
    $passRoot = Join-Path (Join-Path $outputRoot 'claude-code') 'pass'
    foreach ($capability in $capabilities) {
        $record = ([IO.File]::ReadAllText((Join-Path (Join-Path $passRoot $capability) 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
        Assert-Equal 'COMPLETED' ([string]$record.state) "record finalized: $capability"
        Assert-Equal 'PASS' ([string]$record.status) "record verdict: $capability"
        Assert-True (Test-Path -LiteralPath ([string]$record.stdoutPath)) "transcript persisted: $capability"
        Assert-True (Test-Path -LiteralPath ([string]$record.promptPath)) "prompt persisted: $capability"
    }
    $hookRecord = ([IO.File]::ReadAllText((Join-Path (Join-Path $passRoot 'hookFailureIsolation') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath ([string]$hookRecord.settingsPath)) 'hook-isolation probe materializes an injected settings file'
    $mcpRecord = ([IO.File]::ReadAllText((Join-Path (Join-Path $passRoot 'mcpAuthFailureIsolation') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath ([string]$mcpRecord.mcpConfigPath)) 'mcp-isolation probe materializes an injected mcp config'

    # The aggregate must match the Finalize session-results contract exactly.
    $sessionResults = ([IO.File]::ReadAllText([string]$passRun.Data.sessionResultsPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $vendorBlock = $sessionResults.'claude-code'
    $actualKeys = @($vendorBlock.PSObject.Properties.Name | Sort-Object)
    $expectedKeys = @($capabilities | Sort-Object)
    Assert-Equal ([string]::Join(',', $expectedKeys)) ([string]::Join(',', $actualKeys)) 'session results key contract'
    foreach ($capability in $capabilities) {
        Assert-Equal 'PASS' ([string]$vendorBlock.PSObject.Properties[$capability].Value.status) "session result status: $capability"
        $evidence = [string]$vendorBlock.PSObject.Properties[$capability].Value.evidence
        Assert-True (-not [string]::IsNullOrWhiteSpace($evidence)) "session result evidence present: $capability"
        Assert-True (-not $evidence.StartsWith('TEST_ONLY:')) "session result evidence is not synthetic: $capability"
        Assert-True ($evidence -notmatch '(?i)replace with|\bTODO\b|\bTBD\b') "session result evidence has no placeholder: $capability"
    }

    # A vendor CLI that returns nothing must produce a recorded verdict, not an unjudgeable session.
    $env:YAK_SMOKE_STUB_MODE = 'noout'
    $silentRun = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'silent', '-Probe', 'explicitSkill'))
    Assert-Equal 3 $silentRun.ExitCode 'silent vendor run exits non-zero'
    $silentRecord = ([IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'silent') 'explicitSkill') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 'NO_OUTPUT' ([string]$silentRecord.status) 'silent vendor is recorded as NO_OUTPUT'
    Assert-Equal 'COMPLETED' ([string]$silentRecord.state) 'silent vendor record is still finalized'
    $silentSession = ([IO.File]::ReadAllText([string]$silentRun.Data.sessionResultsPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 'NO_OUTPUT' ([string]$silentSession.'claude-code'.explicitSkill.status) 'silent vendor surfaces in session results'
    Assert-Equal 'NOT_RUN' ([string]$silentSession.'claude-code'.subagent.status) 'unrequested probes stay NOT_RUN'

    # A skill resolved outside the release under test must not be reported as a pass.
    $env:YAK_SMOKE_STUB_MODE = 'ambiguous'
    $ambiguousRun = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'ambiguous', '-Probe', 'explicitSkill'))
    Assert-Equal 3 $ambiguousRun.ExitCode 'out-of-release resolution exits non-zero'
    $ambiguousRecord = ([IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'ambiguous') 'explicitSkill') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 'AMBIGUOUS' ([string]$ambiguousRecord.status) 'out-of-release resolution is recorded as AMBIGUOUS'
    Assert-Equal $false ([bool]$ambiguousRecord.pathWithinRelease) 'out-of-release resolution is flagged'

    $unknownProbe = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'unknown', '-Probe', 'notARealProbe'))
    Assert-True ($unknownProbe.ExitCode -ne 0) 'unknown probe name is rejected'

    # "-Probe a b" used to bind "b" to -Release and silently probe the wrong release.
    # Assert behaviour, not text: the binder message is rendered by the host and varies.
    $strayArg = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'stray', '-ListOnly', '-Probe', 'sharedScript', 'subagent'))
    Assert-True ($strayArg.ExitCode -ne 0) 'a stray positional argument is rejected'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'stray') 'run.json'))) 'a stray positional argument aborts before any run record'

    # A comma-separated list survives powershell.exe -File, which passes values verbatim.
    $commaList = Invoke-Smoke -Arguments ($commonArgs + @('-RunId', 'commalist', '-ListOnly', '-Probe', 'sharedScript,subagent'))
    Assert-Equal 0 $commaList.ExitCode 'comma-separated probe list is accepted'
    Assert-Equal 2 (@($commaList.Data.probes).Count) 'comma-separated probe list expands to two probes'

    # A vendor CLI discovers repo-local skills from its cwd, so an in-repo work directory is refused.
    # Name it per run so a leftover from another run cannot mask the assertion.
    $rejectedWorkRoot = Join-Path $repoRoot ".vhk\rejected-work-$(Split-Path -Leaf $fixtureRoot)"
    $inRepoWork = Invoke-Smoke -Arguments @('-Vendor', 'claude-code', '-HomeRoot', $homeRoot, '-OutputRoot', $outputRoot,
        '-WorkRoot', $rejectedWorkRoot, '-CommandOverride', $stubCmd, '-RunId', 'inrepo', '-Probe', 'explicitSkill')
    Assert-True ($inRepoWork.ExitCode -ne 0) 'work directory inside the repository is rejected'
    # Non-interactive PowerShell wraps error text mid-word, so compare without whitespace.
    Assert-True ((Remove-Whitespace -Value $inRepoWork.Text).Contains('mustbeoutsidetherepository')) 'in-repo work directory names the reason'
    Assert-True (-not (Test-Path -LiteralPath $rejectedWorkRoot)) 'a rejected work directory is never created'

    # An unexpanded placeholder must fail loudly instead of reaching the vendor CLI.
    $brokenSpecRoot = Join-Path $fixtureRoot 'broken-spec'
    $null = New-Item -ItemType Directory -Path (Join-Path $brokenSpecRoot 'registry') -Force
    $brokenSpec = ([IO.File]::ReadAllText($specPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $brokenSpec.vendors.'claude-code'.probes.explicitSkill.prompt = 'run {{NOT_A_REAL_PLACEHOLDER}} then print YAK-PROBE::explicitSkill::LOADED'
    New-Utf8NoBomFile -Path (Join-Path $brokenSpecRoot 'registry\vendor-smoke-probes.json') -Content ($brokenSpec | ConvertTo-Json -Depth 12)
    $brokenBase = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $tool, '-RepositoryRoot', $brokenSpecRoot)
    $brokenArgs = @('-Vendor', 'claude-code', '-HomeRoot', $homeRoot, '-OutputRoot', $outputRoot, '-WorkRoot', $workRoot, '-CommandOverride', $stubCmd, '-RunId', 'broken', '-Probe', 'explicitSkill')
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $brokenOutput = @(& powershell @brokenBase @brokenArgs 2>&1) } finally { $ErrorActionPreference = $previous }
    $brokenExit = $LASTEXITCODE
    $brokenText = [string]::Join([Environment]::NewLine, @($brokenOutput | ForEach-Object { [string]$_ }))
    Assert-True ($brokenExit -ne 0) 'unexpanded placeholder never reports a pass'
    $brokenRecord = ([IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'broken') 'explicitSkill') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 'RUNNER_ERROR' ([string]$brokenRecord.status) 'unexpanded placeholder is a recorded verdict'
    Assert-True ((Remove-Whitespace -Value ([string]$brokenRecord.evidence)).Contains('Unresolvedplaceholder')) 'unexpanded placeholder names the reason on disk'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path (Join-Path $outputRoot 'claude-code') 'broken') 'explicitSkill') 'prompt.txt'))) 'a broken prompt is never handed to the vendor CLI'

    # A probe failure must not discard the verdicts of the probes around it.
    $brokenArgsAll = @('-Vendor', 'claude-code', '-HomeRoot', $homeRoot, '-OutputRoot', $outputRoot, '-WorkRoot', $workRoot, '-CommandOverride', $stubCmd, '-RunId', 'brokenmix', '-Probe', 'explicitSkill,negativeRouting')
    $ErrorActionPreference = 'Continue'
    try { $null = @(& powershell @brokenBase @brokenArgsAll 2>&1) } finally { $ErrorActionPreference = $previous }
    $mixRoot = Join-Path (Join-Path $outputRoot 'claude-code') 'brokenmix'
    $mixBroken = ([IO.File]::ReadAllText((Join-Path (Join-Path $mixRoot 'explicitSkill') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $mixHealthy = ([IO.File]::ReadAllText((Join-Path (Join-Path $mixRoot 'negativeRouting') 'record.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
    Assert-Equal 'RUNNER_ERROR' ([string]$mixBroken.status) 'the failing probe is recorded'
    Assert-Equal 'PASS' ([string]$mixHealthy.status) 'a later probe still runs after an earlier one fails'

    Write-Output "PASS: $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "FAIL after $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 1
}
