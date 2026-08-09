#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { delimiter, dirname, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const skipDeep = process.env.VHK_GATES_SKIP_DEEP === '1'
const WINDOWS_SHELL_METACHARS = /[&|<>^%"\r\n]/
let pass = true

process.on('uncaughtException', () => {
  console.log('[goal 2] static contract evaluation: FAIL')
  console.log('[goal 2] gate failed')
  process.exit(1)
})

function gate(label, ok, detail = '') {
  console.log(`[goal 2] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}

function must(condition, label) {
  gate(label, Boolean(condition))
}

function readUtf8(path) {
  const bytes = readFileSync(join(repoRoot, path))
  const offset = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 3 : 0
  return bytes.subarray(offset).toString('utf8')
}

function readJson(path) {
  return JSON.parse(readUtf8(path))
}

function resolveExecutable(name) {
  if (process.platform !== 'win32') return name
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    if (!directory) continue
    const candidate = join(directory, `${name}.exe`)
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate
  }
  return `${name}.exe`
}

function runDirect(command, args, summaryPattern = null) {
  if (process.platform === 'win32' && /\.cmd$/i.test(command)) {
    if (args.some((argument) => WINDOWS_SHELL_METACHARS.test(argument))) {
      return { ok: false, detail: 'unsafe cmd.exe argument rejected' }
    }
    return { ok: false, detail: 'command shim rejected' }
  }
  if (args.some((argument) => /[\0\r\n]/.test(argument))) {
    return { ok: false, detail: 'invalid direct-process argument rejected' }
  }
  try {
    const output = execFileSync(command, args, {
      cwd: repoRoot,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe']
    })
    const match = summaryPattern ? output.match(summaryPattern) : null
    return { ok: true, detail: match ? match[0] : '' }
  } catch (error) {
    const output = String(error?.stdout ?? '')
    const match = summaryPattern ? output.match(summaryPattern) : null
    return { ok: false, detail: match ? match[0] : `exit ${error?.status ?? 'unknown'}` }
  }
}

function comparePortablePath(left, right) {
  const lowerLeft = left.toLowerCase()
  const lowerRight = right.toLowerCase()
  if (lowerLeft < lowerRight) return -1
  if (lowerLeft > lowerRight) return 1
  if (left < right) return -1
  if (left > right) return 1
  return 0
}

function computeSkillManifest(directory) {
  const rows = []
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const fullPath = join(current, entry.name)
      const metadata = lstatSync(fullPath)
      if (metadata.isSymbolicLink()) throw new Error('skill source contains a symbolic link')
      if (entry.isDirectory()) {
        walk(fullPath)
      } else if (entry.isFile()) {
        const bytes = readFileSync(fullPath)
        rows.push({
          path: relative(directory, fullPath).split(sep).join('/'),
          bytes: bytes.length,
          sha256: createHash('sha256').update(bytes).digest('hex').toUpperCase()
        })
      }
    }
  }
  walk(directory)
  rows.sort((left, right) => comparePortablePath(left.path, right.path))
  const digestInput = rows.map((row) => `${row.path}\0${row.bytes}\0${row.sha256}`).join('\n')
  return {
    files: rows,
    digest: createHash('sha256').update(digestInput, 'utf8').digest('hex').toUpperCase()
  }
}

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 2] HARD_STOP detected: FAIL')
  process.exit(1)
}

const requiredPaths = [
  'goals/2-design-to-html-multivendor.md',
  'skills/design-to-html/SKILL.md',
  'skills/design-to-html/references/context-contract.md',
  'skills/design-to-html/references/quality-gate.md',
  'skills/design-to-html/agents/openai.yaml',
  'distribution/manifests/design-to-html.json',
  'distribution/design-toolchain.json',
  'scripts/Manage-MultivendorSkills.ps1',
  'scripts/Manage-ProductDesignContext.ps1',
  'scripts/Test-DesignToHtmlEnvironment.ps1',
  'docs/DESIGN_TO_HTML_HANDOFF.md',
  'docs/MULTIVENDOR_SKILL_DISTRIBUTION.md',
  'tests/DesignToHtmlInvocation.Tests.ps1'
]
for (const path of requiredPaths) must(existsSync(join(repoRoot, path)), `required artifact ${path}`)

const goal = readUtf8('goals/2-design-to-html-multivendor.md')
must(/^status:\s*NOT_STARTED\s*$/m.test(goal), 'Goal 2 status remains NOT_STARTED')
must(/1\.[\s\S]*2\.[\s\S]*3\.[\s\S]*4\.[\s\S]*5\./.test(goal), 'Goal 2 keeps five completion conditions')

const skill = readUtf8('skills/design-to-html/SKILL.md')
must(skill.startsWith('---\nname: design-to-html\ndescription:'), 'design-to-html frontmatter')
must(skill.includes('HTML로 만들어줘') && skill.includes('이 시안 구현해'), 'explicit natural-language triggers')
must(skill.includes('references/context-contract.md') && skill.includes('references/quality-gate.md'), 'skill reference routing')
must(skill.includes('작업 컨텍스트 요약') && skill.includes('design-qa.md') && skill.includes('검증 리포트'), 'skill work context and handoff contract')

const contextContract = readUtf8('skills/design-to-html/references/context-contract.md')
must(contextContract.includes('Current request') && contextContract.includes('Project Git') && contextContract.includes('yohan-brain design context') && contextContract.includes('Notion view'), 'source-of-truth precedence')
must(contextContract.includes('## 작업 컨텍스트 요약') && contextContract.includes('Same branch on two PCs'), 'multi-device WorkContext contract')
must(!/(?:file:\/\/\/|[A-Za-z]:[\\/])/.test(contextContract), 'context contract is machine-path neutral')

const qualityGate = readUtf8('skills/design-to-html/references/quality-gate.md')
must(['360', '432', '768', '1280', '1440'].every((viewport) => qualityGate.includes(viewport)), 'responsive viewport contract')
must(qualityGate.includes('zero console errors') && qualityGate.includes('keyboard path'), 'browser and keyboard evidence contract')
must(qualityGate.includes('final result: passed'), 'literal design QA result contract')

const uiPath = join(repoRoot, 'skills', 'design-to-html', 'agents', 'openai.yaml')
const uiBytes = readFileSync(uiPath)
const ui = uiBytes.toString('utf8')
must(!(uiBytes.length >= 3 && uiBytes[0] === 0xef && uiBytes[1] === 0xbb && uiBytes[2] === 0xbf), 'openai.yaml is UTF-8 without BOM')
must(ui.includes('$design-to-html'), 'explicit Codex invocation metadata')
must(/^policy:\s*\n\s{2}allow_implicit_invocation:\s*true\s*$/m.test(ui), 'implicit invocation policy')

const expectedManifest = readJson('distribution/manifests/design-to-html.json')
const actualManifest = computeSkillManifest(join(repoRoot, 'skills', 'design-to-html'))
must(expectedManifest.schemaVersion === 1 && expectedManifest.skill === 'design-to-html', 'manifest identity')
must(JSON.stringify(expectedManifest.files) === JSON.stringify(actualManifest.files), 'manifest file list, bytes, and hashes')
must(expectedManifest.digest === actualManifest.digest, 'manifest aggregate digest')

const toolchain = readJson('distribution/design-toolchain.json')
must(toolchain.schemaVersion === 1 && toolchain.requiredSkill === 'design-to-html', 'toolchain skill contract')
must(toolchain.tested?.['product-design'] === '0.1.52' && toolchain.tested?.['yohan-core'] === '0.3.22' && toolchain.tested?.workflow === '0.3.9', 'toolchain tested versions')
must(Array.isArray(toolchain.requiredBrainFiles) && toolchain.requiredBrainFiles.length === 2 && toolchain.requiredBrainFiles.every((path) => !/^(?:[A-Za-z]:|\/)/.test(path)), 'toolchain Brain references are repository-relative')

const handoff = readUtf8('docs/DESIGN_TO_HTML_HANDOFF.md')
const readme = readUtf8('README.md')
must(handoff.includes('design-to-html로 HTML 만들어줘') && handoff.includes('새 세션') && handoff.includes('같은 branch'), 'two-PC and new-session handoff')
must(readme.includes('자동 호출은 모델 판단') && readme.includes('design-to-html로'), 'automatic and explicit invocation limits')

const git = runDirect(resolveExecutable('git'), ['diff', '--check'])
gate('git diff --check', git.ok, git.detail)

if (!skipDeep) {
  const powerShell = resolveExecutable('powershell')
  const testFiles = [
    'tests/New-SkillManifest.Tests.ps1',
    'tests/Manage-MultivendorSkills.Tests.ps1',
    'tests/Test-DesignToHtmlEnvironment.Tests.ps1',
    'tests/Manage-ProductDesignContext.Tests.ps1',
    'tests/DesignToHtmlInvocation.Tests.ps1'
  ]
  for (const testFile of testFiles) {
    const result = runDirect(powerShell, [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      testFile
    ], /(?:PASS:\s+\d+ assertions|assertions passed:\s+\d+)/)
    gate(`PowerShell ${testFile}`, result.ok, result.detail)
  }
} else {
  console.log('[goal 2] deep PowerShell regressions: SKIP (VHK_GATES_SKIP_DEEP=1)')
}

if (pass) {
  console.log('[goal 2] gate passes')
  process.exit(0)
}
console.log('[goal 2] gate failed')
process.exit(1)
