#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skillName = 'agent-team-operations'
const skillRoot = join(repoRoot, 'skills', skillName)
const manifestPath = join(repoRoot, 'distribution', 'manifests', `${skillName}.json`)
const requiredVendors = ['agent-plugins', 'claude-code', 'codex', 'cursor', 'antigravity']
let pass = true
let gateCount = 0

const gate = (label, ok, detail = '') => {
  gateCount += 1
  console.log(`[agent-team-operations] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/u, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()

gate('HARD_STOP is absent', !existsSync(join(repoRoot, '.vhk', 'HARD_STOP')))

const required = [
  'skills/agent-team-operations/SKILL.md',
  'skills/agent-team-operations/agents/openai.yaml',
  'skills/agent-team-operations/references/operating-manual.md',
  'distribution/manifests/agent-team-operations.json',
  'docs/audits/agent-team-operations-promotion-2026-08-26.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const skill = read('skills/agent-team-operations/SKILL.md')
const frontmatter = skill.match(/^---\n([\s\S]*?)\n---\n/u)?.[1] ?? ''
const frontmatterKeys = frontmatter
  .split(/\r?\n/u)
  .map((line) => line.match(/^([a-z0-9_-]+):/u)?.[1])
  .filter(Boolean)
  .sort()
gate('frontmatter contains only name and description',
  JSON.stringify(frontmatterKeys) === JSON.stringify(['description', 'name']))
gate('frontmatter identity', /^name:\s*agent-team-operations$/mu.test(frontmatter))

const files = []
const walk = (directory) => {
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name)
    if (statSync(path).isDirectory()) walk(path)
    else files.push(path)
  }
}
walk(skillRoot)
const rows = files.map((path) => {
  const bytes = readFileSync(path)
  return {
    path: relative(skillRoot, path).replaceAll('\\', '/'),
    bytes: bytes.length,
    sha256: sha256(bytes)
  }
}).sort((left, right) => {
  const leftFolded = left.path.toLowerCase()
  const rightFolded = right.path.toLowerCase()
  if (leftFolded < rightFolded) return -1
  if (leftFolded > rightFolded) return 1
  return left.path < right.path ? -1 : left.path > right.path ? 1 : 0
})

try {
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8').replace(/^\uFEFF/u, ''))
  const digestInput = rows.map((row) => `${row.path}\0${row.bytes}\0${row.sha256}`).join('\n')
  gate('manifest identity', manifest.schemaVersion === 1 && manifest.skill === skillName)
  gate('manifest covers every source file', JSON.stringify(manifest.files) === JSON.stringify(rows))
  gate('manifest digest', manifest.digest === sha256(Buffer.from(digestInput, 'utf8')), manifest.digest)
} catch (error) {
  gate('manifest parses', false, error.message)
}

const portableText = files.map((path) => readFileSync(path, 'utf8')).join('\n')
const machineOrRuntimeIdentity = /(?:[A-Za-z]:[\\/]|\\\\|file:\/\/|\/Users\/|\bterm_[0-9a-f-]{8,}|\brun_[0-9a-f]{8,}|\btask_[0-9a-f]{8,}|\battempt_[0-9a-f]{8,})/iu
const fixedModel = /\b(?:gpt-\d|claude-(?:opus|sonnet|haiku|\d)|gemini-\d)/iu
gate('portable source has no machine path or runtime identity', !machineOrRuntimeIdentity.test(portableText))
gate('portable source has no fixed model identity', !fixedModel.test(portableText))

const openai = read('skills/agent-team-operations/agents/openai.yaml')
gate('OpenAI UI metadata names the skill',
  openai.includes('display_name: "Agent Team Operations"') &&
  openai.includes('$agent-team-operations') &&
  openai.includes('allow_implicit_invocation: true'))

const manager = read('scripts/Manage-MultivendorSkills.ps1')
gate('distribution manager accepts and selects the skill',
  manager.match(/agent-team-operations/gu)?.length >= 4)

try {
  const registry = JSON.parse(read('registry/assets.yaml'))
  for (const [kind, id, sourcePath] of [
    ['skill', 'skill.agent-team-operations', 'skills/agent-team-operations'],
    ['manifest', 'manifest.agent-team-operations', 'distribution/manifests/agent-team-operations.json']
  ]) {
    const row = registry.assets.find((candidate) => candidate.id === id)
    gate(`registry ${id}`,
      row?.kind === kind &&
      row?.sourcePath === sourcePath &&
      row?.portability === 'PORTABLE' &&
      row?.lifecycle === 'reviewed' &&
      requiredVendors.every((vendor) => row.vendors.includes(vendor)))
  }
  const validator = registry.assets.find((candidate) => candidate.id === 'script.check-agent-team-operations')
  gate('registry script.check-agent-team-operations',
    validator?.sourcePath === 'scripts/check-agent-team-operations.mjs' && validator?.lifecycle === 'reviewed')
} catch (error) {
  gate('registry parses', false, error.message)
}

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs'], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 120_000,
    windowsHide: true
  }).trim()
  gate('registry and catalog are consistent', output.startsWith('[asset-catalog] PASS'), output)
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

console.log(pass ? `PASS: ${gateCount} gates` : `FAIL: ${gateCount} gates`)
process.exit(pass ? 0 : 1)
