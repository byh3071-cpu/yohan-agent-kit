#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scanner = Join-Path $repoRoot 'scripts\Scan-AgentAssets.ps1'
$workRoot = Join-Path $PSScriptRoot '.work'
$fixtureRoot = Join-Path $workRoot ("asset-scan-{0}-{1}" -f (Get-Date -Format 'yyyyMMddHHmmssfff'), $PID)
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
$externalTarget = $null
$script:assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-SkillFixture {
    param([string]$RelativePath)
    $path = Join-Path $fixtureRoot $RelativePath
    $null = New-Item -ItemType Directory -Path $path -Force
    [IO.File]::WriteAllText((Join-Path $path 'SKILL.md'), "---`nname: fixture`ndescription: fixture`n---`n", (New-Object Text.UTF8Encoding($false)))
    return $path
}

try {
    $null = New-SkillFixture '.claude\skills\html-doc'
    $null = New-SkillFixture '.cursor\skills\planning-diagrams'
    $target = New-SkillFixture '.agents\skills\competitive-brief'
    $link = Join-Path $fixtureRoot '.cursor\skills\competitive-brief'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $link) -Force
    $null = New-Item -ItemType Junction -Path $link -Target $target
    Remove-Item -LiteralPath $target -Recurse -Force

    $externalTargetName = "external-brief-target-$PID"
    $externalTarget = New-SkillFixture "..\$externalTargetName"
    $externalLink = Join-Path $fixtureRoot '.codex\skills\external-brief'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $externalLink) -Force
    $null = New-Item -ItemType Junction -Path $externalLink -Target $externalTarget
    Remove-Item -LiteralPath $externalTarget -Recurse -Force

    $raw = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scanner -HomeRoot $fixtureRoot -OutputFormat Json
    Assert-True ($LASTEXITCODE -eq 0) 'scanner exits successfully'
    $data = [string]::Join([Environment]::NewLine, @($raw)) | ConvertFrom-Json
    Assert-True ([bool]$data.readOnly) 'scanner declares read-only behavior'
    Assert-True (@($data.scannedRoots).Count -ge 19) 'all vendor roots are represented'
    Assert-True (-not (([string]::Join(' ', @($raw))) -match [regex]::Escape($fixtureRoot))) 'absolute HomeRoot is not emitted'

    $html = @($data.observations | Where-Object { $_.name -eq 'html-doc' })
    Assert-True ($html.Count -eq 1) 'html-doc is discovered once'
    Assert-True ($html[0].portability -eq 'UNKNOWN') 'html-doc remains UNKNOWN'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$html[0].contentDigest)) 'physical skill has a digest'

    $planning = @($data.observations | Where-Object { $_.name -eq 'planning-diagrams' })
    Assert-True ($planning.Count -eq 1) 'planning-diagrams is discovered once'
    Assert-True ($planning[0].portability -eq 'UNKNOWN') 'planning-diagrams remains UNKNOWN'

    $broken = @($data.observations | Where-Object { $_.name -eq 'competitive-brief' })
    Assert-True ($broken.Count -eq 1) 'broken junction is discovered once'
    Assert-True ($broken[0].portability -eq 'LEGACY') 'broken junction is LEGACY'
    Assert-True (-not [bool]$broken[0].targetExists) 'broken target is reported missing'

    $externalBroken = @($data.observations | Where-Object { $_.name -eq 'external-brief' })
    Assert-True ($externalBroken.Count -eq 1) 'external broken junction is discovered once'
    Assert-True ($externalBroken[0].portability -eq 'LEGACY') 'external broken junction is LEGACY'
    Assert-True (-not [bool]$externalBroken[0].targetExists) 'external broken target is reported missing'
    Assert-True ([string]$externalBroken[0].target -eq "external://$externalTargetName") 'external target remains redacted'

    Write-Output "PASS: $script:assertions assertions"
}
finally {
    $resolvedWork = (Resolve-Path -LiteralPath $workRoot).Path
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove unexpected test fixture' }
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    if ($externalTarget -and (Test-Path -LiteralPath $externalTarget)) {
        $resolvedExternal = [IO.Path]::GetFullPath($externalTarget)
        if (-not $resolvedExternal.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove unexpected external fixture' }
        Remove-Item -LiteralPath $resolvedExternal -Recurse -Force
    }
}
