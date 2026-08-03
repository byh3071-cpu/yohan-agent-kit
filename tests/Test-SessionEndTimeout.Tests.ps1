#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$checkerPath = Join-Path $repoRoot 'scripts\Test-SessionEndTimeout.ps1'
$fixtureRoot = Join-Path $PSScriptRoot ".work\session-end-timeout-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$PID"
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
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

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ($Text -notmatch $Pattern) { throw "Assertion failed: $Message" }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ($Text -match $Pattern) { throw "Assertion failed: $Message" }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Text
    )

    [IO.File]::WriteAllText($LiteralPath, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Checker {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $baseArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $checkerPath
    )
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& powershell @baseArguments @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    }
}

try {
    $normalPath = Join-Path $fixtureRoot 'normal[1].json'
    Write-Utf8NoBom -LiteralPath $normalPath -Text '{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"safe-command","timeout":3},{"type":"command","timeout":1}]}]}}'
    $normal = Invoke-Checker -Arguments @('-Path', $normalPath)
    Assert-Equal -Expected 0 -Actual $normal.ExitCode -Message 'Timeouts at or below three seconds must pass'
    Assert-Match -Text $normal.Output -Pattern '2 compliant SessionEnd hook' -Message 'Normal result reports the checked hook count'

    $recursiveRoot = Join-Path $fixtureRoot 'recursive'
    $nestedRoot = Join-Path $recursiveRoot 'nested'
    $null = New-Item -ItemType Directory -Path $nestedRoot -Force
    Write-Utf8NoBom -LiteralPath (Join-Path $nestedRoot 'hooks.json') -Text '{"hooks":{"SessionEnd":[{"hooks":[{"timeout":2}]}]}}'
    Write-Utf8NoBom -LiteralPath (Join-Path $recursiveRoot 'not-hooks.json') -Text '{"hooks":{"SessionEnd":[{"hooks":[{"timeout":99}]}]}}'
    $recursive = Invoke-Checker -Arguments @('-RecursePath', $recursiveRoot)
    Assert-Equal -Expected 0 -Actual $recursive.ExitCode -Message 'Recursive search must inspect only hooks.json files'
    Assert-Match -Text $recursive.Output -Pattern '1 compliant SessionEnd hook' -Message 'Recursive search finds a nested hooks.json file'

    $junctionTarget = Join-Path $fixtureRoot 'junction-target'
    $junctionNested = Join-Path $junctionTarget 'nested'
    $junctionPath = Join-Path $fixtureRoot 'junction-root'
    $null = New-Item -ItemType Directory -Path $junctionNested -Force
    Write-Utf8NoBom -LiteralPath (Join-Path $junctionNested 'hooks.json') -Text '{"hooks":{"SessionEnd":[]}}'
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -Force
    $junctionChild = Join-Path $junctionPath 'nested'
    $junction = Invoke-Checker -Arguments @('-RecursePath', $junctionChild)
    Assert-Equal -Expected 1 -Actual $junction.ExitCode -Message 'A normal child below a reparse ancestor must be rejected'
    Assert-Match -Text $junction.Output -Pattern 'not a safe regular directory' -Message 'Reparse ancestor rejection is explicit'
    (Get-Item -LiteralPath $junctionPath -Force).Delete()

    $secretMarker = 'SECRET_VALUE_MUST_NOT_LEAK_7f1a'
    $exceededPath = Join-Path $fixtureRoot 'exceeded.json'
    Write-Utf8NoBom -LiteralPath $exceededPath -Text ("{`"hooks`":{`"SessionEnd`":[{`"hooks`":[{`"command`":`"$secretMarker`",`"timeout`":4}]}]}}")
    $exceeded = Invoke-Checker -Arguments @('-Path', $exceededPath)
    Assert-Equal -Expected 1 -Actual $exceeded.ExitCode -Message 'A timeout over three seconds must fail'
    Assert-Match -Text $exceeded.Output -Pattern 'timeout violation' -Message 'Timeout failure is explicit'
    Assert-NotMatch -Text $exceeded.Output -Pattern $secretMarker -Message 'Timeout failure cannot print hook commands'

    $invalidPath = Join-Path $fixtureRoot 'invalid.json'
    Write-Utf8NoBom -LiteralPath $invalidPath -Text ("{`"secret`":`"$secretMarker`",BROKEN")
    $invalid = Invoke-Checker -Arguments @('-Path', $invalidPath)
    Assert-Equal -Expected 1 -Actual $invalid.ExitCode -Message 'Invalid JSON must fail'
    Assert-Match -Text $invalid.Output -Pattern 'contains invalid JSON' -Message 'JSON parse failure is explicit'
    Assert-NotMatch -Text $invalid.Output -Pattern $secretMarker -Message 'JSON parse failure cannot print source contents'

    $missingPath = Join-Path $fixtureRoot 'missing-session-end.json'
    Write-Utf8NoBom -LiteralPath $missingPath -Text '{"hooks":{"SessionStart":[]}}'
    $missing = Invoke-Checker -Arguments @('-Path', $missingPath)
    Assert-Equal -Expected 0 -Actual $missing.ExitCode -Message 'A document without SessionEnd hooks has no timeout violation'
    Assert-Match -Text $missing.Output -Pattern 'has no SessionEnd hooks' -Message 'Missing SessionEnd is reported clearly'

    foreach ($malformedJson in @(
        '{"hooks":{"SessionEnd":[null]}}',
        '{"hooks":{"SessionEnd":[{}]}}',
        '{"hooks":{"SessionEnd":[{"hooks":null}]}}',
        '{"hooks":{"SessionEnd":[{"hooks":[{"timeout":[3]}]}]}}',
        '{"hooks":{"SessionEnd":"not-an-array"}}',
        '{"hooks":"not-an-object"}',
        '[]'
    )) {
        $malformedPath = Join-Path $fixtureRoot "malformed-$script:assertionCount.json"
        Write-Utf8NoBom -LiteralPath $malformedPath -Text $malformedJson
        $malformed = Invoke-Checker -Arguments @('-Path', $malformedPath)
        Assert-Equal -Expected 1 -Actual $malformed.ExitCode -Message 'Malformed SessionEnd structure must fail closed'
    }

    $syncScriptText = [IO.File]::ReadAllText((Join-Path $repoRoot 'plugins\yohan-core\hooks\sync-marketplace.ps1'))
    $routingScriptText = [IO.File]::ReadAllText((Join-Path $repoRoot 'plugins\yohan-core\hooks\detect-routing-miss.ps1'))
    Assert-NotMatch -Text $syncScriptText -Pattern '(?im)\bgit\s+fetch\b|Start-Process|Start-Job' -Message 'SessionEnd marketplace check must not use network or background jobs'
    Assert-NotMatch -Text $routingScriptText -Pattern '(?im)Start-Process|Start-Job' -Message 'Routing analysis must not start background jobs'
    Assert-Equal -Expected 2 -Actual ([regex]::Matches($routingScriptText, '(?im)&\s+git\s+-c\s+core\.fsmonitor=false\s+-C').Count) -Message 'Every routing Git worktree query must disable fsmonitor hooks and daemons'
    Assert-NotMatch -Text $routingScriptText -Pattern '(?m)(?-i:&\s+git\s+-C)' -Message 'Routing analysis cannot inherit repository fsmonitor configuration'
    Assert-Match -Text $routingScriptText -Pattern '(?im)Get-Content[^\r\n]+-Tail\s+2000' -Message 'Routing analysis must bound transcript reads'

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
