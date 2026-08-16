#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$builder = Join-Path $repoRoot 'scripts\Build-AgentKit.mjs'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "yohan-agent-kit-tests\build-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$outputRoot = Join-Path $fixtureRoot 'releases'
$null = New-Item -ItemType Directory -Path $outputRoot -Force
$script:assertionCount = 0

function Assert-True { param([bool]$Condition, [string]$Message); $script:assertionCount++; if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Equal { param($Expected, $Actual, [string]$Message); $script:assertionCount++; if ([string]$Expected -cne [string]$Actual) { throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]" } }
function Read-JsonUtf8 { param([string]$Path); return [string]([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
function Get-TestSha256File { param([string]$Path); $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($Path); try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $stream.Dispose(); $sha.Dispose() } }

function Invoke-Builder {
    param([string]$Release, [switch]$PermitDirty, [string]$CustomOutputRoot = $outputRoot)
    $arguments = @($builder, '--release', $Release, '--output-root', $CustomOutputRoot, '--json')
    if ($PermitDirty) { $arguments += @('--source-commit', ('1' * 40), '--allow-dirty', '--allow-test-output') }
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& node @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    $text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    $data = $null
    if ($exitCode -eq 0) { $data = $text | ConvertFrom-Json }
    return [pscustomobject]@{ ExitCode = $exitCode; Text = $text; Data = $data }
}

$dirtyProbe = Join-Path $repoRoot (".agent-kit-test-dirty-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
$testExitCode = 1

try {
    $release = 'test-build-a'
    [IO.File]::WriteAllText($dirtyProbe, "test-only`n", (New-Object Text.UTF8Encoding($false)))
    $built = Invoke-Builder -Release $release -PermitDirty
    Assert-Equal 0 $built.ExitCode 'dirty test build with bounded output succeeds'
    Assert-Equal 'Built' $built.Data.status 'builder result status'
    $releaseRoot = Join-Path $outputRoot $release
    Assert-True ([IO.File]::Exists((Join-Path $releaseRoot 'release-manifest.json'))) 'release manifest exists'

    $required = @(
        'packages\agent-plugins\yohan-agent-kit\plugin.json',
        'packages\agent-plugins\yohan-agent-kit\mcp.json',
        'packages\claude-code\.claude-plugin\marketplace.json',
        'packages\claude-code\plugins\yohan-agent-kit\hooks\hooks.json',
        'packages\claude-code\plugins\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\codex\yohan-agent-kit\.codex-plugin\plugin.json',
        'packages\codex\yohan-agent-kit\hooks.json',
        'packages\codex\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\cursor\yohan-agent-kit\.cursor-plugin\plugin.json',
        'packages\cursor\yohan-agent-kit\hooks\hooks.json',
        'packages\cursor\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\antigravity\yohan-agent-kit\plugin.json',
        'packages\antigravity\yohan-agent-kit\hooks.json',
        'packages\antigravity\yohan-agent-kit\scripts\agent-kit-hook.mjs',
        'packages\antigravity\yohan-agent-kit\agents\explorer.md'
    )
    foreach ($path in $required) { Assert-True ([IO.File]::Exists((Join-Path $releaseRoot $path))) "required package file $path" }

    $portableRoot = Join-Path $releaseRoot 'packages\agent-plugins\yohan-agent-kit'
    $portableEntries = @(Get-ChildItem -LiteralPath $portableRoot -Force | ForEach-Object Name | Sort-Object)
    Assert-Equal 'mcp.json,plugin.json,skills' ([string]::Join(',', $portableEntries)) 'Agent Plugins output contains only v1 component roots'
    $portableManifest = Read-JsonUtf8 -Path (Join-Path $portableRoot 'plugin.json')
    Assert-Equal 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json' $portableManifest.'$schema' 'portable plugin schema'
    $portableFields = @($portableManifest.PSObject.Properties.Name)
    Assert-True (-not ($portableFields -contains 'agents') -and -not ($portableFields -contains 'hooks') -and -not ($portableFields -contains 'commands')) 'portable manifest has no native-only fields'
    $portableMcp = Read-JsonUtf8 -Path (Join-Path $portableRoot 'mcp.json')
    Assert-Equal 'stdio' $portableMcp.mcpServers.yohan.type 'portable MCP adds explicit transport'

    $claudeMarketplace = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'packages\claude-code\.claude-plugin\marketplace.json')
    Assert-Equal 'yohan-cc-skills' $claudeMarketplace.name 'compatibility Marketplace namespace retained'
    foreach ($plugin in @('yohan-core', 'workflow', 'critical-thinking', 'statusline', 'yohan-agent-kit')) {
        Assert-True (@($claudeMarketplace.plugins | Where-Object name -eq $plugin).Count -eq 1) "Claude package includes $plugin"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'packages\codex\yohan-agent-kit\agents\merge-advisor.md'))) 'candidate agent is excluded from release'
    $codexManifest = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'packages\codex\yohan-agent-kit\.codex-plugin\plugin.json')
    Assert-Equal './hooks.json' $codexManifest.hooks 'Codex manifest declares hook adapter'
    $cursorHooks = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'packages\cursor\yohan-agent-kit\hooks\hooks.json')
    Assert-Equal 1 $cursorHooks.version 'Cursor hook schema version'
    Assert-True (@($cursorHooks.hooks.sessionEnd).Count -eq 1) 'Cursor sessionEnd adapter exists'
    $antigravityHooks = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'packages\antigravity\yohan-agent-kit\hooks.json')
    Assert-True (@($antigravityHooks.'yohan-agent-kit-observer'.PostInvocation).Count -eq 1) 'Antigravity PostInvocation adapter exists'
    $antigravityManifest = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'packages\antigravity\yohan-agent-kit\plugin.json')
    Assert-Equal 'https://antigravity.google/schemas/v1/plugin.json' $antigravityManifest.'$schema' 'Antigravity native schema'

    $hookSelfTest = @(& node (Join-Path $releaseRoot 'packages\codex\yohan-agent-kit\scripts\agent-kit-hook.mjs') --self-test 2>&1)
    Assert-Equal 0 $LASTEXITCODE 'common hook script self-test succeeds'
    Assert-Equal 'PASS' (($hookSelfTest -join [Environment]::NewLine) | ConvertFrom-Json).status 'common hook self-test status'
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = @(& node (Join-Path $releaseRoot 'packages\codex\yohan-agent-kit\scripts\agent-kit-hook.mjs') --simulate-failure 2>&1)
        $hookFailureExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    Assert-Equal 17 $hookFailureExit 'common hook exposes deterministic failure for host isolation test'

    $manifest = Read-JsonUtf8 -Path (Join-Path $releaseRoot 'release-manifest.json')
    Assert-Equal $release $manifest.releaseId 'manifest release ID'
    Assert-Equal ('1' * 40) $manifest.gitCommit 'manifest exact Git commit'
    Assert-True ([bool]$manifest.dirtyBuild) 'test artifact records dirty provenance'
    Assert-Equal 5 @($manifest.packages).Count 'five package types'
    Assert-True (@($manifest.files).Count -gt 20) 'release manifest covers payload files'
    Assert-Equal 2 @($manifest.compatibility.antigravity.discoveryPaths).Count 'Antigravity IDE and CLI discovery paths are both recorded'
    foreach ($file in @($manifest.files)) {
        $path = Join-Path $releaseRoot ([string]$file.path).Replace('/', '\')
        $hash = Get-TestSha256File -Path $path
        Assert-Equal $file.sha256 $hash "payload hash $($file.path)"
        Assert-Equal $file.bytes (Get-Item -LiteralPath $path).Length "payload size $($file.path)"
    }

    $immutable = Invoke-Builder -Release $release -PermitDirty
    Assert-Equal 1 $immutable.ExitCode 'same release ID cannot overwrite immutable output'
    Assert-True ($immutable.Text -match 'immutable and already exists') 'immutable output rejection reason'

    $outside = Invoke-Builder -Release 'test-build-outside' -PermitDirty -CustomOutputRoot (Join-Path ([IO.Path]::GetTempPath()) 'not-yohan-agent-kit')
    Assert-Equal 1 $outside.ExitCode 'builder rejects output outside bounded roots'

    $linkedOutputOutside = Join-Path $fixtureRoot 'linked-output-outside'
    $linkedOutput = Join-Path $fixtureRoot 'linked-output'
    $null = New-Item -ItemType Directory -Path $linkedOutputOutside -Force
    $null = New-Item -ItemType Junction -Path $linkedOutput -Target $linkedOutputOutside
    $linkedOutputBuild = Invoke-Builder -Release 'test-build-linked-output' -PermitDirty -CustomOutputRoot $linkedOutput
    Assert-Equal 1 $linkedOutputBuild.ExitCode 'builder rejects a linked output root'
    Assert-True ($linkedOutputBuild.Text -match 'linked entry') 'linked output rejection reason'

    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $overrideDeniedOutput = @(& node $builder --release test-override-denied --output-root (Join-Path $repoRoot 'tests\.work') --source-commit ('9' * 40) --json 2>&1)
        $overrideDeniedExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    Assert-Equal 1 $overrideDeniedExit 'source commit override is rejected outside test mode'
    Assert-True (($overrideDeniedOutput -join [Environment]::NewLine) -match 'test-only') 'source override rejection reason'

    $cleanRequired = Invoke-Builder -Release 'test-build-clean-required' -CustomOutputRoot (Join-Path $repoRoot "tests\.work\clean-required-$PID")
    Assert-Equal 1 $cleanRequired.ExitCode 'release build refuses dirty checkout by default'
    Assert-True ($cleanRequired.Text -match 'clean Git checkout') 'clean checkout rejection reason'

    Write-Output "PASS: $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    $testExitCode = 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "FAIL after $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
}
finally {
    if ([IO.File]::Exists($dirtyProbe)) {
        Remove-Item -LiteralPath $dirtyProbe -Force -ErrorAction Stop
    }
}

exit $testExitCode
