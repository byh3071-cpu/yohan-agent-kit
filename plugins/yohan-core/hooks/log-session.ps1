#requires -Version 5.1
# log-session.ps1 — StopFailure 훅: 실패로 끝난 세션만 Notion EXECUTION LOG에 기록(SoT Key로 멱등)
# env 이름: 생태계 표준 NOTION_EXECUTION_LOG_DB_ID 우선, sync 주입분 NOTION_EXECLOG_DB 폴백.
# (감사 F23: 훅이 안 set된 짧은 이름만 읽어 매 세션 no-op였음 → 표준 이름 정렬로 해소.)
$ErrorActionPreference = 'Continue'
$token = $env:NOTION_TOKEN
$db = $env:NOTION_EXECUTION_LOG_DB_ID
if (-not $db) { $db = $env:NOTION_EXECLOG_DB }
if (-not $token -or -not $db) { exit 0 }

try { $evt = ([Console]::In.ReadToEnd() | ConvertFrom-Json) } catch { $evt = $null }
$sid = if ($evt -and $evt.session_id) { "$($evt.session_id)" } else { [guid]::NewGuid().ToString() }
$cwd = (Get-Location).Path
$sotKey = $sid

# 세션당 1회만: 로컬 플래그로 매 턴(Stop 훅) 네트워크 왕복 제거(감사 F5). 있으면 즉시 종료.
$flagDir = Join-Path $env:USERPROFILE '.claude\.cache'
if (-not (Test-Path -LiteralPath $flagDir)) { try { New-Item -ItemType Directory -Path $flagDir -Force | Out-Null } catch {} }
$flag = Join-Path $flagDir ("log-session-$sid.done")
if (Test-Path -LiteralPath $flag) { exit 0 }

$headers = @{ 'Authorization' = "Bearer $token"; 'Notion-Version' = '2022-06-28'; 'Content-Type' = 'application/json; charset=utf-8' }

function Invoke-Notion($uri, $obj) {
  $json = ($obj | ConvertTo-Json -Depth 20)
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bytes
}

# 멱등: SoT Key 이미 있으면 로컬 플래그만 남기고 종료(크로스머신 중복 생성 방지).
try {
  $q = @{ filter = @{ property = 'SoT Key'; rich_text = @{ equals = $sotKey } }; page_size = 1 }
  $existing = Invoke-Notion "https://api.notion.com/v1/databases/$db/query" $q
  if ($existing.results.Count -gt 0) { try { New-Item -ItemType File -Path $flag -Force | Out-Null } catch {}; exit 0 }
} catch { }

$branch = ''
try { $branch = (git -C "$cwd" rev-parse --abbrev-ref HEAD 2>$null) } catch {}
$meta = "Claude Code 세션이 실패로 종료됨 (cwd: $cwd" + $(if ($branch) { "; branch: $branch" } else { '' }) + "). 교훈 칸은 사람이 채운다."
$title = "[CC-FAIL] $(Split-Path $cwd -Leaf) — $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$props = @{
  '이름'      = @{ title = @(@{ text = @{ content = $title } }) }
  '실행일'    = @{ date = @{ start = (Get-Date -Format 'yyyy-MM-dd') } }
  '결과'      = @{ select = @{ name = '실패' } }
  '작업 유형' = @{ select = @{ name = '에러 대응' } }
  '상태'      = @{ status = @{ name = '미처리' } }
  '작업 내용' = @{ rich_text = @(@{ text = @{ content = $meta } }) }
  'SoT Key'   = @{ rich_text = @(@{ text = @{ content = $sotKey } }) }
}
$page = @{ parent = @{ database_id = $db }; properties = $props }
try { Invoke-Notion 'https://api.notion.com/v1/pages' $page | Out-Null; New-Item -ItemType File -Path $flag -Force | Out-Null } catch { }
exit 0
