#requires -Version 5.1
# Names an unnamed startup session from its first normal user prompt.
# https://code.claude.com/docs/en/hooks#userpromptsubmit

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom

function Read-HookInput {
    try {
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $raw = $raw.TrimStart([char]0xFEFF)
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-StatePath {
    param([Parameter(Mandatory = $true)][string]$SessionId)

    $profileRoot = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($profileRoot)) {
        $profileRoot = [Environment]::GetFolderPath('UserProfile')
    }
    if ([string]::IsNullOrWhiteSpace($profileRoot)) { return $null }

    $cacheRoot = [IO.Path]::Combine($profileRoot, '.claude', '.cache', 'auto-session-title')
    $null = [IO.Directory]::CreateDirectory($cacheRoot)
    $safeSessionId = [regex]::Replace($SessionId, '[^A-Za-z0-9._-]', '_')
    if ($safeSessionId.Length -gt 120) { $safeSessionId = $safeSessionId.Substring(0, 120) }
    return [IO.Path]::Combine($cacheRoot, "$safeSessionId.state")
}

function Set-SessionState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('eligible', 'protected', 'done')][string]$State
    )

    [IO.File]::WriteAllText($Path, $State, $utf8NoBom)
}

function Get-SessionState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not [IO.File]::Exists($Path)) { return '' }
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Trim()
}

function Get-PromptTopic {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $line = ($Prompt -replace '\r\n', "`n" -replace '\r', "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return '' }
    $line = ($line -split "`n", 2)[0].Trim()
    $line = $line -replace '^(?:\uADF8|\uC77C\uB2E8|\uC774\uC81C|\uC7A0\uAE50|\uC7A0\uB9CC)\s+', ''
    $line = $line -replace '\s+', ' '
    if ($line.Length -gt 42) {
        $line = $line.Substring(0, 42).Trim() + [char]0x2026
    }
    return $line
}

try {
    $event = Read-HookInput
    if ($null -eq $event) { exit 0 }
    if ($event.PSObject.Properties['agent_id'] -and -not [string]::IsNullOrWhiteSpace([string]$event.agent_id)) { exit 0 }

    $sessionId = [string]$event.session_id
    if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }
    $statePath = Get-StatePath -SessionId $sessionId
    if ([string]::IsNullOrWhiteSpace($statePath)) { exit 0 }

    $eventName = [string]$event.hook_event_name
    if ($eventName -eq 'SessionStart') {
        $source = [string]$event.source
        if ($source -eq 'compact') { exit 0 }
        $existingTitle = if ($event.PSObject.Properties['session_title']) { [string]$event.session_title } else { '' }
        $state = if ($source -eq 'startup' -and [string]::IsNullOrWhiteSpace($existingTitle)) { 'eligible' } else { 'protected' }
        Set-SessionState -Path $statePath -State $state
        exit 0
    }

    if ($eventName -eq 'UserPromptExpansion') {
        $commandName = if ($event.PSObject.Properties['command_name']) { [string]$event.command_name } else { '' }
        $expandedPrompt = if ($event.PSObject.Properties['prompt']) { [string]$event.prompt } else { '' }
        if ($commandName -eq 'rename' -or $expandedPrompt.Trim() -match '^/rename(?:\s|$)') {
            Set-SessionState -Path $statePath -State 'protected'
        }
        exit 0
    }

    if ($eventName -ne 'UserPromptSubmit') { exit 0 }
    if ((Get-SessionState -Path $statePath) -ne 'eligible') { exit 0 }

    $prompt = if ($event.PSObject.Properties['prompt']) { [string]$event.prompt } else { '' }
    if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }
    if ($prompt.Trim() -match '^/rename(?:\s|$)') {
        Set-SessionState -Path $statePath -State 'protected'
        exit 0
    }
    if ($prompt.Trim() -match '^/') { exit 0 }

    $cwd = if ($event.PSObject.Properties['cwd']) { [string]$event.cwd } else { '' }
    $trimmedCwd = $cwd.TrimEnd([char[]]@('\', '/'))
    $project = if ([string]::IsNullOrWhiteSpace($trimmedCwd)) { 'workspace' } else { [IO.Path]::GetFileName($trimmedCwd) }
    if ([string]::IsNullOrWhiteSpace($project)) { $project = 'workspace' }

    $topic = Get-PromptTopic -Prompt $prompt
    if ([string]::IsNullOrWhiteSpace($topic)) { $topic = $project }
    $separator = ' ' + [char]0x00B7 + ' '
    $title = (Get-Date -Format 'yyyy-MM-dd') + $separator + $project + $separator + $topic
    if ($title.Length -gt 200) { $title = $title.Substring(0, 200).Trim() }

    Set-SessionState -Path $statePath -State 'done'
    $payload = @{
        hookSpecificOutput = @{
            hookEventName = 'UserPromptSubmit'
            sessionTitle = $title
        }
    }
    $json = $payload | ConvertTo-Json -Compress -Depth 6
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
}
catch {
    exit 0
}

exit 0
