#requires -Version 5.1

# 사용자 홈에 설치된 에이전트 자산 중 킷 레지스트리가 모르는 것을 찾는다.
# 읽기 전용 — 홈과 Git index를 바꾸지 않는다. Intake Scan 은 사람이 승인 후 실행한다.
# exit 0 = 미등록 없음 / 2 = 미등록 발견 / 1 = 오류
# -IncludeRepos 를 주면 repos.json 의 활성 프로젝트 레포 루트도 함께 본다(옵트인, 읽기 전용).

[CmdletBinding()]
param(
    [string]$RepositoryRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json', 'Hook')]
    [string]$OutputFormat = 'Human',

    # 기준선과 대조해 새로 나타난 자산만 보고한다. 기준선이 없으면 전체가 신규다.
    [switch]$NewOnly,

    # 유일한 쓰기 동작. 현재 미등록 목록을 기준선으로 확정해 다음 검사부터 조용해진다.
    [switch]$UpdateBaseline,

    # 옵트인. repos.json 의 활성 프로젝트 레포(루트 바로 아래 스킬·에이전트·커맨드·룰)도 스캔한다.
    [switch]$IncludeRepos,

    # repos.json 이 있는 개발 루트. 생략하면 $env:PUBLIC\dev 를 찾고, 경로 기준은 repos.json 의 root 값을 쓴다.
    # 명시하면 그 폴더를 경로 기준으로도 쓴다.
    [string]$DevRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# 파이프·파일로 넘길 때만 UTF-8 로 낸다. PS 5.1 기본(CP949)이면 받는 쪽에서 한국어가 깨진다(PAT-002).
# 콘솔에 직접 찍을 때는 건드리지 않아 사용자 터미널 코드페이지가 바뀌지 않는다.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

# 기계가 읽는 JSON 출력은 ASCII 로만 낸다. PS 5.1 표준출력은 OEM 코드페이지(CP949)라
# 한국어를 그대로 쓰면 UTF-8 로 읽는 Claude Code 에서 깨진다. \uXXXX 이스케이프는 인코딩과 무관하다.
function ConvertTo-AsciiJson {
    param($Value, [int]$Depth = 6)

    $json = [string]($Value | ConvertTo-Json -Depth $Depth -Compress)
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($Match) return ('\u{0:x4}' -f [int][char]$Match.Value) })
}

# 스캔 대상: 벤더별 홈 스킬 경로. Manage-MultivendorSkills.ps1 의 배포 경로와 같은 집합.
function Get-ScanRoots {
    param([Parameter(Mandatory = $true)][string]$UserHome)

    return @(
        [pscustomobject][ordered]@{ role = 'Agents'; relative = '.agents\skills' },
        [pscustomobject][ordered]@{ role = 'Claude'; relative = '.claude\skills' },
        [pscustomobject][ordered]@{ role = 'Codex'; relative = '.codex\skills' },
        [pscustomobject][ordered]@{ role = 'Cursor'; relative = '.cursor\skills' }
    ) | ForEach-Object {
        [pscustomobject][ordered]@{
            role = $_.role
            path = Get-NormalizedFullPath (Join-Path $UserHome $_.relative)
        }
    }
}

# 레지스트리에 등록된 자산 id 집합. 대소문자 구분(킷 다른 도구와 동일 기준).
function Get-RegisteredAssetIds {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $registryPath = Join-Path $RepoRoot 'registry\assets.yaml'
    if (-not [IO.File]::Exists($registryPath)) {
        throw "Registry not found: registry\assets.yaml"
    }

    $registry = [string]([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    if ([int]$registry.schemaVersion -ne 1) {
        throw "Unsupported registry schemaVersion: $($registry.schemaVersion)"
    }

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($asset in @($registry.assets)) {
        $null = $ids.Add([string]$asset.id)
    }
    return $ids
}

# 홈에 실재하는 스킬 디렉터리를 수집한다. 링크는 따라가지 않고 종류만 기록한다.
function Get-InstalledSkills {
    param([Parameter(Mandatory = $true)]$ScanRoots)

    $found = @{}

    foreach ($root in $ScanRoots) {
        if (-not [IO.Directory]::Exists($root.path)) { continue }

        foreach ($directory in @(Get-ChildItem -LiteralPath $root.path -Directory -Force -ErrorAction SilentlyContinue)) {
            # 점으로 시작하는 내부 디렉터리(.system 등)는 자산이 아니다.
            if ($directory.Name.StartsWith('.')) { continue }

            $skillFile = Join-Path $directory.FullName 'SKILL.md'
            if (-not [IO.File]::Exists($skillFile)) { continue }

            $isLink = ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            $name = $directory.Name

            if ($found.ContainsKey($name)) {
                $entry = $found[$name]
                $entry.roles += $root.role
                if (-not $isLink -and [string]::IsNullOrWhiteSpace($entry.materialPath)) {
                    $entry.materialPath = $directory.FullName
                }
                continue
            }

            $found[$name] = [pscustomobject][ordered]@{
                name         = $name
                assetId      = "skill.$name"
                roles        = @($root.role)
                materialPath = $(if ($isLink) { '' } else { $directory.FullName })
                linkedOnly   = $isLink
            }
        }
    }

    return @($found.Values | Sort-Object -Property name)
}

# ---- 레포 스캔 (-IncludeRepos 일 때만 호출된다) ----

# StrictMode 2.0 에서 없는 속성을 읽으면 예외가 나므로 선택 속성은 이 함수로 읽는다.
function Get-OptionalProperty {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    try { return (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) }
    catch { return $false }
}

# 본문 해시. BOM 제거 + CRLF→LF 정규화 후 SHA256 이라 줄바꿈 차이로 diverged 가 되지 않는다.
function Get-TextDigest {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $utf8 = New-Object Text.UTF8Encoding($false)
        $text = $utf8.GetString([IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF).Replace("`r`n", "`n")
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = $sha.ComputeHash($utf8.GetBytes($text)) }
        finally { $sha.Dispose() }
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    catch { return '' }
}

# 레지스트리의 project://<repo>/<상대경로> sourcePath 집합(소문자, 슬래시 통일).
function Get-RegisteredProjectSources {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $registryPath = Join-Path $RepoRoot 'registry\assets.yaml'
    $registry = [string]([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    $sources = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @($registry.assets)) {
        $source = [string](Get-OptionalProperty $asset 'sourcePath')
        if ($source.StartsWith('project://', [StringComparison]::OrdinalIgnoreCase)) {
            $null = $sources.Add($source.Substring(10).Replace('\', '/').Trim('/'))
        }
    }
    return $sources
}

# 벤더 폴더 순서. 같은 자산의 대표 항목(digest·경로)을 고르는 우선순위이기도 하다.
$script:RepoVendorDirs = @('.claude', '.agents', '.codex', '.cursor')

# 레포 루트 바로 아래 자산 항목을 모은다. 재귀 없음, 점 시작 이름 제외, 링크는 따라가지 않는다.
function Get-RepoAssetEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $entries = New-Object 'System.Collections.Generic.List[object]'

    $add = {
        param($Kind, $Name, $VendorDir, $Relative, $FullPath, $DigestSource, $IsLink)
        $entries.Add([pscustomobject][ordered]@{
                repo         = $RepoName
                kind         = $Kind
                name         = $Name
                vendorDir    = $VendorDir
                relativePath = $Relative
                digest       = $(if ($IsLink) { '' } else { Get-TextDigest -Path $DigestSource })
                linkedOnly   = [bool]$IsLink
            })
    }

    foreach ($vendor in $script:RepoVendorDirs) {
        $skillsDir = Join-Path $RepoPath "$vendor\skills"
        if ([IO.Directory]::Exists($skillsDir)) {
            foreach ($directory in @([IO.Directory]::GetDirectories($skillsDir))) {
                $name = [IO.Path]::GetFileName($directory)
                if ($name.StartsWith('.')) { continue }
                $skillFile = Join-Path $directory 'SKILL.md'
                if (-not [IO.File]::Exists($skillFile)) { continue }
                & $add 'skill' $name $vendor "$vendor/skills/$name" $directory $skillFile (Test-IsReparsePoint -Path $directory)
            }
        }
    }

    $fileKinds = @(
        [pscustomobject]@{ kind = 'agent'; dir = '.claude\agents'; rel = '.claude/agents'; ext = '.md'; vendor = '.claude' },
        [pscustomobject]@{ kind = 'command'; dir = '.claude\commands'; rel = '.claude/commands'; ext = '.md'; vendor = '.claude' },
        [pscustomobject]@{ kind = 'rule'; dir = '.cursor\rules'; rel = '.cursor/rules'; ext = '.mdc'; vendor = '.cursor' }
    )
    foreach ($spec in $fileKinds) {
        $dir = Join-Path $RepoPath $spec.dir
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($file in @([IO.Directory]::GetFiles($dir))) {
            $leaf = [IO.Path]::GetFileName($file)
            if ($leaf.StartsWith('.')) { continue }
            # 3글자 확장자 패턴은 .NET 이 더 긴 확장자까지 맞추므로 여기서 정확히 거른다.
            if (-not $leaf.EndsWith($spec.ext, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
            & $add $spec.kind $name $spec.vendor "$($spec.rel)/$leaf" $file $file (Test-IsReparsePoint -Path $file)
        }
    }

    return @($entries.ToArray())
}

# repos.json → 대상 레포를 스캔해 (레포,종류,이름) 단위 자산·사본 그룹을 만든다.
function Invoke-RepoScan {
    param(
        [Parameter(Mandatory = $true)][string]$DevRootPath,
        [bool]$DevRootExplicit,
        [Parameter(Mandatory = $true)][string]$KitRoot,
        [Parameter(Mandatory = $true)]$RegisteredIds,
        [Parameter(Mandatory = $true)]$BaselineKeys
    )

    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $result = [pscustomobject][ordered]@{
        devRoot      = $DevRootPath
        repos        = 0
        missingRepos = @()
        linkedRepos  = @()
        warnings     = @()
        assets       = @()
        groups       = @()
    }

    $registryFile = Join-Path $DevRootPath 'repos.json'
    if ([string]::IsNullOrWhiteSpace($DevRootPath) -or -not [IO.File]::Exists($registryFile)) {
        $warnings.Add("repos.json 을 찾지 못해 레포 스캔을 건너뜀: $registryFile")
        $result.warnings = @($warnings.ToArray())
        return $result
    }

    $repoRegistry = $null
    try { $repoRegistry = [string]([IO.File]::ReadAllText($registryFile, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
    catch {
        $warnings.Add("repos.json 을 읽지 못해 레포 스캔을 건너뜀: $($_.Exception.Message)")
        $result.warnings = @($warnings.ToArray())
        return $result
    }

    # 경로 기준: -DevRoot 를 명시했으면 그것, 아니면 repos.json 의 root, 그것도 없으면 DevRoot.
    $baseRoot = $DevRootPath
    $declaredRoot = [string](Get-OptionalProperty $repoRegistry 'root')
    if (-not $DevRootExplicit -and -not [string]::IsNullOrWhiteSpace($declaredRoot) -and [IO.Directory]::Exists($declaredRoot)) {
        $baseRoot = $declaredRoot
    }
    $baseRoot = Get-NormalizedFullPath $baseRoot
    $result.devRoot = $baseRoot

    $allowedGroups = @('yohan-ecosystem', 'products', 'automation')
    $registeredSources = Get-RegisteredProjectSources -RepoRoot $KitRoot

    $missing = New-Object 'System.Collections.Generic.List[string]'
    $linked = New-Object 'System.Collections.Generic.List[string]'
    $rawEntries = New-Object 'System.Collections.Generic.List[object]'
    $repoNamesByAlias = @{}
    $repoCount = 0

    foreach ($repo in @(Get-OptionalProperty $repoRegistry 'repos')) {
        $group = [string](Get-OptionalProperty $repo 'group')
        $lifecycle = [string](Get-OptionalProperty $repo 'lifecycle')
        $name = [string](Get-OptionalProperty $repo 'name')
        if ($allowedGroups -notcontains $group -or $lifecycle -ne 'active' -or [string]::IsNullOrWhiteSpace($name)) { continue }

        $repoCount++
        $localPath = [string](Get-OptionalProperty $repo 'local_path')
        if ([string]::IsNullOrWhiteSpace($localPath)) { $localPath = "$group/$name" }
        $repoPath = $(if ([IO.Path]::IsPathRooted($localPath)) { $localPath } else { Join-Path $baseRoot $localPath })
        $repoPath = Get-NormalizedFullPath $repoPath

        if (-not [IO.Directory]::Exists($repoPath)) { $missing.Add($name); continue }
        if (Test-IsReparsePoint -Path $repoPath) { $linked.Add($name); continue }

        $repoNamesByAlias[$name] = @($name) + @(Get-OptionalProperty $repo 'aliases' | Where-Object { $_ })
        foreach ($entry in @(Get-RepoAssetEntries -RepoName $name -RepoPath $repoPath)) { $rawEntries.Add($entry) }
    }

    # (레포,종류,이름) 단위로 묶어 자산 1건으로 센다. 벤더 폴더별 사본은 vendorDirs 로 모은다.
    $vendorRank = @{}
    for ($i = 0; $i -lt $script:RepoVendorDirs.Count; $i++) { $vendorRank[$script:RepoVendorDirs[$i]] = $i }

    $assetMap = @{}
    foreach ($entry in $rawEntries) {
        $key = ('{0}.{1}@{2}' -f $entry.kind, $entry.name, $entry.repo).ToLowerInvariant()
        if (-not $assetMap.ContainsKey($key)) { $assetMap[$key] = New-Object 'System.Collections.Generic.List[object]' }
        $assetMap[$key].Add($entry)
    }

    $assets = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $assetMap.Keys) {
        $members = @($assetMap[$key] | Sort-Object -Property @{ Expression = { $vendorRank[$_.vendorDir] } })
        $first = $members[0]
        $displayKey = '{0}.{1}@{2}' -f $first.kind, $first.name, $first.repo

        $isRegistered = $false
        foreach ($member in $members) {
            if ($member.kind -eq 'skill' -and $RegisteredIds.Contains("skill.$($member.name)")) { $isRegistered = $true; break }
            foreach ($repoName in $repoNamesByAlias[$member.repo]) {
                $candidates = @("$repoName/$($member.relativePath)")
                if ($member.kind -eq 'skill') { $candidates += "$repoName/skills/$($member.name)" }
                foreach ($candidate in $candidates) {
                    if ($registeredSources.Contains($candidate)) { $isRegistered = $true }
                }
            }
            if ($isRegistered) { break }
        }

        $digestOwner = @($members | Where-Object { $_.digest })
        $assets.Add([pscustomobject][ordered]@{
                repo         = $first.repo
                kind         = $first.kind
                name         = $first.name
                relativePath = $first.relativePath
                vendorDirs   = @($members | ForEach-Object { $_.vendorDir })
                digest       = $(if ($digestOwner.Count -gt 0) { $digestOwner[0].digest } else { '' })
                registered   = $isRegistered
                inBaseline   = $BaselineKeys.Contains($displayKey)
                linkedOnly   = (@($members | Where-Object { -not $_.linkedOnly }).Count -eq 0)
                key          = $displayKey
            })
    }

    # 같은 (종류,이름) 이 2곳 이상(다른 레포 또는 같은 레포의 다른 벤더 폴더)이면 사본 그룹.
    $groupMap = @{}
    foreach ($entry in $rawEntries) {
        $groupKey = ('{0}.{1}' -f $entry.kind, $entry.name).ToLowerInvariant()
        if (-not $groupMap.ContainsKey($groupKey)) { $groupMap[$groupKey] = New-Object 'System.Collections.Generic.List[object]' }
        $groupMap[$groupKey].Add($entry)
    }
    $groups = New-Object 'System.Collections.Generic.List[object]'
    foreach ($groupKey in $groupMap.Keys) {
        $members = @($groupMap[$groupKey].ToArray())
        if ($members.Count -lt 2) { continue }
        $distinct = @($members | Where-Object { $_.digest } | ForEach-Object { $_.digest } | Sort-Object -Unique)
        $groups.Add([pscustomobject][ordered]@{
                kind  = $members[0].kind
                name  = $members[0].name
                repos = @($members | ForEach-Object { $_.repo } | Sort-Object -Unique)
                state = $(if ($distinct.Count -gt 1) { 'diverged' } else { 'identical' })
            })
    }

    $result.repos = $repoCount
    $result.missingRepos = @($missing.ToArray() | Sort-Object)
    $result.linkedRepos = @($linked.ToArray() | Sort-Object)
    $result.warnings = @($warnings.ToArray())
    $result.assets = @($assets.ToArray() | Sort-Object -Property repo, kind, name)
    $result.groups = @($groups.ToArray() | Sort-Object -Property kind, name)
    return $result
}

try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    }
    $RepositoryRoot = Get-NormalizedFullPath $RepositoryRoot

    if ([string]::IsNullOrWhiteSpace($HomeRoot)) {
        $HomeRoot = $env:USERPROFILE
    }
    if ([string]::IsNullOrWhiteSpace($HomeRoot)) {
        throw 'HomeRoot could not be resolved'
    }
    $HomeRoot = Get-NormalizedFullPath $HomeRoot

    $registeredIds = Get-RegisteredAssetIds -RepoRoot $RepositoryRoot
    $installed = Get-InstalledSkills -ScanRoots (Get-ScanRoots -UserHome $HomeRoot)

    $unregistered = @($installed | Where-Object { -not $registeredIds.Contains($_.assetId) })
    $registered = @($installed | Where-Object { $registeredIds.Contains($_.assetId) })

    # 기준선은 "이미 알고 있는 미등록 자산" 목록이다. 여기 없는 것만 신규다.
    $baselinePath = Get-NormalizedFullPath (Join-Path $HomeRoot '.yohan-agent-kit\asset-drift-baseline.json')
    $baselineIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $baselineRepoKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $baselineHasRepoField = $false
    if ([IO.File]::Exists($baselinePath)) {
        $baseline = [string]([IO.File]::ReadAllText($baselinePath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
        foreach ($knownId in @($baseline.knownUnregistered)) {
            $null = $baselineIds.Add([string]$knownId)
        }
        if ($null -ne $baseline.PSObject.Properties['knownUnregisteredRepoAssets']) {
            $baselineHasRepoField = $true
            foreach ($knownKey in @($baseline.knownUnregisteredRepoAssets)) {
                $null = $baselineRepoKeys.Add([string]$knownKey)
            }
        }
    }

    $newlyAppeared = @($unregistered | Where-Object { -not $baselineIds.Contains($_.assetId) })
    # @() 로 다시 감싼다. StrictMode 에서는 빈 배열이 스칼라로 붕괴해 Count 접근이 깨진다.
    $reported = @($(if ($NewOnly -or $OutputFormat -eq 'Hook') { $newlyAppeared } else { $unregistered }))

    # 레포 스캔은 옵트인이다. 실패해도 홈 스캔 결과는 유지하고 훅을 실패시키지 않는다.
    $repoScan = $null
    $repoUnregistered = @()
    $repoReported = @()
    if ($IncludeRepos) {
        $devRootExplicit = $PSBoundParameters.ContainsKey('DevRoot')
        if ([string]::IsNullOrWhiteSpace($DevRoot) -and -not [string]::IsNullOrWhiteSpace($env:PUBLIC)) {
            $DevRoot = Join-Path $env:PUBLIC 'dev'
        }
        try {
            $repoScan = Invoke-RepoScan -DevRootPath $DevRoot -DevRootExplicit $devRootExplicit -KitRoot $RepositoryRoot -RegisteredIds $registeredIds -BaselineKeys $baselineRepoKeys
        }
        catch {
            $repoScan = [pscustomobject][ordered]@{
                devRoot = [string]$DevRoot; repos = 0; missingRepos = @(); linkedRepos = @()
                warnings = @("레포 스캔 실패로 건너뜀: $($_.Exception.Message)"); assets = @(); groups = @()
            }
        }
        foreach ($warning in @($repoScan.warnings)) { [Console]::Error.WriteLine("경고: $warning") }

        $repoUnregistered = @($repoScan.assets | Where-Object { -not $_.registered })
        $repoNew = @($repoUnregistered | Where-Object { -not $_.inBaseline })
        $repoReported = @($(if ($NewOnly -or $OutputFormat -eq 'Hook') { $repoNew } else { $repoUnregistered }))
    }

    if ($UpdateBaseline) {
        $baselineDirectory = Split-Path -Parent $baselinePath
        if (-not [IO.Directory]::Exists($baselineDirectory)) {
            $null = New-Item -ItemType Directory -Path $baselineDirectory -Force
        }
        $snapshot = [pscustomobject][ordered]@{
            schemaVersion     = 1
            knownUnregistered = @($unregistered | ForEach-Object { $_.assetId } | Sort-Object)
        }
        if ($IncludeRepos) {
            $snapshot | Add-Member -NotePropertyName knownUnregisteredRepoAssets -NotePropertyValue @($repoUnregistered | ForEach-Object { $_.key } | Sort-Object)
        }
        elseif ($baselineHasRepoField) {
            # -IncludeRepos 없이 갱신할 때는 기존 레포 기준선을 지우지 않고 보존한다.
            $snapshot | Add-Member -NotePropertyName knownUnregisteredRepoAssets -NotePropertyValue @($baselineRepoKeys | Sort-Object)
        }
        [IO.File]::WriteAllText($baselinePath, ($snapshot | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    }

    # 훅 출력은 Claude Code 계약을 따른다. 신규가 없으면 조용히 통과한다.
    if ($OutputFormat -eq 'Hook') {
        if ($reported.Count -eq 0 -and $repoReported.Count -eq 0) {
            Write-Output '{"suppressOutput":true}'
        }
        elseif (-not $IncludeRepos) {
            $names = (@($reported | ForEach-Object { $_.name }) -join ', ')
            $message = "새 에이전트 자산 $($reported.Count)건이 킷 정본 밖에 있다: $names — Intake 후보로 올릴지 판단 필요"
            Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ systemMessage = $message }))
        }
        else {
            # 홈 + 레포 신규를 한 메시지로 합친다. 이름은 최대 10개까지만 나열하고 나머지는 "외 N건".
            $total = $reported.Count + $repoReported.Count
            $remaining = 10
            $parts = New-Object 'System.Collections.Generic.List[string]'
            if ($reported.Count -gt 0) {
                $take = @($reported | Select-Object -First $remaining | ForEach-Object { $_.name })
                $remaining -= $take.Count
                $parts.Add('홈: ' + ($take -join ', '))
            }
            foreach ($repoGroup in @($repoReported | Group-Object -Property repo)) {
                if ($remaining -le 0) { break }
                $take = @($repoGroup.Group | Select-Object -First $remaining | ForEach-Object { $_.name })
                $remaining -= $take.Count
                $parts.Add("$($repoGroup.Name): " + ($take -join ', '))
            }
            $list = ($parts.ToArray() -join '; ')
            $more = $total - (10 - $remaining)
            if ($more -gt 0) { $list += " 외 $($more)건" }
            $message = "새 에이전트 자산 $($total)건이 킷 정본 밖에 있다: $list — Intake 후보로 올릴지 판단 필요"
            Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ systemMessage = $message }))
        }
        exit 0
    }

    if ($OutputFormat -eq 'Json') {
        $payload = [pscustomobject][ordered]@{
            schemaVersion    = 1
            mode             = 'Drift'
            registeredCount  = $registered.Count
            unregisteredCount = $reported.Count
            unregistered     = @($reported | ForEach-Object {
                [pscustomobject][ordered]@{
                    name         = $_.name
                    assetId      = $_.assetId
                    roles        = @($_.roles)
                    linkedOnly   = [bool]$_.linkedOnly
                }
            })
        }
        if ($IncludeRepos) {
            $payload | Add-Member -NotePropertyName repoScan -NotePropertyValue ([pscustomobject][ordered]@{
                    devRoot           = [string]$repoScan.devRoot
                    repos             = [int]$repoScan.repos
                    missingRepos      = @($repoScan.missingRepos)
                    linkedRepos       = @($repoScan.linkedRepos)
                    warnings          = @($repoScan.warnings)
                    unregisteredCount = $repoReported.Count
                    assets            = @($repoScan.assets | ForEach-Object {
                        [pscustomobject][ordered]@{
                            repo         = $_.repo
                            kind         = $_.kind
                            name         = $_.name
                            relativePath = $_.relativePath
                            vendorDirs   = @($_.vendorDirs)
                            digest       = $_.digest
                            registered   = [bool]$_.registered
                            inBaseline   = [bool]$_.inBaseline
                            linkedOnly   = [bool]$_.linkedOnly
                        }
                    })
                    groups            = @($repoScan.groups)
                })
        }
        Write-Output (ConvertTo-AsciiJson -Value $payload -Depth 8)
    }
    else {
        $scope = $(if ($NewOnly) { '신규' } else { '미등록' })
        Write-Output "킷 레지스트리 등록: $($registered.Count)건 / 전체 미등록: $($unregistered.Count)건 / $scope 보고: $($reported.Count)건"

        if ($reported.Count -gt 0) {
            Write-Output ''
            Write-Output '미등록 자산 (킷 정본에 없음):'
            foreach ($item in $reported) {
                $where = ($item.roles -join ', ')
                Write-Output "  - $($item.name)  [$where]"
            }
            Write-Output ''
            Write-Output 'Intake 후보로 올리려면 자산마다 아래를 사람이 실행한다(출처·라이선스 확인 후):'
            Write-Output '  .\scripts\Manage-AgentIntake.ps1 -Mode Scan -SourcePath <경로> -Kind skill \'
            Write-Output '    -CanonicalId <skill.name> -Provenance "external:<URL>@<sha>" -License <SPDX> -ApproveInboxWrite'
        }

        if ($IncludeRepos) {
            Write-Output ''
            Write-Output "레포 자산: 대상 $($repoScan.repos)개 / 자산 $(@($repoScan.assets).Count)건 / 전체 미등록: $($repoUnregistered.Count)건 / $scope 보고: $($repoReported.Count)건"
            foreach ($warning in @($repoScan.warnings)) { Write-Output "  경고: $warning" }
            if (@($repoScan.missingRepos).Count -gt 0) { Write-Output "  없음: $(@($repoScan.missingRepos) -join ', ')" }
            if (@($repoScan.linkedRepos).Count -gt 0) { Write-Output "  링크라 건너뜀: $(@($repoScan.linkedRepos) -join ', ')" }
            foreach ($repoGroup in @($repoReported | Group-Object -Property repo)) {
                Write-Output "  [$($repoGroup.Name)] 미등록:"
                foreach ($item in $repoGroup.Group) {
                    Write-Output "    - $($item.kind) $($item.name)  [$(@($item.vendorDirs) -join ', ')]$(if ($item.linkedOnly) { ' (링크)' })"
                }
            }
            $repoGroups = @($repoScan.groups)
            if ($repoGroups.Count -gt 0) {
                Write-Output '  사본 그룹:'
                foreach ($copyGroup in @($repoGroups | Sort-Object -Property @{ Expression = { $(if ($_.state -eq 'diverged') { 0 } else { 1 }) } }, kind, name)) {
                    $label = $(if ($copyGroup.state -eq 'diverged') { '!! 내용 다름(diverged)' } else { '동일(identical)' })
                    Write-Output "    - $($copyGroup.kind) $($copyGroup.name): $label  [$(@($copyGroup.repos) -join ', ')]"
                }
            }
        }
    }

    if ($reported.Count -gt 0 -or $repoReported.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    if ($OutputFormat -eq 'Json') {
        Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Drift'; error = [string]$_.Exception.Message }))
    }
    else {
        Write-Output "드리프트 검사 실패: $($_.Exception.Message)"
    }
    exit 1
}
