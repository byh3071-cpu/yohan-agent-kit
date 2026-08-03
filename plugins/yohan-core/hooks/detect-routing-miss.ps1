#requires -Version 5.1
# detect-routing-miss.ps1 — SessionEnd 훅: 상시 지휘자(conductor_always_on) 라우팅 선언 vs 실측 대조.
# 불일치(무선언 M/L, 선언≠실측)면 로컬 캐시 ~/.claude/.cache/routing-misses.jsonl 에 append.
# 크로스레포 쓰기 회피: brain ROUTING-MISSES.md 직접수정 금지(레포 dirty·충돌) → W2-3 메타리뷰가 수확.
# fail-open: 어떤 실패도 세션을 막지 않는다(exit 0).
# ★ 이 파일은 한글 정규식('라우팅:')을 담으므로 반드시 UTF-8 BOM 저장(PS5.1 cp949 오독 방지).
$ErrorActionPreference = 'Continue'
try { $evt = ([Console]::In.ReadToEnd() | ConvertFrom-Json) } catch { exit 0 }
if (-not $evt.session_id) { exit 0 }
$sid = "$($evt.session_id)"
$cwd = if ($evt.cwd) { "$($evt.cwd)" } else { (Get-Location).Path }
$tp = "$($evt.transcript_path)"

$cacheDir = Join-Path $env:USERPROFILE '.claude\.cache'
$startFile = Join-Path $cacheDir "routing-$sid.start"
if (-not (Test-Path -LiteralPath $startFile)) { exit 0 }   # SessionStart baseline 없으면 실측 불가
$start = (Get-Content -Raw -LiteralPath $startFile).Trim()
# 이후 분석이 시간 제한으로 중단돼도 다음 세션에 오래된 기준점이 남지 않게 먼저 정리한다.
Remove-Item -LiteralPath $startFile -Force -ErrorAction SilentlyContinue

# --- 실측: 세션 시작 sha 대비 변경 파일수 (커밋분 ∪ uncommitted) ---
$changed = @{}
try {
  (& git -c core.fsmonitor=false -C "$cwd" diff --name-only "$start" HEAD 2>$null) | ForEach-Object { if ($_) { $changed[$_] = 1 } }
  (& git -c core.fsmonitor=false -C "$cwd" status --porcelain 2>$null) | ForEach-Object { if ($_.Length -gt 3) { $changed[$_.Substring(3)] = 1 } }
} catch {}
$fileCount = $changed.Count
if ($fileCount -eq 0) { exit 0 }
$actual = if ($fileCount -le 2) { 'S' } elseif ($fileCount -le 6) { 'M' } else { 'L' }

# --- 선언: 트랜스크립트에서 마지막 '라우팅: X' (성능 위해 후보 라인만 파싱) ---
$declared = $null
if ($tp -and (Test-Path -LiteralPath $tp)) {
  try {
    # JSONL 전체를 훑지 않고 최근 후보만 읽어 SessionEnd 작업량을 제한한다.
    $candidateLines = @(Get-Content -LiteralPath $tp -Tail 2000 -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '라우팅:' })
    foreach ($line in $candidateLines) {
      try {
        $o = $line | ConvertFrom-Json
        if ($o.role -eq 'assistant' -and $o.content) {
          foreach ($blk in $o.content) {
            if ($blk.type -eq 'text' -and $blk.text -match '라우팅:\s*([SML])\b') { $declared = $matches[1] }
          }
        }
      } catch {}
    }
  } catch {}
}

# --- 미스 판정 ---
$miss = $false; $reason = ''
if (-not $declared) {
  if ($actual -ne 'S') { $miss = $true; $reason = "무선언(실측 $actual, ${fileCount}파일)" }
} elseif ($declared -ne $actual) {
  $miss = $true; $reason = "선언 $declared != 실측 $actual (${fileCount}파일)"
}

if ($miss) {
  $rec = [ordered]@{
    date = (Get-Date -Format 'yyyy-MM-dd'); repo = (Split-Path $cwd -Leaf)
    declared = $(if ($declared) { $declared } else { 'none' }); actual = $actual
    files = $fileCount; signal = $reason; sid = $sid; source = 'auto'
  } | ConvertTo-Json -Compress
  try { Add-Content -LiteralPath (Join-Path $cacheDir 'routing-misses.jsonl') -Value $rec -Encoding UTF8 } catch {}
}
exit 0
