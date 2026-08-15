#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { getWindowsPowerShellEnv } from './windows-powershell-env.mjs'

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
  'goals/4-agent-asset-registry.md', 'registry/assets.yaml', 'distribution/asset-catalog.json',
  'scripts/Build-AssetCatalog.mjs', 'scripts/Scan-AgentAssets.ps1',
  'tests/Scan-AgentAssets.Tests.ps1', 'docs/audits/agent-assets-home-2026-08-14.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const goal = read('goals/4-agent-asset-registry.md')
gate('Goal 4 lifecycle', /status:\s*(?:IN_PROGRESS|DONE)/.test(goal))

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs', '--self-test'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  }).trim()
  gate('catalog digest is LF/CRLF neutral', output.includes('SELF-TEST PASS'), output)
} catch (error) {
  gate('catalog digest is LF/CRLF neutral', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  const output = execFileSync(process.execPath, ['scripts/Build-AssetCatalog.mjs', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true
  }).trim()
  gate('registry schema, coverage, and deterministic catalog', output.startsWith('[asset-catalog] PASS'), output)
} catch (error) {
  console.log(`${error.stdout || ''}${error.stderr || ''}`.trim())
  gate('registry schema, coverage, and deterministic catalog', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  const output = execFileSync('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', 'tests/Scan-AgentAssets.Tests.ps1'
  ], { cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true, env: getWindowsPowerShellEnv(process.env) }).trim()
  gate('read-only home scanner contract', /^PASS:\s+\d+ assertions$/m.test(output), output.split(/\r?\n/).at(-1))
} catch (error) {
  console.log(`${error.stdout || ''}${error.stderr || ''}`.trim())
  gate('read-only home scanner contract', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  const registry = JSON.parse(read('registry/assets.yaml'))
  const catalog = JSON.parse(read('distribution/asset-catalog.json'))
  gate('catalog and registry counts agree', catalog.assetCount === registry.assets.length, `${catalog.assetCount} assets`)
  const ids = new Set(registry.assets.map((asset) => asset.id))
  const expectedLocal = [
    'candidate.html-doc', 'candidate.planning-diagrams', 'legacy.competitive-brief',
    'legacy.interview-me', 'project.yohan-instagram-cardnews',
    'candidate.agent.merge-advisor', 'candidate.agent.prompt-auditor',
    'candidate.agent.prompt-forge', 'candidate.agent.research-scout'
  ]
  gate('sanitized home findings are registered', expectedLocal.every((id) => ids.has(id)))
  const unsafePromotion = registry.assets.filter((asset) => /^(?:home|project):\/\//.test(asset.sourcePath) && ['approved', 'released'].includes(asset.lifecycle))
  gate('local and project candidates cannot auto-promote', unsafePromotion.length === 0)
  const sourcePaths = registry.assets.map((asset) => asset.sourcePath)
  gate('zero duplicate sources of truth', new Set(sourcePaths).size === sourcePaths.length)
} catch (error) {
  gate('registry semantic checks', false, error.message)
}

const protectedFiles = [
  'registry/assets.yaml', 'distribution/asset-catalog.json',
  'docs/audits/agent-assets-home-2026-08-14.md'
]
const protectedText = protectedFiles.map(read).join('\n')
gate('no Windows absolute paths in committed inventory', !/(?:^|[\s"'`])(?:[A-Za-z]:[\\/]|\\\\)/m.test(protectedText))
gate('no secret values in committed inventory', !/(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)/.test(protectedText))
gate('subagent ownership boundary', read('docs/audits/agent-assets-home-2026-08-14.md').includes('프로젝트 전용 Subagent는 소유 프로젝트에 남고'))

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 4] gate passes' : '[goal 4] gate failed')
process.exit(pass ? 0 : 1)
