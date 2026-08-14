#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const argValue = (flag) => { const index = args.indexOf(flag); return index >= 0 ? args[index + 1] : undefined }
const brainRoot = argValue('--brain-root') || process.env.YOHAN_BRAIN_ROOT
let pass = true
const gate = (label, ok, detail = '') => { console.log(`[goal 3] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`); if (!ok) pass = false }
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/, '')

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) { console.log('[goal 3] HARD_STOP detected: FAIL'); process.exit(1) }

for (const path of [
  'goals/3-design-context-html-slice.md', 'scripts/Resolve-DesignContext.ps1', 'scripts/Record-DesignDecision.ps1',
  'tests/DesignContext.Tests.ps1', 'fixtures/design-context-html-slice/index.html',
  'fixtures/design-context-html-slice/source.json', 'fixtures/design-context-html-slice/vendor/lucide-icons.js'
]) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const goal = read('goals/3-design-context-html-slice.md')
gate('Goal 3 lifecycle', /status:\s*(?:IN_PROGRESS|DONE)/.test(goal))
const resolver = read('scripts/Resolve-DesignContext.ps1')
const recorder = read('scripts/Record-DesignDecision.ps1')
const contract = read('skills/design-to-html/references/context-contract.md')
const source = JSON.parse(read('fixtures/design-context-html-slice/source.json'))
gate('pinned contract input', resolver.includes('37068a625d85bb3955579a04d87cc0f5c503c823') && source.contract.ref === '37068a625d85bb3955579a04d87cc0f5c503c823')
gate('Brain PR dependency', source.contract.dependencyPr.endsWith('/pull/194'))
gate('five-tier precedence', ['current-request', 'project-git', 'media', 'common-taste', 'golden'].every((tier) => resolver.includes(`'${tier}'`)) && contract.includes('Minimal DesignContext envelope'))
gate('decision and lifecycle allowlists', ['reuse', 'adapt', 'remix', 'create'].every((item) => recorder.includes(`'${item}'`)) && recorder.includes('stableAutoPromotion = $false'))
gate('machine-path-neutral contract', !/(?:file:\/\/\/|[A-Za-z]:[\\/])/.test(contract))

if (!brainRoot || !existsSync(brainRoot)) {
  gate('pinned Brain repository', false, 'pass --brain-root or set YOHAN_BRAIN_ROOT')
} else {
  try {
    const testOutput = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'tests/DesignContext.Tests.ps1', '-BrainRoot', resolve(brainRoot)], { cwd: repoRoot, encoding: 'utf8', timeout: 5 * 60 * 1000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 })
    gate('resolver and recorder tests', /PASS:\s+\d+ assertions/.test(testOutput), testOutput.trim().split(/\r?\n/).slice(-1)[0])
  } catch (error) {
    const output = `${error.stdout || ''}${error.stderr || ''}`
    console.log(output.split(/\r?\n/).slice(-30).join('\n'))
    gate('resolver and recorder tests', false, `exit ${error.status ?? 'unknown'}`)
  }
  try {
    const workRoot = join(repoRoot, 'tests', '.work')
    mkdirSync(workRoot, { recursive: true })
    const evidenceRoot = mkdtempSync(join(workRoot, 'design-qa-'))
    try {
      const qaOutput = execFileSync(process.execPath, ['scripts/verify-design-context-html.mjs', '--brain-root', resolve(brainRoot), '--evidence-root', evidenceRoot], { cwd: repoRoot, encoding: 'utf8', timeout: 5 * 60 * 1000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 })
      const freshReport = readFileSync(join(evidenceRoot, 'design-qa.md'), 'utf8')
      gate('browser design QA', /^PASS:/m.test(qaOutput) && freshReport.trimEnd().split(/\r?\n/).at(-1) === 'final result: passed', qaOutput.trim().split(/\r?\n/).slice(-1)[0])
    } finally {
      const normalizedWork = `${resolve(workRoot).toLowerCase()}${process.platform === 'win32' ? '\\' : '/'}`
      if (!resolve(evidenceRoot).toLowerCase().startsWith(normalizedWork)) throw new Error('Refusing to clean an unexpected QA directory')
      rmSync(evidenceRoot, { recursive: true, force: true })
    }
  } catch (error) {
    const output = `${error.stdout || ''}${error.stderr || ''}`
    console.log(output.split(/\r?\n/).slice(-30).join('\n'))
    gate('browser design QA', false, `exit ${error.status ?? 'unknown'}`)
  }
}

if (existsSync(join(repoRoot, 'fixtures/design-context-html-slice/evidence/design-qa.md'))) {
  const qa = read('fixtures/design-context-html-slice/evidence/design-qa.md')
  gate('design-qa literal result', qa.trimEnd().split(/\r?\n/).at(-1) === 'final result: passed')
  gate('P0 and P1 are zero', qa.includes('- P0: 0') && qa.includes('- P1: 0'))
} else gate('design-qa evidence', false, 'missing')

try {
  execFileSync('git.exe', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch { gate('git diff --check', false) }

console.log(pass ? '[goal 3] gate passes' : '[goal 3] gate failed')
process.exit(pass ? 0 : 1)
