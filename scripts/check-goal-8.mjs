#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

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
  'tests/AgentKitCompatibility.Tests.ps1', 'fixtures/agent-kit-session-results.example.json',
  'fixtures/agent-kit-transaction-results.example.json', 'docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))
gate('top-level automation obeys HARD_STOP', readFileSync(join(repoRoot, 'scripts/Test-AgentKitCompatibility.ps1'), 'utf8').includes('.vhk\\HARD_STOP'))

if (!skipDeep) {
  try {
    const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'tests/AgentKitCompatibility.Tests.ps1'], {
      cwd: repoRoot, encoding: 'utf8', timeout: 8 * 60_000, windowsHide: true, maxBuffer: 64 * 1024 * 1024
    })
    const summary = output.match(/PASS:\s+\d+ assertions/)?.[0] ?? ''
    gate('local evidence contract tests', Boolean(summary), summary)
  } catch (error) {
    console.log(`${error.stdout ?? ''}${error.stderr ?? ''}`.trim())
    gate('local evidence contract tests', false, `exit ${error.status ?? 'unknown'}`)
  }
} else console.log('[goal 8] deep tests: SKIP (VHK_GATES_SKIP_DEEP=1)')

if (localOnly) {
  console.log('[goal 8] external two-machine evidence: SKIP (local gate only)')
} else {
  const homeEvidence = process.env.YAK_HOME_EVIDENCE
  const laptopEvidence = process.env.YAK_LAPTOP_EVIDENCE
  if (!homeEvidence || !laptopEvidence) gate('two-machine evidence paths provided', false, 'set YAK_HOME_EVIDENCE and YAK_LAPTOP_EVIDENCE')
  else {
    try {
      const output = execFileSync('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', 'scripts/Test-AgentKitCompatibility.ps1', '-Mode', 'Compare',
        '-EvidencePath', homeEvidence, '-OtherEvidencePath', laptopEvidence,
        '-RepositoryRoot', repoRoot, '-OutputFormat', 'Json'
      ], { cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true })
      const result = JSON.parse(output)
      gate('two-machine four-vendor evidence', result.status === 'Compatible', result.releaseId)
    } catch (error) { gate('two-machine four-vendor evidence', false, `exit ${error.status ?? 'unknown'}`) }
  }
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 8] gate passes' : '[goal 8] gate failed')
process.exit(pass ? 0 : 1)
