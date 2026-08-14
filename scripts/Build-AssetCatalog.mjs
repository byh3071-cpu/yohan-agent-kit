#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const registryPath = join(repoRoot, 'registry', 'assets.yaml')
const catalogPath = join(repoRoot, 'distribution', 'asset-catalog.json')
const args = new Set(process.argv.slice(2))
const mode = args.has('--write') ? 'write' : 'check'

const fields = [
  'id', 'kind', 'owner', 'sourcePath', 'portability', 'vendors', 'lifecycle',
  'provenance', 'license', 'requiredEnv', 'evidenceRefs'
]
const portabilityValues = new Set([
  'PORTABLE', 'ADAPTER_REQUIRED', 'VENDOR_SPECIFIC', 'PROJECT_SPECIFIC',
  'LOCAL_ONLY', 'SECRET', 'DUPLICATE', 'LEGACY', 'UNKNOWN'
])
const vendorValues = new Set([
  'agent-plugins', 'claude-code', 'codex', 'cursor', 'antigravity',
  'github-copilot', 'cline', 'windsurf'
])
const lifecycleValues = new Set(['candidate', 'reviewed', 'approved', 'released', 'rejected', 'deprecated'])
const textExtensions = new Set(['', '.cjs', '.css', '.example', '.html', '.js', '.json', '.md', '.mdc', '.mjs', '.ps1', '.toml', '.yaml', '.yml'])

const fail = (message) => { throw new Error(message) }
const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]))
  }
  return value
}
const stableJson = (value) => `${JSON.stringify(stable(value), null, 2)}\n`
const normalize = (path) => path.replaceAll('\\', '/')
const gitExecutable = process.platform === 'win32' ? 'git.exe' : 'git'
const gitFiles = execFileSync(
  gitExecutable,
  ['ls-files', '--cached', '--others', '--exclude-standard'],
  { cwd: repoRoot, encoding: 'utf8', windowsHide: true }
).split(/\r?\n/).filter(Boolean).map(normalize).sort()

function parseRegistry() {
  if (!existsSync(registryPath)) fail('Missing registry/assets.yaml')
  const raw = readFileSync(registryPath, 'utf8').replace(/^\uFEFF/, '')
  let registry
  try {
    // JSON is a strict YAML 1.2 subset. Keeping this file in that subset makes the
    // build dependency-free on PowerShell 5.1 and deterministic across vendors.
    registry = JSON.parse(raw)
  } catch (error) {
    fail(`registry/assets.yaml must use the documented JSON-compatible YAML subset: ${error.message}`)
  }
  if (registry.schemaVersion !== 1 || !Array.isArray(registry.assets)) fail('Unsupported registry schema')
  return registry
}

function discoverRepoAssets() {
  const discovered = new Map()
  const add = (kind, sourcePath) => {
    const existing = discovered.get(sourcePath)
    if (existing && existing !== kind) fail(`Discovery conflict for ${sourcePath}: ${existing} vs ${kind}`)
    discovered.set(sourcePath, kind)
  }

  const rules = new Set([
    'RULES.md', 'CLAUDE.md', 'GEMINI.md', '.cursorrules', '.windsurfrules',
    '.agents/CORE-RULES.md', '.agents/rules/vhk-rules.md', '.clinerules/vhk-rules.md',
    '.cursor/rules/ecosystem.mdc', '.github/copilot-instructions.md',
    'plugins/critical-thinking/AGENTS.md', 'plugins/critical-thinking/GEMINI.md',
    'plugins/yohan-core/CLAUDE.md', 'plugins/yohan-core/output-styles/yohan-voice.md'
  ])
  const configs = new Set([
    '.claude-plugin/marketplace.json', '.cursor/mcp.json.example',
    'distribution/design-toolchain.json', 'dotfiles/claude/settings.json'
  ])

  for (const path of gitFiles) {
    let match
    if ((match = path.match(/^skills\/([^/]+)\/SKILL\.md$/))) add('skill', `skills/${match[1]}`)
    else if ((match = path.match(/^plugins\/([^/]+)\/\.claude-plugin\/plugin\.json$/))) add('plugin', path)
    else if ((match = path.match(/^plugins\/([^/]+)\/skills\/([^/]+)\/SKILL\.md$/))) add('skill', `plugins/${match[1]}/skills/${match[2]}`)
    else if (/^plugins\/[^/]+\/agents\/[^/]+\.md$/.test(path)) add('agent', path)
    else if (/^plugins\/[^/]+\/commands\/[^/]+\.md$/.test(path)) add('command', path)
    else if ((match = path.match(/^plugins\/([^/]+)\/hooks\/hooks\.json$/))) add('hook', `plugins/${match[1]}/hooks`)
    else if (/^plugins\/[^/]+\/\.mcp\.json$/.test(path)) add('mcp', path)
    else if (/^scripts\/[^/]+\.(?:mjs|ps1)$/.test(path)) add('script', path)
    else if (/^distribution\/manifests\/[^/]+\.json$/.test(path)) add('manifest', path)
    else if (path.endsWith('/report-template.html')) add('template', path)
    else if (path === 'fixtures/design-context-html-slice/index.html') add('fixture', 'fixtures/design-context-html-slice')
    else if (rules.has(path)) add('rule', path)
    else if (configs.has(path)) add('config', path)
  }
  return discovered
}

function validateRecord(record, index) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) fail(`Asset ${index} must be an object`)
  const actual = Object.keys(record).sort()
  const expected = [...fields].sort()
  if (JSON.stringify(actual) !== JSON.stringify(expected)) fail(`Asset ${record.id || index} fields differ from the fixed schema`)
  if (!/^[a-z0-9][a-z0-9.-]*$/.test(record.id)) fail(`Invalid asset id: ${record.id}`)
  for (const key of ['kind', 'owner', 'sourcePath', 'provenance', 'license']) {
    if (typeof record[key] !== 'string' || !record[key].trim()) fail(`${record.id}.${key} must be a non-empty string`)
  }
  if (!portabilityValues.has(record.portability)) fail(`${record.id} has invalid portability`)
  if (!lifecycleValues.has(record.lifecycle)) fail(`${record.id} has invalid lifecycle`)
  for (const key of ['vendors', 'requiredEnv', 'evidenceRefs']) {
    if (!Array.isArray(record[key])) fail(`${record.id}.${key} must be an array`)
    if (new Set(record[key]).size !== record[key].length) fail(`${record.id}.${key} contains duplicates`)
  }
  if (record.vendors.some((vendor) => !vendorValues.has(vendor))) fail(`${record.id} has an invalid vendor`)
  if (record.requiredEnv.some((name) => !/^[A-Z][A-Z0-9_]*$/.test(name))) fail(`${record.id} requiredEnv must contain names, never values`)
  if (/^[A-Za-z]:[\\/]|^\\\\|^\/|^~[\\/]|file:\/\//.test(record.sourcePath) || record.sourcePath.includes('\\')) {
    fail(`${record.id} contains a machine-specific sourcePath`)
  }
  const externalSource = /^(?:home|project|external):\/\//.test(record.sourcePath)
  if (!externalSource && !existsSync(join(repoRoot, record.sourcePath))) fail(`${record.id} sourcePath does not exist: ${record.sourcePath}`)
  for (const ref of record.evidenceRefs) {
    if (typeof ref !== 'string' || !ref || /^[A-Za-z]:[\\/]|^\\\\|^~[\\/]|file:\/\//.test(ref)) fail(`${record.id} has an unsafe evidenceRef`)
  }
}

function sourceDigest(sourcePath) {
  if (/^(?:home|project|external):\/\//.test(sourcePath)) return null
  const paths = gitFiles.filter((path) => path === sourcePath || path.startsWith(`${sourcePath}/`))
  if (!paths.length) fail(`No files found for ${sourcePath}`)
  const hash = createHash('sha256')
  for (const path of paths) {
    const bytes = readFileSync(join(repoRoot, path))
    const extension = extname(path).toLowerCase()
    const content = textExtensions.has(extension)
      ? Buffer.from(bytes.toString('utf8').replace(/\r\n/g, '\n'), 'utf8')
      : bytes
    hash.update(path)
    hash.update('\0')
    hash.update(content)
    hash.update('\0')
  }
  return hash.digest('hex')
}

if (args.has('--self-test')) {
  const path = '.cursor/mcp.json.example'
  const digest = (bytes) => {
    const hash = createHash('sha256')
    const extension = extname(path).toLowerCase()
    const content = textExtensions.has(extension)
      ? Buffer.from(bytes.toString('utf8').replace(/\r\n/g, '\n'), 'utf8')
      : bytes
    hash.update(path)
    hash.update('\0')
    hash.update(content)
    hash.update('\0')
    return hash.digest('hex')
  }
  const lf = Buffer.from('{\n  "mcpServers": {}\n}\n', 'utf8')
  const crlf = Buffer.from('{\r\n  "mcpServers": {}\r\n}\r\n', 'utf8')
  if (digest(lf) !== digest(crlf)) fail('Text asset digests must be LF/CRLF neutral')
  console.log('[asset-catalog] SELF-TEST PASS LF/CRLF neutral text digest')
  process.exit(0)
}

function buildCatalog(registry) {
  const ids = new Set()
  const sources = new Set()
  registry.assets.forEach((record, index) => {
    validateRecord(record, index)
    if (ids.has(record.id)) fail(`Duplicate asset id: ${record.id}`)
    if (sources.has(record.sourcePath)) fail(`Duplicate source of truth: ${record.sourcePath}`)
    ids.add(record.id)
    sources.add(record.sourcePath)
  })

  const discovered = discoverRepoAssets()
  const repoRecords = new Map(registry.assets
    .filter((record) => !/^(?:home|project|external):\/\//.test(record.sourcePath))
    .map((record) => [record.sourcePath, record.kind]))
  const missing = [...discovered].filter(([path, kind]) => repoRecords.get(path) !== kind)
  const stale = [...repoRecords].filter(([path, kind]) => discovered.get(path) !== kind)
  if (missing.length) fail(`Unclassified repository assets: ${missing.map(([path, kind]) => `${kind}:${path}`).join(', ')}`)
  if (stale.length) fail(`Registry paths outside discovery contract: ${stale.map(([path, kind]) => `${kind}:${path}`).join(', ')}`)

  const normalizedRegistry = {
    schemaVersion: registry.schemaVersion,
    catalogId: registry.catalogId,
    assets: [...registry.assets].sort((a, b) => a.id.localeCompare(b.id))
  }
  const registryDigest = sha256(stableJson(normalizedRegistry))
  const catalogAssets = normalizedRegistry.assets.map((record) => ({ ...record, contentDigest: sourceDigest(record.sourcePath) }))
  const catalogCore = {
    schemaVersion: 1,
    catalogId: registry.catalogId,
    generatedFrom: 'registry/assets.yaml',
    registryDigest,
    assetCount: catalogAssets.length,
    assets: catalogAssets
  }
  return { ...catalogCore, catalogDigest: sha256(stableJson(catalogCore)) }
}

try {
  const catalog = buildCatalog(parseRegistry())
  const expected = stableJson(catalog)
  if (mode === 'write') {
    const temporary = `${catalogPath}.tmp-${process.pid}`
    writeFileSync(temporary, expected, 'utf8')
    renameSync(temporary, catalogPath)
    console.log(`[asset-catalog] wrote ${catalog.assets.length} assets (${catalog.catalogDigest})`)
  } else {
    if (!existsSync(catalogPath)) fail('distribution/asset-catalog.json is missing; run with --write')
    const actual = readFileSync(catalogPath, 'utf8').replace(/\r\n/g, '\n')
    if (actual !== expected) fail('distribution/asset-catalog.json is stale; run with --write')
    console.log(`[asset-catalog] PASS ${catalog.assets.length} assets (${catalog.catalogDigest})`)
  }
} catch (error) {
  console.error(`[asset-catalog] FAIL ${error.message}`)
  process.exit(1)
}
