#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
let pass = true

const gate = (label, ok, detail = '') => {
  console.log(`[goal 17] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/u, '')
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 17] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/17-claude-skill-deployment.md',
  'docs/decisions/2026-08-26-claude-personal-skill-materialization.md',
  'docs/plans/goal-17-claude-skill-deployment.md',
  'docs/MULTIVENDOR_SKILL_DISTRIBUTION.md',
  'docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md',
  'goals/8-two-machine-four-vendor-validation.md',
  'scripts/Manage-MultivendorSkills.ps1',
  'tests/Manage-MultivendorSkills.Tests.ps1',
  'scripts/check-goal-17.mjs'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const adr = read('docs/decisions/2026-08-26-claude-personal-skill-materialization.md')
const plan = read('docs/plans/goal-17-claude-skill-deployment.md')
const goal = read('goals/17-claude-skill-deployment.md')
gate('ADR frontmatter and body are Accepted',
  /^---[\s\S]*?^status: Accepted\s*$[\s\S]*?^---/mu.test(adr) && adr.includes('- 상태: **Accepted**'))
gate('implementation plan is IN_PROGRESS', /^---[\s\S]*?^status: IN_PROGRESS\s*$/mu.test(plan))
gate('Goal 17 remains IN_PROGRESS', /^---[\s\S]*?^status: IN_PROGRESS\s*$/mu.test(goal))
gate('actual HomeRoot, Git delivery, and paid smoke remain gated',
  has(adr, '실제 HomeRoot', 'commit·push·PR·merge', '유료 fresh smoke') &&
  has(plan, '실제 HomeRoot·Git delivery·유료 smoke는 후속 사람 게이트'))

const manager = read('scripts/Manage-MultivendorSkills.ps1')
gate('manager publishes contract 5 and transaction schema 5',
  has(manager, "contractVersion = 5", "schemaVersion = 5", "[ValidateSet(3, 4, 5)]"))
gate('Claude alone uses the deterministic physical adapter kind',
  has(manager, "role = 'Claude'; category = 'Deploy'; deploymentKind = 'Adapter'", "adapterKind = 'claude-code-personal-physical-copy'"))
gate('historical transaction schemas remain accepted', manager.includes("$transactionSchema -notin @(3, 4, 5)"))
gate('schema 5 preserves and restores the exact Junction',
  has(manager, 'preservedJunctionPath', 'junctionPreserved', 'Move-OwnedJunctionExact', "action -eq 'ReplaceJunctionWithAdapter'"))
gate('Check binds source, adapter, identity, and recovery state into PlanDigest',
  has(manager, 'sourceCommit', 'sourceDigest', 'adapterKind', 'currentJunctionIdentity', 'recoveryIds', 'expectedDigest'))
gate('AGY adapter identity remains distinct',
  has(manager, "adapterKind = 'agy-cli-physical-copy'", 'Get-AgyAdapterInfo', 'New-AgyAdapterDirectory'))

const tests = read('tests/Manage-MultivendorSkills.Tests.ps1')
gate('red-to-green contract assertions are present',
  has(tests, 'Goal 17 install plan uses contract 5', 'Contract 5 materializes Claude as a sealed adapter', 'Missing Claude personal skill plans adapter creation'))
gate('Claude drift and no-overwrite assertions are present',
  has(tests, 'Claude metadata drift is a conflict', 'Claude payload drift is a conflict', 'Claude additional-file drift is a conflict', 'Claude nested reparse drift is a conflict', 'Claude metadata drift is never overwritten'))
gate('schema 3, 4, and 5 Restore assertions are present',
  has(tests, 'Schema 3 Restore compatibility', 'Schema 4 Claude Junction Restore compatibility', 'Schema 5 preserved-junction Restore passes'))
gate('preserved Junction interruption and identity assertions are present',
  has(tests, 'Quarantined Junction before adapter activation is recoverable', 'Interrupted rollback returns the exact original Junction identity', 'Migration exact move preserves the NTFS junction identity'))

const distribution = read('docs/MULTIVENDOR_SKILL_DISTRIBUTION.md')
const goal8 = read('goals/8-two-machine-four-vendor-validation.md')
const runbook = read('docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md')
gate('distribution contract documents schema 5 and historical Restore',
  has(distribution, 'schema 5 write-ahead transaction', 'schema 3·4 백업', 'claude-code-personal-physical-copy', 'fresh `--bare` receipt'))
gate('Goal 8 and runbook separate filesystem health from discovery',
  has(goal8, '[Goal 17](17-claude-skill-deployment.md)', 'filesystem `Healthy`', 'runtime discovery receipt') &&
  has(runbook, '[Goal 17](../goals/17-claude-skill-deployment.md)', 'filesystem `Healthy`', 'fresh `--bare` receipt'))

try {
  const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh'
  const command = [
    '$tokens=$null', '$errors=$null',
    "$null=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/Manage-MultivendorSkills.ps1'),[ref]$tokens,[ref]$errors)",
    'if($errors.Count -gt 0){$errors | ForEach-Object {$_.Message}; exit 1}'
  ].join('; ')
  execFileSync(shell, ['-NoProfile', '-NonInteractive', '-Command', command], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 60_000,
    windowsHide: true
  })
  gate('PowerShell manager parser', true)
} catch (error) {
  gate('PowerShell manager parser', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs'], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 120_000,
    windowsHide: true
  }).trim()
  gate('registry and catalog are consistent', /\[asset-catalog\] PASS/u.test(output), output)
} catch (error) {
  gate('registry and catalog are consistent', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 30_000,
    windowsHide: true
  })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 17] gate passes' : '[goal 17] gate failed')
process.exit(pass ? 0 : 1)
