#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const optionValue = (name, environmentName) => {
  const index = args.indexOf(name)
  if (index >= 0) return resolve(args[index + 1] ?? '')
  return process.env[environmentName] ? resolve(process.env[environmentName]) : ''
}
const brainRoot = optionValue('--brain-root', 'YOHAN_BRAIN_ROOT')
const mcpRoot = optionValue('--mcp-root', 'YOHAN_MCP_ROOT')
let pass = true

const gate = (label, ok, detail = '') => {
  console.log(`[goal 16] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^﻿/u, '')
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 16] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/16-retrieval-receipt-outcome-loop.md',
  'scripts/RetrievalEvidence.Common.ps1',
  'scripts/New-RetrievalQueryFingerprint.ps1',
  'scripts/Record-RetrievalReceipt.ps1',
  'scripts/Record-RetrievalOutcome.ps1',
  'scripts/Get-RetrievalLearningCandidate.ps1',
  'tests/RetrievalEvidence.Tests.ps1',
  'tests/RetrievalEvidence.CrossRepo.Tests.ps1',
  'tests/generate_actual_retrieval_envelope.py',
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const goal = read('goals/16-retrieval-receipt-outcome-loop.md')
gate('Goal 16 identity and provider', has(goal, 'id: 16', 'size: L', 'execution_provider: native-approved', 'automatic_fallback: false'))
gate('Goal 16 preserves explicit-only boundary', has(goal, '명시적 post-action', '모든 query 자동 기록', '사용자 홈 HMAC 키 설치'))

const common = read('scripts/RetrievalEvidence.Common.ps1')
const fingerprint = read('scripts/New-RetrievalQueryFingerprint.ps1')
const receipt = read('scripts/Record-RetrievalReceipt.ps1')
const outcome = read('scripts/Record-RetrievalOutcome.ps1')
const candidate = read('scripts/Get-RetrievalLearningCandidate.ps1')
gate('contract uses exact Git objects and schema digest', has(common, 'rev-parse', '--verify', '^{commit}', 'schema_bundle_digest', 'Pinned schema bundle bytes do not match ExpectedSchemaDigest'))
gate('contract requires active implemented state', has(common, 'Retrieval evidence index is not active', 'Retrieval evidence contract is not active/implemented', 'agent_kit_implementation_ref'))
gate('event storage is append-only and reparse guarded', has(common, 'Add-JsonLineAppendOnly', '[IO.FileMode]::CreateNew', '[IO.FileMode]::Open', 'ReparsePoint', 'Duplicate $IdProperty'))
gate('fingerprint reads stdin and process environment only', has(fingerprint, '[Console]::In.ReadToEnd()', '[EnvironmentVariableTarget]::Process', 'HMACSHA256', 'hmac-sha256-v1'))
gate('receipt requires volatile non-persisted diagnostics', has(receipt, 'retrieval-diagnostics/v1', '[bool]$diagnostics.volatile -ne $true', '[bool]$diagnostics.persisted -ne $false'))
gate('receipt records exact document lineage', has(receipt, 'document_id = $documentId', 'content_hash = $contentHash', 'locator = $locator', 'persistent_query_copy = $false'))
gate('human outcome cannot be inferred by an agent', has(outcome, "if ($SignalKind -eq 'human-explicit')", "if ($ActorType -ne 'human')", 'explicit human-approval ref'))
gate('candidate is deterministic and candidate-only', has(candidate, 'retrieval-learning-candidate/v1', "'candidate-' + (Get-Sha256Hex", "status = 'candidate'", 'stable_auto_promotion = $false'))
gate('candidate without outcome cannot preserve', has(candidate, "$reasonCodes.Add('no-outcome')", "$disposition = 'review'", "$disposition = 'preserve'", "$verdicts[0] -ceq 'helpful'"))

const scripts = required.filter((path) => path.endsWith('.ps1'))
const absolutePath = /(?:[A-Za-z]:[\\/]|file:\/\/|Users[\\/]|Public[\\/]dev)/u
gate('no machine-specific path hardcoding', scripts.every((path) => !absolutePath.test(read(path))))
gate('no Git or external service mutation in recorders', [receipt, outcome, candidate].every((text) => !/(?:git\s+(?:commit|push)|Notion|Qdrant\s+write|Invoke-RestMethod)/iu.test(text)))

try {
  const parserCommand = [
    '$failed=$false',
    ...scripts.map((path) => `$e=$null;$t=$null;[void][Management.Automation.Language.Parser]::ParseFile('${join(repoRoot, path).replaceAll("'", "''")}',[ref]$t,[ref]$e);if($e.Count -gt 0){$failed=$true;$e|ForEach-Object{Write-Error $_.Message}}`),
    'if($failed){exit 1}',
  ].join(';')
  execFileSync('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', parserCommand], { cwd: repoRoot, encoding: 'utf8', timeout: 60_000, windowsHide: true })
  gate('PowerShell 5.1 syntax', true)
} catch (error) {
  gate('PowerShell 5.1 syntax', false, `exit ${error.status ?? 'unknown'}`)
}

gate('Brain contract root supplied', Boolean(brainRoot) && existsSync(brainRoot), brainRoot || 'missing --brain-root')
if (brainRoot && existsSync(brainRoot)) {
  try {
    const output = execFileSync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', 'tests/RetrievalEvidence.Tests.ps1', '-BrainContractRoot', brainRoot,
    ], { cwd: repoRoot, encoding: 'utf8', timeout: 5 * 60_000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 })
    gate('native retrieval evidence tests', /^PASS: \d+ assertions/mu.test(output), output.trim())
  } catch (error) {
    gate('native retrieval evidence tests', false, String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
  }
}

gate('MCP implementation root supplied', Boolean(mcpRoot) && existsSync(mcpRoot), mcpRoot || 'missing --mcp-root')
if (brainRoot && existsSync(brainRoot) && mcpRoot && existsSync(mcpRoot)) {
  try {
    const git = process.platform === 'win32' ? 'git.exe' : 'git'
    const gitText = (cwd, commandArgs) => execFileSync(git, commandArgs, { cwd, encoding: 'utf8', timeout: 30_000, windowsHide: true }).trim()
    const brainRef = gitText(brainRoot, ['rev-parse', 'HEAD'])
    const mcpRef = gitText(mcpRoot, ['rev-parse', 'HEAD'])
    const contractIndex = gitText(brainRoot, ['show', `${brainRef}:memory/retrieval-evidence/index.yaml`])
    const exactValue = (key, length) => new RegExp(`^\\s*${key}: ([0-9a-f]{${length}})\\s*$`, 'mu').exec(contractIndex)?.[1] ?? ''
    const schemaDigest = exactValue('schema_bundle_digest', 64)
    const schemaSourceRef = exactValue('schema_source_ref', 40)
    const pinnedMcpRef = exactValue('mcp_diagnostics_implementation_ref', 40)
    const pinnedAgentKitRef = exactValue('agent_kit_implementation_ref', 40)

    gate('Brain exact schema digest discovered', /^[0-9a-f]{64}$/u.test(schemaDigest), schemaDigest || 'missing')
    gate('MCP checkout matches activated implementation ref', pinnedMcpRef === mcpRef, `${pinnedMcpRef || 'missing'} / ${mcpRef}`)
    let brainSchemaAncestor = false
    let agentKitImplementationAncestor = false
    try { gitText(brainRoot, ['merge-base', '--is-ancestor', schemaSourceRef, brainRef]); brainSchemaAncestor = true } catch {}
    try { gitText(repoRoot, ['merge-base', '--is-ancestor', pinnedAgentKitRef, 'HEAD']); agentKitImplementationAncestor = true } catch {}
    gate('Brain checkout descends from schema source ref', brainSchemaAncestor, schemaSourceRef || 'missing')
    gate('Agent Kit checkout descends from activated implementation ref', agentKitImplementationAncestor, pinnedAgentKitRef || 'missing')

    if (/^[0-9a-f]{64}$/u.test(schemaDigest) && pinnedMcpRef === mcpRef && brainSchemaAncestor && agentKitImplementationAncestor) {
      const crossOutput = execFileSync('powershell.exe', [
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', 'tests/RetrievalEvidence.CrossRepo.Tests.ps1',
        '-BrainRoot', brainRoot, '-BrainRef', brainRef, '-ContractSchemaDigest', schemaDigest,
        '-McpRoot', mcpRoot, '-McpRef', mcpRef,
      ], { cwd: repoRoot, encoding: 'utf8', timeout: 5 * 60_000, windowsHide: true, maxBuffer: 16 * 1024 * 1024 })
      gate('actual MCP envelope cross-repository fixture', /^PASS: \d+ assertions/mu.test(crossOutput), crossOutput.trim())
    } else {
      gate('actual MCP envelope cross-repository fixture', false, 'handshake prerequisite failed')
    }
  } catch (error) {
    gate('actual MCP envelope cross-repository fixture', false, String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
  }
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 16] gate passes' : '[goal 16] gate failed')
process.exit(pass ? 0 : 1)
