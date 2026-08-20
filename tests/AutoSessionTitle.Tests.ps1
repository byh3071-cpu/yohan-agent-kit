#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hookPath = Join-Path $repoRoot 'plugins\yohan-core\hooks\auto-session-title.ps1'
$fixtureRoot = Join-Path $PSScriptRoot ".work\auto-session-title-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$fixtureUser = Join-Path $fixtureRoot 'user'
$projectPath = Join-Path $fixtureRoot '새 프로젝트'
$null = New-Item -ItemType Directory -Path $fixtureUser,$projectPath -Force
$script:assertionCount = 0

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ([string]$Expected -cne [string]$Actual) {
        throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-TitleHook {
    param([Parameter(Mandatory = $true)][string]$Payload)

    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
        throw "Production hook is missing: $hookPath"
    }

    $callId = [guid]::NewGuid().ToString('N')
    $stdinPath = Join-Path $fixtureRoot "stdin-$callId.json"
    $stdoutPath = Join-Path $fixtureRoot "stdout-$callId.json"
    $stderrPath = Join-Path $fixtureRoot "stderr-$callId.txt"
    [IO.File]::WriteAllText($stdinPath, $Payload, $utf8NoBom)

    $command = 'set "USERPROFILE=' + $fixtureUser + '" && ' +
        '"' + (Get-Command powershell.exe -ErrorAction Stop).Source + '" ' +
        '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $hookPath + '" ' +
        '< "' + $stdinPath + '" > "' + $stdoutPath + '" 2> "' + $stderrPath + '"'

    try {
        $null = & cmd.exe /d /s /c $command
        $exitCode = $LASTEXITCODE
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::UTF8) } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8) } else { '' }
    }
    finally {
        foreach ($path in @($stdinPath, $stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

function New-Payload {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [hashtable]$Fields = @{}
    )

    $payload = [ordered]@{
        session_id = $SessionId
        cwd = $projectPath
        hook_event_name = $Event
    }
    foreach ($entry in $Fields.GetEnumerator()) { $payload[$entry.Key] = $entry.Value }
    return ($payload | ConvertTo-Json -Compress -Depth 8)
}

function Assert-SilentSuccess {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-Equal -Expected 0 -Actual $Result.ExitCode -Message "$Message exits successfully"
    Assert-Equal -Expected '' -Actual $Result.Stdout -Message "$Message has no stdout"
    Assert-Equal -Expected '' -Actual $Result.Stderr -Message "$Message has no stderr"
}

try {
    $startup = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'new-session' -Fields @{ source = 'startup' })
    Assert-SilentSuccess -Result $startup -Message 'Unnamed startup'

    $firstPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'new-session' -Fields @{ prompt = "일단 결제 오류 원인 조사해줘`n둘째 줄" })
    Assert-Equal -Expected 0 -Actual $firstPrompt.ExitCode -Message 'First prompt exits successfully'
    Assert-Equal -Expected '' -Actual $firstPrompt.Stderr -Message 'First prompt has no stderr'
    $firstOutput = $firstPrompt.Stdout | ConvertFrom-Json
    Assert-Equal -Expected 'UserPromptSubmit' -Actual $firstOutput.hookSpecificOutput.hookEventName -Message 'Output identifies the hook event'
    Assert-Equal -Expected "$(Get-Date -Format 'yyyy-MM-dd') · 새 프로젝트 · 결제 오류 원인 조사해줘" -Actual $firstOutput.hookSpecificOutput.sessionTitle -Message 'First prompt creates the expected title'

    $repeatPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'new-session' -Fields @{ prompt = '두 번째 요청' })
    Assert-SilentSuccess -Result $repeatPrompt -Message 'Repeated prompt'

    $namedStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'named-session' -Fields @{ source = 'startup'; session_title = '직접 붙인 이름' })
    Assert-SilentSuccess -Result $namedStart -Message 'Named startup'
    $namedPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'named-session' -Fields @{ prompt = '덮어쓰면 안 됨' })
    Assert-SilentSuccess -Result $namedPrompt -Message 'Prompt after named startup'

    $resumeStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'resume-session' -Fields @{ source = 'resume' })
    Assert-SilentSuccess -Result $resumeStart -Message 'Resume startup'
    $resumePrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'resume-session' -Fields @{ prompt = '재개 제목 보존' })
    Assert-SilentSuccess -Result $resumePrompt -Message 'Prompt after resume'

    $renameStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'rename-session' -Fields @{ source = 'startup' })
    Assert-SilentSuccess -Result $renameStart -Message 'Rename scenario startup'
    $renameCommand = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptExpansion' -SessionId 'rename-session' -Fields @{ command_name = 'rename'; prompt = '/rename 직접 이름' })
    Assert-SilentSuccess -Result $renameCommand -Message 'Explicit rename command'
    $afterRename = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'rename-session' -Fields @{ prompt = '수동 이름 유지' })
    Assert-SilentSuccess -Result $afterRename -Message 'Prompt after explicit rename'

    $agentStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'agent-session' -Fields @{ source = 'startup' })
    Assert-SilentSuccess -Result $agentStart -Message 'Agent scenario startup'
    $agentPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'agent-session' -Fields @{ prompt = '서브에이전트 요청'; agent_id = 'agent-1' })
    Assert-SilentSuccess -Result $agentPrompt -Message 'Subagent prompt'
    $mainPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'agent-session' -Fields @{ prompt = '메인 요청' })
    Assert-Equal -Expected 0 -Actual $mainPrompt.ExitCode -Message 'Main prompt after subagent exits successfully'
    $mainOutput = $mainPrompt.Stdout | ConvertFrom-Json
    Assert-Equal -Expected "$(Get-Date -Format 'yyyy-MM-dd') · 새 프로젝트 · 메인 요청" -Actual $mainOutput.hookSpecificOutput.sessionTitle -Message 'Subagent does not consume the title opportunity'

    $slashStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'slash-session' -Fields @{ source = 'startup' })
    Assert-SilentSuccess -Result $slashStart -Message 'Slash scenario startup'
    $slashPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'slash-session' -Fields @{ prompt = '/help' })
    Assert-SilentSuccess -Result $slashPrompt -Message 'Slash prompt'
    $afterSlash = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'slash-session' -Fields @{ prompt = '실제 첫 요청' })
    $slashOutput = $afterSlash.Stdout | ConvertFrom-Json
    Assert-Equal -Expected "$(Get-Date -Format 'yyyy-MM-dd') · 새 프로젝트 · 실제 첫 요청" -Actual $slashOutput.hookSpecificOutput.sessionTitle -Message 'Slash prompt does not consume the title opportunity'

    $malformed = Invoke-TitleHook -Payload '{broken'
    Assert-SilentSuccess -Result $malformed -Message 'Malformed input'

    $longStart = Invoke-TitleHook -Payload (New-Payload -Event 'SessionStart' -SessionId 'long-session' -Fields @{ source = 'startup' })
    Assert-SilentSuccess -Result $longStart -Message 'Long prompt scenario startup'
    $longPrompt = Invoke-TitleHook -Payload (New-Payload -Event 'UserPromptSubmit' -SessionId 'long-session' -Fields @{ prompt = ('가' * 80) })
    $longOutput = $longPrompt.Stdout | ConvertFrom-Json
    Assert-True -Condition ($longOutput.hookSpecificOutput.sessionTitle.Length -le 200) -Message 'Title stays within the Claude Code limit'
    Assert-True -Condition $longOutput.hookSpecificOutput.sessionTitle.EndsWith([string][char]0x2026) -Message 'Long topics end with an ellipsis'

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
