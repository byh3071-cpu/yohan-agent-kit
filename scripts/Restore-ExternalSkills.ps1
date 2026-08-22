#requires -Version 5.1

# registry/assets.yaml 에 external:// 로 등록된 외부 스킬을 원본 저장소에서 재설치한다.
# 목록을 하드코딩하지 않고 레지스트리를 읽으므로, 등록만 늘리면 복원 범위도 함께 늘어난다.
# 기본은 계획 출력(읽기 전용)이며 실제 설치는 -ApproveInstall 을 명시할 때만 수행한다.
# exit 0 = 대상 없음 또는 성공 / 1 = 오류 / 2 = 설치할 대상이 있음(계획 모드)

[CmdletBinding()]
param(
    [string]$RepositoryRoot,

    # 특정 출처 저장소만 복원한다. 예: 'tjboudreaux/cc-thinking-skills'
    [string]$Owner,

    # 설치 대상 에이전트. skills CLI 의 --agent 값을 그대로 전달한다.
    [string[]]$Agent = @('claude-code'),

    [ValidateSet('Human', 'Json')]
    [string]$OutputFormat = 'Human',

    [switch]$ApproveInstall
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

# provenance 는 external:https://github.com/<owner>/<repo>@<sha> 형태다.
function Get-SourceRef {
    param([Parameter(Mandatory = $true)][string]$Provenance)

    if ($Provenance -notmatch '^external:https://github\.com/([^/]+)/([^/@]+)@([0-9a-f]{7,40})$') {
        return $null
    }
    return [pscustomobject][ordered]@{
        slug = "$($Matches[1])/$($Matches[2])"
        sha  = $Matches[3]
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    }
    $RepositoryRoot = Get-NormalizedFullPath $RepositoryRoot

    $registryPath = Join-Path $RepositoryRoot 'registry\assets.yaml'
    if (-not [IO.File]::Exists($registryPath)) { throw 'Registry not found: registry\assets.yaml' }

    $registry = [string]([IO.File]::ReadAllText($registryPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
    if ([int]$registry.schemaVersion -ne 1) { throw "Unsupported registry schemaVersion: $($registry.schemaVersion)" }

    $external = @($registry.assets | Where-Object { [string]$_.sourcePath -like 'external://*' })
    if (-not [string]::IsNullOrWhiteSpace($Owner)) {
        $external = @($external | Where-Object { [string]$_.owner -eq $Owner })
    }

    # 같은 저장소에서 온 스킬은 한 번의 명령으로 묶어 설치한다.
    $groups = @()
    foreach ($group in ($external | Group-Object -Property owner)) {
        $ref = Get-SourceRef -Provenance ([string]$group.Group[0].provenance)
        if ($null -eq $ref) {
            Write-Output "출처 형식을 해석할 수 없어 건너뜀: $($group.Name)"
            continue
        }
        $skills = @($group.Group | ForEach-Object { ([string]$_.id) -replace '^skill\.', '' } | Sort-Object)
        $arguments = @('-y', 'skills@latest', 'add', $ref.slug)
        foreach ($s in $skills) { $arguments += @('--skill', $s) }
        foreach ($a in $Agent) { $arguments += @('--agent', $a) }
        $arguments += '-g'

        $groups += [pscustomobject][ordered]@{
            owner   = [string]$group.Name
            slug    = $ref.slug
            sha     = $ref.sha
            skills  = $skills
            command = "npx $([string]::Join(' ', $arguments))"
            args    = $arguments
        }
    }

    if ($OutputFormat -eq 'Json') {
        Write-Output (([pscustomobject][ordered]@{
            schemaVersion = 1
            mode          = $(if ($ApproveInstall) { 'Install' } else { 'Plan' })
            groupCount    = $groups.Count
            skillCount    = @($external).Count
            groups        = @($groups | ForEach-Object {
                [pscustomobject][ordered]@{ owner = $_.owner; sha = $_.sha; skills = @($_.skills); command = $_.command }
            })
        }) | ConvertTo-Json -Depth 6 -Compress)
    }
    else {
        Write-Output "외부 등록 자산 $(@($external).Count)건 / 출처 $($groups.Count)곳"
        foreach ($g in $groups) {
            Write-Output ''
            Write-Output "[$($g.owner)] $($g.skills.Count)건  (기록 시점 $($g.sha.Substring(0, 7)))"
            Write-Output "  $($g.command)"
        }
        if (-not $ApproveInstall -and $groups.Count -gt 0) {
            Write-Output ''
            Write-Output '계획만 출력했다. 실제 설치는 -ApproveInstall 을 붙여 실행한다.'
            Write-Output '설치되는 것은 각 저장소의 현재 기본 브랜치 내용이며 위 SHA 로 고정되지 않는다.'
        }
    }

    if (-not $ApproveInstall) {
        if ($groups.Count -gt 0) { exit 2 }
        exit 0
    }

    foreach ($g in $groups) {
        Write-Output "설치: $($g.owner) ($($g.skills.Count)건)"
        & npx @($g.args)
        if ($LASTEXITCODE -ne 0) { throw "설치 실패: $($g.owner) (exit $LASTEXITCODE)" }
    }
    Write-Output '복원 완료'
    exit 0
}
catch {
    if ($OutputFormat -eq 'Json') {
        Write-Output (([pscustomobject][ordered]@{ schemaVersion = 1; mode = 'Restore'; error = [string]$_.Exception.Message }) | ConvertTo-Json -Compress)
    }
    else {
        Write-Output "복원 실패: $($_.Exception.Message)"
    }
    exit 1
}
