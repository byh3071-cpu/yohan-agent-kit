#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$checkerPath = Join-Path $repoRoot 'scripts\Test-DesignToHtmlEnvironment.ps1'
$toolchainPath = Join-Path $repoRoot 'distribution\design-toolchain.json'
$skillManifestPath = Join-Path $repoRoot 'distribution\manifests\design-to-html.json'
$powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$fixtureRoot = Join-Path $PSScriptRoot (".work\design-environment-run-{0}" -f [Guid]::NewGuid().ToString('N'))
$script:assertionCount = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ([string]$Expected -cne [string]$Actual) {
        throw "Assertion failed: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $parent = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $parent -Force
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Checker {
    param(
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$HomeRoot,
        [ValidateSet('Human', 'Json')][string]$OutputFormat = 'Json'
    )

    $output = @(& $powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checkerPath `
        -BrainRoot $BrainRoot -HomeRoot $HomeRoot -OutputFormat $OutputFormat 2>&1)
    $exitCode = $LASTEXITCODE
    $raw = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    $data = $null
    if ($OutputFormat -eq 'Json') {
        try { $data = $raw | ConvertFrom-Json }
        catch { throw "Checker returned invalid JSON (exit=$exitCode): $raw" }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Raw = $raw }
}

function New-BrainFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$Complete
    )

    $root = Join-Path $fixtureRoot $Name
    $null = New-Item -ItemType Directory -Path $root -Force
    if ($Complete) {
        Write-Utf8NoBom -Path (Join-Path $root 'memory\rules\html-artifact-design.md') -Text "# Design rules`nTOP-SECRET-BRAIN`n"
        Write-Utf8NoBom -Path (Join-Path $root 'docs\reference\websites\ai-workspace-context-trust-navigator.md') -Text "# Reference`nVerified state`n"
    }
    return $root
}

function Add-DesignSkillJunctions {
    param([Parameter(Mandatory = $true)][string]$HomeRoot)

    $source = Join-Path $repoRoot 'skills\design-to-html'
    $targets = @(
        '.agents\skills\design-to-html',
        '.claude\skills\design-to-html',
        '.gemini\config\skills\design-to-html'
    )
    foreach ($relativeTarget in $targets) {
        $target = Join-Path $HomeRoot $relativeTarget
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        $null = New-Item -ItemType Junction -Path $target -Target $source
    }
}

function Add-PluginVersion {
    param(
        [Parameter(Mandatory = $true)][string]$HomeRoot,
        [Parameter(Mandatory = $true)][ValidateSet('product-design', 'yohan-core', 'workflow')][string]$Plugin,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $relative = switch ($Plugin) {
        'product-design' { ".codex\plugins\cache\openai-curated-remote\product-design\$Version" }
        'yohan-core' { ".codex\plugins\cache\yohan-cc-skills\yohan-core\$Version" }
        'workflow' { ".codex\plugins\cache\yohan-cc-skills\workflow\$Version" }
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $HomeRoot $relative) -Force
}

function Add-TestedPlugins {
    param([Parameter(Mandatory = $true)][string]$HomeRoot)

    Add-PluginVersion -HomeRoot $HomeRoot -Plugin product-design -Version '0.1.52'
    Add-PluginVersion -HomeRoot $HomeRoot -Plugin yohan-core -Version '0.3.22'
    Add-PluginVersion -HomeRoot $HomeRoot -Plugin workflow -Version '0.3.9'
}

function Get-TreeSignature {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not [IO.Directory]::Exists($Root)) { return '<missing>' }
    $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
    $rows = New-Object Collections.Generic.List[string]
    $pending = New-Object Collections.Generic.Queue[string]
    $pending.Enqueue($rootPath)
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force | Sort-Object Name)) {
            $relative = $item.FullName.Substring($rootPath.Length).TrimStart('\').Replace('\', '/')
            $isReparse = ([int]$item.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isReparse) {
                $target = [string]$item.Target
                $rows.Add("link|$relative|$target")
            }
            elseif ($item.PSIsContainer) {
                $rows.Add("dir|$relative")
                $pending.Enqueue($item.FullName)
            }
            else {
                $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                $rows.Add("file|$relative|$($item.Length)|$hash")
            }
        }
    }
    return [string]::Join("`n", @($rows | Sort-Object))
}

function Remove-FixtureRootSafely {
    if (-not [IO.Directory]::Exists($fixtureRoot)) { return }
    $reparsePoints = @(Get-ChildItem -LiteralPath $fixtureRoot -Force -Recurse | Where-Object {
        ([int]$_.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0
    } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($entry in $reparsePoints) {
        if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
        else { [IO.File]::Delete($entry.FullName) }
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}

try {
    Assert-True -Condition ([IO.File]::Exists($toolchainPath)) -Message 'toolchain contract exists'
    Assert-True -Condition ([IO.File]::Exists($skillManifestPath)) -Message 'design-to-html manifest exists'
    Assert-True -Condition ([IO.File]::Exists($checkerPath)) -Message 'environment checker exists'

    $toolchain = [IO.File]::ReadAllText($toolchainPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $skillManifest = [IO.File]::ReadAllText($skillManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-Equal -Expected 'design-to-html' -Actual $skillManifest.skill -Message 'skill manifest identity'
    Assert-True -Condition ([string]$skillManifest.digest -match '^[A-F0-9]{64}$') -Message 'skill manifest digest format'
    $expectedSkillDigest = [string]$skillManifest.digest
    Assert-Equal -Expected 1 -Actual $toolchain.schemaVersion -Message 'toolchain schema version'
    Assert-Equal -Expected '0.1.52' -Actual $toolchain.tested.'product-design' -Message 'tested Product Design version'
    Assert-Equal -Expected '0.3.22' -Actual $toolchain.tested.'yohan-core' -Message 'tested yohan-core version'
    Assert-Equal -Expected '0.3.9' -Actual $toolchain.tested.workflow -Message 'tested workflow version'
    Assert-Equal -Expected 'design-to-html' -Actual $toolchain.requiredSkill -Message 'required skill identity'

    $missingBrain = New-BrainFixture -Name 'missing-brain'
    $emptyHome = Join-Path $fixtureRoot 'empty-home'
    $beforeMissing = Get-TreeSignature -Root $fixtureRoot
    $missing = Invoke-Checker -BrainRoot $missingBrain -HomeRoot $emptyHome
    $afterMissing = Get-TreeSignature -Root $fixtureRoot
    Assert-Equal -Expected 2 -Actual $missing.ExitCode -Message 'missing prerequisites exit code'
    Assert-Equal -Expected 'Missing' -Actual $missing.Data.status -Message 'missing brain and skill status'
    Assert-Equal -Expected 'Installable' -Actual $missing.Data.skill.managerStatus -Message 'manager Check status is reported'
    Assert-Equal -Expected $expectedSkillDigest -Actual $missing.Data.skill.sourceDigest -Message 'canonical source digest is reported'
    Assert-True -Condition (@($missing.Data.missing).Count -ge 3) -Message 'missing evidence includes brain files and required skill'
    Assert-Equal -Expected $beforeMissing -Actual $afterMissing -Message 'missing Check leaves the entire fixture tree unchanged'
    Assert-True -Condition (-not [IO.Directory]::Exists($emptyHome)) -Message 'missing HomeRoot is not created or overblocked'

    $healthyBrain = New-BrainFixture -Name 'healthy-brain' -Complete
    $healthyHome = Join-Path $fixtureRoot 'healthy-home'
    Add-DesignSkillJunctions -HomeRoot $healthyHome
    Add-TestedPlugins -HomeRoot $healthyHome
    $beforeHealthy = Get-TreeSignature -Root $fixtureRoot
    $healthy = Invoke-Checker -BrainRoot $healthyBrain -HomeRoot $healthyHome
    $afterHealthy = Get-TreeSignature -Root $fixtureRoot
    Assert-Equal -Expected 0 -Actual $healthy.ExitCode -Message 'healthy environment exit code'
    Assert-Equal -Expected 'Healthy' -Actual $healthy.Data.status -Message 'complete environment status'
    Assert-Equal -Expected 'Healthy' -Actual $healthy.Data.skill.managerStatus -Message 'healthy manager Check status'
    Assert-Equal -Expected 3 -Actual @($healthy.Data.plugins | Where-Object { $_.state -eq 'Tested' }).Count -Message 'all exact tested plugin versions detected'
    Assert-Equal -Expected $beforeHealthy -Actual $afterHealthy -Message 'healthy Check leaves the entire fixture tree unchanged'

    Assert-True -Condition (-not $healthy.Raw.Contains($healthyBrain)) -Message 'JSON omits absolute BrainRoot'
    Assert-True -Condition (-not $healthy.Raw.Contains($healthyHome)) -Message 'JSON omits absolute HomeRoot'
    Assert-True -Condition (-not $healthy.Raw.Contains($repoRoot)) -Message 'JSON evidence omits absolute repository root'
    Assert-True -Condition (-not $healthy.Raw.Contains('TOP-SECRET-BRAIN')) -Message 'JSON omits source contents and secrets'
    Assert-True -Condition (@($healthy.Data.brainFiles | Where-Object { [string]$_.path -match '^[A-Za-z]:|^[/\\]{2}' }).Count -eq 0) -Message 'brain evidence paths remain repository-relative'

    $unsafeBrainTarget = New-BrainFixture -Name 'unsafe-brain-target' -Complete
    $unsafeBrain = Join-Path $fixtureRoot 'unsafe-brain-junction'
    $null = New-Item -ItemType Junction -Path $unsafeBrain -Target $unsafeBrainTarget
    $beforeUnsafe = Get-TreeSignature -Root $fixtureRoot
    $unsafe = Invoke-Checker -BrainRoot $unsafeBrain -HomeRoot $healthyHome
    $afterUnsafe = Get-TreeSignature -Root $fixtureRoot
    Assert-Equal -Expected 3 -Actual $unsafe.ExitCode -Message 'reparse BrainRoot fails closed'
    Assert-Equal -Expected 'Drift' -Actual $unsafe.Data.status -Message 'reparse BrainRoot drift status'
    Assert-Equal -Expected 2 -Actual @($unsafe.Data.brainFiles | Where-Object { $_.state -eq 'Unsafe' }).Count -Message 'reparse BrainRoot is not traversed for either required file'
    Assert-Equal -Expected 2 -Actual @($unsafe.Data.drift | Where-Object { $_.code -eq 'UnsafePath' }).Count -Message 'reparse BrainRoot reports path-safety evidence'
    Assert-Equal -Expected $beforeUnsafe -Actual $afterUnsafe -Message 'unsafe Check leaves the entire fixture tree unchanged'

    $realParent = Join-Path $fixtureRoot 'parent-junction-real'
    $realBrain = Join-Path $realParent 'brain'
    Write-Utf8NoBom -Path (Join-Path $realBrain 'memory\rules\html-artifact-design.md') -Text "# Outside design rules`nPARENT-JUNCTION-SENTINEL`n"
    Write-Utf8NoBom -Path (Join-Path $realBrain 'docs\reference\websites\ai-workspace-context-trust-navigator.md') -Text "# Outside reference`nPARENT-JUNCTION-SENTINEL`n"
    $linkedParent = Join-Path $fixtureRoot 'parent-junction-link'
    $null = New-Item -ItemType Junction -Path $linkedParent -Target $realParent
    $nestedBrainRoot = Join-Path $linkedParent 'brain'
    $beforeParentJunction = Get-TreeSignature -Root $fixtureRoot
    $parentJunction = Invoke-Checker -BrainRoot $nestedBrainRoot -HomeRoot $healthyHome
    $afterParentJunction = Get-TreeSignature -Root $fixtureRoot
    Assert-Equal -Expected 3 -Actual $parentJunction.ExitCode -Message 'BrainRoot below a parent junction fails closed'
    Assert-Equal -Expected 'Drift' -Actual $parentJunction.Data.status -Message 'parent junction BrainRoot drift status'
    Assert-Equal -Expected 2 -Actual @($parentJunction.Data.brainFiles | Where-Object { $_.state -eq 'Unsafe' -and $null -eq $_.digest }).Count -Message 'parent junction files stay Unsafe without digest reads'
    Assert-Equal -Expected 2 -Actual @($parentJunction.Data.drift | Where-Object { $_.code -eq 'UnsafePath' }).Count -Message 'parent junction reports path-safety evidence'
    Assert-True -Condition (-not $parentJunction.Raw.Contains('PARENT-JUNCTION-SENTINEL')) -Message 'parent junction source content is never emitted'
    Assert-Equal -Expected $beforeParentJunction -Actual $afterParentJunction -Message 'parent junction Check leaves target, link, and sentinel unchanged'

    $driftBrain = New-BrainFixture -Name 'drift-brain' -Complete
    $driftHome = Join-Path $fixtureRoot 'drift-home'
    Add-DesignSkillJunctions -HomeRoot $driftHome
    Add-PluginVersion -HomeRoot $driftHome -Plugin product-design -Version '0.1.53'
    Add-PluginVersion -HomeRoot $driftHome -Plugin yohan-core -Version '0.3.22'
    Add-PluginVersion -HomeRoot $driftHome -Plugin workflow -Version '0.3.9'
    $drift = Invoke-Checker -BrainRoot $driftBrain -HomeRoot $driftHome
    Assert-Equal -Expected 3 -Actual $drift.ExitCode -Message 'tested-version drift exit code'
    Assert-Equal -Expected 'Drift' -Actual $drift.Data.status -Message 'Product Design version mismatch is Drift'
    Assert-Equal -Expected 'Healthy' -Actual $drift.Data.skill.managerStatus -Message 'plugin drift does not become source failure'
    $productDrift = @($drift.Data.plugins | Where-Object { $_.name -eq 'product-design' })
    Assert-Equal -Expected 1 -Actual $productDrift.Count -Message 'one Product Design evidence item'
    Assert-Equal -Expected 'Drift' -Actual $productDrift[0].state -Message 'Product Design mismatch evidence state'

    $optionalBrain = New-BrainFixture -Name 'optional-brain' -Complete
    $optionalHome = Join-Path $fixtureRoot 'optional-home'
    Add-DesignSkillJunctions -HomeRoot $optionalHome
    $optional = Invoke-Checker -BrainRoot $optionalBrain -HomeRoot $optionalHome
    Assert-Equal -Expected 0 -Actual $optional.ExitCode -Message 'optional plugin absence does not fail the environment'
    Assert-Equal -Expected 'Healthy' -Actual $optional.Data.status -Message 'optional plugin absence remains Healthy'
    Assert-Equal -Expected 3 -Actual @($optional.Data.warnings | Where-Object { $_.category -eq 'capability' }).Count -Message 'optional plugin absences are capability warnings'

    $newerBrain = New-BrainFixture -Name 'newer-brain' -Complete
    $newerHome = Join-Path $fixtureRoot 'newer-home'
    Add-DesignSkillJunctions -HomeRoot $newerHome
    Add-TestedPlugins -HomeRoot $newerHome
    Add-PluginVersion -HomeRoot $newerHome -Plugin product-design -Version '0.1.53'
    $newer = Invoke-Checker -BrainRoot $newerBrain -HomeRoot $newerHome
    Assert-Equal -Expected 'Healthy' -Actual $newer.Data.status -Message 'tested version plus newer version remains Healthy'
    $newerProduct = @($newer.Data.plugins | Where-Object { $_.name -eq 'product-design' })[0]
    Assert-Equal -Expected 'TestedWithNewerAvailable' -Actual $newerProduct.state -Message 'extra newer version treatment is explicit'
    Assert-True -Condition (@($newer.Data.warnings | Where-Object { $_.code -eq 'NewerVersionAvailable' }).Count -eq 1) -Message 'extra newer version emits one warning'

    $humanOne = Invoke-Checker -BrainRoot $healthyBrain -HomeRoot $healthyHome -OutputFormat Human
    $humanTwo = Invoke-Checker -BrainRoot $healthyBrain -HomeRoot $healthyHome -OutputFormat Human
    Assert-Equal -Expected 0 -Actual $humanOne.ExitCode -Message 'human output healthy exit code'
    Assert-Equal -Expected $humanOne.Raw -Actual $humanTwo.Raw -Message 'human stdout is deterministic'
    Assert-True -Condition ($humanOne.Raw -match '^Mode: Check\r?\nStatus: Healthy') -Message 'human output starts with stable summary'
    Assert-True -Condition (-not $humanOne.Raw.Contains($healthyBrain)) -Message 'human output omits absolute BrainRoot'
    Assert-True -Condition (-not $humanOne.Raw.Contains($healthyHome)) -Message 'human output omits absolute HomeRoot'

    Write-Output "Test-DesignToHtmlEnvironment assertions passed: $script:assertionCount"
}
finally {
    Remove-FixtureRootSafely
}
