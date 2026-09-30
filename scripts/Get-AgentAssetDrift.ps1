#requires -Version 5.1

# 사용자 홈에 설치된 에이전트 자산 중 킷 레지스트리가 모르는 것을 찾는다.
# 읽기 전용 — 홈과 Git index를 바꾸지 않는다. Intake Scan 은 사람이 승인 후 실행한다.
# exit 0 = 미등록 없음 / 2 = 미등록 발견 / 1 = 오류. Hook 모드는 항상 exit 0(오류는 systemMessage 로 알린다).
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
    return , $ids
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

# 다른 도구가 관리하는 파일의 마커. 주인 도구의 실제 규칙을 그대로 옮긴다.
#  공통: 마커는 줄 맨 앞(들여쓰기 없음)에서 시작해 같은 줄에서 '-->' 로 닫혀야 한다. 코드 펜스(``` / ~~~) 안의 줄은
#        마커가 아니다(닫히지 않은 펜스는 파일 끝까지). 예시·인용은 이 조건에서 걸러진다.
#  yohan-brain-roster: kind=rule, name=agent-roster 인 파일에서 BEGIN 뒤에 END 가 있을 때만
#                      (근거: yohan-brain ops/propagation/propagate-roster-card.ps1 이 이 .mdc 를 통째로 생성).
#  vhk-template      : kind=rule, name=ecosystem 인 파일에서 ECOSYSTEM-MDC:START 뒤에 END 가 있을 때만
#                      (근거: vhk src/commands/sync.ts isVhkTemplate = START·END 둘 다 포함). 버전은 START 뒤 첫 토큰 v<1~9자리>.
#  vhk-projection    : kind=skill. VHK parseManagedContent 규칙 그대로 — 마지막 비어 있지 않은 줄이
#                      `<!-- vhk-agent-skill: <name>@<n> source=.agents/skills sha256=<64hex> -->` 이고, name 이 폴더 이름과 같고,
#                      마커를 뺀 본문(CRLF→LF, 끝 개행 보장)의 SHA256 이 sha256 과 같아야 한다.
function Read-NormalizedText {
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$KeepBom)

    $text = (New-Object Text.UTF8Encoding($false)).GetString([IO.File]::ReadAllBytes($Path))
    # 투영본 판정·해시는 VHK 와 똑같이 BOM 을 떼지 않는다(파일 앞 BOM 은 본문의 첫 글자로 해시에 들어간다).
    if (-not $KeepBom) { $text = $text.TrimStart([char]0xFEFF) }
    return $text.Replace("`r`n", "`n")
}

# VHK canonicalContent + contentHash: CRLF→LF 후 끝 개행을 보장하고 SHA256(소문자 hex).
function Get-CanonicalTextHash {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $canonical = $Text.Replace("`r`n", "`n")
    if (-not $canonical.EndsWith("`n")) { $canonical += "`n" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash((New-Object Text.UTF8Encoding($false)).GetBytes($canonical)) }
    finally { $sha.Dispose() }
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

# 파일 한 개의 관리 마커 판정. 항상 객체를 돌려준다(by='' 이면 관리 아님, reject 는 마커 후보가 있었는데 거절한 이유).
function Get-ManagedMarker {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Kind = '', [string]$Name = '')

    $none = [pscustomobject][ordered]@{ by = ''; version = ''; source = ''; sha = ''; reject = '' }
    try { $rawText = Read-NormalizedText -Path $Path -KeepBom } catch { return $none }
    $text = $rawText.TrimStart([char]0xFEFF)
    $lines = $text.Split("`n")
    # 투영본은 VHK parseManagedContent 처럼 BOM 을 남긴 원문 줄로 본다.
    $rawLines = $rawText.Split("`n")

    # 코드 펜스 밖의 줄만 live.
    $live = New-Object 'bool[]' $lines.Count
    $fenceChar = ''
    $fenceLen = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($fenceChar -ne '') {
            if ($line -match '^ {0,3}(`{3,}|~{3,})[ \t]*$' -and $Matches[1].Substring(0, 1) -ceq $fenceChar -and $Matches[1].Length -ge $fenceLen) { $fenceChar = '' }
            continue
        }
        if ($line -match '^ {0,3}(`{3,}|~{3,})') {
            $fenceChar = $Matches[1].Substring(0, 1)
            $fenceLen = $Matches[1].Length
            continue
        }
        $live[$i] = $true
    }
    $findLive = {
        param($Pattern, $From)
        for ($j = $From; $j -lt $lines.Count; $j++) { if ($live[$j] -and $lines[$j] -cmatch $Pattern) { return $j } }
        return -1
    }

    $reject = ''

    # --- yohan-brain-roster ---
    $hasRoster = $text.Contains('YOHAN-ROSTER-CARD:BEGIN')
    if ($Kind -eq 'rule' -and $Name -ieq 'agent-roster') {
        $begin = & $findLive '^<!-- YOHAN-ROSTER-CARD:BEGIN(?![\w-]).*-->[ \t]*$' 0
        if ($begin -ge 0 -and (& $findLive '^<!-- YOHAN-ROSTER-CARD:END -->[ \t]*$' ($begin + 1)) -ge 0) {
            return [pscustomobject][ordered]@{ by = 'yohan-brain-roster'; version = ''; source = ''; sha = ''; reject = '' }
        }
        if ($hasRoster -and $reject -eq '') { $reject = 'invalid-marker' }
    }
    elseif ($hasRoster -and $reject -eq '') { $reject = 'wrong-file' }

    # --- vhk-template ---
    $hasTemplate = $text.Contains('ECOSYSTEM-MDC:START')
    if ($Kind -eq 'rule' -and $Name -ieq 'ecosystem') {
        $start = & $findLive '^<!-- ECOSYSTEM-MDC:START(?![\w-])(?:[ \t]+(?!-->)(?<tok>\S+))?.*-->[ \t]*$' 0
        if ($start -ge 0 -and (& $findLive '^<!-- ECOSYSTEM-MDC:END(?![\w-]).*-->[ \t]*$' ($start + 1)) -ge 0) {
            $null = $lines[$start] -cmatch '^<!-- ECOSYSTEM-MDC:START(?![\w-])(?:[ \t]+(?!-->)(?<tok>\S+))?.*-->[ \t]*$'
            $token = $(if ($Matches.ContainsKey('tok')) { [string]$Matches['tok'] } else { '' })
            # 해석할 수 없는 표기(V3, v3.1, 버전 없음, 10자리 이상)는 'unknown'. v03 은 v3 으로 정규화한다.
            $version = $(if ($token -cmatch '^v([0-9]{1,9})$') { 'v' + [int]$Matches[1] } else { 'unknown' })
            return [pscustomobject][ordered]@{ by = 'vhk-template'; version = $version; source = ''; sha = ''; reject = '' }
        }
        if ($hasTemplate -and $reject -eq '') { $reject = 'invalid-marker' }
    }
    elseif ($hasTemplate -and $reject -eq '') { $reject = 'wrong-file' }

    # --- vhk-projection ---
    $hasProjection = $text.Contains('vhk-agent-skill:')
    if ($Kind -eq 'skill') {
        # VHK 는 마지막 비어 있지 않은 줄만 본다. 코드 펜스 여부는 따지지 않는다(roster·template 과 다르다).
        $last = $rawLines.Count - 1
        while ($last -ge 0 -and $rawLines[$last] -eq '') { $last-- }
        if ($last -ge 0 -and $rawLines[$last] -cmatch '^<!-- vhk-agent-skill: ([a-z0-9-]+)@([0-9]+) source=\.agents/skills sha256=([a-f0-9]{64}) -->$') {
            $markerName = $Matches[1]
            $markerSha = $Matches[3]
            if ($markerName -cne $Name) { if ($reject -eq '') { $reject = 'name-mismatch' } }
            elseif ((Get-CanonicalTextHash -Text ($(if ($last -gt 0) { @($rawLines[0..($last - 1)]) -join "`n" } else { '' }))) -cne $markerSha) { if ($reject -eq '') { $reject = 'sha-mismatch' } }
            else {
                return [pscustomobject][ordered]@{ by = 'vhk-projection'; version = ''; source = '.agents/skills'; sha = $markerSha; reject = '' }
            }
        }
        elseif ($hasProjection -and $reject -eq '') { $reject = 'invalid-marker' }
    }
    elseif ($hasProjection -and $reject -eq '') { $reject = 'wrong-file' }

    $none.reject = $reject
    return $none
}

# 자산(벤더 사본 묶음) 단위 관리 판정. 규칙:
#  - 유효한 마커 사본이 하나도 없으면 관리 아님(마커 후보가 있었으면 그 거절 이유를 남긴다).
#  - 마커 종류가 사본끼리 다르면 관리 아님(mixed-marker-kinds).
#  - 마커 없는 사본이 있으면 관리 아님. 단 vhk-projection 의 '.agents' 사본은 예외로, 그 정규화 해시가
#    형제 마커 사본의 sha256 과 같을 때만 허용한다(VHK 정본과 투영본이 같은 본문임이 증명될 때).
#  - 링크만 있는(읽지 못한) 사본은 마커 없는 사본으로 친다(linked-copy).
function Resolve-ManagedState {
    param([Parameter(Mandatory = $true)]$Members)

    $none = [pscustomobject][ordered]@{ by = ''; version = ''; source = ''; reason = '' }
    $marked = @($Members | Where-Object { $_.managedBy })
    if ($marked.Count -eq 0) {
        $rejects = @($Members | Where-Object { $_.managedRejectReason } | ForEach-Object { $_.managedRejectReason } | Sort-Object -Unique)
        $none.reason = ($rejects -join ';')
        return $none
    }
    $kinds = @($marked | ForEach-Object { $_.managedBy } | Sort-Object -Unique)
    if ($kinds.Count -gt 1) { $none.reason = 'mixed-marker-kinds'; return $none }
    $shas = @($marked | Where-Object { $_.managedSha } | ForEach-Object { $_.managedSha })
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    foreach ($copy in @($Members | Where-Object { -not $_.managedBy })) {
        if ($copy.linkedOnly) { $reasons.Add("linked-copy:$($copy.vendorDir)"); continue }
        $canon = [string]$copy.canonHash
        if ($kinds[0] -eq 'vhk-projection' -and $copy.vendorDir -eq '.agents' -and $canon -and ($shas -contains $canon)) { continue }
        $reasons.Add("unmarked-copy:$($copy.vendorDir)")
    }
    if ($reasons.Count -gt 0) { $none.reason = ($reasons.ToArray() -join ';'); return $none }
    $withVersion = @($marked | Where-Object { $_.managedVersion })
    $withSource = @($marked | Where-Object { $_.managedSource })
    return [pscustomobject][ordered]@{
        by      = [string]$kinds[0]
        # 사본끼리 버전이 다르면 대표 항목(벤더 우선순위 첫 사본)의 값을 쓴다.
        version = $(if ($withVersion.Count -gt 0) { [string]$withVersion[0].managedVersion } else { '' })
        source  = $(if ($withSource.Count -gt 0) { [string]$withSource[0].managedSource } else { '' })
        reason  = ''
    }
}


# 킷 레지스트리 JSON 을 한 번만 읽는다.
function Read-KitRegistry {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $registryPath = Join-Path $RepoRoot 'registry\assets.yaml'
    return ([string]([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json)
}

# 레지스트리의 project://<repo>/<상대경로> sourcePath 집합(대소문자 무시, 슬래시 통일).
# HashSet 을 그대로 return 하면 파이프라인이 원소로 풀어 0개면 $null, 1개면 문자열이 된다 → 쉼표로 감싼다.
function Get-RegisteredProjectSources {
    param([Parameter(Mandatory = $true)]$Registry)

    $sources = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @($Registry.assets)) {
        $source = [string](Get-OptionalProperty $asset 'sourcePath')
        if ($source.StartsWith('project://', [StringComparison]::OrdinalIgnoreCase)) {
            $null = $sources.Add($source.Substring(10).Replace('\', '/').Trim('/'))
        }
    }
    return , $sources
}

# 킷 자신을 가리키는 일반 상대 sourcePath 집합(scheme 없는 것만, 예: .cursor/rules/ecosystem.mdc).
function Get-RegisteredRelativeSources {
    param([Parameter(Mandatory = $true)]$Registry)

    $sources = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @($Registry.assets)) {
        $source = [string](Get-OptionalProperty $asset 'sourcePath')
        if ([string]::IsNullOrWhiteSpace($source) -or $source.Contains('://') -or [IO.Path]::IsPathRooted($source)) { continue }
        $null = $sources.Add($source.Replace('\', '/').Trim('/'))
    }
    return , $sources
}

# id → sourcePath. 레포 스킬 이름 일치 판정용(대소문자 무시, 다른 레포 판정과 같은 기준).
function Get-RegistrySourceById {
    param([Parameter(Mandatory = $true)]$Registry)

    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @($Registry.assets)) {
        $map[[string](Get-OptionalProperty $asset 'id')] = [string](Get-OptionalProperty $asset 'sourcePath')
    }
    return , $map
}

# 킷 쪽 스킬 실제 파일의 해시. 로컬 경로가 아니거나 파일이 없으면 '' (비교 불가).
function Get-KitSkillDigest {
    param([Parameter(Mandatory = $true)][string]$KitRoot, [string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or $SourcePath.Contains('://') -or [IO.Path]::IsPathRooted($SourcePath)) { return '' }
    $path = Get-NormalizedFullPath (Join-Path $KitRoot $SourcePath.Replace('/', '\'))
    if (-not $path.StartsWith($KitRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { return '' }
    if ([IO.Directory]::Exists($path)) { $path = Join-Path $path 'SKILL.md' }
    if (-not [IO.File]::Exists($path)) { return '' }
    return (Get-TextDigest -Path $path)
}

# 벤더 폴더 순서. 같은 자산의 대표 항목(digest·경로)을 고르는 우선순위이기도 하다.
$script:RepoVendorDirs = @('.claude', '.agents', '.codex', '.cursor')

# 레포 루트 바로 아래 자산 항목을 모은다. 재귀 없음, 점 시작 이름 제외.
# 벤더 폴더·하위 폴더가 링크(reparse point)면 따라가지 않고 skipped 에 기록한다.
function Get-RepoAssetEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $skipped = New-Object 'System.Collections.Generic.List[string]'

    $add = {
        param($Kind, $Name, $VendorDir, $Relative, $FullPath, $DigestSource, $IsLink)
        $marker = $(if ($IsLink) { $null } else { Get-ManagedMarker -Path $DigestSource -Kind $Kind -Name $Name })
        $canonHash = ''
        if (-not $IsLink -and $Kind -eq 'skill') { try { $canonHash = Get-CanonicalTextHash -Text (Read-NormalizedText -Path $DigestSource -KeepBom) } catch { $canonHash = '' } }
        $entries.Add([pscustomobject][ordered]@{
                managedBy      = $(if ($marker) { $marker.by } else { '' })
                managedVersion = $(if ($marker) { $marker.version } else { '' })
                managedSource  = $(if ($marker) { $marker.source } else { '' })
                managedSha     = $(if ($marker) { $marker.sha } else { '' })
                managedRejectReason = $(if ($marker) { $marker.reject } else { '' })
                canonHash      = $canonHash
                repo         = $RepoName
                kind         = $Kind
                name         = $Name
                vendorDir    = $VendorDir
                relativePath = $Relative
                digest       = $(if ($IsLink) { '' } else { Get-TextDigest -Path $DigestSource })
                linkedOnly   = [bool]$IsLink
            })
    }

    # 스캔해도 되는 폴더인지 판정한다. 링크면 기록만 하고 false.
    $usable = {
        param($Vendor, $Sub)
        $vendorPath = Join-Path $RepoPath $Vendor
        if (-not [IO.Directory]::Exists($vendorPath)) { return $false }
        if (Test-IsReparsePoint -Path $vendorPath) {
            if (-not $skipped.Contains($Vendor)) { $skipped.Add($Vendor) }
            return $false
        }
        $subPath = Join-Path $vendorPath $Sub
        if (-not [IO.Directory]::Exists($subPath)) { return $false }
        if (Test-IsReparsePoint -Path $subPath) {
            $rel = "$Vendor/$Sub"
            if (-not $skipped.Contains($rel)) { $skipped.Add($rel) }
            return $false
        }
        return $true
    }

    foreach ($vendor in $script:RepoVendorDirs) {
        if (-not (& $usable $vendor 'skills')) { continue }
        foreach ($directory in @([IO.Directory]::GetDirectories((Join-Path $RepoPath "$vendor\skills")))) {
            $name = [IO.Path]::GetFileName($directory)
            if ($name.StartsWith('.')) { continue }
            $skillFile = Join-Path $directory 'SKILL.md'
            if (-not [IO.File]::Exists($skillFile)) { continue }
            & $add 'skill' $name $vendor "$vendor/skills/$name" $directory $skillFile (Test-IsReparsePoint -Path $directory)
        }
    }

    $fileKinds = @(
        [pscustomobject]@{ kind = 'agent'; sub = 'agents'; ext = '.md'; vendor = '.claude' },
        [pscustomobject]@{ kind = 'command'; sub = 'commands'; ext = '.md'; vendor = '.claude' },
        [pscustomobject]@{ kind = 'rule'; sub = 'rules'; ext = '.mdc'; vendor = '.cursor' }
    )
    foreach ($spec in $fileKinds) {
        if (-not (& $usable $spec.vendor $spec.sub)) { continue }
        foreach ($file in @([IO.Directory]::GetFiles((Join-Path $RepoPath "$($spec.vendor)\$($spec.sub)")))) {
            $leaf = [IO.Path]::GetFileName($file)
            if ($leaf.StartsWith('.')) { continue }
            # 3글자 확장자 패턴은 .NET 이 더 긴 확장자까지 맞추므로 여기서 정확히 거른다.
            if (-not $leaf.EndsWith($spec.ext, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
            & $add $spec.kind $name $spec.vendor "$($spec.vendor)/$($spec.sub)/$leaf" $file $file (Test-IsReparsePoint -Path $file)
        }
    }

    return [pscustomobject][ordered]@{ entries = @($entries.ToArray()); skipped = @($skipped.ToArray()) }
}

# 스캔 실패 결과를 만든다. scanFailed=true 면 호출부는 기존 레포 기준선을 그대로 보존해야 한다.
function New-RepoScanFailure {
    param([string]$DevRootPath, [string]$Message, [string]$Reason = '')

    return [pscustomobject][ordered]@{
        devRoot = $DevRootPath; repos = 0; missingRepos = @(); linkedRepos = @(); failedRepos = @()
        skippedLinks = @(); preserveRepos = @(); preserveTokenMap = @{}; scanFailed = $true; failureReason = $Reason
        warnings = @($Message); assets = @(); groups = @()
    }
}

# 레포의 이름 + 별칭(대소문자 무시 중복 제거).
function Get-RepoTokens {
    param($Repo)

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $repoName = [string](Get-OptionalProperty $Repo 'name')
    if (-not [string]::IsNullOrWhiteSpace($repoName) -and $seen.Add($repoName)) { $tokens.Add($repoName) }
    foreach ($alias in @(Get-OptionalProperty $Repo 'aliases')) {
        if ($alias -and $seen.Add([string]$alias)) { $tokens.Add([string]$alias) }
    }
    return @($tokens.ToArray())
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

    $registryFile = Join-Path $DevRootPath 'repos.json'
    if ([string]::IsNullOrWhiteSpace($DevRootPath) -or -not [IO.File]::Exists($registryFile)) {
        return (New-RepoScanFailure $DevRootPath "repos.json 을 찾지 못해 레포 스캔을 건너뜀: $registryFile" 'repos.json 없음')
    }

    $repoRegistry = $null
    try { $repoRegistry = [string]([IO.File]::ReadAllText($registryFile, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
    catch {
        return (New-RepoScanFailure $DevRootPath "repos.json 을 읽지 못해 레포 스캔을 건너뜀: $($_.Exception.Message)" 'repos.json 읽기 실패')
    }
    # 최상위가 객체가 아니거나(null·배열·문자열) repos 가 배열이 아니면 스캔하지 않고 경고한다.
    if ($null -eq $repoRegistry -or $repoRegistry -isnot [pscustomobject]) {
        return (New-RepoScanFailure $DevRootPath 'repos.json 형식이 올바르지 않아 레포 스캔을 건너뜀: 최상위가 객체가 아님' 'repos.json 형식 오류')
    }
    # 함수 반환은 배열을 풀어 1개짜리를 객체로 바꾸므로 속성 값을 직접 읽는다.
    $repoItems = $null
    if ($null -ne $repoRegistry.PSObject.Properties['repos']) { $repoItems = $repoRegistry.PSObject.Properties['repos'].Value }
    if ($null -eq $repoItems -or $repoItems -isnot [array]) {
        return (New-RepoScanFailure $DevRootPath 'repos.json 형식이 올바르지 않아 레포 스캔을 건너뜀: repos 배열이 없음' 'repos.json 형식 오류')
    }

    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $result = New-RepoScanFailure $DevRootPath ''
    $result.scanFailed = $false

    # 경로 기준: -DevRoot 를 명시했으면 그것, 아니면 repos.json 의 root(실재할 때), 그것도 없으면 DevRoot.
    $baseRoot = $DevRootPath
    $declaredRoot = [string](Get-OptionalProperty $repoRegistry 'root')
    if (-not $DevRootExplicit -and -not [string]::IsNullOrWhiteSpace($declaredRoot) -and [IO.Directory]::Exists($declaredRoot)) {
        $baseRoot = $declaredRoot
    }
    $baseRoot = Get-NormalizedFullPath $baseRoot
    $result.devRoot = $baseRoot

    $allowedGroups = @('yohan-ecosystem', 'products', 'automation')
    $kitSelfNames = @('yohan-agent-kit', 'yohan-cc-skills')
    $registry = Read-KitRegistry -RepoRoot $KitRoot
    $registeredSources = Get-RegisteredProjectSources -Registry $registry
    $relativeSources = Get-RegisteredRelativeSources -Registry $registry
    $sourceById = Get-RegistrySourceById -Registry $registry
    $kitDigestCache = @{}

    # 이름·별칭 충돌(다른 레포와 겹치거나 이름 중복)을 미리 센다. 충돌한 레포는 건너뛴다.
    # 충돌 계산은 스캔 대상(대상 group + active)끼리만 한다. archived 같은 비대상 레포는 영향을 주지 않는다.
    $tokenCount = @{}
    foreach ($repo in $repoItems) {
        $repoName = [string](Get-OptionalProperty $repo 'name')
        if ($allowedGroups -notcontains [string](Get-OptionalProperty $repo 'group') -or [string](Get-OptionalProperty $repo 'lifecycle') -ne 'active' -or [string]::IsNullOrWhiteSpace($repoName)) { continue }
        foreach ($token in @(Get-RepoTokens $repo)) { $tokenCount[$token.ToLowerInvariant()] = 1 + $(if ($tokenCount.ContainsKey($token.ToLowerInvariant())) { $tokenCount[$token.ToLowerInvariant()] } else { 0 }) }
    }
    # 기준선 보존용: 별칭(옛 이름) → 현재 이름. 스캔 못 한 레포의 옛 키를 현재 이름 키로 바꿔 저장한다.
    $tokenToName = @{}

    $missing = New-Object 'System.Collections.Generic.List[string]'
    $linked = New-Object 'System.Collections.Generic.List[string]'
    $failed = New-Object 'System.Collections.Generic.List[string]'
    $partial = New-Object 'System.Collections.Generic.List[string]'
    $skippedLinks = New-Object 'System.Collections.Generic.List[string]'
    $rawEntries = New-Object 'System.Collections.Generic.List[object]'
    $repoTokens = @{}
    $repoCount = 0

    foreach ($repo in $repoItems) {
        $group = [string](Get-OptionalProperty $repo 'group')
        $lifecycle = [string](Get-OptionalProperty $repo 'lifecycle')
        $name = [string](Get-OptionalProperty $repo 'name')
        if ($allowedGroups -notcontains $group -or $lifecycle -ne 'active' -or [string]::IsNullOrWhiteSpace($name)) { continue }

        $repoCount++
        foreach ($token in @(Get-RepoTokens $repo)) { $tokenToName[$token.ToLowerInvariant()] = $name }
        # 레포 단위로 격리한다: 한 레포의 예외가 나머지 스캔을 막지 않는다.
        try {
            $aliases = @(Get-OptionalProperty $repo 'aliases' | Where-Object { $_ } | ForEach-Object { [string]$_ })
            $conflict = @(@($name) + $aliases | Where-Object { $tokenCount[$_.ToLowerInvariant()] -gt 1 })
            if ($conflict.Count -gt 0) {
                $failed.Add($name)
                $warnings.Add("레포 이름·별칭이 다른 레포와 겹쳐 건너뜀 ($name): $($conflict -join ', ')")
                continue
            }

            $localPath = [string](Get-OptionalProperty $repo 'local_path')
            if ([string]::IsNullOrWhiteSpace($localPath)) { $localPath = "$group/$name" }
            $repoPath = $(if ([IO.Path]::IsPathRooted($localPath)) { $localPath } else { Join-Path $baseRoot $localPath })
            $repoPath = Get-NormalizedFullPath $repoPath

            if (-not [IO.Directory]::Exists($repoPath)) { $missing.Add($name); continue }
            if (Test-IsReparsePoint -Path $repoPath) { $linked.Add($name); continue }

            $scanned = Get-RepoAssetEntries -RepoName $name -RepoPath $repoPath
            foreach ($entry in @($scanned.entries)) { $rawEntries.Add($entry) }
            foreach ($skip in @($scanned.skipped)) { $skippedLinks.Add("$name/$skip") }
            if (@($scanned.skipped).Count -gt 0) { $partial.Add($name) }
            $repoTokens[$name] = @($name) + $aliases
        }
        catch {
            $failed.Add($name)
            $warnings.Add("레포 스캔 실패로 건너뜀 ($name): $($_.Exception.Message)")
        }
    }

    # 대상 레포가 0개면 "성공"이 아니다: 기준선을 전부 지우지 않도록 스캔 실패와 똑같이 다룬다.
    if ($repoCount -eq 0) {
        return (New-RepoScanFailure $DevRootPath '스캔 대상 레포(대상 group + active)가 0개라 레포 스캔을 건너뜀' '대상 레포 0개')
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

        # 등록 판정: (1) 스킬 id 가 있고 킷 실제 파일과 내용 해시가 같음 (2) project:// 정확 일치
        # (3) 스캔 대상이 킷 자신이면 일반 상대 sourcePath 일치. 이름만 같은 스킬은 등록으로 보지 않고 표시만 한다.
        $isRegistered = $false
        $nameMatches = $false
        # 스킬 id 판정은 자산 단위다: 해시가 있는 벤더 사본이 전부 킷 본문과 같을 때만 등록. 하나라도 다르면 표시만.
        if ($first.kind -eq 'skill') {
            $skillId = "skill.$($first.name)"
            if ($sourceById.ContainsKey($skillId)) {
                $cacheKey = $skillId.ToLowerInvariant()
                if (-not $kitDigestCache.ContainsKey($cacheKey)) { $kitDigestCache[$cacheKey] = Get-KitSkillDigest -KitRoot $KitRoot -SourcePath $sourceById[$skillId] }
                $kitDigest = $kitDigestCache[$cacheKey]
                $hashed = @($members | Where-Object { $_.digest })
                if ($kitDigest -and $hashed.Count -gt 0 -and @($hashed | Where-Object { $_.digest -cne $kitDigest }).Count -eq 0) { $isRegistered = $true }
                else { $nameMatches = $true }
            }
        }
        foreach ($member in $members) {
            foreach ($token in $repoTokens[$member.repo]) {
                if ($registeredSources.Contains("$token/$($member.relativePath)")) { $isRegistered = $true }
                if ($kitSelfNames -contains $token.ToLowerInvariant() -and $relativeSources.Contains($member.relativePath)) { $isRegistered = $true }
            }
        }

        $digestOwner = @($members | Where-Object { $_.digest })
        $managed = Resolve-ManagedState -Members $members
        $assets.Add([pscustomobject][ordered]@{
                repo          = $first.repo
                kind          = $first.kind
                name          = $first.name
                relativePath  = $first.relativePath
                vendorDirs    = @($members | ForEach-Object { $_.vendorDir })
                digest        = $(if ($digestOwner.Count -gt 0) { $digestOwner[0].digest } else { '' })
                registered    = $isRegistered
                nameMatchesKit = ($nameMatches -and -not $isRegistered)
                # 레포 이름이 바뀌어 옛 이름이 별칭으로 남은 경우, 옛 이름 키도 같은 자산으로 인정한다.
                inBaseline    = (@(@($repoTokens[$first.repo]) | Where-Object { $BaselineKeys.Contains(('{0}.{1}@{2}' -f $first.kind, $first.name, $_)) }).Count -gt 0)
                linkedOnly    = (@($members | Where-Object { -not $_.linkedOnly }).Count -eq 0)
                managedBy      = $managed.by
                managedVersion = $managed.version
                managedSource  = $managed.source
                managedRejectReason = [string]$managed.reason
                key           = $displayKey
            })
    }

    # 같은 (종류,이름) 이 2곳 이상(다른 레포 또는 같은 레포의 다른 벤더 폴더)이면 사본 그룹.
    # 해시가 없는 멤버(링크·읽기 실패)가 있으면 비교할 수 없으므로 unknown.
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
        $state = $(if (@($members | Where-Object { -not $_.digest }).Count -gt 0) { 'unknown' } elseif ($distinct.Count -gt 1) { 'diverged' } else { 'identical' })
        $groups.Add([pscustomobject][ordered]@{
                kind  = $members[0].kind
                name  = $members[0].name
                repos = @($members | ForEach-Object { $_.repo } | Sort-Object -Unique)
                state = $state
            })
    }

    $preserve = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($list in @($missing, $linked, $failed, $partial)) { foreach ($item in $list) { $null = $preserve.Add($item) } }

    $result.preserveTokenMap = $tokenToName
    $result.repos = $repoCount
    $result.missingRepos = @($missing.ToArray() | Sort-Object)
    $result.linkedRepos = @($linked.ToArray() | Sort-Object)
    $result.failedRepos = @($failed.ToArray() | Sort-Object)
    $result.skippedLinks = @($skippedLinks.ToArray() | Sort-Object)
    $result.preserveRepos = @($preserve | Sort-Object)
    $result.warnings = @($warnings.ToArray())
    $result.assets = @($assets.ToArray() | Sort-Object -Property repo, kind, name)
    $result.groups = @($groups.ToArray() | Sort-Object -Property kind, name)
    return $result
}

$script:ManagedLabels = @{
    'yohan-brain-roster' = 'yohan-brain 라우팅 카드'
    'vhk-template'       = 'VHK 경계 규칙'
    'vhk-projection'     = 'VHK 스킬 투영본'
}

# 관리 주체별 건수·버전 분포. 버전이 섞이면 최신(숫자 최대)보다 낮은 버전의 레포를 outdated 로 표시한다.
function Get-ManagedSummary {
    param($ManagedAssets)

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($byGroup in @($ManagedAssets | Group-Object -Property managedBy | Sort-Object -Property Name)) {
        $versionEntries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($versionGroup in @($byGroup.Group | Group-Object -Property managedVersion)) {
            $number = $(if ($versionGroup.Name -match '^v([0-9]{1,9})$') { [int]$Matches[1] } else { -1 })
            $versionEntries.Add([pscustomobject][ordered]@{
                    version = [string]$versionGroup.Name
                    number  = $number
                    count   = $versionGroup.Count
                    repos   = @($versionGroup.Group | ForEach-Object { $_.repo } | Sort-Object -Unique)
                })
        }
        $ordered = @($versionEntries.ToArray() | Sort-Object -Property @{ Expression = { $_.number }; Descending = $true }, version)
        $latest = @($ordered | Where-Object { $_.number -ge 0 } | Select-Object -First 1)
        $latestNumber = $(if ($latest.Count -gt 0) { $latest[0].number } else { -1 })
        $outdated = @($ordered | Where-Object { $latestNumber -ge 0 -and $_.number -ge 0 -and $_.number -lt $latestNumber } | ForEach-Object { $_.repos } | Sort-Object -Unique)
        $items.Add([pscustomobject][ordered]@{
                managedBy      = [string]$byGroup.Name
                label          = [string]$script:ManagedLabels[[string]$byGroup.Name]
                count          = $byGroup.Count
                versions       = @($ordered | ForEach-Object { [pscustomobject][ordered]@{ version = $_.version; count = $_.count; repos = @($_.repos) } })
                latestVersion  = $(if ($latest.Count -gt 0) { $latest[0].version } else { '' })
                outdatedRepos  = @($outdated)
            })
    }
    return @($items.ToArray())
}

# 기준선 읽기. 쓰는 쪽이 임시 파일을 교체하는 순간 읽는 쪽은 "파일 없음"이나 공유 위반(IOException)을 볼 수 있어
# 짧게 재시도한다(최대 3회 × 50ms). 교체가 진행 중이 아니면(임시 파일 없음) 없는 파일은 곧바로 null 이다.
function Read-BaselineText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $directory = Split-Path -Parent $Path
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            if ([IO.File]::Exists($Path)) { return [string][IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }
            $replacing = [IO.Directory]::Exists($directory) -and @([IO.Directory]::GetFiles($directory, ([IO.Path]::GetFileName($Path) + '.tmp-*'))).Count -gt 0
            if (-not $replacing) { return $null }
        }
        catch [IO.IOException] {
            if ($attempt -eq 3) { throw }
        }
        Start-Sleep -Milliseconds 50
    }
    return $null
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
    $baselineText = Read-BaselineText -Path $baselinePath
    if ($null -ne $baselineText) {
        $baseline = [string]$baselineText | ConvertFrom-Json
        foreach ($knownId in @($baseline.knownUnregistered)) {
            $null = $baselineIds.Add([string]$knownId)
        }
        if ($null -ne $baseline.PSObject.Properties['knownUnregisteredRepoAssets']) {
            $baselineHasRepoField = $true
            foreach ($knownKey in @($baseline.knownUnregisteredRepoAssets)) {
                # null·빈 값은 키가 아니다(@($null) 이 [""] 로 저장되는 것을 막는다).
                if (-not [string]::IsNullOrEmpty([string]$knownKey)) { $null = $baselineRepoKeys.Add([string]$knownKey) }
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
    $repoManaged = @()
    $repoManagedSummary = @()
    if ($IncludeRepos) {
        $devRootExplicit = $PSBoundParameters.ContainsKey('DevRoot')
        if ([string]::IsNullOrWhiteSpace($DevRoot) -and -not [string]::IsNullOrWhiteSpace($env:PUBLIC)) {
            $DevRoot = Join-Path $env:PUBLIC 'dev'
        }
        try {
            $repoScan = Invoke-RepoScan -DevRootPath $DevRoot -DevRootExplicit $devRootExplicit -KitRoot $RepositoryRoot -RegisteredIds $registeredIds -BaselineKeys $baselineRepoKeys
        }
        catch {
            $repoScan = New-RepoScanFailure ([string]$DevRoot) "레포 스캔 실패로 건너뜀: $($_.Exception.Message)" '스캔 예외'
        }
        # 등록되지 않았어도 다른 도구가 관리하는 자산(마커 있음)은 미등록 수·Hook 알림에서 뺀다.
        $repoManaged = @($repoScan.assets | Where-Object { -not $_.registered -and $_.managedBy })
        # 요약 단계는 격리한다: 여기서 실패해도 검사 전체는 죽지 않고 경고만 남긴다.
        try { $repoManagedSummary = @(Get-ManagedSummary -ManagedAssets $repoManaged) }
        catch {
            $repoManagedSummary = @()
            $repoScan.warnings = @($repoScan.warnings) + "관리 자산 요약을 만들지 못해 건너뜀: $($_.Exception.Message)"
        }
        # Human 은 본문 섹션에 경고를 싣는다. stderr 는 기계 출력(Hook/Json)일 때만 쓴다(중복 방지).
        if ($OutputFormat -ne 'Human') {
            foreach ($warning in @($repoScan.warnings)) { [Console]::Error.WriteLine("경고: $warning") }
        }
        $repoUnregistered = @($repoScan.assets | Where-Object { -not $_.registered -and -not $_.managedBy })
        $repoNew = @($repoUnregistered | Where-Object { -not $_.inBaseline })
        $repoReported = @($(if ($NewOnly -or $OutputFormat -eq 'Hook') { $repoNew } else { $repoUnregistered }))
    }

    if ($UpdateBaseline) {
        $baselineDirectory = Split-Path -Parent $baselinePath
        if (-not [IO.Directory]::Exists($baselineDirectory)) {
            $null = New-Item -ItemType Directory -Path $baselineDirectory -Force
        }
        $fields = [ordered]@{
            schemaVersion     = 1
            knownUnregistered = @($unregistered | ForEach-Object { $_.assetId } | Sort-Object)
        }
        if ($IncludeRepos -and -not $repoScan.scanFailed) {
            # 성공: 새 미등록 키 + (없음·링크·실패·일부 건너뜀 레포에 속한 기존 키). 못 본 레포의 기준선은 지우지 않는다.
            $keep = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($repoName in @($repoScan.preserveRepos)) { $null = $keep.Add([string]$repoName) }
            $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($item in $repoUnregistered) { $null = $keys.Add([string]$item.key) }
            foreach ($oldKey in $baselineRepoKeys) {
                $at = $oldKey.LastIndexOf('@')
                if ($at -lt 0) { continue }
                # 옛 이름(별칭)으로 저장된 키도 같은 레포로 보고, 저장할 때는 현재 이름 키로 바꾼다.
                $currentName = $repoScan.preserveTokenMap[$oldKey.Substring($at + 1).ToLowerInvariant()]
                if ($null -ne $currentName -and $keep.Contains([string]$currentName)) { $null = $keys.Add($oldKey.Substring(0, $at + 1) + $currentName) }
            }
            $fields['knownUnregisteredRepoAssets'] = @($keys | Sort-Object)
        }
        elseif ($baselineHasRepoField) {
            # -IncludeRepos 없이 갱신하거나 스캔이 실패했으면 기존 레포 기준선을 그대로 보존한다.
            $fields['knownUnregisteredRepoAssets'] = @($baselineRepoKeys | Sort-Object)
        }
        $snapshot = [pscustomobject]$fields
        # 임시 파일에 쓴 뒤 교체한다(원자적). 읽는 쪽은 교체 순간 없음·공유 위반을 볼 수 있어 재시도한다(Read-BaselineText).
        $temporaryPath = "$baselinePath.tmp-$PID"
        try {
            [IO.File]::WriteAllText($temporaryPath, ($snapshot | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
            if ([IO.File]::Exists($baselinePath)) { [IO.File]::Replace($temporaryPath, $baselinePath, [NullString]::Value) }
            else { [IO.File]::Move($temporaryPath, $baselinePath) }
        }
        finally {
            if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
        }
    }

    # 훅 출력은 Claude Code 계약을 따른다. 신규가 없으면 조용히 통과한다.
    if ($OutputFormat -eq 'Hook') {
        # 스캔 전체 실패("레포 스캔 건너뜀(원인)")와 일부 실패("일부 건너뜀 N건")를 문구로 구분한다.
        $skipText = $(if (-not $IncludeRepos) { '' } elseif ($repoScan.scanFailed) { "레포 스캔 건너뜀($($repoScan.failureReason))" } elseif (@($repoScan.warnings).Count -gt 0) { "레포 스캔 일부 건너뜀 $(@($repoScan.warnings).Count)건" } else { '' })
        if ($reported.Count -eq 0 -and $repoReported.Count -eq 0 -and $skipText -eq '') {
            Write-Output '{"suppressOutput":true}'
        }
        elseif (-not $IncludeRepos) {
            $names = (@($reported | ForEach-Object { $_.name }) -join ', ')
            $message = "새 에이전트 자산 $($reported.Count)건이 킷 정본 밖에 있다: $names — Intake 후보로 올릴지 판단 필요"
            Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ systemMessage = $message }))
        }
        elseif ($reported.Count -eq 0 -and $repoReported.Count -eq 0) {
            # 신규는 없지만 스캔이 일부 건너뛰어졌으면 그 사실만 알린다(조용히 넘기지 않는다).
            Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ systemMessage = $skipText }))
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
                $take = @($repoGroup.Group | Select-Object -First $remaining | ForEach-Object { $_.name + $(if ($_.managedRejectReason) { '(관리 표식 무효)' } else { '' }) })
                $remaining -= $take.Count
                $parts.Add("$($repoGroup.Name): " + ($take -join ', '))
            }
            $list = ($parts.ToArray() -join '; ')
            $more = $total - (10 - $remaining)
            if ($more -gt 0) { $list += " 외 $($more)건" }
            $message = "새 에이전트 자산 $($total)건이 킷 정본 밖에 있다: $list — Intake 후보로 올릴지 판단 필요"
            if ($skipText) { $message += $(if ($repoScan.scanFailed) { " / $skipText" } else { " ($skipText)" }) }
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
                    failedRepos       = @($repoScan.failedRepos)
                    skippedLinks      = @($repoScan.skippedLinks)
                    scanFailed        = [bool]$repoScan.scanFailed
                    warnings          = @($repoScan.warnings)
                    unregisteredCount = $repoReported.Count
                    managedCount      = $repoManaged.Count
                    managedSummary    = @($repoManagedSummary)
                    assets            = @($repoScan.assets | ForEach-Object {
                        [pscustomobject][ordered]@{
                            repo         = $_.repo
                            kind         = $_.kind
                            name         = $_.name
                            relativePath = $_.relativePath
                            vendorDirs   = @($_.vendorDirs)
                            digest       = $_.digest
                            registered   = [bool]$_.registered
                            nameMatchesKit = [bool]$_.nameMatchesKit
                            inBaseline   = [bool]$_.inBaseline
                            linkedOnly   = [bool]$_.linkedOnly
                            managedBy    = [string]$_.managedBy
                            managedVersion = [string]$_.managedVersion
                            managedSource = [string]$_.managedSource
                            managedRejectReason = [string]$_.managedRejectReason
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
            Write-Output "레포 자산: 대상 $($repoScan.repos)개 / 자산 $(@($repoScan.assets).Count)건 / 전체 미등록: $($repoUnregistered.Count)건 / $scope 보고: $($repoReported.Count)건 / 다른 도구가 관리함: $($repoManaged.Count)건"
            foreach ($warning in @($repoScan.warnings)) { Write-Output "  경고: $warning" }
            if (@($repoScan.missingRepos).Count -gt 0) { Write-Output "  없음: $(@($repoScan.missingRepos) -join ', ')" }
            if (@($repoScan.linkedRepos).Count -gt 0) { Write-Output "  링크라 건너뜀: $(@($repoScan.linkedRepos) -join ', ')" }
            if (@($repoScan.skippedLinks).Count -gt 0) { Write-Output "  링크 폴더라 건너뜀: $(@($repoScan.skippedLinks) -join ', ')" }
            foreach ($repoGroup in @($repoReported | Group-Object -Property repo)) {
                Write-Output "  [$($repoGroup.Name)] 미등록:"
                foreach ($item in $repoGroup.Group) {
                    Write-Output "    - $($item.kind) $($item.name)  [$(@($item.vendorDirs) -join ', ')]$(if ($item.linkedOnly) { ' (링크)' })$(if ($item.nameMatchesKit) { ' (킷과 이름만 같음)' })$(if ($item.managedRejectReason) { " (관리 표식 무효: $($item.managedRejectReason))" })"
                }
            }
            if ($repoManagedSummary.Count -gt 0) {
                Write-Output '  다른 도구가 관리함 (킷 미등록으로 세지 않음):'
                foreach ($summary in $repoManagedSummary) {
                    $detail = $(if (@($summary.versions | Where-Object { $_.version }).Count -gt 0) {
                            (@($summary.versions | ForEach-Object {
                                        $label = $(if ($_.version -ceq 'unknown') { '버전 불명' } elseif ($_.version) { $_.version } else { '버전 없음' })
                                        $flag = @($_.repos | Where-Object { $summary.outdatedRepos -contains $_ })
                                        $old = $(if ($_.version -ceq 'unknown') { "($(@($_.repos) -join ', '))" } elseif ($flag.Count -gt 0) { "($($flag -join ', '))" } else { '' })
                                        "$label $($_.count)곳$old"
                                    }) -join ' · ')
                        } else { "$($summary.count)건" })
                    Write-Output "    - $($summary.label) $detail"
                }
            }
            $repoGroups = @($repoScan.groups)
            if ($repoGroups.Count -gt 0) {
                Write-Output '  사본 그룹:'
                foreach ($copyGroup in @($repoGroups | Sort-Object -Property @{ Expression = { $(if ($_.state -eq 'diverged') { 0 } else { 1 }) } }, kind, name)) {
                    $label = $(if ($copyGroup.state -eq 'diverged') { '!! 내용 다름(diverged)' } elseif ($copyGroup.state -eq 'unknown') { '비교 불가(unknown)' } else { '동일(identical)' })
                    Write-Output "    - $($copyGroup.kind) $($copyGroup.name): $label  [$(@($copyGroup.repos) -join ', ')]"
                }
            }
        }
    }

    if ($reported.Count -gt 0 -or $repoReported.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    if ($OutputFormat -eq 'Hook') {
        # 훅은 실패해도 세션을 막지 않는다: 오류를 ASCII systemMessage 로 알리고 exit 0.
        Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ systemMessage = "드리프트 검사 실패: $($_.Exception.Message)" }))
        exit 0
    }
    if ($OutputFormat -eq 'Json') {
        Write-Output (ConvertTo-AsciiJson -Value ([pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Drift'; error = [string]$_.Exception.Message }))
    }
    else {
        Write-Output "드리프트 검사 실패: $($_.Exception.Message)"
    }
    exit 1
}
