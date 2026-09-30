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
    param([string[]]$Arguments, [hashtable]$Environment = @{}, [string]$Kit = '')

    if (-not $Kit) { $Kit = $kitRoot }
    $all = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script,
        '-RepositoryRoot', $Kit, '-HomeRoot', $homeRoot) + $Arguments
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
$extraLinks = New-Object 'System.Collections.Generic.List[string]'

# 킷 루트(레지스트리만)를 만든다. Assets 는 hashtable 배열.
function New-KitRoot {
    param([string]$Name, $Assets)
    $path = Join-Path $fixtureRoot $Name
    New-FixtureFile (Join-Path $path 'registry\assets.yaml') ([ordered]@{ schemaVersion = 1; assets = @($Assets) } | ConvertTo-Json -Depth 5)
    return $path
}

# repos.json 만 있는 개발 루트. Repos 는 hashtable 배열.
function New-DevRootAt {
    param([string]$Path, $Repos, [string]$Root = 'Z:/nonexistent-dev-root')
    New-FixtureFile (Join-Path $Path 'repos.json') ([ordered]@{ schema = 'dev-repo-registry'; schema_version = 2; root = $Root; repos = @($Repos) } | ConvertTo-Json -Depth 5)
}
try {
    # ---- 가짜 킷 루트: 레지스트리만 있으면 된다 ----
    $kitRoot = Join-Path $fixtureRoot 'kit'
    $registry = [ordered]@{
        schemaVersion = 1
        assets        = @(
            [ordered]@{ id = 'skill.known-skill'; sourcePath = 'skills/known-skill' },
            [ordered]@{ id = 'project.reg-skill'; sourcePath = 'project://alpha/.claude/skills/reg-skill' },
            [ordered]@{ id = 'project.reg-agent'; sourcePath = 'project://alpha/.claude/agents/reg-agent.md' },
            [ordered]@{ id = 'project.aliased'; sourcePath = 'project://beta-alias/.claude/skills/aliased' },
            # 벤더 폴더를 뺀 형태는 등록으로 인정하지 않는다(정확 일치만).
            [ordered]@{ id = 'project.stripped'; sourcePath = 'project://alpha/skills/new-skill' },
            # 킷 자신을 가리키는 일반 상대 경로(킷 레포를 스캔할 때만 의미가 있다).
            [ordered]@{ id = 'rule.cursor-ecosystem'; sourcePath = '.cursor/rules/ecosystem.mdc' },
            # 이름 일치 판정: 로컬 파일이 있는 스킬 / 로컬 파일이 없는(external) 스킬
            [ordered]@{ id = 'skill.kit-skill'; sourcePath = 'skills/kit-skill' },
            [ordered]@{ id = 'skill.ext-skill'; sourcePath = 'external://example/ext-skill' },
            [ordered]@{ id = 'skill.multi-skill'; sourcePath = 'skills/multi-skill' },
            # 킷 루트 밖을 가리키는 sourcePath 는 비교 대상이 아니다.
            [ordered]@{ id = 'skill.esc-skill'; sourcePath = '../outside/esc-skill' }
        )
    }
    New-FixtureFile (Join-Path $kitRoot 'registry\assets.yaml') ($registry | ConvertTo-Json -Depth 5)

    $kitSkillBody = "---`nname: kit-skill`n---`nkit body`n"
    $multiBody = "---`nname: multi-skill`n---`nmulti kit body`n"
    New-FixtureFile (Join-Path $kitRoot 'skills\multi-skill\SKILL.md') $multiBody
    $escBody = "---`nname: esc-skill`n---`noutside body`n"
    New-FixtureFile (Join-Path $fixtureRoot 'outside\esc-skill\SKILL.md') $escBody
    New-FixtureFile (Join-Path $kitRoot 'skills\kit-skill\SKILL.md') $kitSkillBody

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
    New-FixtureFile (Join-Path $alpha '.claude\agents\.x.md') "점 파일`n"
    # 킷 파일과 내용이 같지만 CRLF 인 스킬 → 등록, 이름만 같은 external 스킬 → 표시만
    New-FixtureFile (Join-Path $alpha '.claude\skills\kit-skill\SKILL.md') $kitSkillBody.Replace("`n", "`r`n")
    New-SkillAt $alpha '.claude' 'ext-skill'
    # 벤더 사본 중 하나(.claude)만 킷과 같고 .agents 는 다르다 → 미등록
    New-FixtureFile (Join-Path $alpha '.claude\skills\multi-skill\SKILL.md') $multiBody
    New-FixtureFile (Join-Path $alpha '.agents\skills\multi-skill\SKILL.md') "---`nname: multi-skill`n---`nlocal edit`n"
    New-FixtureFile (Join-Path $alpha '.claude\skills\esc-skill\SKILL.md') $escBody
    # LF(.claude) 와 CRLF(.cursor) 만 있는 단독 그룹
    New-FixtureFile (Join-Path $alpha '.claude\skills\pair\SKILL.md') "---`nname: pair`n---`nP`n"
    New-FixtureFile (Join-Path $alpha '.cursor\skills\pair\SKILL.md') "---`r`nname: pair`r`n---`r`nP`r`n"

    # beta: local_path 사용 + aliases, alpha 의 shared 와 내용이 다른 사본
    $beta = Join-Path $devRoot 'custom\beta-dir'
    New-FixtureFile (Join-Path $beta '.agents\skills\shared\SKILL.md') "---`nname: shared`n---`nDIFFERENT body`n"
    New-SkillAt $beta '.claude' 'aliased'
    New-FixtureFile (Join-Path $beta '.claude\skills\kit-skill\SKILL.md') "---`nname: kit-skill`n---`nDIFFERENT from kit`n"
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
    Assert-True ((@($rs.assets | Where-Object { $_.name.StartsWith('.') })).Count -eq 0) '(b) dot-prefixed agent files (.claude/agents/.x.md) are excluded'
    Assert-True ((Get-RepoAsset 'alpha' 'skill' 'deep').Count -eq 0 -and (Get-RepoAsset 'alpha' 'skill' 'nope').Count -eq 0) '(b) no recursion below the repo root'
    Assert-True ($scan.err -eq '') '(b) no warning when everything resolves'

    # ---- (d) project:// 등록 자산은 제외 ----
    $regSkill = Get-RepoAsset 'alpha' 'skill' 'reg-skill'
    Assert-True ($regSkill.Count -eq 1 -and $regSkill[0].registered) '(d) project:// skill is registered'
    Assert-True ((Get-RepoAsset 'alpha' 'agent' 'reg-agent')[0].registered) '(d) project:// agent is registered'
    Assert-True ((Get-RepoAsset 'beta' 'skill' 'aliased')[0].registered) '(d) alias + exact project:// path is registered'
    Assert-True (-not (Get-RepoAsset 'alpha' 'skill' 'new-skill')[0].registered) '(d) vendor-stripped project:// path (repo/skills/name) is NOT accepted'
    # 이름 일치 판정(B안): 내용 해시가 같아야 등록, 다르거나 비교할 로컬 파일이 없으면 표시만
    $kitSame = (Get-RepoAsset 'alpha' 'skill' 'kit-skill')[0]
    Assert-True ($kitSame.registered -and -not $kitSame.nameMatchesKit) '(d) same content as the kit file (CRLF-normalized) is registered'
    $kitDiff = (Get-RepoAsset 'beta' 'skill' 'kit-skill')[0]
    Assert-True (-not $kitDiff.registered -and $kitDiff.nameMatchesKit) '(d) same name but different content is not registered, only flagged'
    $extName = (Get-RepoAsset 'alpha' 'skill' 'ext-skill')[0]
    Assert-True (-not $extName.registered -and $extName.nameMatchesKit) '(d) external:// sourcePath cannot be compared, so only flagged'
    Assert-True (-not (Get-RepoAsset 'alpha' 'skill' 'new-skill')[0].nameMatchesKit) '(d) plain unregistered skill has no name match flag'
    $multi = (Get-RepoAsset 'alpha' 'skill' 'multi-skill')[0]
    Assert-True (@($multi.vendorDirs).Count -eq 2 -and -not $multi.registered -and $multi.nameMatchesKit) '(1) only one vendor copy equals the kit body: not registered, flagged'
    $esc = (Get-RepoAsset 'alpha' 'skill' 'esc-skill')[0]
    Assert-True (-not $esc.registered -and $esc.nameMatchesKit) '(7) a kit sourcePath that escapes the kit root (../) never registers'
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
    $pair = @($rs.groups | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'pair' })
    Assert-True ($pair.Count -eq 1 -and $pair[0].state -eq 'identical') '(e) a lone LF(.claude) vs CRLF(.cursor) pair is identical'

    # CRLF 만 다른 사본은 identical 이어야 한다(alpha 내부 .claude vs .cursor 는 shared 그룹의 일부라 별도 확인)
    $alphaOnly = @($rs.groups | Where-Object { $_.name -eq 'shared' })[0]
    Assert-True ($alphaOnly.state -eq 'diverged') '(e) diverged wins over identical pairs in one group'

    # ---- (c) 기준선: 넣으면 조용, 신규만 다시 잡힘 ----
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline') $childEnv
    $baselineText = [IO.File]::ReadAllText($baselinePath, $utf8)
    $baseline = $baselineText | ConvertFrom-Json
    $keys = @($baseline.knownUnregisteredRepoAssets)
    Assert-True ($keys.Count -eq 24) "(c) baseline stores 24 repo asset keys, got $($keys.Count)"
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
    Assert-True (@($preserved.knownUnregisteredRepoAssets).Count -eq 24) '(c) -UpdateBaseline without -IncludeRepos preserves the repo field'

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
    Assert-True ($hookMessage.Contains('자산 26건') -and $hookMessage.Contains('외 16건')) "(h) names capped at 10 with remainder: $hookMessage"

    # ---- (f) repos.json 없음 / 레포 폴더 없음 ----
    $noRegistry = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', (Join-Path $fixtureRoot 'no-such-dev'))
    Assert-True ($noRegistry.exit -eq 0) '(f) missing repos.json does not fail the hook'
    Assert-True ($noRegistry.err.Contains('repos.json') -and @($noRegistry.err -split "`n").Count -eq 1) '(f) exactly one warning line on stderr'
    $noRegistryMessage = ($noRegistry.out | ConvertFrom-Json).systemMessage
    Assert-True ($noRegistryMessage -ceq ('새 에이전트 자산 1건이 킷 정본 밖에 있다: 홈: home-skill' + $promptSuffix + ' / 레포 스캔 건너뜀(repos.json 없음)')) '(f) home scan still runs and the whole-scan skip is worded differently'
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


    # ================= 적대 검증 후속 결함 =================

    # ---- 결함1: HashSet 을 return 하면 원소로 풀리는 문제 (project:// 0개·1개·대문자 레포명) ----
    $kit0 = New-KitRoot 'kit0' @([ordered]@{ id = 'skill.known-skill'; sourcePath = 'skills/known-skill' }, [ordered]@{ id = 'skill.other'; sourcePath = 'skills/other' })
    $d0 = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $devRoot) @{} $kit0).out | ConvertFrom-Json
    Assert-True (@($d0.repoScan.warnings).Count -eq 0 -and $d0.repoScan.repos -eq 5) '(1) zero project:// sources: repo scan still runs without an exception'
    Assert-True (@($d0.repoScan.assets | Where-Object { $_.name -eq 'new-skill' -and -not $_.registered }).Count -eq 1) '(1) zero project:// sources: nothing is registered by accident'

    $kit1 = New-KitRoot 'kit1' @([ordered]@{ id = 'project.x'; sourcePath = 'project://xalpha/.claude/skills/new-skill' })
    $d1 = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $devRoot) @{} $kit1).out | ConvertFrom-Json
    Assert-True (@($d1.repoScan.assets | Where-Object { $_.name -eq 'new-skill' -and $_.registered }).Count -eq 0) '(1) one project:// source: no substring match (xalpha must not register alpha)'

    $kit2 = New-KitRoot 'kit2' @([ordered]@{ id = 'project.a'; sourcePath = 'project://ALPHA/.claude/skills/reg-skill' }, [ordered]@{ id = 'project.x'; sourcePath = 'project://xalpha/.claude/skills/new-skill' })
    $d2 = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $devRoot) @{} $kit2).out | ConvertFrom-Json
    Assert-True (@($d2.repoScan.assets | Where-Object { $_.name -eq 'reg-skill' -and $_.registered }).Count -eq 1) '(1) uppercase repo name in project:// matches case-insensitively'
    Assert-True (@($d2.repoScan.assets | Where-Object { $_.name -eq 'new-skill' -and $_.registered }).Count -eq 0) '(1) longer sibling repo name still does not match'

    # 홈 쪽: id 1개짜리 레지스트리에서 부분 문자열로 등록되면 안 된다
    $kit3 = New-KitRoot 'kit3' @([ordered]@{ id = 'skill.home-skill-long'; sourcePath = 'skills/home-skill-long' })
    $d3 = (Invoke-Drift @('-OutputFormat', 'Json') @{} $kit3).out | ConvertFrom-Json
    Assert-True (@($d3.unregistered | Where-Object { $_.name -eq 'home-skill' }).Count -eq 1) '(1) single-id registry: home-skill is not a substring match of home-skill-long'

    # ---- 결함6b: 실존 root 와 -DevRoot 를 같이 줬을 때 우선순위 ----
    $rootDev = Join-Path $fixtureRoot 'root-dev'
    New-SkillAt (Join-Path $rootDev 'products\probe') '.claude' 'from-root'
    $pub2 = Join-Path $fixtureRoot 'pub2'
    $dev2 = Join-Path $pub2 'dev'
    New-SkillAt (Join-Path $dev2 'products\probe') '.claude' 'from-devroot'
    New-DevRootAt $dev2 @([ordered]@{ name = 'probe'; group = 'products'; lifecycle = 'active' }) $rootDev.Replace('\', '/')
    $explicit = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $dev2)).out | ConvertFrom-Json
    $explicitNames = @($explicit.repoScan.assets | ForEach-Object { $_.name })
    Assert-True (($explicitNames -contains 'from-devroot') -and -not ($explicitNames -contains 'from-root')) '(6b) explicit -DevRoot wins over an existing repos.json root'
    $implicit = (Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos') @{ PUBLIC = $pub2 }).out | ConvertFrom-Json
    $implicitNames = @($implicit.repoScan.assets | ForEach-Object { $_.name })
    Assert-True (($implicitNames -contains 'from-root') -and -not ($implicitNames -contains 'from-devroot')) '(6b) without -DevRoot the existing repos.json root is the path base'

    # ---- 결함2·3·6e: 스캔 실패·일부 실패와 -UpdateBaseline ----
    $dev3 = Join-Path $fixtureRoot 'pub3\dev'
    New-SkillAt (Join-Path $dev3 'products\okrepo') '.claude' 's1'
    New-DevRootAt $dev3 @(
        [ordered]@{ name = 'okrepo'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'badpath'; group = 'products'; lifecycle = 'active'; local_path = 'a<b>|c' },
        [ordered]@{ name = 'gone'; group = 'automation'; lifecycle = 'active' })
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":[],"knownUnregisteredRepoAssets":["skill.stale@okrepo","skill.old@badpath","skill.g@gone"]}'
    $partial = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', $dev3)
    Assert-True ($partial.exit -eq 0) '(3) a bad repo does not fail the hook'
    Assert-True (@($partial.out.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0) '(3) partial-skip Hook message is ASCII only'
    Assert-True ((($partial.out | ConvertFrom-Json).systemMessage).Contains('(레포 스캔 일부 건너뜀 1건)')) '(3) Hook reports how many repos were skipped'
    Assert-True ($partial.err.Contains('badpath')) '(3) the failing repo is named in the warning'
    $partialKeys = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    Assert-True ($partialKeys.Count -eq 3 -and ($partialKeys -contains 'skill.s1@okrepo')) '(2) scanned repo keys are refreshed'
    Assert-True (($partialKeys -contains 'skill.old@badpath') -and ($partialKeys -contains 'skill.g@gone')) '(2) keys of failed and missing repos are preserved'
    Assert-True (-not ($partialKeys -contains 'skill.stale@okrepo')) '(2) stale keys of successfully scanned repos are dropped'
    $noNew = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $dev3)
    Assert-True ((($noNew.out | ConvertFrom-Json).systemMessage) -ceq '레포 스캔 일부 건너뜀 1건') '(3) zero new assets but a skipped repo still produces a message'

    $before = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    $failedScan = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', (Join-Path $fixtureRoot 'nope3'))
    Assert-True ($failedScan.exit -eq 0) '(2) failed scan + -UpdateBaseline exits 0'
    $after = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    Assert-True ($after.Count -eq 3 -and (($before | Sort-Object) -join '|') -ceq (($after | Sort-Object) -join '|')) '(2) failed scan keeps the repo baseline exactly as it was'

    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":[],"knownUnregisteredRepoAssets":null}'
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', (Join-Path $fixtureRoot 'nope3'))
    $nullText = [IO.File]::ReadAllText($baselinePath, $utf8)
    Assert-True ((-not $nullText.Contains('""')) -and @(($nullText | ConvertFrom-Json).knownUnregisteredRepoAssets).Count -eq 0) '(10) null baseline field is saved as [] not [""]'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $baselinePath) -Filter '*.tmp-*').Count -eq 0) '(10) no temporary baseline file is left behind'

    $humanWarn = Invoke-Drift @('-IncludeRepos', '-DevRoot', (Join-Path $fixtureRoot 'nope3'))
    Assert-True ($humanWarn.err -eq '' -and [regex]::Matches($humanWarn.out, '경고:').Count -eq 1) '(10) Human prints the warning once (stdout only)'

    # ---- repos.json 형태 이상 ----
    $shapeCase = 0
    foreach ($content in @('[]', 'null', '', '{"repos":{}}', '[{"name":"a"}]')) {
        $shapeCase++
        $shapeDev = Join-Path $fixtureRoot "shape$shapeCase"
        New-FixtureFile (Join-Path $shapeDev 'repos.json') $content
        $shape = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $shapeDev)
        Assert-True ($shape.exit -eq 0 -and $shape.err.Contains('repos.json')) "(10) malformed repos.json case $shapeCase warns and exits 0"
    }

    # ---- 결함5·7·8·10: 킷 자신·이름/별칭 충돌·링크 폴더·unknown ----
    $dev4 = Join-Path $fixtureRoot 'pub4\dev'
    New-SkillAt (Join-Path $dev4 'products\a1') '.claude' 'c1'
    New-SkillAt (Join-Path $dev4 'products\a2') '.claude' 'c2'
    $a3 = Join-Path $dev4 'products\a3'
    New-SkillAt $a3 '.claude' 's3'
    New-SkillAt $a3 '.claude' 'lk' 'lk body'
    $cursorTarget = Join-Path $fixtureRoot 'cursor-target'
    New-FixtureFile (Join-Path $cursorTarget 'skills\hidden-by-link\SKILL.md') "숨은 스킬`n"
    $null = New-Item -ItemType Junction -Path (Join-Path $a3 '.cursor') -Target $cursorTarget
    $extraLinks.Add((Join-Path $a3 '.cursor'))
    $other = Join-Path $dev4 'products\other-repo'
    New-FixtureFile (Join-Path $other '.cursor\rules\ecosystem.mdc') "eco`n"
    $lkTarget = Join-Path $fixtureRoot 'lk-target'
    New-FixtureFile (Join-Path $lkTarget 'SKILL.md') "lk body`n"
    $null = New-Item -ItemType Directory -Path (Join-Path $other '.claude\skills') -Force
    $null = New-Item -ItemType Junction -Path (Join-Path $other '.claude\skills\lk') -Target $lkTarget
    $extraLinks.Add((Join-Path $other '.claude\skills\lk'))
    New-FixtureFile (Join-Path $dev4 'automation\kit-copy\.cursor\rules\ecosystem.mdc') "eco`n"
    New-DevRootAt $dev4 @(
        [ordered]@{ name = 'a1'; group = 'products'; lifecycle = 'active'; aliases = @('x-alias') },
        [ordered]@{ name = 'a2'; group = 'products'; lifecycle = 'active'; aliases = @('x-alias') },
        [ordered]@{ name = 'a3'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'other-repo'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'yohan-cc-skills'; group = 'automation'; lifecycle = 'active'; local_path = 'automation/kit-copy' })
    $scan4 = Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $dev4)
    $rs4 = ($scan4.out | ConvertFrom-Json).repoScan
    Assert-True ((@($rs4.failedRepos) -join ',') -eq 'a1,a2' -and @($rs4.warnings).Count -eq 2) '(7) aliases shared by two repos: both are skipped with a warning'
    Assert-True (@($rs4.assets | Where-Object { $_.repo -in @('a1', 'a2') }).Count -eq 0) '(7) conflicting repos yield no assets'
    Assert-True (@($rs4.assets | Where-Object { $_.repo -eq 'a3' -and $_.name -eq 's3' }).Count -eq 1) '(7) a healthy repo is still scanned'
    Assert-True ((@($rs4.skippedLinks) -contains 'a3/.cursor') -and @($rs4.assets | Where-Object { $_.name -eq 'hidden-by-link' }).Count -eq 0) '(8) a linked vendor folder is not followed and is recorded'
    $kitCopyRule = @($rs4.assets | Where-Object { $_.repo -eq 'yohan-cc-skills' -and $_.name -eq 'ecosystem' })
    Assert-True ($kitCopyRule.Count -eq 1 -and $kitCopyRule[0].registered) '(5) kit repo: a plain relative sourcePath registers the asset by repo name'
    $otherRule = @($rs4.assets | Where-Object { $_.repo -eq 'other-repo' -and $_.name -eq 'ecosystem' })
    Assert-True ($otherRule.Count -eq 1 -and -not $otherRule[0].registered) '(5) non-kit repo with the same relative path is not registered'
    $lkGroup = @($rs4.groups | Where-Object { $_.name -eq 'lk' })
    Assert-True ($lkGroup.Count -eq 1 -and $lkGroup[0].state -eq 'unknown') '(10) a group with a member that has no hash is unknown'

    # ---- 결함10: Hook 모드 catch 는 ASCII systemMessage + exit 0, Json 은 기존 그대로(exit 1) ----
    $brokenKit = Join-Path $fixtureRoot 'kit-broken'
    New-FixtureFile (Join-Path $brokenKit 'registry\assets.yaml') '{ 깨진'
    $hookCatch = Invoke-Drift @('-OutputFormat', 'Hook') @{} $brokenKit
    Assert-True ($hookCatch.exit -eq 0 -and @($hookCatch.out.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0) '(10) Hook failure is an ASCII message with exit 0'
    Assert-True ((($hookCatch.out | ConvertFrom-Json).systemMessage).StartsWith('드리프트 검사 실패:')) '(10) Hook failure message says the check failed'
    $jsonCatch = Invoke-Drift @('-OutputFormat', 'Json') @{} $brokenKit
    Assert-True ($jsonCatch.exit -eq 1 -and $jsonCatch.out.Contains('"error"')) '(10) Json failure keeps exit 1 and the error field'

    # ================= 2차 적대 검증(낮음) 후속 =================

    # ---- 2·6: 대상 레포가 0개면 스캔 실패와 똑같이 기준선을 보존하고, 문구는 "일부 건너뜀"과 다르다 ----
    $dev5 = Join-Path $fixtureRoot 'pub5\dev'
    New-DevRootAt $dev5 @([ordered]@{ name = 'only-game'; group = 'games'; lifecycle = 'active' })
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":[],"knownUnregisteredRepoAssets":["skill.a@r1","skill.b@r2"]}'
    $zero = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', $dev5)
    Assert-True ($zero.exit -eq 0 -and $zero.err.Contains('0')) '(2) zero target repos warns and exits 0'
    Assert-True ((($zero.out | ConvertFrom-Json).systemMessage).EndsWith(' / 레포 스캔 건너뜀(대상 레포 0개)')) '(6) whole-scan skip is worded "건너뜀(원인)" not "일부 건너뜀"'
    $zeroKeys = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    Assert-True ($zeroKeys.Count -eq 2 -and ($zeroKeys -contains 'skill.a@r1') -and ($zeroKeys -contains 'skill.b@r2')) '(2) zero target repos keeps the whole repo baseline'
    $zeroAlone = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $dev5)
    Assert-True ((($zeroAlone.out | ConvertFrom-Json).systemMessage) -ceq '레포 스캔 건너뜀(대상 레포 0개)') '(6) whole-scan skip message stands alone when nothing is new'
    Assert-True (-not (($zeroAlone.out | ConvertFrom-Json).systemMessage).Contains('일부')) '(6) whole-scan skip never says partial'

    # ---- 3: 옛 이름이 별칭으로 남은 경우 ----
    $dev6 = Join-Path $fixtureRoot 'pub6\dev'
    New-SkillAt (Join-Path $dev6 'products\newname') '.claude' 's6'
    New-DevRootAt $dev6 @(
        [ordered]@{ name = 'newname'; group = 'products'; lifecycle = 'active'; aliases = @('oldname') },
        [ordered]@{ name = 'gone6'; group = 'automation'; lifecycle = 'active'; aliases = @('oldgone') })
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":["skill.home-skill"],"knownUnregisteredRepoAssets":["skill.s6@oldname","skill.g@oldgone"]}'
    $aliasQuiet = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $dev6)
    Assert-True ($aliasQuiet.exit -eq 0 -and $aliasQuiet.out -ceq '{"suppressOutput":true}') '(3) a key stored under the old repo name still counts as known (inBaseline via alias)'
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', $dev6)
    $aliasKeys = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    Assert-True ($aliasKeys.Count -eq 2 -and ($aliasKeys -contains 'skill.s6@newname') -and ($aliasKeys -contains 'skill.g@gone6')) '(3) saved keys are rewritten to the current repo name (scanned and preserved alike)'

    # ---- 4: 비대상(archived) 레포의 별칭 때문에 활성 레포가 건너뛰어지지 않는다 ----
    $dev7 = Join-Path $fixtureRoot 'pub7\dev'
    New-SkillAt (Join-Path $dev7 'products\act7') '.claude' 's7'
    New-DevRootAt $dev7 @(
        [ordered]@{ name = 'act7'; group = 'products'; lifecycle = 'active'; aliases = @('shared7') },
        [ordered]@{ name = 'arch7'; group = 'products'; lifecycle = 'archived'; aliases = @('shared7') })
    $rs7 = ((Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $dev7)).out | ConvertFrom-Json).repoScan
    Assert-True (@($rs7.failedRepos).Count -eq 0 -and @($rs7.warnings).Count -eq 0 -and @($rs7.assets | Where-Object { $_.name -eq 's7' }).Count -eq 1) '(4) an archived repo sharing an alias does not block the active repo'

    # ---- 7: 링크 레포·벤더 링크 레포의 기존 키는 -UpdateBaseline 뒤에도 남는다 ----
    $dev8 = Join-Path $fixtureRoot 'pub8\dev'
    New-SkillAt (Join-Path $dev8 'products\okrepo8') '.claude' 's8'
    New-SkillAt (Join-Path $dev8 'products\vlink') '.claude' 'vs'
    $null = New-Item -ItemType Junction -Path (Join-Path $dev8 'products\vlink\.cursor') -Target $cursorTarget
    $extraLinks.Add((Join-Path $dev8 'products\vlink\.cursor'))
    $linkRepoTarget = Join-Path $fixtureRoot 'link8-target'
    New-SkillAt $linkRepoTarget '.claude' 'l'
    $null = New-Item -ItemType Junction -Path (Join-Path $dev8 'products\linkrepo') -Target $linkRepoTarget
    $extraLinks.Add((Join-Path $dev8 'products\linkrepo'))
    New-DevRootAt $dev8 @(
        [ordered]@{ name = 'okrepo8'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'linkrepo'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'vlink'; group = 'products'; lifecycle = 'active' })
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":[],"knownUnregisteredRepoAssets":["skill.l@linkrepo","skill.v@vlink","skill.stale@okrepo8"]}'
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', $dev8)
    $linkKeys = @(([IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json).knownUnregisteredRepoAssets)
    Assert-True ($linkKeys -contains 'skill.l@linkrepo') '(7) a linked repo root keeps its previous baseline key'
    Assert-True (($linkKeys -contains 'skill.v@vlink') -and ($linkKeys -contains 'skill.vs@vlink')) '(7) a repo with a linked vendor folder keeps old keys and gains the scanned one'
    Assert-True (($linkKeys -contains 'skill.s8@okrepo8') -and -not ($linkKeys -contains 'skill.stale@okrepo8')) '(7) fully scanned repos are refreshed (stale key dropped)'
    # ================= 관리 마커(다른 도구가 관리하는 자산) =================
    $rosterBlock = "---`nalwaysApply: true`n---`n앞 내용`n<!-- YOHAN-ROSTER-CARD:BEGIN sha=abc -->`n카드 본문`n<!-- YOHAN-ROSTER-CARD:END -->`n뒤 내용`n"
    $ecoBlock = { param($v) "<!-- ECOSYSTEM-MDC:START v$v -->`n경계 규칙`n<!-- ECOSYSTEM-MDC:END -->`n" }
    $projMarker = '<!-- vhk-agent-skill: proj@2 source=.agents/skills/proj sha256=0123abcdEF -->'
    $dev9 = Join-Path $fixtureRoot 'pub9\dev'
    $r1 = Join-Path $dev9 'products\m1'
    # 로스터 카드: 파일 중간에 마커 + CRLF
    New-FixtureFile (Join-Path $r1 '.cursor\rules\agent-roster.mdc') $rosterBlock.Replace("`n", "`r`n")
    New-FixtureFile (Join-Path $r1 '.cursor\rules\ecosystem.mdc') (& $ecoBlock 3)
    # 투영본: .claude 에 마커, .agents(VHK 정본)엔 마커 없음 → 관리
    New-FixtureFile (Join-Path $r1 '.claude\skills\proj\SKILL.md') "---`nname: proj`n---`n$projMarker`n본문`n"
    New-FixtureFile (Join-Path $r1 '.agents\skills\proj\SKILL.md') "---`nname: proj`n---`n본문`n"
    New-SkillAt $r1 '.claude' 'plain-one'
    New-FixtureFile (Join-Path $dev9 'products\m2\.cursor\rules\ecosystem.mdc') ((& $ecoBlock 3).Replace("`n", "`r`n"))
    New-FixtureFile (Join-Path $dev9 'products\m3\.cursor\rules\ecosystem.mdc') (& $ecoBlock 2)
    New-FixtureFile (Join-Path $dev9 'products\m4\.cursor\rules\ecosystem.mdc') (& $ecoBlock 3)
    # 마커가 일부 사본에만 있음(.cursor 에 마커 없는 사본) → 관리 아님
    $r5 = Join-Path $dev9 'products\m5'
    New-FixtureFile (Join-Path $r5 '.claude\skills\half\SKILL.md') "---`nname: half`n---`n$projMarker`n"
    New-FixtureFile (Join-Path $r5 '.cursor\skills\half\SKILL.md') "---`nname: half`n---`n사람이 만든 사본`n"
    # 비슷하지만 다른 문자열 → 인식하지 않음
    New-FixtureFile (Join-Path $r5 '.cursor\rules\begin-only.mdc') "<!-- BEGIN -->`n본문`n"
    New-FixtureFile (Join-Path $r5 '.cursor\rules\other-card.mdc') "<!-- ROSTER-CARD:BEGIN -->`n본문`n"
    New-FixtureFile (Join-Path $r5 '.cursor\rules\eco-end.mdc') "<!-- ECOSYSTEM-MDC:END v3 -->`n본문`n"
    New-FixtureFile (Join-Path $r5 '.cursor\rules\prose.mdc') "설명: ``<!-- YOHAN-ROSTER-CARD:BEGIN`` 마커를 쓴다`n"
    New-FixtureFile (Join-Path $r5 '.cursor\rules\suffix.mdc') "<!-- YOHAN-ROSTER-CARD:BEGINNING -->`n"
    New-FixtureFile (Join-Path $r5 '.claude\skills\badproj\SKILL.md') "---`nname: badproj`n---`n<!-- vhk-agent-skill: badproj@1 source=x -->`n"
    New-DevRootAt $dev9 @(
        [ordered]@{ name = 'm1'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'm2'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'm3'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'm4'; group = 'products'; lifecycle = 'active' },
        [ordered]@{ name = 'm5'; group = 'products'; lifecycle = 'active' })
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":["skill.home-skill"]}'
    $scan9 = Invoke-Drift @('-OutputFormat', 'Json', '-IncludeRepos', '-DevRoot', $dev9)
    $rs9 = ($scan9.out | ConvertFrom-Json).repoScan
    $byName = { param($repo, $name) , @($rs9.assets | Where-Object { $_.repo -eq $repo -and $_.name -eq $name }) }
    $roster = & $byName 'm1' 'agent-roster'
    Assert-True ($roster.Count -eq 1 -and $roster[0].managedBy -ceq 'yohan-brain-roster' -and $roster[0].managedVersion -ceq '') 'managed: roster marker in the middle of a CRLF file is recognized'
    $eco3 = & $byName 'm1' 'ecosystem'
    Assert-True ($eco3.Count -eq 1 -and $eco3[0].managedBy -ceq 'vhk-template' -and $eco3[0].managedVersion -ceq 'v3') 'managed: ECOSYSTEM-MDC marker gives template version v3'
    $eco2 = & $byName 'm2' 'ecosystem'
    Assert-True ($eco2[0].managedBy -ceq 'vhk-template' -and $eco2[0].managedVersion -ceq 'v3') 'managed: CRLF ecosystem file is recognized'
    Assert-True ((& $byName 'm3' 'ecosystem')[0].managedVersion -ceq 'v2') 'managed: version is parsed per file (v2 is not forced to v3)'
    $proj = & $byName 'm1' 'proj'
    Assert-True ($proj.Count -eq 1 -and $proj[0].managedBy -ceq 'vhk-projection' -and $proj[0].managedSource -ceq '.agents/skills/proj' -and (@($proj[0].vendorDirs) -join ',') -ceq '.claude,.agents') 'managed: vhk projection with unmarked .agents canonical copy is managed and keeps source'
    Assert-True ((& $byName 'm1' 'plain-one')[0].managedBy -ceq '') 'managed: an asset without any marker stays unmanaged'
    Assert-True ((& $byName 'm5' 'half')[0].managedBy -ceq '') 'managed: marker on only some copies (unmarked non-.agents copy) is NOT managed'
    foreach ($fake in @('begin-only', 'other-card', 'eco-end', 'prose', 'suffix', 'badproj')) {
        Assert-True ((& $byName 'm5' $fake)[0].managedBy -ceq '') "managed: lookalike '$fake' is not recognized"
    }
    Assert-True ($rs9.managedCount -eq 6) 'managed: Json managedCount counts only recognized assets (roster, 4 ecosystem, proj)'
    Assert-True ($rs9.unregisteredCount -eq 8) 'managed: managed assets are removed from the unregistered count'
    $tpl = @($rs9.managedSummary | Where-Object { $_.managedBy -eq 'vhk-template' })
    Assert-True ($tpl.Count -eq 1 -and $tpl[0].count -eq 4 -and $tpl[0].latestVersion -ceq 'v3' -and (@($tpl[0].outdatedRepos) -join ',') -ceq 'm3') 'managed: version mix marks the older repo (m3) as outdated'
    $human9 = Invoke-Drift @('-IncludeRepos', '-DevRoot', $dev9)
    Assert-True ($human9.out.Contains('다른 도구가 관리함') -and $human9.out.Contains('VHK 경계 규칙 v3 3곳 · v2 1곳(m3)')) 'managed: Human shows the version distribution with the old repo'
    Assert-True ($human9.out.Contains('yohan-brain 라우팅 카드 1건') -and $human9.out.Contains('VHK 스킬 투영본 1건')) 'managed: Human lists roster and projection counts'
    $hook9 = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $dev9)
    $msg9 = ($hook9.out | ConvertFrom-Json).systemMessage
    Assert-True ($msg9.Contains('plain-one') -and -not $msg9.Contains('ecosystem') -and -not $msg9.Contains('agent-roster') -and ($msg9 -notmatch '(^|[ :,])proj([,; ]|$)')) 'managed: managed assets are left out of the Hook alert'
    # 관리 자산만 있는 개발 루트는 Hook 이 조용해야 한다
    $dev10 = Join-Path $fixtureRoot 'pub10\dev'
    New-FixtureFile (Join-Path $dev10 'products\only\.cursor\rules\ecosystem.mdc') (& $ecoBlock 3)
    New-DevRootAt $dev10 @([ordered]@{ name = 'only'; group = 'products'; lifecycle = 'active' })
    $quiet10 = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-DevRoot', $dev10)
    Assert-True ($quiet10.out -ceq '{"suppressOutput":true}') 'managed: a repo with only managed assets keeps the Hook silent'
    # 기준선 스키마 불변: 관리 자산 키는 기록되지 않고 기존 키 보존 규칙은 그대로
    New-FixtureFile $baselinePath '{"schemaVersion":1,"knownUnregistered":[],"knownUnregisteredRepoAssets":["rule.ecosystem@only","skill.gone@missing-repo"]}'
    $null = Invoke-Drift @('-OutputFormat', 'Hook', '-IncludeRepos', '-UpdateBaseline', '-DevRoot', $dev10)
    $base10 = [IO.File]::ReadAllText($baselinePath, $utf8) | ConvertFrom-Json
    Assert-True ((@($base10.PSObject.Properties.Name) -join ',') -ceq 'schemaVersion,knownUnregistered,knownUnregisteredRepoAssets' -and @($base10.knownUnregisteredRepoAssets).Count -eq 0) 'managed: baseline schema is unchanged and managed keys are not stored'
    Write-Output "PASS: $script:assertions assertions"
}
finally {
    $resolvedWork = (Resolve-Path -LiteralPath $workRoot).Path
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($resolvedWork + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove unexpected test fixture' }
    # 링크는 대상까지 지우지 않도록 링크만 먼저 끊는다.
    if ($zetaLink -and [IO.Directory]::Exists($zetaLink)) { [IO.Directory]::Delete($zetaLink) }
    foreach ($link in $extraLinks) { if ([IO.Directory]::Exists($link)) { [IO.Directory]::Delete($link) } }
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
