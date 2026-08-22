#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skillRoot = join(repoRoot, 'skills', 'design-team')
let pass = true

const gate = (label, ok, detail = '') => {
  console.log(`[goal 11] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 11] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/11-design-team.md',
  'skills/design-team/SKILL.md',
  'skills/design-team/agents/openai.yaml',
  'skills/design-team/references/context-contract.md',
  'skills/design-team/references/team-contract.md',
  'skills/design-team/references/report-contract.md',
  'distribution/manifests/design-team.json',
  'docs/audits/design-team-skill-2026-08-22.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const skill = read('skills/design-team/SKILL.md')
const frontmatter = skill.match(/^---\n([\s\S]*?)\n---/u)?.[1] ?? ''
const frontmatterKeys = frontmatter.split(/\r?\n/u).map((line) => line.match(/^([a-z0-9_-]+):/u)?.[1]).filter(Boolean)
gate('frontmatter keys are name and description only', JSON.stringify(frontmatterKeys.sort()) === JSON.stringify(['description', 'name']))
gate('portable ownership', skill.includes('owner workspace or repository') && skill.includes("owner's versioned source of truth"))
gate('three-option human gate', skill.includes('exactly three materially different visual options') && skill.includes("wait for the user's selection"))
gate('regulated safety boundary', skill.includes('named qualified human approver') && skill.includes('is not regulatory validation or evidence of compliance'))
gate('medium-specific HTML handoff', skill.includes('code-based responsive interactive HTML outcome') && skill.includes('print, spatial, service, hardware'))

const skillFiles = []
const walk = (directory) => {
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name)
    if (statSync(path).isDirectory()) walk(path)
    else skillFiles.push(path)
  }
}
walk(skillRoot)
const machineSpecific = /(?:[A-Za-z]:[\\/]|\\\\|file:\/\/|Users[\\/])/u
gate('no machine-specific paths', skillFiles.every((path) => !machineSpecific.test(readFileSync(path, 'utf8'))))
gate('no product or fixed-model coupling', skillFiles.every((path) => !/(?:yohan-control-tower|MOVA|\bGPT-5\.6\b|\bLuna\b|\bSol\b|\bTerra\b)/iu.test(readFileSync(path, 'utf8'))))

try {
  const manifest = JSON.parse(read('distribution/manifests/design-team.json'))
  const rows = skillFiles.map((path) => {
    const bytes = readFileSync(path)
    return {
      path: relative(skillRoot, path).replaceAll('\\', '/'),
      bytes: bytes.length,
      sha256: sha256(bytes)
    }
  }).sort((a, b) => a.path.localeCompare(b.path, 'en', { sensitivity: 'base' }) || a.path.localeCompare(b.path, 'en'))
  const digestInput = rows.map((row) => `${row.path}\0${row.bytes}\0${row.sha256}`).join('\n')
  gate('manifest skill identity', manifest.schemaVersion === 1 && manifest.skill === 'design-team')
  gate('manifest file rows', JSON.stringify(manifest.files) === JSON.stringify(rows))
  gate('manifest digest', manifest.digest === sha256(Buffer.from(digestInput, 'utf8')), manifest.digest)
} catch (error) {
  gate('manifest parse and integrity', false, error.message)
}

try {
  const registry = JSON.parse(read('registry/assets.yaml'))
  const skillAsset = registry.assets.find((asset) => asset.id === 'skill.design-team')
  const manifestAsset = registry.assets.find((asset) => asset.id === 'manifest.design-team')
  gate('registry skill reviewed', skillAsset?.sourcePath === 'skills/design-team' && skillAsset?.lifecycle === 'reviewed')
  gate('registry manifest reviewed', manifestAsset?.sourcePath === 'distribution/manifests/design-team.json' && manifestAsset?.lifecycle === 'reviewed')
} catch (error) {
  gate('registry records', false, error.message)
}

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true
  }).trim()
  gate('asset catalog deterministic', output.startsWith('[asset-catalog] PASS'), output)
} catch (error) {
  gate('asset catalog deterministic', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 11] gate passes' : '[goal 11] gate failed')
process.exit(pass ? 0 : 1)
