#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skillNames = [
  'supervised-session-conductor',
  'restart-safe-handoff',
  'runtime-incident-investigator'
]
const manifestNames = ['design-team', ...skillNames]
const requiredVendors = ['agent-plugins', 'claude-code', 'codex', 'cursor', 'antigravity']
let pass = true

const gate = (label, ok, detail = '') => {
  console.log(`[goal 15] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^﻿/u, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 15] HARD_STOP detected: FAIL')
  process.exit(1)
}

for (const path of [
  'goals/15-session-operations-skills.md',
  'docs/audits/session-operations-skills-2026-08-23.md',
  'tests/fixtures/session-operations-adversarial.json',
  'skills/design-team/references/session-continuity.md',
  'skills/supervised-session-conductor/references/operating-manual.md',
  ...skillNames.flatMap((name) => [`skills/${name}/SKILL.md`, `skills/${name}/agents/openai.yaml`]),
  ...manifestNames.map((name) => `distribution/manifests/${name}.json`)
]) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const conductor = read('skills/supervised-session-conductor/SKILL.md')
gate('conductor description has positive and negative routing',
  has(conductor, 'supervise multiple workers or producers', 'Do not use for solo task tracking', 'restart handoff', 'root-cause investigation'))
gate('conductor separates report and lifecycle evidence',
  has(conductor, 'A report without `worker_done`', '`worker_done` without a report', 'Never translate silence'))
gate('conductor blocks duplicate writer and owns one final gate',
  has(conductor, 'Do not create a second writer', 'one compact final gate', 'Workers do not interview the user independently'))
gate('conductor conditionally routes live coordination',
  has(conductor, 'installed `orchestration` skill', 'version-matched live guide', 'installed `orca-cli` skill'))
gate('conductor links the portable operating manual',
  has(conductor, 'references/operating-manual.md', 'does not merge worker responsibilities'))

const handoff = read('skills/restart-safe-handoff/SKILL.md')
gate('handoff description has positive and negative routing',
  has(handoff, 'survive a session, process, machine, or conductor restart', 'Do not use for live worker supervision', 'incident root-cause analysis'))
gate('handoff attempt is not a receipt',
  has(handoff, 'A handoff attempt is an event, never proof of receipt', '**Content receipt**', '**Delivery receipt**'))
gate('handoff distinguishes sent and acknowledged',
  has(handoff, 'supports `sent`, not `acknowledged`', 'Do not resend blindly'))
gate('handoff fails closed on ownership',
  has(handoff, 'If the coordinator is alive, do not take over', 'If liveness is unknown', 'No timeout, process disappearance'))

const investigator = read('skills/runtime-incident-investigator/SKILL.md')
gate('investigator description has positive and negative routing',
  has(investigator, 'ambiguous failure spans application, runtime, terminal, provider, or project state', 'Do not use for live worker supervision', 'localized code bug'))
gate('investigator separates five read-only layers',
  has(investigator, '| App |', '| Runtime |', '| Terminal |', '| Provider |', '| Project |'))
gate('investigator separates claims and disproof',
  has(investigator, '**Observed**', '**Inferred**', '**Disconfirmed**', '**Proposed check**', 'disproof condition'))
gate('investigator does not manufacture causality',
  has(investigator, 'correlated only', 'Neither observation proves it caused the other', 'successful retry is not proof'))

const manual = read('skills/supervised-session-conductor/references/operating-manual.md')
gate('manual maps distinct responsibilities',
  has(manual, 'Responsibility map', '`restart-safe-handoff`', '`runtime-incident-investigator`', 'installed domain skill'))
gate('manual has start, interrupt, resume, and close flow',
  has(manual, 'Start the run', 'Handle conflict and interruption', 'Resume after a restart', 'Close the run'))
gate('manual preserves portable live boundary',
  has(manual, 'stores no terminal commands, provider versions, machine paths', 'project-owned evidence'))

const distributionManager = read('scripts/Manage-MultivendorSkills.ps1')
gate('multivendor manager selects all three session operations skills',
  skillNames.every((name) => distributionManager.includes(`'${name}'`)))

const designContinuity = read('skills/design-team/references/session-continuity.md')
gate('generic handoff links to design domain extension',
  has(handoff, '../design-team/references/session-continuity.md', 'design approval, taste, artifact visibility'))
gate('design continuity links back without replacing generic ownership',
  has(designContinuity, '../../restart-safe-handoff/SKILL.md', 'generic skill owns durable bundle, writer ownership, takeover'))

const fixture = JSON.parse(read('tests/fixtures/session-operations-adversarial.json'))
const expectedCases = {
  'report-without-worker-done': ['supervised-session-conductor', 'content-present-runtime-unresolved', 'final-complete'],
  'worker-done-without-report': ['supervised-session-conductor', 'runtime-complete-content-missing', 'deliverable-verified'],
  'live-coordinator-blocks-takeover': ['restart-safe-handoff', 'ownership-active', 'takeover-authorized'],
  'design-vs-qa-conflict': ['supervised-session-conductor', 'conflict-open', 'worker-self-approval'],
  'same-time-enoent-runtime-unavailable': ['runtime-incident-investigator', 'correlated-not-causal', 'enoent-caused-runtime-loss']
}
gate('fixture schema and exact adversarial case count', fixture.schemaVersion === 1 && fixture.cases.length === 5)
for (const [id, [ownerSkill, classification, forbiddenClaim]] of Object.entries(expectedCases)) {
  const row = fixture.cases.find((candidate) => candidate.id === id)
  gate(`fixture ${id}`,
    row?.ownerSkill === ownerSkill &&
    row?.expected?.classification === classification &&
    row?.expected?.forbiddenClaims?.includes(forbiddenClaim))
}

const genericFiles = []
const walk = (directory) => {
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name)
    if (statSync(path).isDirectory()) walk(path)
    else genericFiles.push(path)
  }
}
for (const name of skillNames) walk(join(repoRoot, 'skills', name))
const machineSpecific = /(?:[A-Za-z]:[\\/]|\\\\|file:\/\/|Users[\\/])/u
const fixedCoupling = /(?:control-tower|\bMOVA\b|\bGPT-[0-9]|\bClaude-[0-9]|\bGemini-[0-9])/iu
gate('generic skills have no machine-specific paths',
  genericFiles.every((path) => !machineSpecific.test(readFileSync(path, 'utf8'))))
gate('generic skills have no fixed project or model coupling',
  genericFiles.every((path) => !fixedCoupling.test(readFileSync(path, 'utf8'))))

const manifestRows = (skillName) => {
  const root = join(repoRoot, 'skills', skillName)
  const files = []
  const collect = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name)
      if (statSync(path).isDirectory()) collect(path)
      else files.push(path)
    }
  }
  collect(root)
  return files.map((path) => {
    const bytes = readFileSync(path)
    return {
      path: relative(root, path).replaceAll('\\', '/'),
      bytes: bytes.length,
      sha256: sha256(bytes)
    }
  }).sort((a, b) => a.path.localeCompare(b.path, 'en', { sensitivity: 'base' }) || a.path.localeCompare(b.path, 'en'))
}

for (const name of manifestNames) {
  try {
    const manifest = JSON.parse(read(`distribution/manifests/${name}.json`))
    const rows = manifestRows(name)
    const digestInput = rows.map((row) => `${row.path}\0${row.bytes}\0${row.sha256}`).join('\n')
    gate(`manifest ${name} covers every file`, JSON.stringify(manifest.files) === JSON.stringify(rows))
    gate(`manifest ${name} digest`, manifest.digest === sha256(Buffer.from(digestInput, 'utf8')), manifest.digest)
  } catch (error) {
    gate(`manifest ${name} parse and integrity`, false, error.message)
  }
}

try {
  const registry = JSON.parse(read('registry/assets.yaml'))
  for (const name of skillNames) {
    for (const [kind, id, sourcePath] of [
      ['skill', `skill.${name}`, `skills/${name}`],
      ['manifest', `manifest.${name}`, `distribution/manifests/${name}.json`]
    ]) {
      const row = registry.assets.find((candidate) => candidate.id === id)
      gate(`registry ${id}`,
        row?.kind === kind &&
        row?.sourcePath === sourcePath &&
        row?.portability === 'PORTABLE' &&
        row?.lifecycle === 'reviewed' &&
        requiredVendors.every((vendor) => row.vendors.includes(vendor)))
    }
  }
  const script = registry.assets.find((candidate) => candidate.id === 'script.check-goal-15')
  gate('registry script.check-goal-15', script?.sourcePath === 'scripts/check-goal-15.mjs' && script?.lifecycle === 'reviewed')
} catch (error) {
  gate('registry parses', false, error.message)
}

for (const prior of [11, 12, 13, 14]) {
  try {
    const output = execFileSync(process.execPath, [`scripts/check-goal-${prior}.mjs`], {
      cwd: repoRoot,
      encoding: 'utf8',
      timeout: 240_000,
      windowsHide: true
    }).trim()
    gate(`goal ${prior} gate still passes`, /gate passes/u.test(output))
  } catch (error) {
    gate(`goal ${prior} gate still passes`, false, `exit ${error.status ?? 'unknown'}`)
  }
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

console.log(pass ? '[goal 15] gate passes' : '[goal 15] gate failed')
process.exit(pass ? 0 : 1)
