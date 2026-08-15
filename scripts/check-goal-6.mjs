#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { getWindowsPowerShellEnv } from './windows-powershell-env.mjs'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skipDeep = process.env.VHK_GATES_SKIP_DEEP === '1'
let pass = true
const gate = (label, ok, detail = '') => {
  console.log(`[goal 6] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')

if (existsSync(join(repoRoot, '.vhk/HARD_STOP'))) {
  console.log('[goal 6] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/6-versioned-release-store.md', 'registry/release-bundles.json',
  'scripts/Build-AgentKit.mjs', 'scripts/Manage-AgentKit.ps1',
  'tests/Build-AgentKit.Tests.ps1', 'tests/Manage-AgentKit.Tests.ps1',
  'docs/AGENT_KIT_RELEASES.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

try {
  const config = JSON.parse(read('registry/release-bundles.json'))
  const targets = Object.keys(config.targets).sort()
  gate('five output package contracts', JSON.stringify(targets) === JSON.stringify(['agent-plugins', 'antigravity', 'claude-code', 'codex', 'cursor']))
  gate('Agent Plugins is skills plus MCP only', JSON.stringify(config.targets['agent-plugins'].components) === JSON.stringify(['skills', 'mcp']))
  gate('Claude compatibility namespace is documented', read('docs/AGENT_KIT_RELEASES.md').includes('yohan-cc-skills'))
} catch (error) { gate('release registry contract', false, error.message) }

const manager = read('scripts/Manage-AgentKit.ps1')
gate('top-level public modes', ['Check', 'Install', 'Update', 'Restore'].every((mode) => manager.includes(`'${mode}'`)))
gate('mutations require explicit global-home approval', manager.includes('ApproveGlobalHomeWrite') && manager.includes('PlanDigest'))
gate('Antigravity mutations bind the checked native agy identity',
  manager.includes('AntigravityCommandDigest') &&
  manager.includes('Get-AntigravityCommandIdentity') &&
  manager.includes('Production Antigravity command must resolve to the native agy.exe application') &&
  manager.includes('Antigravity command identity changed after Check; run Check again'))
gate('Antigravity read-only preflight binds the approved agy identity',
  manager.split('$approvedAntigravityCommandIdentity = Assert-AntigravityCommandDigest').length - 1 === 2 &&
  manager.includes("Test-AntigravityPluginRegistered -Command $AntigravityCliCommand -UserHome $UserHome -PluginName 'yohan-agent-kit' -ExpectedCommandIdentity $approvedAntigravityCommandIdentity") &&
  manager.includes('Get-AntigravityManagedRestoreState -Item $item -Command $AntigravityCliCommand -UserHome $UserHome -ExpectedCommandIdentity $approvedAntigravityCommandIdentity'))
gate('top-level automation obeys HARD_STOP', manager.includes('.vhk\\HARD_STOP') && read('scripts/Build-AgentKit.mjs').includes("'.vhk', 'HARD_STOP'"))
gate('exact rollback identity', manager.includes('Get-JunctionIdentity') && manager.includes('BackupId format is invalid'))
gate('low-level skill manager remains present', existsSync(join(repoRoot, 'scripts/Manage-MultivendorSkills.ps1')))

if (!skipDeep) {
  for (const test of ['tests/Build-AgentKit.Tests.ps1', 'tests/Manage-AgentKit.Tests.ps1']) {
    try {
      const output = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', test], {
        cwd: repoRoot, encoding: 'utf8', timeout: 8 * 60_000, windowsHide: true, maxBuffer: 64 * 1024 * 1024,
        env: getWindowsPowerShellEnv(process.env)
      })
      const summary = output.match(/PASS:\s+\d+ assertions/)?.[0] ?? ''
      gate(test, Boolean(summary), summary)
    } catch (error) {
      console.log(`${error.stdout ?? ''}${error.stderr ?? ''}`.trim())
      gate(test, false, `exit ${error.status ?? 'unknown'}`)
    }
  }
} else console.log('[goal 6] deep tests: SKIP (VHK_GATES_SKIP_DEEP=1)')

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 6] gate passes' : '[goal 6] gate failed')
process.exit(pass ? 0 : 1)
