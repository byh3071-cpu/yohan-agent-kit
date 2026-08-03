#requires -Version 5.1

[CmdletBinding()]
param(
    [string[]]$Path,
    [string[]]$RecursePath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$maximumTimeoutSeconds = 3.0
$targets = New-Object 'System.Collections.Generic.List[string]'
$inputErrors = New-Object 'System.Collections.Generic.List[string]'

function Test-HasReparseAncestor {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Entry)

    $current = $Entry
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        $current = if ($current -is [System.IO.FileInfo]) { $current.Directory } else { $current.Parent }
    }
    return $false
}

function Add-Target {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    try {
        $entry = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
        if (-not $entry.PSIsContainer -and -not (Test-HasReparseAncestor -Entry $entry)) {
            $targets.Add($entry.FullName)
            return
        }
    }
    catch {
        # 입력별 세부 경로나 예외 메시지를 노출하지 않고 아래의 일반 오류로 통일한다.
    }

    $inputErrors.Add('An explicit path is not a readable regular file.')
}

function Add-TargetsRecursively {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    try {
        $root = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
        if (-not $root.PSIsContainer -or (Test-HasReparseAncestor -Entry $root)) {
            $inputErrors.Add('A recursive path is not a safe regular directory.')
            return
        }

        $pending = New-Object 'System.Collections.Generic.Queue[string]'
        $pending.Enqueue($root.FullName)
        while ($pending.Count -gt 0) {
            $directory = $pending.Dequeue()
            foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
                $isReparsePoint = (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
                if ($entry.PSIsContainer) {
                    if (-not $isReparsePoint) { $pending.Enqueue($entry.FullName) }
                    continue
                }
                if (-not $isReparsePoint -and $entry.Name -ieq 'hooks.json') {
                    $targets.Add($entry.FullName)
                }
            }
        }
    }
    catch {
        $inputErrors.Add('A recursive path could not be inspected safely.')
    }
}

function Test-JsonObject {
    param([AllowNull()]$Value)

    return ($null -ne $Value -and $Value.GetType() -eq [System.Management.Automation.PSCustomObject])
}

function Test-NumericTimeout {
    param([AllowNull()]$Value)

    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $typeCode = [Type]::GetTypeCode($Value.GetType())
    return $typeCode -in @(
        [TypeCode]::Byte,
        [TypeCode]::SByte,
        [TypeCode]::Int16,
        [TypeCode]::UInt16,
        [TypeCode]::Int32,
        [TypeCode]::UInt32,
        [TypeCode]::Int64,
        [TypeCode]::UInt64,
        [TypeCode]::Single,
        [TypeCode]::Double,
        [TypeCode]::Decimal
    )
}

if (-not $PSBoundParameters.ContainsKey('Path') -and -not $PSBoundParameters.ContainsKey('RecursePath')) {
    $Path = @(Join-Path $PSScriptRoot '..\plugins\yohan-core\hooks\hooks.json')
}

if ($null -ne $Path) {
    foreach ($candidate in $Path) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $inputErrors.Add('An explicit path is empty.')
        }
        else {
            Add-Target -LiteralPath $candidate
        }
    }
}

if ($null -ne $RecursePath) {
    foreach ($candidate in $RecursePath) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $inputErrors.Add('A recursive path is empty.')
        }
        else {
            Add-TargetsRecursively -LiteralPath $candidate
        }
    }
}

foreach ($message in $inputErrors) { [Console]::Error.WriteLine("ERROR: $message") }
if ($inputErrors.Count -gt 0) { exit 1 }

$uniqueTargets = @($targets | Sort-Object -Unique)
if ($uniqueTargets.Count -eq 0) {
    [Console]::Error.WriteLine('ERROR: No hooks.json targets were found.')
    exit 1
}

$hasFailure = $false
$targetNumber = 0
foreach ($target in $uniqueTargets) {
    $targetNumber++
    try {
        $jsonText = [IO.File]::ReadAllText($target)
        $document = $jsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        [Console]::Error.WriteLine("ERROR: target[$targetNumber] contains invalid JSON.")
        $hasFailure = $true
        continue
    }

    if (-not (Test-JsonObject -Value $document)) {
        [Console]::Error.WriteLine("ERROR: target[$targetNumber] has an invalid document structure.")
        $hasFailure = $true
        continue
    }

    $hooksProperty = $document.PSObject.Properties['hooks']
    $hooks = $null
    if ($null -ne $hooksProperty) { $hooks = $hooksProperty.Value }
    $sessionEndProperty = if (Test-JsonObject -Value $hooks) { $hooks.PSObject.Properties['SessionEnd'] } else { $null }
    if ($null -eq $sessionEndProperty) {
        if ($null -ne $hooksProperty -and -not (Test-JsonObject -Value $hooks)) {
            [Console]::Error.WriteLine("ERROR: target[$targetNumber] has an invalid hooks structure.")
            $hasFailure = $true
            continue
        }
        Write-Output "PASS: target[$targetNumber] has no SessionEnd hooks."
        continue
    }

    $sessionEnd = $sessionEndProperty.Value

    if (-not (Test-JsonObject -Value $hooks) -or $sessionEnd -isnot [object[]]) {
        [Console]::Error.WriteLine("ERROR: target[$targetNumber] has an invalid SessionEnd structure.")
        $hasFailure = $true
        continue
    }

    $hookCount = 0
    $violationCount = 0
    foreach ($group in @($sessionEnd)) {
        if (-not (Test-JsonObject -Value $group)) {
            $violationCount++
            continue
        }
        $groupHooksProperty = $group.PSObject.Properties['hooks']
        if ($null -eq $groupHooksProperty) {
            $violationCount++
            continue
        }
        $groupHooks = $groupHooksProperty.Value
        if ($groupHooks -isnot [object[]]) {
            $violationCount++
            continue
        }
        foreach ($hook in @($groupHooks)) {
            if (-not (Test-JsonObject -Value $hook)) {
                $violationCount++
                continue
            }
            $hookCount++
            $timeoutProperty = $hook.PSObject.Properties['timeout']
            if ($null -eq $timeoutProperty) {
                $violationCount++
                continue
            }
            # PSPropertyInfo.Value를 함수에서 반환하면 PS 5.1이 1원소 배열을 스칼라로 풀 수 있으므로 직접 대입한다.
            $timeout = $timeoutProperty.Value
            if (-not (Test-NumericTimeout -Value $timeout)) {
                $violationCount++
                continue
            }
            $numericTimeout = [double]$timeout
            if ([double]::IsNaN($numericTimeout) -or [double]::IsInfinity($numericTimeout) -or $numericTimeout -le 0 -or $numericTimeout -gt $maximumTimeoutSeconds) {
                $violationCount++
            }
        }
    }

    if ($violationCount -gt 0) {
        [Console]::Error.WriteLine("ERROR: target[$targetNumber] has $violationCount SessionEnd timeout violation(s); every timeout must be greater than 0 and at most 3 seconds.")
        $hasFailure = $true
    }
    else {
        Write-Output "PASS: target[$targetNumber] has $hookCount compliant SessionEnd hook(s)."
    }
}

if ($hasFailure) { exit 1 }
exit 0
