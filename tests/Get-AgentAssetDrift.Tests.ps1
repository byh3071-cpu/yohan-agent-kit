#requires -Version 5.1

# Get-AgentAssetDrift.ps1 의 레포 스캔(-IncludeRepos) 계약 테스트.
# 가짜 킷 루트(레지스트리)·가짜 HomeRoot·가짜 DevRoot(repos.json + 가짜 레포)만 쓴다. 실제 홈·레포는 건드리지 않는다.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repoRoot 'scripts\Get-AgentAssetDrift.ps1'
$workRoot = Join-Path $PSScriptRoot '.work'
$fixtureRoot = Join-Path $workRoot ("asset-drift-{0}-{1}" -f (Get-Date -Format 'yyyyMMddHHmmssfff'), $PID)
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
$fixtureRoot = (Resolve-Path -LiteralPath $fixtureRoot).Path
$script:assertions = 0
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function New-FixtureFile {
    param([string]$Path, [string]$Content)
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    [IO.File]::WriteAllText($Path, $Content, $utf8)
}

function New-SkillAt {
    param([string]$Base, [string]$Vendor, [string]$Name, [string]$Body = 'body')
    New-FixtureFile (Join-Path $Base "$Vendor\skills\$Name\SKILL.md") "---`nname: $Name`n---`n$Body`n"
}

# 자식 프로세스로 실행해 stdout·stderr·종료코드를 따로 받는다(2>&1 은 PS 5.1 에서 오류 레코드로 감싸져 쓰지 않는다).
function Invoke-Drift {
    param([string[]]$Arguments, [hashtable]$Environment = @{})

    $all = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script,
        '-RepositoryRoot', $kitRoot, '-HomeRoot', $homeRoot) + $Arguments
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = (($all | ForEach-Object { if ($_ -match '[\s"]' ) { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    foreach ($key in $Environment.Keys) { $psi.EnvironmentVariables[$key] = [string]$Environment[$key] }

    $process = [Diagnostics.Process]::Start($psi)
    $errTask = $process.StandardError.ReadToEndAsync()
    $out = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ exit = $process.ExitCode; out = $out.Trim(); err = $errTask.Result.Trim() }
}

function ConvertTo-ExpectedAscii {
    param([string]$Json)
    return [regex]::Replace($Json, '[^\x00-\x7F]', { param($m) return ('\u{0:x4}' -f [int][char]$m.Value) })
}

function Get-TreeSnapshot {
    param([string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $hash = $(if ($_.PSIsContainer) { '-' } else { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
            '{0}|{1}|{2}' -f $_.FullName, $hash, $_.LastWriteTimeUtc.Ticks
        })
}

$zetaLink = $null
try {
    # ---- 가짜 킷 루트: 레지스트리만 있으면 된다 ----
    $kitRoot = Join-Path $fixtureRoot 'kit'
    $registry = [ordered]@{
        schemaVersion = 1
        assets        = @(
            [ordered]@{ id = 'skill.known-skill'; sourcePath = 'skills/known-skill' },
            [ordered]@{ id = 'project.reg-skill'; sourcePath = 'project://alpha/.claude/skills/reg-skill' },
            [ordered]@{ id = 'project.reg-agent'; sourcePath = 'project://alpha/.claude/agents/reg-agent.md' },
            [ordered]@{ id = 'project.aliased'; sourcePath = 'project://beta-alias/skills/aliased' }
        )
    }
    New-FixtureFile (Join-Path $kitRoot 'registry\assets.yaml') ($registry | ConvertTo-Json -Depth 5)

    # ---- 가짜 HomeRoot ----
    $homeRoot = Join-Path $fixtureRoot 'home'
    New-SkillAt $homeRoot '.claude' 'home-skill'
    New-SkillAt $homeRoot '.claude' 'known-skill'

    # ---- 가짜 DevRoot (환경변수 PUBLIC 기준 기본 탐색을 검증하려고 pub\dev 로 둔다) ----
    $publicRoot = Join-Path $fixtureRoot 'pub'
    $devRoot = Join-Path $publicRoot 'dev'
    $skillA = "---`nname: shared`n---`nsame body`n"

    # alpha: 등록/미등록 혼합, 벤더 폴더 간 사본, 한국어 이름 룰
    $alpha = Join-Path $devRoot 'products\alpha'
    New-SkillAt $alpha '.claude' 'reg-skill'
    New-SkillAt $alpha '.claude' 'new-skill'
    New-FixtureFile (Join-Path $alpha '.claude\skills\shared\SKILL.md') $skillA
    New-FixtureFile (Join-Path $alpha '.cursor\skills\shared\SKILL.md') ($skillA.Replace("`n", "`r`n"))
    New-FixtureFile (Join-Path $alpha '.claude\skills\twin\SKILL.md') "---`nname: twin`n---`nA`n"
    New-FixtureFile (Join-Path $alpha '.agents\skills\twin\SKILL.md') "---`nname: twin`n---`nA`n"
    New-FixtureFile (Join-Path $alpha '.claude\agents\reg-agent.md') "agent`n"
    New-FixtureFile (Join-Path $alpha '.claude\agents\free-agent.md') "agent`n"
    New-FixtureFile (Join-Path $alpha '.cursor\rules\한국어-룰.mdc') "룰 본문`n"
    New-FixtureFile (Join-Path $alpha '.cursor\rules\ignored.mdcx') "확장자 다름`n"
    New-SkillAt $alpha '.claude' '.hidden'
    New-FixtureFile (Join-Path $alpha '.claude\skills\holder\nested\.claude\skills\deep\SKILL.md') "깊은 곳`n"
    New-FixtureFile (Join-Path $alpha 'docs\.claude\skills\nope\SKILL.md') "루트 아래가 아님`n"

    # beta: local_path 사용 + aliases, alpha 의 shared 와 내용이 다른 사본
    $beta = Join-Path $devRoot 'custom\beta-dir'
    New-FixtureFile (Join-Path $beta '.agents\skills\shared\SKILL.md') "---`nname: shared`n---`nDIFFERENT body`n"
    New-SkillAt $beta '.claude' 'aliased'
    New-FixtureFile (Join-Path $beta '.claude\commands\cmd.md') "command`n"

    # many: 이름 10개 상한 검증용
    $many = Join-Path $devRoot 'automation\many'
    1..12 | ForEach-Object { New-SkillAt $many '.claude' ('skill-{0:d2}' -f $_) }

    # 대상 아님: games 그룹, archived, 폴더 없음(gamma), 링크 루트(zeta)
    New-SkillAt (Join-Path $devRoot 'games\delta') '.claude' 'game-skill'
    New-SkillAt (Join-Path $devRoot 'products\eps') '.claude' 'archived-skill'
    $zetaTarget = Join-Path $fixtureRoot 'zeta-target'
    New-SkillAt $zetaTarget '.claude' 'via-link'
    $zetaLink = Join-Path $devRoot 'products\zeta'
    $null = New-Item -ItemType Junction -Path $zetaLink -Target $zetaTarget

    $repoList = @(
        [ordered]@{ name = 'alpha'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'beta'; group = 'automation'; lifecycle = 'active'; local_path = 'custom/beta-dir'; aliases = @('beta-alias') },
        [ordered]@{ name = 'many'; group = 'automation'; lifecycle = 'active' },
        [ordered]@{ name = 'gamma'; group = 'yohan-ecosystem'; lifecycle = 'active' },
        [ordered]@{ name = 'delta'; group = 'games'; lifecycle = 'active' },
        [ordered]@{ name = 'eps'; group = 'products'; lifecycle = 'archived' },
        [ordered]@{ name = 'zeta'; group = 'products'; lifecycle = 'active' }
    )
    # root 는 일부러 없는 경로로 둔다: -DevRoot 를 주면 무시되고, 안 주면 존재하지 않아 DevRoot 로 되돌아가야 한다.
    $reposJson = [ordered]@{ schema = 'dev-repo-registry'; schema_version = 2; root = 'Z:/nonexistent-dev-root'; repos = $repoList }
    New-FixtureFile (Join-Path $devRoot 'repos.json') ($reposJson | ConvertTo-Json -Depth 5)

    $baselinePath = Join-Path $homeRoot '.yohan-agent-kit\asset-drift-baseline.json'
    $promptSuffix = ' — Intake 후보로 올릴지 판단 필요'

    # ---- (a) -IncludeRepos 없으면 기존 출력과 동일 (DevRoot 를 줘도 무시) ----
    $legacyJson = Invoke-Drift @('-OutputFormat', 'Json')
    Assert-True ($legacyJson.exit -eq 2) '(a) legacy Json exits 2 when unregistered exists'
    $expectedJson = '{"schemaVersion":1,"mode":"Drift","registeredCount":1,"unregisteredCount":1,"unregistered":[{"name":"home-skill","assetId":"skill.home-skill","roles":["Claude"],"linkedOnly":false}]}'
    Assert-True ($legacyJson.out -ceq $expectedJson) '(a) legacy Json output is byte-identical to the pre-change contract'
    $legacyIgnoresDev = Invoke-Drift @('-OutputFormat', 'Json', '-DevRoot', $devRoot)
    Assert-True ($legacyIgnoresDev.out -ceq $expectedJson) '(a) -DevRoot without -IncludeRepos changes nothing'

    $legacyHook = Invoke-Drift @('-OutputFormat', 'Hook')
    $expectedHook = ConvertTo-ExpectedAscii ('{"systemMessage":"새 에이전트 자산 1건이 킷 정본 밖에 있다: home-skill' + $promptSuffix + '"}')
    Assert-True ($legacyHook.exit -eq 0 -and $legacyHook.out -ceq $expectedHook) '(a) legacy Hook message is byte-identical'

    $legacyHuman = Invoke-Drift @()
    Assert-True (-not $legacyHuman.out.Contains('레포 자산')) '(a) legacy Human has no repo section'
    Assert-True ($legacyHuman.out.StartsWith('킷 레지스트리 등록: 1건 / 전체 미등록: 1건 / 미등록 보고: 1건')) '(a) legacy Human header unchanged'

    # ---- 스캔 전후 트리 스냅샷 (g 읽기 전용의 기준) ----
    $treeBefore = Get-TreeSnapshot $devRoot

    # ---- (b) 미등록 레포 자산이 잡힌다 (환경변수 PUBLIC 기준 기본 탐색) ----
    $childEnv = @{ PUBLIC = $publicRoot }
    $scan = Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos') $childEnv
    Assert-True ($scan.exit -eq 2) '(b) exit 2 with unregistered repo assets'
    $data = $scan.out | ConvertFrom-Json
    Assert-True ($data.unregisteredCount -eq 1 -and $data.unregistered[0].name -eq 'home-skill') '(b) home fields are kept as-is'
    $rs = $data.repoScan
    Assert-True ($rs.repos -eq 5) "(b) 5 target repos (alpha, beta, many, gamma, zeta; games and archived excluded), got $($rs.repos)"
    Assert-True (@($rs.missingRepos) -contains 'gamma' -and @($rs.missingRepos).Count -eq 1) '(b) missing repo listed'
    Assert-True (@($rs.linkedRepos) -contains 'zeta') '(b) junction repo root is skipped and reported'
    Assert-True (@($rs.assets | Where-Object { $_.repo -in @('delta', 'eps', 'zeta') }).Count -eq 0) '(b) excluded repos yield no assets'

    function Get-RepoAsset { param($Repo, $Kind, $Name) return ,@($rs.assets | Where-Object { $_.repo -eq $Repo -and $_.kind -eq $Kind -and $_.name -eq $Name }) }
    $newSkill = Get-RepoAsset 'alpha' 'skill' 'new-skill'
    Assert-True ($newSkill.Count -eq 1 -and -not $newSkill[0].registered -and -not $newSkill[0].inBaseline) '(b) unregistered repo skill detected as new'
    Assert-True ($newSkill[0].relativePath -eq '.claude/skills/new-skill' -and @($newSkill[0].vendorDirs) -contains '.claude') '(b) relativePath and vendorDirs reported'
    Assert-True (-not [string]::IsNullOrWhiteSpace($newSkill[0].digest) -and -not $newSkill[0].linkedOnly) '(b) digest present and not linked'
    Assert-True ((Get-RepoAsset 'alpha' 'agent' 'free-agent').Count -eq 1) '(b) agent found under .claude/agents'
    Assert-True ((Get-RepoAsset 'beta' 'command' 'cmd').Count -eq 1) '(b) command found under .claude/commands'
    Assert-True ((Get-RepoAsset 'alpha' 'rule' '한국어-룰').Count -eq 1) '(b) rule found under .cursor/rules'
    Assert-True ((Get-RepoAsset 'alpha' 'rule' 'ignored').Count -eq 0) '(b) .mdcx is not a rule'
    Assert-True ((Get-RepoAsset 'alpha' 'skill' '.hidden').Count -eq 0) '(b) dot-prefixed names are excluded'
    Assert-True ((Get-RepoAsset 'alpha' 'skill' 'deep').Count -eq 0 -and (Get-RepoAsset 'alpha' 'skill' 'nope').Count -eq 0) '(b) no recursion below the repo root'
    Assert-True ($scan.err -eq '') '(b) no warning when everything resolves'

    # ---- (d) project:// 등록 자산은 제외 ----
    $regSkill = Get-RepoAsset 'alpha' 'skill' 'reg-skill'
    Assert-True ($regSkill.Count -eq 1 -and $regSkill[0].registered) '(d) project:// skill is registered'
    Assert-True ((Get-RepoAsset 'alpha' 'agent' 'reg-agent')[0].registered) '(d) project:// agent is registered'
    Assert-True ((Get-RepoAsset 'beta' 'skill' 'aliased')[0].registered) '(d) alias + vendor-stripped project:// path is registered'
    $humanRepos = Invoke-Drift @('-IncludeRepos') $childEnv
    Assert-True ($humanRepos.out.Contains('레포 자산:') -and $humanRepos.out.Contains('없음: gamma')) '(d) Human shows repo section and missing list'
    Assert-True (-not $humanRepos.out.Contains('reg-skill') -and -not $humanRepos.out.Contains('reg-agent')) '(d) registered repo assets are not listed as unregistered'
    Assert-True ($humanRepos.out.Contains('new-skill') -and $humanRepos.out.Contains('내용 다름(diverged)')) '(d) Human lists unregistered and highlights diverged'

    # ---- (e) 사본 그룹 ----
    $shared = @($rs.groups | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'shared' })
    Assert-True ($shared.Count -eq 1 -and $shared[0].state -eq 'diverged') '(e) different content across repos is diverged'
    Assert-True (@($shared[0].repos) -contains 'alpha' -and @($shared[0].repos) -contains 'beta') '(e) group lists both repos'
    $twin = @($rs.groups | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'twin' })
    Assert-True ($twin.Count -eq 1 -and $twin[0].state -eq 'identical') '(e) same content across vendor folders is identical'
    $alphaShared = Get-RepoAsset 'alpha' 'skill' 'shared'
    Assert-True (@($alphaShared[0].vendorDirs).Count -eq 2) '(e) vendor copies inside one repo collapse into one asset'
    Assert-True (@($rs.groups | Where-Object { $_.name -eq 'new-skill' }).Count -eq 0) '(e) single copies form no group'

    # CRLF 만 다른 사본은 identical 이어야 한다(alpha 내부 .claude vs .cursor 는 shared 그룹의 일부라 별도 확인)
    $alphaOnly = @($rs.groups | Where-Object { $_.name -eq 'shared' })[0]
    Assert-True ($alphaOnly.state -eq 'diverged') '(e) diverged wins over identical pairs in one group'

    # ---- (c) 기준선: 넣으면 조용, 신규만 다시 잡힘 ----
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline') $childEnv
    $baselineText = [IO.File]::ReadAllText($baselinePath, $utf8)
    $baseline = $baselineText | ConvertFrom-Json
    $keys = @($baseline.knownUnregisteredRepoAssets)
    Assert-True ($keys.Count -eq 19) "(c) baseline stores 19 repo asset keys, got $($keys.Count)"
    Assert-True ($keys -contains 'skill.new-skill@alpha' -and $keys -contains 'rule.한국어-룰@alpha') '(c) keys use kind.name@repo'
    Assert-True ((@($keys | Sort-Object) -join '|') -ceq ($keys -join '|')) '(c) keys are sorted'
    Assert-True (@($baseline.knownUnregistered) -contains 'skill.home-skill') '(c) legacy knownUnregistered still written'

    $quiet = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos') $childEnv
    Assert-True ($quiet.exit -eq 0 -and $quiet.out -ceq '{"suppressOutput":true}') '(c) baseline makes Hook silent'
    $quietNewOnly = Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-NewOnly') $childEnv
    Assert-True ($quietNewOnly.exit -eq 0) '(c) -NewOnly exits 0 when nothing new'
    Assert-True ((($quietNewOnly.out | ConvertFrom-Json).repoScan.assets | Where-Object { $_.inBaseline }).Count -gt 0) '(c) inBaseline flag is reported'

    # -IncludeRepos 없는 -UpdateBaseline 은 레포 필드를 보존한다
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-UpdateBaseline')
    $preserved = [IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json
    Assert-True (@($preserved.knownUnregisteredRepoAssets).Count -eq 19) '(c) -UpdateBaseline without -IncludeRepos preserves the repo field'

    # 신규 자산 1건만 다시 알린다
    New-SkillAt $alpha '.claude' 'fresh-one'
    $fresh = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos') $childEnv
    $freshMessage = ($fresh.out | ConvertFrom-Json).systemMessage
    Assert-True ($freshMessage -ceq ('새 에이전트 자산 1건이 킷 정본 밖에 있다: alpha: fresh-one' + $promptSuffix)) "(c) only the new repo asset is announced: $freshMessage"
    # 방금 만든 파일의 디렉터리 mtime 이 안정된 뒤(=위 스캔 이후)에 스냅샷을 잡는다.
    $treeBefore = Get-TreeSnapshot $devRoot

    # 기준선이 옛 형식(레포 필드 없음)이면 새 필드 없이 갱신된다
    Remove-Item -LiteralPath $baselinePath -Force
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-UpdateBaseline')
    $oldStyle = [IO.File]::ReadAllText($baselinePath, $utf8)
    Assert-True (-not $oldStyle.Contains('knownUnregisteredRepoAssets')) '(c) legacy baseline shape is unchanged without -IncludeRepos'

    # ---- (h) 한국어 포함 Hook 출력은 ASCII 전용 + 10개 상한 ----
    Remove-Item -LiteralPath $baselinePath -Force
    $hook = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos') $childEnv
    Assert-True ($hook.exit -eq 0) '(h) Hook exits 0'
    Assert-True (@($hook.out.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0) '(h) Hook stdout is ASCII only'
    $hookMessage = ($hook.out | ConvertFrom-Json).systemMessage
    Assert-True ($hookMessage.Contains('홈: home-skill; alpha: ')) '(h) message groups names per repo, home first'
    Assert-True ($hookMessage.Contains('한국어-룰')) '(h) Korean asset name survives the round trip'
    Assert-True ($hookMessage.Contains('자산 21건') -and $hookMessage.Contains('외 11건')) "(h) names capped at 10 with remainder: $hookMessage"

    # ---- (f) repos.json 없음 / 레포 폴더 없음 ----
    $noRegistry = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', (Join-Path $fixtureRoot 'no-such-dev'))
    Assert-True ($noRegistry.exit -eq 0) '(f) missing repos.json does not fail the hook'
    Assert-True ($noRegistry.err.Contains('repos.json') -and @($noRegistry.err -split "`n").Count -eq 1) '(f) exactly one warning line on stderr'
    $noRegistryMessage = ($noRegistry.out | ConvertFrom-Json).systemMessage
    Assert-True ($noRegistryMessage -ceq ('새 에이전트 자산 1건이 킷 정본 밖에 있다: 홈: home-skill' + $promptSuffix)) '(f) home scan still runs'
    $noRegistryJson = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', (Join-Path $fixtureRoot 'no-such-dev'))).out | ConvertFrom-Json
    Assert-True ($noRegistryJson.repoScan.repos -eq 0 -and @($noRegistryJson.repoScan.warnings).Count -eq 1) '(f) Json carries the warning'
    $badRegistryDev = Join-Path $fixtureRoot 'bad-dev'
    New-FixtureFile (Join-Path $badRegistryDev 'repos.json') '{ 깨진 json'
    $badRegistry = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $badRegistryDev)
    Assert-True ($badRegistry.exit -eq 0 -and $badRegistry.err.Contains('repos.json')) '(f) unreadable repos.json warns and continues'

    # ---- (g) 읽기 전용: 스캔 전후 DevRoot 트리(파일 목록·해시·mtime) 동일 ----
    $null = Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-UpdateBaseline') $childEnv
    $null = Invoke-Drift @('-IncludeRepos', '-NewOnly') $childEnv
    $treeAfter = Get-TreeSnapshot $devRoot
    Assert-True (($treeBefore -join "`n") -ceq ($treeAfter -join "`n")) '(g) DevRoot tree is unchanged after scans'
    Assert-True ($treeBefore.Count -gt 20) '(g) snapshot is not trivially empty'

    Write-Output "PASS: $script:assertions assertions"
}
finally {
    $resolvedWork = (Resolve-Path -LiteralPath $workRoot).Path
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove unexpected test fixture' }
    # 링크는 대상까지 지우지 않도록 링크만 먼저 끊는다.
    if ($zetaLink -and [IO.Directory]::Exists($zetaLink)) { [IO.Directory]::Delete($zetaLink) }
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
