#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
let pass = true
const gate = (label, ok, detail = '') => {
  console.log(`[goal 4] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 4] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/4-claude-auto-session-title.md',
  'plugins/yohan-core/hooks/auto-session-title.ps1',
  'plugins/yohan-core/hooks/hooks.json',
  'plugins/yohan-core/.claude-plugin/plugin.json',
  '.claude-plugin/marketplace.json',
  'tests/AutoSessionTitle.Tests.ps1'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const goal = read('goals/4-claude-auto-session-title.md')
gate('Goal 4 lifecycle', /status:\s*(?:IN_PROGRESS|DONE)/.test(goal))

if (existsSync(join(repoRoot, 'plugins/yohan-core/hooks/auto-session-title.ps1'))) {
  const script = read('plugins/yohan-core/hooks/auto-session-title.ps1')
  gate('machine-neutral hook', !/(?:C:\\Users\\|C:\/Users\/|Users\\Public)/i.test(script))
}

try {
  const hooks = JSON.parse(read('plugins/yohan-core/hooks/hooks.json')).hooks
  const commands = (event) => (hooks[event] || []).flatMap((group) => group.hooks || []).map((hook) => hook.command || '')
  for (const event of ['SessionStart', 'UserPromptExpansion', 'UserPromptSubmit']) {
    gate(`${event} registration`, commands(event).some((command) => command.includes('${CLAUDE_PLUGIN_ROOT}/hooks/auto-session-title.ps1')))
  }
} catch (error) {
  gate('hooks.json schema', false, error.message)
}

try {
  const pluginVersion = JSON.parse(read('plugins/yohan-core/.claude-plugin/plugin.json')).version
  const marketplace = JSON.parse(read('.claude-plugin/marketplace.json'))
  const listedVersion = marketplace.plugins.find((plugin) => plugin.name === 'yohan-core')?.version
  gate('plugin cache version bump', pluginVersion === '0.3.24' && listedVersion === pluginVersion, `${pluginVersion}/${listedVersion}`)
} catch (error) {
  gate('plugin manifest consistency', false, error.message)
}

try {
  const output = execFileSync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'tests/AutoSessionTitle.Tests.ps1'], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 2 * 60 * 1000,
    windowsHide: true,
    maxBuffer: 4 * 1024 * 1024
  })
  gate('PowerShell behavior tests', /PASS:\s+\d+ assertions/.test(output), output.trim().split(/\r?\n/).slice(-1)[0])
} catch (error) {
  const output = `${error.stdout || ''}${error.stderr || ''}`
  console.log(output.split(/\r?\n/).slice(-20).join('\n'))
  gate('PowerShell behavior tests', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  execFileSync('git.exe', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 4] gate passes' : '[goal 4] gate failed')
process.exit(pass ? 0 : 1)
