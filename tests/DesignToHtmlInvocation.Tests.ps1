#requires -Version 5.1

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$managerPath = Join-Path $repoRoot 'scripts\Manage-MultivendorSkills.ps1'
$workRoot = Join-Path $PSScriptRoot '.work'
$fixtureRoot = Join-Path $workRoot ("design-to-html-invocation-{0}" -f [Guid]::NewGuid().ToString('N'))
$homeRoot = Join-Path $fixtureRoot 'home'
$script:assertionCount = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:assertionCount++
    if ($Expected -cne $Actual) { throw $Message }
}

function Get-TestSha256File {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-PowerShellExecutable {
    foreach ($candidate in @(Get-Command powershell.exe -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $source = [string]$candidate.Source
        if (-not [string]::IsNullOrWhiteSpace($source) -and [IO.File]::Exists($source)) { return $source }
    }
    throw 'powershell.exe is unavailable'
}

function Invoke-ManagerJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = @(& $script:powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $managerPath @Arguments -OutputFormat Json 2>&1)
    $exitCode = $LASTEXITCODE
    $json = [string]::Join("`n", @($output | ForEach-Object { [string]$_ }))
    try { $data = $json | ConvertFrom-Json }
    catch { throw 'Manager did not return valid JSON' }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data }
}

function Invoke-FreshDiscoveryProbe {
    $probe = @'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Get-Sha256File([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToUpperInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-Manifest([string]$Directory) {
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $rows = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'File reparse point is forbidden' }
        $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $rows += [pscustomobject][ordered]@{
            path = $relative
            bytes = [int64]$file.Length
            sha256 = Get-Sha256File $file.FullName
        }
    }
    $rows = @($rows | Sort-Object -Property @{ Expression = { $_.path.ToLowerInvariant() } }, @{ Expression = { $_.path } })
    $digestInput = [string]::Join("`n", @($rows | ForEach-Object { "$($_.path)`0$($_.bytes)`0$($_.sha256)" }))
    return [pscustomobject][ordered]@{ files = $rows; digest = Get-Sha256Text $digestInput }
}

$homeRoot = [IO.Path]::GetFullPath($env:YOHAN_SMOKE_HOME_ROOT)
$expectedDigest = [string]$env:YOHAN_SMOKE_EXPECTED_DIGEST
$definitions = @(
    [pscustomobject]@{ consumer = 'CodexCursorAgents'; path = '.agents/skills/design-to-html' },
    [pscustomobject]@{ consumer = 'ClaudeCode'; path = '.claude/skills/design-to-html' },
    [pscustomobject]@{ consumer = 'AntigravityStandard'; path = '.gemini/config/skills/design-to-html' }
)

$discoveries = @()
foreach ($definition in $definitions) {
    $target = Join-Path $homeRoot ($definition.path.Replace('/', '\'))
    $entry = Get-Item -LiteralPath $target -Force
    $manifest = Get-Manifest $target
    $skillText = [IO.File]::ReadAllText((Join-Path $target 'SKILL.md'), [Text.Encoding]::UTF8)
    $uiPath = Join-Path $target 'agents\openai.yaml'
    $uiBytes = [IO.File]::ReadAllBytes($uiPath)
    $uiText = [Text.Encoding]::UTF8.GetString($uiBytes)
    $frontmatter = [regex]::Match($skillText, '(?s)\A---\r?\nname:\s*design-to-html\r?\ndescription:\s*(?<description>.+?)\r?\n---')
    $description = if ($frontmatter.Success) { [string]$frontmatter.Groups['description'].Value } else { '' }
    $htmlTrigger = [string]::Concat([char[]]@(0x0048, 0x0054, 0x004D, 0x004C, 0xB85C, 0x0020, 0xB9CC, 0xB4E4, 0xC5B4, 0xC918))
    $mockupTrigger = [string]::Concat([char[]]@(0xC774, 0x0020, 0xC2DC, 0xC548, 0x0020, 0xAD6C, 0xD604, 0xD574))
    $discoveries += [pscustomobject][ordered]@{
        consumer = $definition.consumer
        path = $definition.path
        junction = ([string]$entry.LinkType -eq 'Junction')
        digest = [string]$manifest.digest
        digestMatches = ([string]$manifest.digest -ceq $expectedDigest)
        frontmatter = $frontmatter.Success
        triggerContract = ($description.Contains($htmlTrigger) -and $description.Contains($mockupTrigger))
        explicitInvocation = $uiText.Contains('$design-to-html')
        implicitInvocation = [regex]::IsMatch($uiText, '(?m)^\s{2}allow_implicit_invocation:\s*true\s*$')
        utf8NoBom = -not ($uiBytes.Length -ge 3 -and $uiBytes[0] -eq 0xEF -and $uiBytes[1] -eq 0xBB -and $uiBytes[2] -eq 0xBF)
    }
}

[pscustomobject][ordered]@{
    schemaVersion = 1
    processIsFresh = ($PID -ne [int]$env:YOHAN_SMOKE_PARENT_PID)
    discoveries = $discoveries
} | ConvertTo-Json -Depth 8 -Compress
'@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
    $previousHome = [Environment]::GetEnvironmentVariable('YOHAN_SMOKE_HOME_ROOT', 'Process')
    $previousDigest = [Environment]::GetEnvironmentVariable('YOHAN_SMOKE_EXPECTED_DIGEST', 'Process')
    $previousPid = [Environment]::GetEnvironmentVariable('YOHAN_SMOKE_PARENT_PID', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_HOME_ROOT', $homeRoot, 'Process')
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_EXPECTED_DIGEST', $script:expectedDigest, 'Process')
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_PARENT_PID', [string]$PID, 'Process')
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& $script:powerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousErrorActionPreference }
    }
    finally {
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_HOME_ROOT', $previousHome, 'Process')
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_EXPECTED_DIGEST', $previousDigest, 'Process')
        [Environment]::SetEnvironmentVariable('YOHAN_SMOKE_PARENT_PID', $previousPid, 'Process')
    }
    if ($exitCode -ne 0) {
        throw 'Fresh discovery process failed'
    }
    try { return ([string]::Join("`n", @($output | ForEach-Object { [string]$_ })) | ConvertFrom-Json) }
    catch { throw 'Fresh discovery process did not return valid JSON' }
}

function Remove-FixtureRootSafely {
    if (-not [IO.Directory]::Exists($fixtureRoot)) { return }
    $normalizedWorkRoot = [IO.Path]::GetFullPath($workRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $normalizedFixture.StartsWith($normalizedWorkRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture cleanup escaped tests/.work'
    }
    $reparsePoints = @(Get-ChildItem -LiteralPath $fixtureRoot -Force -Recurse | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($entry in $reparsePoints) {
        if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
        else { [IO.File]::Delete($entry.FullName) }
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    if ([IO.Directory]::Exists($fixtureRoot)) { throw 'Fixture cleanup did not finish' }
}

$manifestPath = Join-Path $repoRoot 'distribution\manifests\design-to-html.json'
$script:powerShell = $null
$script:expectedDigest = $null
$backupId = $null
$testPassed = $false
$failureReason = 'isolated invocation smoke failed'

try {
    $script:powerShell = Get-PowerShellExecutable
    Assert-True -Condition ([IO.File]::Exists($manifestPath)) -Message 'Committed skill manifest must exist'
    try { $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { throw 'Committed skill manifest must be valid JSON' }
    Assert-Equal -Expected 'design-to-html' -Actual ([string]$manifest.skill) -Message 'Committed skill manifest identity'
    Assert-True -Condition ([string]$manifest.digest -match '^[A-F0-9]{64}$') -Message 'Committed skill manifest digest format'
    $script:expectedDigest = [string]$manifest.digest

    $normalizedWorkRoot = [IO.Path]::GetFullPath($workRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    Assert-True -Condition $normalizedFixture.StartsWith($normalizedWorkRoot, [StringComparison]::OrdinalIgnoreCase) -Message 'Fixture must stay under tests/.work'

    $check = Invoke-ManagerJson -Arguments @('-Mode', 'Check', '-Skill', 'design-to-html', '-RepositoryRoot', $repoRoot, '-HomeRoot', $homeRoot)
    Assert-Equal -Expected 2 -Actual $check.ExitCode -Message 'Isolated HomeRoot must be installable'
    Assert-Equal -Expected 'Installable' -Actual ([string]$check.Data.status) -Message 'Check status before isolated install'
    Assert-True -Condition ([string]$check.Data.planDigest -match '^[A-Fa-f0-9]{64}$') -Message 'Check must return a bounded PlanDigest'

    $install = Invoke-ManagerJson -Arguments @('-Mode', 'Install', '-Skill', 'design-to-html', '-RepositoryRoot', $repoRoot, '-HomeRoot', $homeRoot, '-PlanDigest', [string]$check.Data.planDigest, '-ApproveGlobalHomeWrite')
    Assert-Equal -Expected 0 -Actual $install.ExitCode -Message 'Isolated install exit code'
    Assert-Equal -Expected 'Committed' -Actual ([string]$install.Data.status) -Message 'Isolated install status'
    $backupId = [string]$install.Data.backupId

    $fresh = Invoke-FreshDiscoveryProbe
    Assert-True -Condition ([bool]$fresh.processIsFresh) -Message 'Discovery probe must run in a new powershell.exe process'
    Assert-Equal -Expected 3 -Actual @($fresh.discoveries).Count -Message 'All three active discovery roots are probed'
    Assert-Equal -Expected '.agents/skills/design-to-html' -Actual ([string]@($fresh.discoveries)[0].path) -Message 'Codex and agents discovery path'
    Assert-Equal -Expected '.claude/skills/design-to-html' -Actual ([string]@($fresh.discoveries)[1].path) -Message 'Claude Code discovery path'
    Assert-Equal -Expected '.gemini/config/skills/design-to-html' -Actual ([string]@($fresh.discoveries)[2].path) -Message 'Antigravity standard discovery path'
    foreach ($discovery in @($fresh.discoveries)) {
        Assert-True -Condition ([bool]$discovery.junction) -Message 'Discovery entry must be a canonical junction'
        Assert-Equal -Expected $script:expectedDigest -Actual ([string]$discovery.digest) -Message 'Installed skill digest must match the committed manifest'
        Assert-True -Condition ([bool]$discovery.digestMatches) -Message 'Fresh process must independently match the committed digest'
        Assert-True -Condition ([bool]$discovery.frontmatter) -Message 'Fresh process must parse the design-to-html frontmatter contract'
        Assert-True -Condition ([bool]$discovery.triggerContract) -Message 'Fresh process must see explicit natural-language triggers'
        Assert-True -Condition ([bool]$discovery.explicitInvocation) -Message 'Fresh process must see the explicit $design-to-html invocation contract'
        Assert-True -Condition ([bool]$discovery.implicitInvocation) -Message 'Fresh process must see implicit invocation metadata'
        Assert-True -Condition ([bool]$discovery.utf8NoBom) -Message 'Fresh process must read openai.yaml as UTF-8 without BOM'
    }

    $testPassed = $true
}
catch {
    $failureReason = [string]$_.Exception.Message
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($backupId)) {
        try {
            $restoreCheck = Invoke-ManagerJson -Arguments @('-Mode', 'Check', '-RepositoryRoot', $repoRoot, '-HomeRoot', $homeRoot, '-BackupId', $backupId)
            if ($restoreCheck.ExitCode -eq 0 -and [string]$restoreCheck.Data.planDigest -match '^[A-Fa-f0-9]{64}$') {
                $null = Invoke-ManagerJson -Arguments @('-Mode', 'Restore', '-RepositoryRoot', $repoRoot, '-HomeRoot', $homeRoot, '-BackupId', $backupId, '-PlanDigest', [string]$restoreCheck.Data.planDigest, '-ApproveGlobalHomeWrite')
            }
        }
        catch { }
    }
    try { Remove-FixtureRootSafely }
    catch {
        $testPassed = $false
        $failureReason = 'isolated fixture cleanup failed'
    }
}

if ($testPassed) {
    Write-Output "PASS: $script:assertionCount assertions"
    exit 0
}
Write-Output "ERROR: isolated invocation smoke failed: $failureReason"
Write-Output "FAIL after $script:assertionCount assertions"
exit 1
