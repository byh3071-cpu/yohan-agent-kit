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

function Add-Target {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    try {
        $entry = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
        if (-not $entry.PSIsContainer -and (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) {
            $targets.Add($entry.FullName)
            return
        }
    }
    catch { }

    $inputErrors.Add('An explicit path is not a readable regular file.')
}

function Add-TargetsRecursively {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    try {
        $root = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
        if (-not $root.PSIsContainer -or (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
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

function Get-PropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
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

    $hooks = Get-PropertyValue -InputObject $document -Name 'hooks'
    $sessionEnd = Get-PropertyValue -InputObject $hooks -Name 'SessionEnd'
    if ($null -eq $sessionEnd) {
        Write-Output "PASS: target[$targetNumber] has no SessionEnd hooks."
        continue
    }

    $hookCount = 0
    $violationCount = 0
    foreach ($group in @($sessionEnd)) {
        foreach ($hook in @(Get-PropertyValue -InputObject $group -Name 'hooks')) {
            if ($null -eq $hook) { continue }
            $hookCount++
            $timeout = Get-PropertyValue -InputObject $hook -Name 'timeout'
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
