#requires -Version 5.1

[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArguments)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$testHome = $env:YOHAN_TEST_AGY_HOME
if ([string]::IsNullOrWhiteSpace($testHome)) { throw 'YOHAN_TEST_AGY_HOME is required' }
$pluginRoot = Join-Path $testHome '.gemini\config\plugins'
$registryPath = Join-Path $testHome '.fake-agy-registry.json'

function Read-Registry {
    if (-not [IO.File]::Exists($registryPath)) { return @() }
    $parsed = ([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8) | ConvertFrom-Json)
    return @($parsed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Write-Registry {
    param([string[]]$Names)
    $parent = Split-Path -Parent $registryPath
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $json = ConvertTo-Json -InputObject @($Names | Sort-Object -Unique) -Compress
    [IO.File]::WriteAllText($registryPath, $json, (New-Object Text.UTF8Encoding($false)))
}

function Copy-Directory {
    param([string]$Source, [string]$Destination)
    if ([IO.Directory]::Exists($Destination)) { throw "Plugin destination exists: $Destination" }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    foreach ($directory in @(Get-ChildItem -LiteralPath $Source -Directory -Recurse -Force | Sort-Object FullName)) {
        $relative = $directory.FullName.Substring($Source.Length).TrimStart('\')
        $null = New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        $parent = Split-Path -Parent $target
        if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        [IO.File]::Copy($file.FullName, $target, $false)
    }
}

if ($CommandArguments.Count -lt 2 -or $CommandArguments[0] -cne 'plugin') { throw 'Expected plugin command' }
$operation = $CommandArguments[1]
switch ($operation) {
    'list' {
        $imports = @(Read-Registry | ForEach-Object { [pscustomobject][ordered]@{ name = [string]$_ } })
        if ($imports.Count -eq 0) { Write-Output 'No imported plugins.' }
        else { Write-Output (ConvertTo-Json -InputObject ([pscustomobject][ordered]@{ imports = $imports }) -Depth 8 -Compress) }
    }
    'validate' {
        if ($CommandArguments.Count -ne 3 -or -not [IO.File]::Exists((Join-Path $CommandArguments[2] 'plugin.json'))) { throw 'Invalid plugin source' }
        Write-Output 'Plugin is valid.'
    }
    'install' {
        if ($CommandArguments.Count -ne 3) { throw 'Install requires a source' }
        $source = [IO.Path]::GetFullPath($CommandArguments[2]).TrimEnd('\')
        $manifest = [string]([IO.File]::ReadAllText((Join-Path $source 'plugin.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
        $name = [string]$manifest.name
        $destination = Join-Path $pluginRoot $name
        Copy-Directory -Source $source -Destination $destination
        Write-Registry -Names @(@(Read-Registry) + $name)
        Write-Output "Installed $name"
    }
    'uninstall' {
        if ($CommandArguments.Count -ne 3) { throw 'Uninstall requires a name' }
        $name = [string]$CommandArguments[2]
        $destination = Join-Path $pluginRoot $name
        if ([IO.Directory]::Exists($destination)) { [IO.Directory]::Delete($destination, $true) }
        Write-Registry -Names @(Read-Registry | Where-Object { [string]$_ -cne $name })
        Write-Output "Uninstalled $name"
    }
    default { throw "Unsupported fake agy operation: $operation" }
}
