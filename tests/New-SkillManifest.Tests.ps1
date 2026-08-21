#requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generatorPath = Join-Path $repoRoot 'scripts\New-SkillManifest.ps1'
$powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("yohan-skill-manifest-tests-{0}" -f [Guid]::NewGuid().ToString('N'))
$xdgConfigRoot = Join-Path $fixtureRoot '.xdg'
$script:assertionCount = 0
$script:failures = @()

function Get-TestSha256File {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-True -Condition ([regex]::IsMatch($Actual, $Pattern)) -Message "$Message`nActual: $Actual"
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ($Expected -cne $Actual) {
        throw "$Message`nExpected: $Expected`nActual: $Actual"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git.exe -C $WorkingDirectory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "git $([string]::Join(' ', $Arguments)) failed: $([string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ })))"
    }
    return $output
}

function New-TestRepository {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Join-Path $fixtureRoot $Name
    $null = New-Item -ItemType Directory -Path $path -Force
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('init', '-q')
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('config', 'core.autocrlf', 'false')
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('config', 'user.email', 'manifest-tests@example.invalid')
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('config', 'user.name', 'Manifest Tests')
    [IO.File]::WriteAllText((Join-Path $path 'README.md'), "fixture`n", (New-Object Text.UTF8Encoding($false)))
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('add', '--', 'README.md')
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('commit', '-q', '-m', 'test: fixture')
    return $path
}

function New-CleanSkillRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Skill = 'fixture-skill'
    )

    $path = New-TestRepository -Name $Name
    $skillDirectory = Join-Path $path "skills\$Skill"
    $null = New-Item -ItemType Directory -Path (Join-Path $skillDirectory 'agents') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $skillDirectory 'references') -Force
    [IO.File]::WriteAllText(
        (Join-Path $skillDirectory 'SKILL.md'),
        "---`nname: $Skill`ndescription: Test skill.`n---`n`n# Fixture`n",
        (New-Object Text.UTF8Encoding($false))
    )
    [IO.File]::WriteAllText(
        (Join-Path $skillDirectory 'agents\openai.yaml'),
        "interface:`n  display_name: Fixture`n",
        (New-Object Text.UTF8Encoding($false))
    )
    [IO.File]::WriteAllText(
        (Join-Path $skillDirectory 'references\Guide.md'),
        "# Guide`n`nFixture reference.`n",
        (New-Object Text.UTF8Encoding($false))
    )
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('add', '--', "skills/$Skill")
    $null = Invoke-Git -WorkingDirectory $path -Arguments @('commit', '-q', '-m', 'test: add skill')
    return $path
}

function Get-ManagerDirectoryManifest {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $managerPath = Join-Path $repoRoot 'scripts\Manage-MultivendorSkills.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($managerPath, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal -Expected 0 -Actual $parseErrors.Count -Message 'Existing manager must parse for digest cross-check'
    $requiredFunctions = @(
        'Get-NormalizedFullPath',
        'Test-PathWithin',
        'Assert-PathWithin',
        'Get-RelativePathPortable',
        'Get-Sha256Text',
        'Get-Sha256File',
        'Get-DirectoryManifest'
    )
    $topLevelFunctions = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })
    foreach ($name in $requiredFunctions) {
        $definition = @($topLevelFunctions | Where-Object { $_.Name -eq $name })
        Assert-Equal -Expected 1 -Actual $definition.Count -Message "Existing manager function exists: $name"
        . ([scriptblock]::Create([string]$definition[0].Extent.Text))
    }
    return Get-DirectoryManifest -Directory $Directory
}

function Invoke-Generator {
    param(
        [string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Skill,
        [switch]$Write
    )

    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $generatorPath,
        '-Skill', $Skill
    )
    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $arguments += @('-RepositoryRoot', $RepositoryRoot)
    }
    if ($Write) { $arguments += '-Write' }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    }
}

function Run-Test {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    try {
        & $Body
        Write-Output "PASS: $Name"
    }
    catch {
        $script:failures += "$Name :: $($_.Exception.Message)"
        Write-Output "FAIL: $Name"
    }
}

function Remove-TestFixtureRoot {
    $normalizedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\', '/')
    if (-not $normalizedFixtureRoot.StartsWith($normalizedTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $normalizedFixtureRoot).StartsWith('yohan-skill-manifest-tests-', [StringComparison]::Ordinal)) {
        throw "Refusing to clean an unexpected fixture root: $normalizedFixtureRoot"
    }

    $pending = New-Object Collections.Generic.Stack[string]
    $directories = New-Object Collections.Generic.List[string]
    $pending.Push($normalizedFixtureRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $directories.Add($directory)
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
                else { [IO.File]::Delete($entry.FullName) }
                continue
            }
            if ($entry.PSIsContainer) {
                $pending.Push($entry.FullName)
                continue
            }
            [IO.File]::SetAttributes($entry.FullName, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($entry.FullName)
        }
    }

    foreach ($directory in @($directories | Sort-Object { $_.Length } -Descending)) {
        if ([IO.Directory]::Exists($directory)) { [IO.Directory]::Delete($directory, $false) }
    }
}

$null = New-Item -ItemType Directory -Path $xdgConfigRoot -Force
$env:XDG_CONFIG_HOME = $xdgConfigRoot

Run-Test -Name 'missing skill directory is rejected with a stable reason' -Body {
    $fixture = New-TestRepository -Name 'missing-skill'
    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'missing-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Missing skill directory must fail'
    Assert-Match -Actual $result.Text -Pattern 'Skill directory does not exist' -Message 'Missing skill failure reason'
}

Run-Test -Name 'repository root defaults to the generator parent directory' -Body {
    $result = Invoke-Generator -Skill 'design-to-html'
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'Default RepositoryRoot generation exit code'
    $manifest = $result.Text | ConvertFrom-Json
    Assert-Equal -Expected 'design-to-html' -Actual ([string]$manifest.skill) -Message 'Default RepositoryRoot resolves the canonical skill'
}

Run-Test -Name 'clean tracked skill produces the exact deterministic manifest without a default write' -Body {
    $fixture = New-CleanSkillRepository -Name 'deterministic'
    $skill = 'fixture-skill'
    $skillDirectory = Join-Path $fixture "skills\$skill"
    $manifestPath = Join-Path $fixture "distribution\manifests\$skill.json"

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill $skill
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'Clean tracked skill generation exit code'
    Assert-True -Condition (-not [IO.File]::Exists($manifestPath)) -Message 'Default generation must not write a manifest'
    $manifest = $result.Text | ConvertFrom-Json
    Assert-Equal -Expected 1 -Actual ([int]$manifest.schemaVersion) -Message 'Manifest schema version'
    Assert-Equal -Expected $skill -Actual ([string]$manifest.skill) -Message 'Manifest skill name'

    $expectedPaths = @('agents/openai.yaml', 'references/Guide.md', 'SKILL.md')
    $actualPaths = @($manifest.files | ForEach-Object { [string]$_.path })
    Assert-Equal -Expected ([string]::Join('|', $expectedPaths)) -Actual ([string]::Join('|', $actualPaths)) -Message 'Manifest path order'
    foreach ($row in @($manifest.files)) {
        $filePath = Join-Path $skillDirectory ([string]$row.path).Replace('/', '\')
        $file = Get-Item -LiteralPath $filePath
        $hash = Get-TestSha256File -Path $filePath
        Assert-Equal -Expected ([int64]$file.Length) -Actual ([int64]$row.bytes) -Message "Independent byte count: $($row.path)"
        Assert-Equal -Expected $hash -Actual ([string]$row.sha256) -Message "Independent SHA-256: $($row.path)"
    }

    $managerManifest = Get-ManagerDirectoryManifest -Directory $skillDirectory
    Assert-Equal -Expected ([string]$managerManifest.digest) -Actual ([string]$manifest.digest) -Message 'Generator digest matches existing manager exactly'

    $writeResult = Invoke-Generator -RepositoryRoot $fixture -Skill $skill -Write
    Assert-Equal -Expected 0 -Actual $writeResult.ExitCode -Message 'Write mode exit code'
    Assert-True -Condition ([IO.File]::Exists($manifestPath)) -Message 'Write mode creates the expected manifest'
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $hasBom = $manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 0xEF -and $manifestBytes[1] -eq 0xBB -and $manifestBytes[2] -eq 0xBF
    Assert-True -Condition (-not $hasBom) -Message 'Written manifest uses UTF-8 without BOM'
    $writtenManifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-Equal -Expected ([string]$manifest.digest) -Actual ([string]$writtenManifest.digest) -Message 'Write mode preserves the default digest'
}

Run-Test -Name 'nested reparse point is rejected before traversal' -Body {
    $fixture = New-CleanSkillRepository -Name 'nested-reparse'
    $outsideDirectory = Join-Path $fixture 'outside-reference'
    $junctionPath = Join-Path $fixture 'skills\fixture-skill\references\linked'
    $null = New-Item -ItemType Directory -Path $outsideDirectory -Force
    [IO.File]::WriteAllText((Join-Path $outsideDirectory 'outside.md'), "outside`n", (New-Object Text.UTF8Encoding($false)))
    $null = New-Item -ItemType Junction -Path $junctionPath -Target $outsideDirectory

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Nested reparse point must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)reparse point' -Message 'Nested reparse failure reason'
}

Run-Test -Name 'case-insensitive duplicate tracked paths are rejected' -Body {
    $fixture = New-CleanSkillRepository -Name 'case-collision'
    $skillRelative = 'skills/fixture-skill'
    $casePath = Join-Path $fixture 'skills\fixture-skill\references\Case.md'
    [IO.File]::WriteAllText($casePath, "case collision`n", (New-Object Text.UTF8Encoding($false)))
    $null = Invoke-Git -WorkingDirectory $fixture -Arguments @('add', '--', "$skillRelative/references/Case.md")
    $null = Invoke-Git -WorkingDirectory $fixture -Arguments @('commit', '-q', '-m', 'test: add collision source')
    $blob = [string](@(Invoke-Git -WorkingDirectory $fixture -Arguments @('hash-object', '-w', '--', $casePath))[0])
    $null = Invoke-Git -WorkingDirectory $fixture -Arguments @(
        'update-index',
        '--add',
        '--cacheinfo',
        "100644,$blob,$skillRelative/references/case.md"
    )
    $tracked = @(Invoke-Git -WorkingDirectory $fixture -Arguments @('ls-files', '--', $skillRelative))
    $collisionEntries = @($tracked | Where-Object { ([string]$_).ToLowerInvariant().EndsWith('/references/case.md') })
    Assert-Equal -Expected 2 -Actual $collisionEntries.Count -Message 'Fixture contains two case-colliding index paths'

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Case-insensitive duplicate must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)case-colliding path' -Message 'Case collision failure reason'
}

Run-Test -Name 'non-UTF8 SKILL.md is rejected before Git drift reporting' -Body {
    $fixture = New-CleanSkillRepository -Name 'invalid-utf8'
    $skillFile = Join-Path $fixture 'skills\fixture-skill\SKILL.md'
    [IO.File]::WriteAllBytes($skillFile, [byte[]](0xFF, 0xFE, 0xFA))

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Invalid UTF-8 SKILL.md must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)SKILL\.md is not valid UTF-8' -Message 'Invalid UTF-8 failure reason'
}

Run-Test -Name 'untracked skill file is rejected' -Body {
    $fixture = New-CleanSkillRepository -Name 'untracked-file'
    $untrackedPath = Join-Path $fixture 'skills\fixture-skill\references\untracked.md'
    [IO.File]::WriteAllText($untrackedPath, "untracked`n", (New-Object Text.UTF8Encoding($false)))

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Untracked skill file must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)untracked skill file' -Message 'Untracked skill failure reason'
}

Run-Test -Name 'tracked working file that differs from the index is rejected' -Body {
    $fixture = New-CleanSkillRepository -Name 'index-drift'
    $changedPath = Join-Path $fixture 'skills\fixture-skill\references\Guide.md'
    [IO.File]::AppendAllText($changedPath, "changed`n", (New-Object Text.UTF8Encoding($false)))

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Working tree/index mismatch must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)differs from Git index' -Message 'Working tree/index mismatch reason'
}

Run-Test -Name 'staged skill change that differs from HEAD is rejected' -Body {
    $fixture = New-CleanSkillRepository -Name 'staged-drift'
    $changedPath = Join-Path $fixture 'skills\fixture-skill\references\Guide.md'
    [IO.File]::AppendAllText($changedPath, "staged`n", (New-Object Text.UTF8Encoding($false)))
    $null = Invoke-Git -WorkingDirectory $fixture -Arguments @('add', '--', 'skills/fixture-skill/references/Guide.md')

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Index/HEAD mismatch must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)Git index differs from HEAD' -Message 'Index/HEAD mismatch reason'
}

Run-Test -Name 'Write rejects a distribution directory junction without changing the external manifest' -Body {
    $fixture = New-CleanSkillRepository -Name 'distribution-output-junction'
    $outsideDistribution = Join-Path $fixtureRoot 'outside-distribution'
    $outsideManifests = Join-Path $outsideDistribution 'manifests'
    $outsideManifest = Join-Path $outsideManifests 'fixture-skill.json'
    $null = New-Item -ItemType Directory -Path $outsideManifests -Force
    [IO.File]::WriteAllText($outsideManifest, "external sentinel`n", (New-Object Text.UTF8Encoding($false)))
    $null = New-Item -ItemType Junction -Path (Join-Path $fixture 'distribution') -Target $outsideDistribution

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill' -Write
    Assert-Equal -Expected "external sentinel`n" -Actual ([IO.File]::ReadAllText($outsideManifest, [Text.Encoding]::UTF8)) -Message 'Distribution junction target remains unchanged'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Distribution directory junction must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)reparse point' -Message 'Distribution junction failure reason'
}

Run-Test -Name 'Write rejects a manifests directory junction without changing the external manifest' -Body {
    $fixture = New-CleanSkillRepository -Name 'manifests-output-junction'
    $distribution = Join-Path $fixture 'distribution'
    $outsideManifests = Join-Path $fixtureRoot 'outside-manifests'
    $outsideManifest = Join-Path $outsideManifests 'fixture-skill.json'
    $null = New-Item -ItemType Directory -Path $distribution -Force
    $null = New-Item -ItemType Directory -Path $outsideManifests -Force
    [IO.File]::WriteAllText($outsideManifest, "external sentinel`n", (New-Object Text.UTF8Encoding($false)))
    $null = New-Item -ItemType Junction -Path (Join-Path $distribution 'manifests') -Target $outsideManifests

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill' -Write
    Assert-Equal -Expected "external sentinel`n" -Actual ([IO.File]::ReadAllText($outsideManifest, [Text.Encoding]::UTF8)) -Message 'Manifests junction target remains unchanged'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Manifests directory junction must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)reparse point' -Message 'Manifests junction failure reason'
}

Run-Test -Name 'Write rejects an existing reparse target without changing its external content' -Body {
    $fixture = New-CleanSkillRepository -Name 'manifest-target-reparse'
    $manifestDirectory = Join-Path $fixture 'distribution\manifests'
    $manifestTarget = Join-Path $manifestDirectory 'fixture-skill.json'
    $outsideFile = Join-Path $fixtureRoot 'outside-target.json'
    $outsideDirectory = Join-Path $fixtureRoot 'outside-target-directory'
    $null = New-Item -ItemType Directory -Path $manifestDirectory -Force
    [IO.File]::WriteAllText($outsideFile, "external sentinel`n", (New-Object Text.UTF8Encoding($false)))
    $usesFileLink = $true
    try {
        $null = New-Item -ItemType SymbolicLink -Path $manifestTarget -Target $outsideFile -ErrorAction Stop
    }
    catch {
        $usesFileLink = $false
        $null = New-Item -ItemType Directory -Path $outsideDirectory -Force
        [IO.File]::WriteAllText((Join-Path $outsideDirectory 'sentinel.txt'), "external sentinel`n", (New-Object Text.UTF8Encoding($false)))
        $null = New-Item -ItemType Junction -Path $manifestTarget -Target $outsideDirectory
    }

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill' -Write
    if ($usesFileLink) {
        Assert-Equal -Expected "external sentinel`n" -Actual ([IO.File]::ReadAllText($outsideFile, [Text.Encoding]::UTF8)) -Message 'Manifest file link target remains unchanged'
    }
    else {
        Assert-Equal -Expected "external sentinel`n" -Actual ([IO.File]::ReadAllText((Join-Path $outsideDirectory 'sentinel.txt'), [Text.Encoding]::UTF8)) -Message 'Manifest junction target remains unchanged'
    }
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Existing reparse manifest target must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)reparse point' -Message 'Manifest target reparse failure reason'
}

Run-Test -Name 'Write rejects an existing hard-link target without changing its external content' -Body {
    $fixture = New-CleanSkillRepository -Name 'manifest-target-hard-link'
    $manifestDirectory = Join-Path $fixture 'distribution\manifests'
    $manifestTarget = Join-Path $manifestDirectory 'fixture-skill.json'
    $outsideFile = Join-Path $fixtureRoot 'outside-hard-link-target.json'
    $null = New-Item -ItemType Directory -Path $manifestDirectory -Force
    [IO.File]::WriteAllText($outsideFile, "external sentinel`n", (New-Object Text.UTF8Encoding($false)))
    $null = New-Item -ItemType HardLink -Path $manifestTarget -Target $outsideFile

    $result = Invoke-Generator -RepositoryRoot $fixture -Skill 'fixture-skill' -Write
    Assert-Equal -Expected "external sentinel`n" -Actual ([IO.File]::ReadAllText($outsideFile, [Text.Encoding]::UTF8)) -Message 'Manifest hard-link target remains unchanged'
    Assert-True -Condition ($result.ExitCode -ne 0) -Message 'Existing hard-link manifest target must fail'
    Assert-Match -Actual $result.Text -Pattern '(?i)(hard.?link|linked target)' -Message 'Manifest hard-link failure reason'
}

if ($script:failures.Count -gt 0) {
    Write-Output "ERROR: $([string]::Join(' | ', $script:failures))"
    Write-Output "FAIL after $script:assertionCount assertions"
    Write-Output "Fixture retained: $fixtureRoot"
    exit 1
}

Write-Output "PASS: $script:assertionCount assertions"
Remove-TestFixtureRoot
Write-Output "Fixture cleaned: $fixtureRoot"
exit 0
