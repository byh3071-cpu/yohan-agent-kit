#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skipDeep = process.env.VHK_GATES_SKIP_DEEP === '1'
let pass = true
const gate = (label, ok, detail = '') => {
  console.log(`[goal 7] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 7] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/7-knowledge-intake.md', 'scripts/Manage-AgentIntake.ps1',
  'tests/Manage-AgentIntake.Tests.ps1', 'docs/AGENT_KIT_INTAKE.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const script = read('scripts/Manage-AgentIntake.ps1')
gate('raw inbox remains outside repository', script.includes("'.yohan-agent-kit\\inbox'") && read('.gitignore').includes('.yohan-agent-kit/'))
gate('candidate and reviewed are automation ceiling', script.includes("lifecycle = 'candidate'") && script.includes("lifecycle = 'reviewed'"))
gate('no automatic push or PR creation', !/\bgit\s+push\b|\bgh\s+pr\s+create\b|Invoke-RestMethod/.test(script))
gate('secret, absolute path, duplicate, and license checks', ['secret-pattern', 'absolute-path', 'duplicate:', 'license:'].every((value) => script.includes(value)))
gate('Draft bundle records pushAuthorized false', script.includes('pushAuthorized = $false'))
gate('top-level automation obeys HARD_STOP', script.includes('.vhk\\HARD_STOP'))

if (!skipDeep) {
  try {
    const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'tests/Manage-AgentIntake.Tests.ps1'], {
      cwd: repoRoot, encoding: 'utf8', timeout: 8 * 60_000, windowsHide: true, maxBuffer: 64 * 1024 * 1024
    })
    const summary = output.match(/PASS:\s+\d+ assertions/)?.[0] ?? ''
    gate('intake lifecycle and safety tests', Boolean(summary), summary)
  } catch (error) {
    console.log(`${error.stdout ?? ''}${error.stderr ?? ''}`.trim())
    gate('intake lifecycle and safety tests', false, `exit ${error.status ?? 'unknown'}`)
  }
} else console.log('[goal 7] deep tests: SKIP (VHK_GATES_SKIP_DEEP=1)')

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 7] gate passes' : '[goal 7] gate failed')
process.exit(pass ? 0 : 1)
