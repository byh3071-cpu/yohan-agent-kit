#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { getWindowsPowerShellEnv } from './windows-powershell-env.mjs'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const localOnly = process.argv.includes('--local') || process.env.VHK_GATES_SKIP_EXTERNAL === '1'
const skipDeep = process.env.VHK_GATES_SKIP_DEEP === '1'
let pass = true
const gate = (label, ok, detail = '') => {
  console.log(`[goal 8] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 8] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/8-two-machine-four-vendor-validation.md', 'scripts/Test-AgentKitCompatibility.ps1',
  'goals/9-vendor-payload-chain-attestation.md',
  'tests/AgentKitCompatibility.Tests.ps1', 'fixtures/agent-kit-session-results.example.json',
  'fixtures/agent-kit-transaction-results.example.json', 'docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))
const compatibility = readFileSync(join(repoRoot, 'scripts/Test-AgentKitCompatibility.ps1'), 'utf8')
gate('top-level automation obeys HARD_STOP', compatibility.includes('.vhk\\HARD_STOP'))
gate('single-machine verification binds evidence to current live state',
  compatibility.includes('schemaVersion must be 2; regenerate evidence') &&
  compatibility.includes('agent-kit-home-root-v1') &&
  compatibility.includes('House PC evidence machine ID differs from the current machine') &&
  compatibility.includes('House PC evidence HomeRoot digest differs from the current canonical HomeRoot') &&
  compatibility.includes("Join-Path $kitRoot 'active.json'") &&
  compatibility.includes("Join-Path $kitRoot 'active'") &&
  compatibility.includes('House PC evidence release identity differs from the installed release') &&
  compatibility.includes('Current house-PC CLI identity differs from the evidence') &&
  compatibility.includes('Antigravity evidence requires the native agy.exe application'))
gate('wrapper payload-chain attestation remains an explicit P2 follow-up',
  readFileSync(join(repoRoot, 'goals/8-two-machine-four-vendor-validation.md'), 'utf8').includes('Goal 9') &&
  readFileSync(join(repoRoot, 'docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md'), 'utf8').includes('SingleMachineVerified`는 wrapper 뒤 backend payload-chain 무결성을 증명하지 않는다'))

if (!skipDeep) {
  try {
    const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'tests/AgentKitCompatibility.Tests.ps1'], {
      cwd: repoRoot, encoding: 'utf8', timeout: 8 * 60_000, windowsHide: true, maxBuffer: 64 * 1024 * 1024,
      env: getWindowsPowerShellEnv(process.env)
    })
    const summary = output.match(/PASS:\s+\d+ assertions/)?.[0] ?? ''
    gate('local evidence contract tests', Boolean(summary), summary)
  } catch (error) {
    console.log(`${error.stdout ?? ''}${error.stderr ?? ''}`.trim())
    gate('local evidence contract tests', false, `exit ${error.status ?? 'unknown'}`)
  }
} else console.log('[goal 8] deep tests: SKIP (VHK_GATES_SKIP_DEEP=1)')

if (localOnly) {
  console.log('[goal 8] external house-PC evidence: SKIP (local contract gate only)')
} else {
  const homeEvidence = process.env.YAK_HOME_EVIDENCE
  const laptopEvidence = process.env.YAK_LAPTOP_EVIDENCE
  if (!homeEvidence) gate('house-PC evidence path provided', false, 'set YAK_HOME_EVIDENCE')
  else {
    try {
      const output = execFileSync('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', 'scripts/Test-AgentKitCompatibility.ps1', '-Mode', 'Verify',
        '-EvidencePath', homeEvidence,
        '-RepositoryRoot', repoRoot, '-OutputFormat', 'Json'
      ], { cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true, env: getWindowsPowerShellEnv(process.env) })
      const result = JSON.parse(output)
      gate('house-PC four-vendor final evidence', result.status === 'SingleMachineVerified', result.releaseId)
    } catch (error) { gate('house-PC four-vendor final evidence', false, `exit ${error.status ?? 'unknown'}`) }
  }

  if (!laptopEvidence) {
    console.log('[goal 8] optional laptop comparison: DEFERRED')
  } else if (homeEvidence) {
    try {
      const output = execFileSync('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', 'scripts/Test-AgentKitCompatibility.ps1', '-Mode', 'Compare',
        '-EvidencePath', homeEvidence, '-OtherEvidencePath', laptopEvidence,
        '-RepositoryRoot', repoRoot, '-OutputFormat', 'Json'
      ], { cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true, env: getWindowsPowerShellEnv(process.env) })
      const result = JSON.parse(output)
      gate('optional multi-machine comparison', result.status === 'Compatible', result.releaseId)
    } catch (error) { gate('optional multi-machine comparison', false, `exit ${error.status ?? 'unknown'}`) }
  }
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 8] gate passes' : '[goal 8] gate failed')
process.exit(pass ? 0 : 1)
