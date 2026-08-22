#requires -Version 5.1

# 사용자 홈에 설치된 에이전트 자산 중 킷 레지스트리가 모르는 것을 찾는다.
# 읽기 전용 — 홈과 Git index를 바꾸지 않는다. Intake Scan 은 사람이 승인 후 실행한다.
# exit 0 = 미등록 없음 / 2 = 미등록 발견 / 1 = 오류

[CmdletBinding()]
param(
    [string]$RepositoryRoot,

    [string]$HomeRoot,

    [ValidateSet('Human', 'Json', 'Hook')]
    [string]$OutputFormat = 'Human',

    # 기준선과 대조해 새로 나타난 자산만 보고한다. 기준선이 없으면 전체가 신규다.
    [switch]$NewOnly,

    # 유일한 쓰기 동작. 현재 미등록 목록을 기준선으로 확정해 다음 검사부터 조용해진다.
    [switch]$UpdateBaseline
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not [string]::Equals($full, $root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
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
    if ([IO.File]::Exists($baselinePath)) {
        $baseline = [string]([IO.File]::ReadAllText($baselinePath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
        foreach ($knownId in @($baseline.knownUnregistered)) {
            $null = $baselineIds.Add([string]$knownId)
        }
    }

    $newlyAppeared = @($unregistered | Where-Object { -not $baselineIds.Contains($_.assetId) })
    # @() 로 다시 감싼다. StrictMode 에서는 빈 배열이 스칼라로 붕괴해 Count 접근이 깨진다.
    $reported = @($(if ($NewOnly -or $OutputFormat -eq 'Hook') { $newlyAppeared } else { $unregistered }))

    if ($UpdateBaseline) {
        $baselineDirectory = Split-Path -Parent $baselinePath
        if (-not [IO.Directory]::Exists($baselineDirectory)) {
            $null = New-Item -ItemType Directory -Path $baselineDirectory -Force
        }
        $snapshot = [pscustomobject][ordered]@{
            schemaVersion     = 1
            knownUnregistered = @($unregistered | ForEach-Object { $_.assetId } | Sort-Object)
        }
        [IO.File]::WriteAllText($baselinePath, ($snapshot | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    }

    # 훅 출력은 Claude Code 계약을 따른다. 신규가 없으면 조용히 통과한다.
    if ($OutputFormat -eq 'Hook') {
        if ($reported.Count -eq 0) {
            Write-Output '{"suppressOutput":true}'
        }
        else {
            $names = (@($reported | ForEach-Object { $_.name }) -join ', ')
            $message = "새 에이전트 자산 $($reported.Count)건이 킷 정본 밖에 있다: $names — Intake 후보로 올릴지 판단 필요"
            Write-Output (([pscustomobject][ordered]@{ systemMessage = $message }) | ConvertTo-Json -Compress)
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
        Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
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
    }

    if ($reported.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    if ($OutputFormat -eq 'Json') {
        Write-Output (([pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Drift'; error = [string]$_.Exception.Message }) | ConvertTo-Json -Compress)
    }
    else {
        Write-Output "드리프트 검사 실패: $($_.Exception.Message)"
    }
    exit 1
}
