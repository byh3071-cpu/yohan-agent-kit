#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adapterPath = Join-Path $repoRoot 'scripts\Manage-ProductDesignContext.ps1'
$powerShell = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$fixtureRoot = Join-Path $PSScriptRoot (".work\product-design-context-run-{0}" -f [Guid]::NewGuid().ToString('N'))
$script:assertionCount = 0
$script:failures = @()

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

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-True -Condition ([regex]::IsMatch($Actual, $Pattern)) -Message "$Message. Actual=[$Actual]"
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Get-FixtureSha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Get-FixtureTransactionSeal {
    param([Parameter(Mandatory = $true)]$Transaction)

    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("schema|$([int]$Transaction.schemaVersion)")
    $lines.Add("owner|$([string]$Transaction.owner)")
    $lines.Add("target|$([string]$Transaction.targetRelativePath)|$([string]$Transaction.targetDigest)")
    $lines.Add("plan|$([string]$Transaction.installPlanDigest)")
    $lines.Add("brain|$([string]$Transaction.brainRootKey)")
    $lines.Add("home|$([string]$Transaction.homeRootKey)")
    foreach ($source in @($Transaction.sources)) {
        $lines.Add("source|$([string]$source.name)|$([string]$source.path)|$([string]$source.sha256)")
    }
    foreach ($relativePath in @($Transaction.createdDirectories)) { $lines.Add("directory|$([string]$relativePath)") }
    return Get-FixtureSha256Text -Text ([string]::Join("`n", $lines.ToArray()))
}

function New-Fixture {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = Join-Path $fixtureRoot $Name
    $brain = Join-Path $root 'brain'
    $userHome = Join-Path $root 'home'
    $null = New-Item -ItemType Directory -Path $userHome -Force
    Write-Utf8NoBom -Path (Join-Path $brain 'memory\rules\html-artifact-design.md') -Text "# HTML artifact rules`nUse calm typography.`n"
    Write-Utf8NoBom -Path (Join-Path $brain 'docs\reference\websites\ai-workspace-context-trust-navigator.md') -Text "# Context trust navigator`nShow evidence before action.`n"
    return [pscustomobject]@{ Root = $root; Brain = $brain; Home = $userHome }
}

function Get-TreeSignature {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not [IO.Directory]::Exists($Root)) { return '<missing>' }
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $rows = New-Object Collections.Generic.List[string]
    $pending = New-Object Collections.Generic.Stack[string]
    $pending.Push($normalizedRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force | Sort-Object FullName)) {
            $relative = $entry.FullName.Substring($normalizedRoot.Length).TrimStart('\', '/').Replace('\', '/')
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $rows.Add("link|$relative|$($entry.LinkType)")
                continue
            }
            if ($entry.PSIsContainer) {
                $rows.Add("dir|$relative")
                $pending.Push($entry.FullName)
            }
            else {
                $digest = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
                $rows.Add("file|$relative|$digest")
            }
        }
    }
    return [string]::Join("`n", @($rows | Sort-Object))
}

function Invoke-Adapter {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Check', 'Install', 'Restore')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$BrainRoot,
        [Parameter(Mandatory = $true)][string]$HomeRoot,
        [string]$PlanDigest,
        [switch]$ApproveGlobalHomeWrite,
        [ValidateSet('Human', 'Json')][string]$OutputFormat = 'Json'
    )

    $normalizedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($candidateRoot in @($BrainRoot, $HomeRoot)) {
        $normalizedCandidateRoot = [IO.Path]::GetFullPath($candidateRoot).TrimEnd('\', '/')
        if (-not $normalizedCandidateRoot.StartsWith($normalizedFixtureRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to invoke adapter outside the isolated fixture root: $normalizedCandidateRoot"
        }
    }

    $arguments = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $adapterPath,
        '-Mode', $Mode,
        '-BrainRoot', $BrainRoot,
        '-HomeRoot', $HomeRoot,
        '-OutputFormat', $OutputFormat
    )
    if (-not [string]::IsNullOrWhiteSpace($PlanDigest)) { $arguments += @('-PlanDigest', $PlanDigest) }
    if ($ApproveGlobalHomeWrite) { $arguments += '-ApproveGlobalHomeWrite' }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }
    $raw = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
    $data = $null
    if ($OutputFormat -eq 'Json') {
        try { $data = $raw | ConvertFrom-Json }
        catch { throw "Adapter returned invalid JSON (exit=$exitCode): $raw" }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Data = $data; Raw = $raw }
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
    $normalizedTestsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.work')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $normalizedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd('\', '/')
    if (-not $normalizedFixtureRoot.StartsWith($normalizedTestsRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $normalizedFixtureRoot).StartsWith('product-design-context-run-', [StringComparison]::Ordinal)) {
        throw "Refusing to clean unexpected fixture root: $normalizedFixtureRoot"
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
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName); continue }
            [IO.File]::SetAttributes($entry.FullName, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($entry.FullName)
        }
    }
    foreach ($directory in @($directories | Sort-Object { $_.Length } -Descending)) {
        if ([IO.Directory]::Exists($directory)) { [IO.Directory]::Delete($directory, $false) }
    }
}

$null = New-Item -ItemType Directory -Path $fixtureRoot -Force

Run-Test -Name 'Check on an empty isolated home is deterministic and read-only' -Body {
    $fixture = New-Fixture -Name 'check-empty'
    $before = Get-TreeSignature -Root $fixture.Home
    $first = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $second = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $humanFirst = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -OutputFormat Human
    $humanSecond = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -OutputFormat Human

    Assert-Equal -Expected 2 -Actual $first.ExitCode -Message 'Installable Check exit code'
    Assert-Equal -Expected 'Installable' -Actual ([string]$first.Data.status) -Message 'Empty home state'
    Assert-Match -Actual ([string]$first.Data.planDigest) -Pattern '^[A-F0-9]{64}$' -Message 'Plan digest shape'
    Assert-Equal -Expected $first.Raw -Actual $second.Raw -Message 'JSON evidence is deterministic'
    Assert-Equal -Expected $humanFirst.Raw -Actual $humanSecond.Raw -Message 'Human evidence is deterministic'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Check creates no home files or directories'
    Assert-True -Condition (-not $first.Raw.Contains($fixture.Root)) -Message 'JSON does not expose raw fixture paths'
}

Run-Test -Name 'Install without explicit approval is rejected without writes' -Body {
    $fixture = New-Fixture -Name 'unapproved'
    $plan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $before = Get-TreeSignature -Root $fixture.Home
    $result = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$plan.Data.planDigest)

    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'Unapproved Install exit code'
    Assert-Equal -Expected 'Rejected' -Actual ([string]$result.Data.status) -Message 'Unapproved Install status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Unapproved Install has zero writes'
}

Run-Test -Name 'Approved exact plan installs official Product Design context and becomes Healthy' -Body {
    $fixture = New-Fixture -Name 'approved'
    $plan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $result = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$plan.Data.planDigest) -ApproveGlobalHomeWrite
    $post = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    $transaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $text = [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)
    $bytes = [IO.File]::ReadAllBytes($target)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'Approved Install exit code'
    Assert-Equal -Expected 'Healthy' -Actual ([string]$result.Data.status) -Message 'Approved Install status'
    Assert-Equal -Expected 'Healthy' -Actual ([string]$post.Data.status) -Message 'Post-install Check status'
    Assert-True -Condition ([bool]$post.Data.owned) -Message 'Post-install state has owned transaction evidence'
    Assert-True -Condition ([IO.File]::Exists($transaction)) -Message 'Owned transaction evidence exists'
    Assert-True -Condition (-not $hasBom) -Message 'Installed context is UTF-8 without BOM'
    Assert-True -Condition ($text.Contains('# Codebase References')) -Message 'Official Codebase References section is present'
    Assert-True -Condition ($text.Contains('# Design Tokens And Theme Sources')) -Message 'Official Design Tokens section is present'
    Assert-True -Condition ($text.Contains((Join-Path $fixture.Brain 'memory\rules\html-artifact-design.md'))) -Message 'Installed context resolves design rules to an absolute path'
    Assert-True -Condition ($text.Contains((Join-Path $fixture.Brain 'docs\reference\websites\ai-workspace-context-trust-navigator.md'))) -Message 'Installed context resolves reference to an absolute path'
}

Run-Test -Name 'Edited installed target becomes Conflict and is never overwritten' -Body {
    $fixture = New-Fixture -Name 'edited-conflict'
    $plan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$plan.Data.planDigest) -ApproveGlobalHomeWrite
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    Write-Utf8NoBom -Path $target -Text "user-owned edit`n"
    $conflict = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $install = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$conflict.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 3 -Actual $conflict.ExitCode -Message 'Edited target Check exit code'
    Assert-Equal -Expected 'Conflict' -Actual ([string]$conflict.Data.status) -Message 'Edited target state'
    Assert-Equal -Expected 3 -Actual $install.ExitCode -Message 'Conflict Install exit code'
    Assert-Equal -Expected "user-owned edit`n" -Actual ([IO.File]::ReadAllText($target, [Text.Encoding]::UTF8)) -Message 'Conflict target stays byte-for-byte unchanged'
}

Run-Test -Name 'Stale plan digest is rejected before any home write' -Body {
    $fixture = New-Fixture -Name 'stale-plan'
    $plan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    Write-Utf8NoBom -Path (Join-Path $fixture.Brain 'memory\rules\html-artifact-design.md') -Text "# Changed rules`n"
    $before = Get-TreeSignature -Root $fixture.Home
    $result = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$plan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'Stale Install exit code'
    Assert-Equal -Expected 'Rejected' -Actual ([string]$result.Data.status) -Message 'Stale Install status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Stale plan causes no home writes'
}

Run-Test -Name 'Restore removes only owned bytes and returns the exact pre-install tree' -Body {
    $fixture = New-Fixture -Name 'restore'
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $restorePlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $restore = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$restorePlan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 0 -Actual $restore.ExitCode -Message 'Restore exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$restore.Data.status) -Message 'Restore status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Restore returns exact pre-install home tree'
}

Run-Test -Name 'Owned install remains restorable after its Git source changes' -Body {
    $fixture = New-Fixture -Name 'restore-after-source-change'
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    Write-Utf8NoBom -Path (Join-Path $fixture.Brain 'memory\rules\html-artifact-design.md') -Text "# New Git rules`n"
    $restorePlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $restore = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$restorePlan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 'Healthy' -Actual ([string]$restorePlan.Data.status) -Message 'Path-based installed context stays current after source drift'
    Assert-True -Condition ([bool]$restorePlan.Data.owned) -Message 'Source drift does not erase owned transaction identity'
    Assert-Equal -Expected 0 -Actual $restore.ExitCode -Message 'Owned Restore after source drift exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$restore.Data.status) -Message 'Owned Restore after source drift status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Restore after source drift returns exact pre-install tree'
}

Run-Test -Name 'Tampered transaction directory claims lose ownership without deleting any bytes' -Body {
    $fixture = New-Fixture -Name 'tampered-transaction'
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $outside = Join-Path $fixture.Root 'outside-sentinel.txt'
    Write-Utf8NoBom -Path $outside -Text "outside sentinel`n"
    $transaction = [IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $transaction.createdDirectories = @('../../outside')
    Write-Utf8NoBom -Path $transactionPath -Text ([string]($transaction | ConvertTo-Json -Depth 8 -Compress))
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $restore = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$check.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-True -Condition (-not [bool]$check.Data.owned) -Message 'Unsafe transaction directory claim is not owned evidence'
    Assert-Equal -Expected 3 -Actual $restore.ExitCode -Message 'Tampered transaction Restore exit code'
    Assert-True -Condition ([IO.File]::Exists($target)) -Message 'Tampered transaction cannot remove installed target'
    Assert-Equal -Expected "outside sentinel`n" -Actual ([IO.File]::ReadAllText($outside, [Text.Encoding]::UTF8)) -Message 'Tampered transaction cannot touch outside bytes'
}

Run-Test -Name 'A resealed transaction cannot claim and delete arbitrary target bytes' -Body {
    $fixture = New-Fixture -Name 'forged-target-digest'
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $outside = Join-Path $fixture.Root 'forged-external-sentinel.txt'
    $arbitraryBytes = "arbitrary user context must survive`n"
    Write-Utf8NoBom -Path $target -Text $arbitraryBytes
    Write-Utf8NoBom -Path $outside -Text "external sentinel must survive`n"
    $transaction = [IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $transaction.targetDigest = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant()
    $transaction.evidenceDigest = Get-FixtureTransactionSeal -Transaction $transaction
    Write-Utf8NoBom -Path $transactionPath -Text ([string]($transaction | ConvertTo-Json -Depth 8 -Compress))
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $restore = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$check.Data.planDigest) -ApproveGlobalHomeWrite
    $targetExists = [IO.File]::Exists($target)
    $targetAfter = if ($targetExists) { [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) } else { '<missing>' }

    Assert-Equal -Expected 'Conflict' -Actual ([string]$check.Data.status) -Message 'Arbitrary target remains a conflict'
    Assert-True -Condition (-not [bool]$check.Data.owned) -Message 'Resealed arbitrary target is not owned evidence'
    Assert-Equal -Expected 3 -Actual $restore.ExitCode -Message 'Forged transaction Restore exit code'
    Assert-True -Condition $targetExists -Message 'Forged transaction cannot delete arbitrary target'
    Assert-Equal -Expected $arbitraryBytes -Actual $targetAfter -Message 'Arbitrary target stays byte-for-byte unchanged'
    Assert-Equal -Expected "external sentinel must survive`n" -Actual ([IO.File]::ReadAllText($outside, [Text.Encoding]::UTF8)) -Message 'External sentinel stays byte-for-byte unchanged'
}

Run-Test -Name 'Exact target with unowned transaction reports Conflict rather than Healthy' -Body {
    $fixture = New-Fixture -Name 'exact-unowned'
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $transaction = [IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $transaction.evidenceDigest = ('0' * 64)
    Write-Utf8NoBom -Path $transactionPath -Text ([string]($transaction | ConvertTo-Json -Depth 8 -Compress))
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'Exact unmanaged target Check exit code'
    Assert-Equal -Expected 'Conflict' -Actual ([string]$check.Data.status) -Message 'Exact unmanaged target status'
    Assert-True -Condition (-not [bool]$check.Data.owned) -Message 'Exact unmanaged target remains unowned'
}

Run-Test -Name 'Restore resumes safely when the owned target was already removed' -Body {
    $fixture = New-Fixture -Name 'restore-resume'
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    [IO.File]::Delete($target)
    $recoveryPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $restore = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$recoveryPlan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 'Conflict' -Actual ([string]$recoveryPlan.Data.status) -Message 'Interrupted Restore exposes a recovery state'
    Assert-True -Condition ([bool]$recoveryPlan.Data.owned) -Message 'Retained transaction remains owned recovery evidence'
    Assert-Equal -Expected 0 -Actual $restore.ExitCode -Message 'Resumed Restore exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$restore.Data.status) -Message 'Resumed Restore status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Resumed Restore returns exact pre-install tree'
}

Run-Test -Name 'Existing HomeRoot journal file is a non-overwritable Conflict' -Body {
    $fixture = New-Fixture -Name 'journal-file-collision'
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $target = Join-Path $fixture.Home '.codex\state\plugins\product-design\user-context.md'
    Write-Utf8NoBom -Path $transactionPath -Text "user-owned journal collision`n"
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $install = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$check.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'Journal file collision Check exit code'
    Assert-Equal -Expected 'Conflict' -Actual ([string]$check.Data.status) -Message 'Journal file collision status'
    Assert-Equal -Expected 3 -Actual $install.ExitCode -Message 'Journal file collision Install exit code'
    Assert-Equal -Expected "user-owned journal collision`n" -Actual ([IO.File]::ReadAllText($transactionPath, [Text.Encoding]::UTF8)) -Message 'Journal collision stays byte-for-byte unchanged'
    Assert-True -Condition (-not [IO.File]::Exists($target)) -Message 'Journal collision prevents target creation'
}

Run-Test -Name 'HomeRoot journal reparse point is Unsafe without following external bytes' -Body {
    $fixture = New-Fixture -Name 'journal-reparse'
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $outsideDirectory = Join-Path $fixture.Root 'external-journal-directory'
    $outsideSentinel = Join-Path $outsideDirectory 'sentinel.txt'
    $null = New-Item -ItemType Directory -Path $outsideDirectory -Force
    Write-Utf8NoBom -Path $outsideSentinel -Text "external reparse sentinel`n"
    $null = New-Item -ItemType Junction -Path $transactionPath -Target $outsideDirectory
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'Journal reparse Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$check.Data.status) -Message 'Journal reparse state'
    Assert-Equal -Expected "external reparse sentinel`n" -Actual ([IO.File]::ReadAllText($outsideSentinel, [Text.Encoding]::UTF8)) -Message 'Journal reparse external bytes stay unchanged'
}

Run-Test -Name 'HomeRoot journal hard link is Unsafe without changing external bytes' -Body {
    $fixture = New-Fixture -Name 'journal-hardlink'
    $transactionPath = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $outsideFile = Join-Path $fixture.Root 'external-journal-file.txt'
    Write-Utf8NoBom -Path $outsideFile -Text "external hard-link journal sentinel`n"
    $null = New-Item -ItemType HardLink -Path $transactionPath -Target $outsideFile
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'Journal hard-link Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$check.Data.status) -Message 'Journal hard-link state'
    Assert-Equal -Expected "external hard-link journal sentinel`n" -Actual ([IO.File]::ReadAllText($outsideFile, [Text.Encoding]::UTF8)) -Message 'Journal hard-link external bytes stay unchanged'
}

Run-Test -Name 'Restore keeps stable recovery evidence until created-directory cleanup succeeds' -Body {
    $fixture = New-Fixture -Name 'restore-cleanup-recovery'
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $targetDirectory = Join-Path $fixture.Home '.codex\state\plugins\product-design'
    $target = Join-Path $targetDirectory 'user-context.md'
    $stableTransaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    $nestedTransaction = Join-Path $targetDirectory '.user-context.transaction.json'
    $blocker = Join-Path $targetDirectory 'user-sentinel.txt'

    Assert-True -Condition ([IO.File]::Exists($stableTransaction)) -Message 'Recovery evidence is stored directly under the pre-existing HomeRoot'
    Assert-True -Condition (-not [IO.File]::Exists($nestedTransaction)) -Message 'Recovery evidence is outside directories Restore must remove'
    Write-Utf8NoBom -Path $blocker -Text "user sentinel blocks cleanup`n"
    $restorePlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $interrupted = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$restorePlan.Data.planDigest) -ApproveGlobalHomeWrite
    $recoveryPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $interrupted.ExitCode -Message 'Blocked directory cleanup reports a recoverable failure'
    Assert-True -Condition (-not [IO.File]::Exists($target)) -Message 'Owned target deletion may complete before cleanup interruption'
    Assert-True -Condition ([IO.File]::Exists($stableTransaction)) -Message 'Recovery evidence survives cleanup interruption'
    Assert-Equal -Expected "user sentinel blocks cleanup`n" -Actual ([IO.File]::ReadAllText($blocker, [Text.Encoding]::UTF8)) -Message 'Cleanup interruption never deletes user bytes'
    Assert-Equal -Expected 'Conflict' -Actual ([string]$recoveryPlan.Data.status) -Message 'Interrupted cleanup exposes a recovery state'
    Assert-True -Condition ([bool]$recoveryPlan.Data.owned) -Message 'Interrupted cleanup retains owned evidence'

    [IO.File]::Delete($blocker)
    $resumed = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$recoveryPlan.Data.planDigest) -ApproveGlobalHomeWrite
    Assert-Equal -Expected 0 -Actual $resumed.ExitCode -Message 'Cleanup recovery Restore exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$resumed.Data.status) -Message 'Cleanup recovery Restore status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Cleanup recovery returns exact pre-install tree'
}

Run-Test -Name 'Restore rejects an ordinary file replacing its created leaf directory and remains resumable' -Body {
    $fixture = New-Fixture -Name 'restore-leaf-file-collision'
    $preexistingPlugins = Join-Path $fixture.Home '.codex\state\plugins'
    $null = New-Item -ItemType Directory -Path $preexistingPlugins -Force
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $targetDirectory = Join-Path $preexistingPlugins 'product-design'
    $target = Join-Path $targetDirectory 'user-context.md'
    $stableTransaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    [IO.File]::Delete($target)
    [IO.Directory]::Delete($targetDirectory, $false)
    Write-Utf8NoBom -Path $targetDirectory -Text "user leaf blocker`n"
    $restorePlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $blocked = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$restorePlan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 3 -Actual $blocked.ExitCode -Message 'Created leaf file collision Restore exit code'
    Assert-Equal -Expected 'Rejected' -Actual ([string]$blocked.Data.status) -Message 'Created leaf file collision Restore status'
    Assert-Equal -Expected "user leaf blocker`n" -Actual ([IO.File]::ReadAllText($targetDirectory, [Text.Encoding]::UTF8)) -Message 'Created leaf file collision stays byte-for-byte unchanged'
    Assert-True -Condition ([IO.File]::Exists($stableTransaction)) -Message 'Leaf collision retains stable recovery journal'

    [IO.File]::Delete($targetDirectory)
    $recoveryPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $resumed = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$recoveryPlan.Data.planDigest) -ApproveGlobalHomeWrite
    Assert-Equal -Expected 0 -Actual $resumed.ExitCode -Message 'Created leaf collision resumed Restore exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$resumed.Data.status) -Message 'Created leaf collision resumed Restore status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Created leaf collision recovery returns exact pre-install tree'
}

Run-Test -Name 'Restore rejects an ordinary file replacing its created parent directory and remains resumable' -Body {
    $fixture = New-Fixture -Name 'restore-parent-file-collision'
    $preexistingState = Join-Path $fixture.Home '.codex\state'
    $null = New-Item -ItemType Directory -Path $preexistingState -Force
    $before = Get-TreeSignature -Root $fixture.Home
    $installPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $null = Invoke-Adapter -Mode Install -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$installPlan.Data.planDigest) -ApproveGlobalHomeWrite
    $pluginsDirectory = Join-Path $preexistingState 'plugins'
    $targetDirectory = Join-Path $pluginsDirectory 'product-design'
    $target = Join-Path $targetDirectory 'user-context.md'
    $stableTransaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    [IO.File]::Delete($target)
    [IO.Directory]::Delete($targetDirectory, $false)
    [IO.Directory]::Delete($pluginsDirectory, $false)
    Write-Utf8NoBom -Path $pluginsDirectory -Text "user parent blocker`n"
    $restorePlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $blocked = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$restorePlan.Data.planDigest) -ApproveGlobalHomeWrite

    Assert-Equal -Expected 3 -Actual $blocked.ExitCode -Message 'Created parent file collision Restore exit code'
    Assert-Equal -Expected 'Rejected' -Actual ([string]$blocked.Data.status) -Message 'Created parent file collision Restore status'
    Assert-Equal -Expected "user parent blocker`n" -Actual ([IO.File]::ReadAllText($pluginsDirectory, [Text.Encoding]::UTF8)) -Message 'Created parent file collision stays byte-for-byte unchanged'
    Assert-True -Condition ([IO.File]::Exists($stableTransaction)) -Message 'Parent collision retains stable recovery journal'

    [IO.File]::Delete($pluginsDirectory)
    $recoveryPlan = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home
    $resumed = Invoke-Adapter -Mode Restore -BrainRoot $fixture.Brain -HomeRoot $fixture.Home -PlanDigest ([string]$recoveryPlan.Data.planDigest) -ApproveGlobalHomeWrite
    Assert-Equal -Expected 0 -Actual $resumed.ExitCode -Message 'Created parent collision resumed Restore exit code'
    Assert-Equal -Expected 'Restored' -Actual ([string]$resumed.Data.status) -Message 'Created parent collision resumed Restore status'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Created parent collision recovery returns exact pre-install tree'
}

Run-Test -Name 'Check rejects a HomeRoot dot-codex file before classifying descendants as Missing' -Body {
    $fixture = New-Fixture -Name 'home-dot-codex-file'
    $ancestorFile = Join-Path $fixture.Home '.codex'
    $stableTransaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    Write-Utf8NoBom -Path $ancestorFile -Text "user dot-codex file`n"
    $before = Get-TreeSignature -Root $fixture.Home
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'HomeRoot dot-codex file Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$check.Data.status) -Message 'HomeRoot dot-codex file state'
    Assert-Equal -Expected "user dot-codex file`n" -Actual ([IO.File]::ReadAllText($ancestorFile, [Text.Encoding]::UTF8)) -Message 'HomeRoot dot-codex file stays byte-for-byte unchanged'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'HomeRoot dot-codex file Check has zero writes'
    Assert-True -Condition (-not [IO.File]::Exists($stableTransaction)) -Message 'Unsafe HomeRoot ancestor creates no journal'
}

Run-Test -Name 'Check rejects a deeper HomeRoot state file before classifying descendants as Missing' -Body {
    $fixture = New-Fixture -Name 'home-state-file'
    $ancestorFile = Join-Path $fixture.Home '.codex\state'
    $stableTransaction = Join-Path $fixture.Home '.yohan-product-design-context.transaction.json'
    Write-Utf8NoBom -Path $ancestorFile -Text "user state file`n"
    $before = Get-TreeSignature -Root $fixture.Home
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'HomeRoot state file Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$check.Data.status) -Message 'HomeRoot state file state'
    Assert-Equal -Expected "user state file`n" -Actual ([IO.File]::ReadAllText($ancestorFile, [Text.Encoding]::UTF8)) -Message 'HomeRoot state file stays byte-for-byte unchanged'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'HomeRoot state file Check has zero writes'
    Assert-True -Condition (-not [IO.File]::Exists($stableTransaction)) -Message 'Unsafe deeper HomeRoot ancestor creates no journal'
}

Run-Test -Name 'Check rejects an ordinary file in a Brain source ancestor without touching either root' -Body {
    $fixture = New-Fixture -Name 'brain-source-ancestor-file'
    $rulesFile = Join-Path $fixture.Brain 'memory\rules\html-artifact-design.md'
    $rulesDirectory = Split-Path -Parent $rulesFile
    $memoryPath = Split-Path -Parent $rulesDirectory
    [IO.File]::Delete($rulesFile)
    [IO.Directory]::Delete($rulesDirectory, $false)
    [IO.Directory]::Delete($memoryPath, $false)
    Write-Utf8NoBom -Path $memoryPath -Text "brain ancestor file`n"
    $brainBefore = Get-TreeSignature -Root $fixture.Brain
    $homeBefore = Get-TreeSignature -Root $fixture.Home
    $check = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $check.ExitCode -Message 'Brain source ancestor file Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$check.Data.status) -Message 'Brain source ancestor file state'
    Assert-Equal -Expected "brain ancestor file`n" -Actual ([IO.File]::ReadAllText($memoryPath, [Text.Encoding]::UTF8)) -Message 'Brain source ancestor file stays byte-for-byte unchanged'
    Assert-Equal -Expected $brainBefore -Actual (Get-TreeSignature -Root $fixture.Brain) -Message 'Brain source ancestor Check has zero Brain writes'
    Assert-Equal -Expected $homeBefore -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Brain source ancestor Check has zero Home writes'
}

Run-Test -Name 'A junction above BrainRoot and HomeRoot is rejected without following it' -Body {
    $container = Join-Path $fixtureRoot 'ancestor-junction'
    $outside = Join-Path $fixtureRoot 'ancestor-junction-outside'
    $junction = Join-Path $container 'redirect'
    $brain = Join-Path $outside 'brain'
    $userHome = Join-Path $outside 'home'
    $null = New-Item -ItemType Directory -Path $container -Force
    $null = New-Item -ItemType Directory -Path $userHome -Force
    Write-Utf8NoBom -Path (Join-Path $brain 'memory\rules\html-artifact-design.md') -Text "external sentinel rules`n"
    Write-Utf8NoBom -Path (Join-Path $brain 'docs\reference\websites\ai-workspace-context-trust-navigator.md') -Text "external sentinel reference`n"
    $null = New-Item -ItemType Junction -Path $junction -Target $outside
    $result = Invoke-Adapter -Mode Check -BrainRoot (Join-Path $junction 'brain') -HomeRoot (Join-Path $junction 'home')

    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'Ancestor junction Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$result.Data.status) -Message 'Ancestor junction state'
    Assert-True -Condition (-not [IO.File]::Exists((Join-Path $userHome '.codex\state\plugins\product-design\user-context.md'))) -Message 'External target is not written'
}

Run-Test -Name 'An existing hard-link target is Unsafe and its external bytes stay unchanged' -Body {
    $fixture = New-Fixture -Name 'hardlink-target'
    $targetDirectory = Join-Path $fixture.Home '.codex\state\plugins\product-design'
    $target = Join-Path $targetDirectory 'user-context.md'
    $outside = Join-Path $fixture.Root 'external-user-context.md'
    $null = New-Item -ItemType Directory -Path $targetDirectory -Force
    Write-Utf8NoBom -Path $outside -Text "external hard-link sentinel`n"
    $null = New-Item -ItemType HardLink -Path $target -Target $outside
    $result = Invoke-Adapter -Mode Check -BrainRoot $fixture.Brain -HomeRoot $fixture.Home

    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'Hard-link target Check exit code'
    Assert-Equal -Expected 'Unsafe' -Actual ([string]$result.Data.status) -Message 'Hard-link target state'
    Assert-Equal -Expected "external hard-link sentinel`n" -Actual ([IO.File]::ReadAllText($outside, [Text.Encoding]::UTF8)) -Message 'External hard-link bytes stay unchanged'
}

Run-Test -Name 'Traversal-bearing root input fails closed without writes' -Body {
    $fixture = New-Fixture -Name 'invalid-roots'
    $before = Get-TreeSignature -Root $fixture.Home
    $traversal = Invoke-Adapter -Mode Check -BrainRoot (Join-Path $fixture.Brain '..\brain') -HomeRoot $fixture.Home

    Assert-Equal -Expected 'Unsafe' -Actual ([string]$traversal.Data.status) -Message 'Traversal root state'
    Assert-Equal -Expected $before -Actual (Get-TreeSignature -Root $fixture.Home) -Message 'Invalid roots cause no writes'
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
