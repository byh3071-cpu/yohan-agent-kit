#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
let pass = true
const gate = (label, ok, detail = '') => {
  console.log(`[goal 5] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 5] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/5-yohan-agent-kit-identity.md', 'docs/YOHAN_AGENT_KIT_MIGRATION.md',
  'docs/audits/yohan-agent-kit-identity-2026-08-14.md', 'registry/assets.yaml',
  'distribution/asset-catalog.json', '.claude-plugin/marketplace.json'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const currentIdentityFiles = ['RULES.md', 'README.md', 'docs/ARCHITECTURE.md', 'docs/PRD.md', 'goals/_meta.md']
gate('current product identity', currentIdentityFiles.every((path) => /yohan-agent-kit|Yohan Agent Kit/.test(read(path))))
gate('canonical GitHub source', [
  'RULES.md', 'README.md', 'dotfiles/claude/settings.json',
  'plugins/yohan-core/.claude-plugin/plugin.json', 'plugins/critical-thinking/.claude-plugin/plugin.json'
].every((path) => read(path).includes('byh3071-cpu/yohan-agent-kit')))

const marketplace = JSON.parse(read('.claude-plugin/marketplace.json'))
gate('compatibility Marketplace namespace retained', marketplace.name === 'yohan-cc-skills')
const expectedPlugins = ['critical-thinking', 'statusline', 'workflow', 'yohan-core']
gate('plugin IDs retained', JSON.stringify(marketplace.plugins.map(({ name }) => name).sort()) === JSON.stringify(expectedPlugins))

const settings = JSON.parse(read('dotfiles/claude/settings.json'))
gate('Marketplace source uses renamed GitHub repository', settings.extraKnownMarketplaces?.['yohan-cc-skills']?.source?.repo === 'byh3071-cpu/yohan-agent-kit')
gate('enabled plugin namespace remains compatible', Object.keys(settings.enabledPlugins ?? {}).filter((key) => key.includes('yohan')).every((key) => key.endsWith('@yohan-cc-skills')))

try {
  const registry = JSON.parse(read('registry/assets.yaml'))
  const catalog = JSON.parse(read('distribution/asset-catalog.json'))
  const repoOwned = registry.assets.filter((asset) => asset.provenance === 'repo-authored')
  gate('repo-authored registry owner renamed', repoOwned.every((asset) => asset.owner !== 'yohan-cc-skills'))
  const goal5Gate = registry.assets.find((asset) => asset.sourcePath === 'scripts/check-goal-5.mjs')
  gate('new Goal 5 gate is registered', goal5Gate?.owner === 'yohan-agent-kit')
  gate('Goal 5 gate remains adapter-bound', goal5Gate?.portability === 'ADAPTER_REQUIRED' && !goal5Gate?.vendors.includes('agent-plugins'))
  gate('catalog and registry counts agree', catalog.assetCount === registry.assets.length, `${catalog.assetCount} assets`)
} catch (error) { gate('registry identity checks', false, error.message) }

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true
  }).trim()
  gate('asset catalog is current', output.startsWith('[asset-catalog] PASS'), output)
} catch (error) { gate('asset catalog is current', false, `exit ${error.status ?? 'unknown'}`) }

const contractRef = '37068a625d85bb3955579a04d87cc0f5c503c823'
gate('design contract exact ref', ['scripts/Resolve-DesignContext.ps1', 'scripts/Record-DesignDecision.ps1'].every((path) => read(path).includes(contractRef)))
gate('design execution owner', ['scripts/Resolve-DesignContext.ps1', 'scripts/Record-DesignDecision.ps1'].every((path) => read(path).includes('resolver_recording_execution: yohan-agent-kit')))

const migration = read('docs/YOHAN_AGENT_KIT_MIGRATION.md')
gate('compatibility split documented', [
  'byh3071-cpu/yohan-agent-kit', 'yohan-cc-skills',
  'C:\\Users\\Public\\dev\\automation\\yohan-cc-skills', '~/.yohan-agent-kit/releases/<release-id>/'
].every((value) => migration.includes(value)))

try {
  const remote = execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['remote', 'get-url', 'origin'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  }).trim()
  gate('origin uses renamed GitHub repository', /byh3071-cpu\/yohan-agent-kit(?:\.git)?$/.test(remote), remote)
} catch (error) { gate('origin uses renamed GitHub repository', false, error.message) }

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 5] gate passes' : '[goal 5] gate failed')
process.exit(pass ? 0 : 1)
