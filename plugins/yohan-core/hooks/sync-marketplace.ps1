#requires -Version 5.1
# sync-marketplace.ps1 — SessionEnd 훅: 이미 가져온 원격 참조와 로컬 상태를 가볍게 비교.
# 이 스크립트는 <repo>/plugins/yohan-core/hooks/ 에 위치 → 3단계 위가 레포 루트(클론 경로 무관).
$ErrorActionPreference = 'Continue'
$skills = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..') -ErrorAction SilentlyContinue).Path
# SessionEnd 제한 안에서 끝나도록 네트워크 요청은 하지 않는다. 원격 갱신은 다음 부팅의 git-auto-pull이 담당한다.
# .git 존재 가드: 마켓 설치본은 비-git 일 수 있어 비교가 무의미(또는 엉뚱한 상위 레포를 건드림) → git 클론일 때만 진행.
if ($skills -and (Test-Path $skills) -and (Test-Path (Join-Path $skills '.git'))) {
  Push-Location $skills
  try {
    $local = git rev-parse '@' 2>$null
    $remote = git rev-parse '@{u}' 2>$null
    if ($local -and $remote -and ($local -ne $remote)) {
      Write-Output "[yohan-core] yohan-cc-skills 원격 업데이트 있음 → 다음 부팅 git-auto-pull이 반영하거나 '/plugin marketplace update' 실행 권장."
    }
  } catch {} finally { Pop-Location }
}
exit 0
