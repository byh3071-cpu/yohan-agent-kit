#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import {
  existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync
} from 'node:fs'
import { basename, dirname, join, parse, relative, resolve, sep } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const gitExecutable = process.platform === 'win32' ? 'git.exe' : 'git'
const args = process.argv.slice(2)

function valueOf(name) {
  const index = args.indexOf(name)
  if (index < 0 || index === args.length - 1) return null
  return args[index + 1]
}

const releaseId = valueOf('--release')
const outputRoot = resolve(repoRoot, valueOf('--output-root') ?? 'dist/releases')
const allowDirty = args.includes('--allow-dirty')
const allowTestOutput = args.includes('--allow-test-output')
const sourceCommitOverride = valueOf('--source-commit')
const jsonOutput = args.includes('--json')

const fail = (message) => { throw new Error(message) }
const normalize = (path) => path.replaceAll('\\', '/')
const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]))
  }
  return value
}
const stableJson = (value) => `${JSON.stringify(stable(value), null, 2)}\n`

function releaseManifestDigest(core) {
  const lines = [
    `schema=${core.schemaVersion}`, `release=${core.releaseId}`, `kit=${core.kitVersion}`,
    `commit=${core.gitCommit}`, `dirty=${String(core.dirtyBuild).toLowerCase()}`,
    `catalog=${core.catalogDigest}`, `assetCatalog=${core.assetCatalogDigest}`
  ]
  for (const name of [...core.packages].sort()) lines.push(`package=${name}`)
  for (const vendor of Object.keys(core.compatibility).sort()) {
    const item = core.compatibility[vendor]
    lines.push(`compat|${vendor}|${item.testedVersion}|${item.manifest}|${item.discoveryPath ?? ''}|${[...(item.discoveryPaths ?? [])].join(',')}|${[...item.components].join(',')}`)
  }
  for (const file of [...core.files].sort((a, b) => a.path.localeCompare(b.path))) lines.push(`file|${file.path}|${file.bytes}|${file.sha256}`)
  lines.push(`rollback|${core.rollback.command}|${core.rollback.backupRoot}`)
  return sha256(lines.join('\n'))
}

function assertWithin(root, candidate, label) {
  const base = resolve(root)
  const path = resolve(candidate)
  if (path !== base && !path.startsWith(`${base}${sep}`)) fail(`${label} escapes ${base}`)
}

function assertNoLinkedAncestors(candidate, includeLeaf = false) {
  const full = resolve(candidate)
  const pathRoot = parse(full).root
  const segments = relative(pathRoot, full).split(sep).filter(Boolean)
  const limit = includeLeaf ? segments.length : Math.max(0, segments.length - 1)
  let current = pathRoot
  for (let index = 0; index < limit; index++) {
    current = join(current, segments[index])
    if (!existsSync(current)) break
    const metadata = lstatSync(current)
    if (metadata.isSymbolicLink()) fail(`Build output path contains a linked entry: ${normalize(current)}`)
    if (!metadata.isDirectory() && index < limit - 1) fail(`Build output ancestor is not a directory: ${normalize(current)}`)
  }
}

function readJson(path, label) {
  if (!existsSync(path)) fail(`${label} is missing: ${normalize(relative(repoRoot, path))}`)
  try { return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, '')) } catch (error) {
    fail(`${label} is invalid JSON: ${error.message}`)
  }
}

function git(args) {
  return execFileSync(gitExecutable, args, { cwd: repoRoot, encoding: 'utf8', windowsHide: true }).trim()
}

if (!releaseId || !/^[a-z0-9][a-z0-9._-]{0,127}$/i.test(releaseId) || releaseId.includes('..')) {
  console.error('[agent-kit-build] FAIL --release must be a safe 1-128 character release ID')
  process.exit(1)
}

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.error('[agent-kit-build] FAIL .vhk/HARD_STOP detected')
  process.exit(1)
}

try {
  if (sourceCommitOverride && !(allowDirty && allowTestOutput)) fail('--source-commit is test-only and requires --allow-dirty plus --allow-test-output')
  const allowedRoots = [resolve(repoRoot, 'dist'), resolve(repoRoot, 'tests/.work')]
  if (allowTestOutput && allowDirty) allowedRoots.push(resolve(tmpdir(), 'yohan-agent-kit-tests'))
  if (!allowedRoots.some((root) => outputRoot === root || outputRoot.startsWith(`${root}${sep}`))) {
    fail('Output root must stay under dist/, tests/.work/, or the explicitly enabled bounded test temp root')
  }
  assertNoLinkedAncestors(outputRoot, true)

  const releaseConfig = readJson(join(repoRoot, 'registry/release-bundles.json'), 'Release bundle registry')
  const registry = readJson(join(repoRoot, 'registry/assets.yaml'), 'Asset registry')
  const catalog = readJson(join(repoRoot, 'distribution/asset-catalog.json'), 'Asset catalog')
  if (releaseConfig.schemaVersion !== 1 || registry.schemaVersion !== 1 || catalog.schemaVersion !== 1) fail('Unsupported input schema')
  if (catalog.registryDigest !== sha256(stableJson({
    schemaVersion: registry.schemaVersion,
    catalogId: registry.catalogId,
    assets: [...registry.assets].sort((a, b) => a.id.localeCompare(b.id))
  }))) fail('Asset catalog registry digest is stale')

  const sourceCommit = sourceCommitOverride ?? git(['rev-parse', 'HEAD'])
  if (!/^[a-f0-9]{40}$/i.test(sourceCommit)) fail('Source commit must be a full 40-character Git SHA')
  const dirty = git(['status', '--porcelain=v1']).length > 0
  if (dirty && !allowDirty) fail('Release builds require a clean Git checkout')

  const finalRoot = join(outputRoot, releaseId)
  if (existsSync(finalRoot)) fail(`Release output is immutable and already exists: ${normalize(relative(repoRoot, finalRoot))}`)
  mkdirSync(outputRoot, { recursive: true })
  const stagingRoot = join(outputRoot, `.${releaseId}.staging-${process.pid}`)
  if (existsSync(stagingRoot)) fail('A staging directory for this build already exists')
  mkdirSync(stagingRoot)

  const gitFiles = git(['ls-files', '--cached', '--others', '--exclude-standard'])
    .split(/\r?\n/).filter(Boolean).map(normalize).sort()
  const written = new Map()
  const caseFoldedPaths = new Map()

  function writeBytes(destination, bytes) {
    assertWithin(stagingRoot, destination, 'Artifact path')
    const relativePath = normalize(relative(stagingRoot, destination))
    const digest = sha256(bytes)
    const folded = relativePath.toLowerCase()
    const spelling = caseFoldedPaths.get(folded)
    if (spelling && spelling !== relativePath) fail(`Case-colliding artifact paths: ${spelling} vs ${relativePath}`)
    const prior = written.get(relativePath)
    if (prior && prior !== digest) fail(`Artifact collision: ${relativePath}`)
    if (prior) return
    mkdirSync(dirname(destination), { recursive: true })
    writeFileSync(destination, bytes)
    written.set(relativePath, digest)
    caseFoldedPaths.set(folded, relativePath)
  }

  function writeJson(destination, value) {
    writeBytes(destination, Buffer.from(stableJson(value), 'utf8'))
  }

  function copyAsset(sourcePath, destination) {
    if (/^(?:home|project|external):\/\//.test(sourcePath)) fail(`External asset cannot enter a release: ${sourcePath}`)
    const source = join(repoRoot, sourcePath)
    const entry = lstatSync(source)
    if (entry.isSymbolicLink()) fail(`Reparse/symbolic source is forbidden: ${sourcePath}`)
    if (entry.isFile()) {
      if (!gitFiles.includes(normalize(sourcePath))) fail(`Release source is not visible to Git: ${sourcePath}`)
      writeBytes(destination, readFileSync(source))
      return
    }
    if (!entry.isDirectory()) fail(`Unsupported release source kind: ${sourcePath}`)
    const prefix = `${normalize(sourcePath).replace(/\/$/, '')}/`
    const files = gitFiles.filter((path) => path.startsWith(prefix))
    if (!files.length) fail(`Release source directory is empty: ${sourcePath}`)
    for (const file of files) {
      const sourceFile = join(repoRoot, file)
      const fileEntry = lstatSync(sourceFile)
      if (!fileEntry.isFile() || fileEntry.isSymbolicLink()) fail(`Release source must contain regular files only: ${file}`)
      writeBytes(join(destination, file.slice(prefix.length)), readFileSync(sourceFile))
    }
  }

  const releaseAssets = registry.assets.filter((asset) => releaseConfig.releaseLifecycles.includes(asset.lifecycle))
  const portableRoot = join(stagingRoot, 'packages/agent-plugins/yohan-agent-kit')
  const claudeRoot = join(stagingRoot, 'packages/claude-code')
  const nativeRoots = {
    codex: join(stagingRoot, 'packages/codex/yohan-agent-kit'),
    cursor: join(stagingRoot, 'packages/cursor/yohan-agent-kit'),
    antigravity: join(stagingRoot, 'packages/antigravity/yohan-agent-kit')
  }

  const pluginMetadata = new Map()
  for (const asset of releaseAssets.filter((asset) => asset.kind === 'plugin')) {
    const match = asset.sourcePath.match(/^plugins\/([^/]+)\/.claude-plugin\/plugin\.json$/)
    if (match) pluginMetadata.set(match[1], readJson(join(repoRoot, asset.sourcePath), `Plugin ${match[1]}`))
  }

  function pluginBundle(sourcePath) {
    return sourcePath.match(/^plugins\/([^/]+)\//)?.[1] ?? 'yohan-agent-kit'
  }

  function assetLeaf(sourcePath) {
    return basename(sourcePath)
  }

  function nativeDestination(vendor, asset) {
    const root = nativeRoots[vendor]
    if (asset.kind === 'skill') return join(root, 'skills', assetLeaf(asset.sourcePath))
    if (asset.kind === 'agent') return join(root, 'agents', basename(asset.sourcePath))
    if (asset.kind === 'command') return join(root, 'commands', basename(asset.sourcePath))
    if (asset.kind === 'script') return join(root, 'scripts', basename(asset.sourcePath))
    if (asset.kind === 'hook') {
      if (vendor === 'codex') return join(root, 'hooks.json')
      if (vendor === 'cursor') return join(root, 'hooks')
      if (vendor === 'antigravity') return join(root, 'hooks.json')
    }
    if (asset.kind === 'rule') {
      if (vendor === 'cursor') return join(root, 'rules', `${asset.id.replaceAll('.', '-')}${asset.sourcePath.endsWith('.mdc') ? '.mdc' : '.md'}`)
      if (vendor === 'antigravity') return join(root, 'rules', `${asset.id.replaceAll('.', '-')}.md`)
      return join(root, 'references/rules', `${asset.id.replaceAll('.', '-')}.md`)
    }
    return null
  }

  for (const asset of releaseAssets) {
    if (asset.kind === 'script' && !releaseConfig.packageScriptIds.includes(asset.id)) continue
    if (asset.kind === 'skill' && asset.vendors.includes('agent-plugins') && asset.portability === 'PORTABLE') {
      copyAsset(asset.sourcePath, join(portableRoot, 'skills', assetLeaf(asset.sourcePath)))
    }

    if (asset.vendors.includes('claude-code')) {
      const bundle = pluginBundle(asset.sourcePath)
      let destination = null
      if (asset.kind === 'plugin') destination = join(claudeRoot, asset.sourcePath)
      else if (asset.kind === 'skill') destination = join(claudeRoot, 'plugins', bundle, 'skills', assetLeaf(asset.sourcePath))
      else if (asset.kind === 'agent') destination = join(claudeRoot, 'plugins', bundle, 'agents', basename(asset.sourcePath))
      else if (asset.kind === 'command') destination = join(claudeRoot, 'plugins', bundle, 'commands', basename(asset.sourcePath))
      else if (asset.kind === 'hook') destination = join(claudeRoot, 'plugins', bundle, 'hooks')
      else if (asset.kind === 'mcp') destination = join(claudeRoot, 'plugins', bundle, '.mcp.json')
      else if (asset.kind === 'script') destination = join(claudeRoot, 'plugins/yohan-agent-kit/scripts', basename(asset.sourcePath))
      else if (asset.kind === 'rule') destination = join(claudeRoot, 'plugins', bundle, asset.id === 'rule.yohan-core-voice' ? 'output-styles/yohan-voice.md' : 'references/rules', `${asset.id.replaceAll('.', '-')}.md`)
      if (destination) copyAsset(asset.sourcePath, destination)
    }

    for (const vendor of Object.keys(nativeRoots)) {
      if (!asset.vendors.includes(vendor)) continue
      const supported = new Set(releaseConfig.targets[vendor].components)
      const component = asset.kind === 'rule' ? 'rules' : `${asset.kind}s`
      if (!supported.has(component)) continue
      const destination = nativeDestination(vendor, asset)
      if (destination) copyAsset(asset.sourcePath, destination)
    }
  }

  const yohanMcpAsset = releaseAssets.find((asset) => asset.kind === 'mcp' && asset.id === 'mcp.yohan')
  if (!yohanMcpAsset) fail('Released Yohan MCP connection definition is missing')
  const nativeMcp = readJson(join(repoRoot, yohanMcpAsset.sourcePath), 'Yohan MCP definition')
  const portableMcp = {
    $schema: 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json',
    mcpServers: Object.fromEntries(Object.entries(nativeMcp.mcpServers).map(([name, server]) => [name, { type: 'stdio', ...server }]))
  }
  writeJson(join(portableRoot, 'mcp.json'), portableMcp)
  writeJson(join(nativeRoots.codex, '.mcp.json'), nativeMcp)
  writeJson(join(nativeRoots.cursor, 'mcp.json'), nativeMcp)
  writeJson(join(nativeRoots.antigravity, 'mcp_config.json'), nativeMcp)

  const commonMetadata = {
    name: releaseConfig.portablePlugin,
    version: releaseConfig.kitVersion,
    description: 'Yohan reusable agent skills, workflows, roles, rules, and MCP connection definitions.',
    author: { name: 'Yohan' },
    repository: releaseConfig.repository,
    license: 'UNLICENSED'
  }
  writeJson(join(portableRoot, 'plugin.json'), {
    $schema: 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json',
    ...commonMetadata
  })
  writeJson(join(nativeRoots.codex, '.codex-plugin/plugin.json'), {
    ...commonMetadata,
    skills: './skills/',
    hooks: './hooks.json',
    mcpServers: './.mcp.json',
    interface: {
      displayName: 'Yohan Agent Kit',
      shortDescription: 'Yohan agent workflows and reusable operating knowledge',
      longDescription: 'Portable Yohan skills, reusable agent roles, workflow scripts, and Yohan MCP connection definitions.',
      developerName: 'Yohan',
      category: 'Developer Tools',
      capabilities: ['Interactive', 'Write'],
      websiteURL: releaseConfig.repository,
      defaultPrompt: ['Use the Yohan workflow that best matches this task.']
    }
  })
  writeJson(join(nativeRoots.cursor, '.cursor-plugin/plugin.json'), {
    ...commonMetadata,
    displayName: 'Yohan Agent Kit',
    skills: 'skills',
    agents: 'agents',
    commands: 'commands'
  })
  writeJson(join(nativeRoots.antigravity, 'plugin.json'), {
    $schema: 'https://antigravity.google/schemas/v1/plugin.json',
    name: releaseConfig.portablePlugin,
    description: commonMetadata.description
  })

  const portableClaudePlugin = join(claudeRoot, 'plugins/yohan-agent-kit')
  writeJson(join(portableClaudePlugin, '.claude-plugin/plugin.json'), commonMetadata)
  const claudeMarketplace = readJson(join(repoRoot, '.claude-plugin/marketplace.json'), 'Claude Marketplace')
  const generatedMarketplace = structuredClone(claudeMarketplace)
  if (!generatedMarketplace.plugins.some((plugin) => plugin.name === releaseConfig.portablePlugin)) {
    generatedMarketplace.plugins.push({
      name: releaseConfig.portablePlugin,
      source: './plugins/yohan-agent-kit',
      description: commonMetadata.description,
      version: releaseConfig.kitVersion
    })
  }
  writeJson(join(claudeRoot, '.claude-plugin/marketplace.json'), generatedMarketplace)

  const payload = [...written.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([path, digest]) => ({
    path,
    sha256: digest,
    bytes: lstatSync(join(stagingRoot, path)).size
  }))
  const compatibility = Object.fromEntries(Object.entries(releaseConfig.targets).map(([vendor, config]) => [vendor, {
    testedVersion: config.testedVersion,
    components: config.components,
    manifest: config.manifest,
    discoveryPath: config.discoveryPath,
    discoveryPaths: [config.discoveryPath, ...(config.additionalDiscoveryPaths ?? [])].filter(Boolean)
  }]))
  const manifestCore = {
    schemaVersion: 1,
    releaseId,
    kitVersion: releaseConfig.kitVersion,
    gitCommit: sourceCommit.toLowerCase(),
    dirtyBuild: dirty,
    catalogDigest: catalog.catalogDigest,
    assetCatalogDigest: sha256(readFileSync(join(repoRoot, 'distribution/asset-catalog.json'))),
    packages: Object.keys(releaseConfig.targets).sort(),
    compatibility,
    files: payload,
    rollback: {
      command: '.\\scripts\\Manage-AgentKit.ps1 -Mode Restore -BackupId <id> -PlanDigest <digest> -ApproveGlobalHomeWrite',
      backupRoot: '~/.yohan-agent-kit/backups/'
    }
  }
  const manifest = { ...manifestCore, manifestDigest: releaseManifestDigest(manifestCore) }
  writeFileSync(join(stagingRoot, 'release-manifest.json'), stableJson(manifest), 'utf8')
  renameSync(stagingRoot, finalRoot)

  const result = { status: 'Built', releaseId, output: normalize(relative(repoRoot, finalRoot)), manifestDigest: manifest.manifestDigest, files: payload.length }
  if (jsonOutput) console.log(JSON.stringify(result))
  else console.log(`[agent-kit-build] PASS ${releaseId} ${payload.length} files (${manifest.manifestDigest})`)
} catch (error) {
  console.error(`[agent-kit-build] FAIL ${error.message}`)
  process.exit(1)
}
