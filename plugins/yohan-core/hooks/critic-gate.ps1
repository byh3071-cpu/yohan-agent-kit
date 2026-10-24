#requires -Version 5.1
# critic-gate.ps1 — git push 직전 게이트: critic 통과 마커 확인
# 2026-10-07: 강제 critic/release-gate는 전면 보류한다. 이 과거 hook은 실행 게이트가 아니다.
# 시크릿·파괴적 명령 보호 hook과 사람 승인 경계는 별도로 유지한다.
exit 0

$ErrorActionPreference = 'Continue'

# stdin의 tool_input.command를 읽어 git push가 아니면 즉시 통과(읽기 전용·일반 명령은 자동 승인).
# hooks.json의 if 매처가 적용 안 되는 환경 대비 — 스크립트가 직접 명령어를 보고 push에만 게이트를 건다.
$cmd = ''
try {
  $raw = [Console]::In.ReadToEnd()
  if ($raw) { $cmd = "$(($raw | ConvertFrom-Json).tool_input.command)" }
} catch { $cmd = '' }
if ($cmd -notmatch '(?i)\bgit\b(\s+-\S+(\s+\S+)?)*\s+push\b') { exit 0 }

$gate = Join-Path (Get-Location).Path '.claude/.gate-pass'
$ok = $false
if (Test-Path $gate) {
  $age = (Get-Date) - (Get-Item $gate).LastWriteTime
  if ($age.TotalHours -lt 6) { $ok = $true }
}
if (-not $ok) {
  $reason = "critic-gate: 릴리즈 게이트 미통과. '/flow' 또는 '/release-gate'로 적대적 리뷰를 통과한 뒤 push 하세요. (통과 시 .claude/.gate-pass 갱신)"
  $out = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } } | ConvertTo-Json -Depth 5 -Compress
  # PAT-002: 비-ASCII 를 \uXXXX 로 강제(모지바케·JSON 파싱실패 방지).
  $out = [regex]::Replace($out, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]($m.Value[0]) })
  Write-Output $out
}
exit 0
