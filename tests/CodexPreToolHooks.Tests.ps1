#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pluginRoot = Join-Path $repoRoot 'plugins\yohan-core'
$hooksPath = Join-Path $pluginRoot 'hooks\hooks.json'
$fixtureRoot = Join-Path $PSScriptRoot ".work\codex-pretool-hooks-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
$script:assertionCount = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    $script:assertionCount++
    if ([string]$Expected -cne [string]$Actual) {
        throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertionCount++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-HookCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Payload
    )

    $callId = [guid]::NewGuid().ToString('N')
    $stdinPath = Join-Path $fixtureRoot "stdin-$callId.json"
    $stdoutPath = Join-Path $fixtureRoot "stdout-$callId.json"
    $stderrPath = Join-Path $fixtureRoot "stderr-$callId.txt"
    [IO.File]::WriteAllText($stdinPath, $Payload, $utf8NoBom)

    $cmd = 'set "CLAUDE_PLUGIN_ROOT=' + $pluginRoot + '" && ' +
        'cd /d "' + $fixtureRoot + '" && ' +
        $Command + ' < "' + $stdinPath + '" > "' + $stdoutPath + '" 2> "' + $stderrPath + '"'

    try {
        $null = & cmd.exe /d /s /c $cmd
        $exitCode = $LASTEXITCODE
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::UTF8).Trim() } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8).Trim() } else { '' }
    }
    finally {
        foreach ($path in @($stdinPath, $stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Stdout = $stdout; Stderr = $stderr }
}

try {
    $hooksText = [IO.File]::ReadAllText($hooksPath, [Text.Encoding]::UTF8)
    $config = $hooksText | ConvertFrom-Json
    $handlers = @($config.hooks.PreToolUse | ForEach-Object { $_.hooks } | ForEach-Object { $_ })
    $expectedScripts = @('protect-secrets.ps1', 'destructive-guard.ps1', 'pre-commit-check.ps1', 'critic-gate.ps1')

    Assert-Equal 4 $handlers.Count 'all four PreToolUse handlers are present'
    Assert-True (-not $hooksText.Contains('C:\Users\')) 'tracked hook config contains no personal absolute path'

    foreach ($scriptName in $expectedScripts) {
        $handler = @($handlers | Where-Object { [string]$_.command -match [regex]::Escape("/hooks/$scriptName") })
        Assert-Equal 1 $handler.Count "$scriptName has one handler"
        Assert-True ([string]$handler[0].command -match '^powershell .*\$\{CLAUDE_PLUGIN_ROOT\}/hooks/') "$scriptName preserves the Claude command"
        Assert-True ([string]$handler[0].commandWindows -match [regex]::Escape("Join-Path `$env:CLAUDE_PLUGIN_ROOT 'hooks/$scriptName'")) "$scriptName resolves the Codex plugin root in PowerShell"

        $allowPayload = [ordered]@{
            hook_event_name = 'PreToolUse'
            tool_name = 'Bash'
            tool_input = @{ command = 'git status --short' }
        } | ConvertTo-Json -Compress -Depth 6
        $allow = Invoke-HookCommand -Command ([string]$handler[0].commandWindows) -Payload $allowPayload
        Assert-Equal 0 $allow.ExitCode "$scriptName allows a harmless command"
        Assert-Equal '' $allow.Stdout "$scriptName is silent for a harmless command"
        Assert-Equal '' $allow.Stderr "$scriptName has no path or parser error"
    }

    $secretHandler = @($handlers | Where-Object { [string]$_.command -match 'protect-secrets\.ps1' })[0]
    $secretPayload = [ordered]@{
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = 'Get-Content .env' }
    } | ConvertTo-Json -Compress -Depth 6
    $secret = Invoke-HookCommand -Command ([string]$secretHandler.commandWindows) -Payload $secretPayload
    Assert-Equal 0 $secret.ExitCode 'secret guard reports a policy decision without crashing'
    Assert-Equal 'deny' (($secret.Stdout | ConvertFrom-Json).hookSpecificOutput.permissionDecision) 'secret guard denies sensitive input'

    $destructiveHandler = @($handlers | Where-Object { [string]$_.command -match 'destructive-guard\.ps1' })[0]
    $destructivePayload = [ordered]@{
        hook_event_name = 'PreToolUse'
        tool_name = 'Bash'
        tool_input = @{ command = 'git reset --hard' }
    } | ConvertTo-Json -Compress -Depth 6
    $destructive = Invoke-HookCommand -Command ([string]$destructiveHandler.commandWindows) -Payload $destructivePayload
    Assert-Equal 0 $destructive.ExitCode 'destructive guard reports a policy decision without crashing'
    Assert-Equal 'ask' (($destructive.Stdout | ConvertFrom-Json).hookSpecificOutput.permissionDecision) 'destructive guard requests confirmation'

    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    Write-Output "PASS: $script:assertionCount assertions; fixture cleaned"
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output "FAIL after $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 1
}
