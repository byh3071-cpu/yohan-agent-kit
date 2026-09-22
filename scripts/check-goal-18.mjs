#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
let pass = true

const gate = (label, ok, detail = '') => {
  console.log(`[goal 18] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/u, '')
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))
const stable = (value) => Array.isArray(value)
  ? value.map(stable)
  : value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]))
    : value
const sha256 = (value) => createHash('sha256').update(JSON.stringify(stable(value)), 'utf8').digest('hex')
const optionValue = (name, environmentName) => {
  const index = args.indexOf(name)
  if (index >= 0) {
    const value = args[index + 1]
    if (!value || value.startsWith('--')) throw new Error(`${name} requires a path`)
    return resolve(value)
  }
  return process.env[environmentName] ? resolve(process.env[environmentName]) : ''
}

let brainRoot = ''
let mcpRoot = ''
try {
  brainRoot = optionValue('--brain-root', 'YOHAN_BRAIN_ROOT')
  mcpRoot = optionValue('--mcp-root', 'YOHAN_MCP_ROOT')
  gate('Goal 16 optional roots are supplied together', Boolean(brainRoot) === Boolean(mcpRoot))
} catch (error) {
  gate('Goal 16 optional root arguments parse', false, error.message)
}

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 18] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/18-session-resume-packet.md',
  'docs/plans/p2-session-resume-implementation.md',
  'docs/contracts/session-resume-packet-v1.md',
  'docs/audits/p2-session-resume-2026-09-22.md',
  'docs/audits/fixtures/p2-muse-session-ownership.json',
  'docs/audits/fixtures/p2-muse-session-resume-packet.json',
  'docs/audits/fixtures/p2-muse-session-resume-ack.json',
  'schemas/session-resume-packet-v1.schema.json',
  'scripts/SessionResumePacket.mjs',
  'tests/SessionResumePacket.Tests.ps1',
  'tests/fixtures/session-resume-packet-cases.json',
  'plugins/workflow/skills/handoff/SKILL.md',
  'scripts/check-goal-18.mjs'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const safeRead = (path) => existsSync(join(repoRoot, path)) ? read(path) : ''
const goal = safeRead('goals/18-session-resume-packet.md')
const plan = safeRead('docs/plans/p2-session-resume-implementation.md')
const contract = safeRead('docs/contracts/session-resume-packet-v1.md')
const audit = safeRead('docs/audits/p2-session-resume-2026-09-22.md')
const ownershipFixtureText = safeRead('docs/audits/fixtures/p2-muse-session-ownership.json')
const packetFixtureText = safeRead('docs/audits/fixtures/p2-muse-session-resume-packet.json')
const ackFixtureText = safeRead('docs/audits/fixtures/p2-muse-session-resume-ack.json')
const schemaText = safeRead('schemas/session-resume-packet-v1.schema.json')
const implementation = safeRead('scripts/SessionResumePacket.mjs')
const tests = safeRead('tests/SessionResumePacket.Tests.ps1')
const fixtureText = safeRead('tests/fixtures/session-resume-packet-cases.json')
const handoff = safeRead('plugins/workflow/skills/handoff/SKILL.md')

gate('Goal 18 identity and provider',
  has(goal, 'id: 18', 'status: IN_PROGRESS', 'execution_provider: native-approved', 'automatic_fallback: false'))
gate('Goal 18 keeps P4, Graph, home install, and takeover out of scope',
  has(goal, 'MOVA 자동 전달·재전송·재접속(P4 소유)', 'Graph/Graphiti', '사용자 홈 설치', '자동 writer takeover'))
gate('plan binds P1 context to deterministic prepare verify ack flow',
  has(plan, 'task-context/v1', 'session-resume-packet/v1', 'prepare', 'verify', 'ack', 'content receipt', 'delivery receipt'))

gate('contract defines all three explicit commands',
  has(contract, 'SessionResumePacket.mjs prepare', 'SessionResumePacket.mjs verify', 'SessionResumePacket.mjs ack'))
gate('contract separates content and delivery receipts',
  has(contract, 'receipts.content.digest', 'receipts.delivery', 'ACKNOWLEDGED', '별도'))
gate('contract documents fail-closed result classes',
  has(contract, 'INVALID', 'STALE', 'CONFLICTED', 'INDETERMINATE'))
gate('contract preserves real-machine boundary and forbids automatic takeover',
  has(contract, 'REAL_MACHINE_UNVERIFIED', 'takeover'))
gate('audit records exact local receipt and the real-machine boundary',
  has(audit, 'Packet digest:', 'Fresh-process verification: `VERIFIED`', 'Delivery status: `ACKNOWLEDGED`', 'Takeover: `false`', 'REAL_MACHINE_UNVERIFIED'))

try {
  const ownershipFixture = JSON.parse(ownershipFixtureText)
  const packetFixture = JSON.parse(packetFixtureText)
  const ackFixture = JSON.parse(ackFixtureText)
  const { content_digest: ownershipDigest, ...ownershipProjection } = ownershipFixture
  const { receipts: packetReceipts, ...packetProjection } = packetFixture
  const { delivery_digest: ackDigest, ...ackProjection } = ackFixture
  gate('repro ownership fixture schema and digest',
    ownershipFixture.schema === 'session-ownership/v1' && /^[a-f0-9]{64}$/u.test(ownershipDigest) && sha256(ownershipProjection) === ownershipDigest)
  gate('repro packet fixture schema and content digest',
    packetFixture.schema === 'session-resume-packet/v1' && packetReceipts?.content?.digest === sha256(packetProjection))
  gate('repro packet binds exact ownership identity and digest',
    packetFixture.ownership?.content_digest === ownershipDigest &&
    packetFixture.ownership?.active_writer === ownershipFixture.active_writer &&
    packetFixture.ownership?.writer_epoch === ownershipFixture.writer_epoch &&
    packetFixture.ownership?.liveness === ownershipFixture.liveness &&
    packetFixture.ownership?.source_ref === ownershipFixture.source_ref &&
    packetFixture.ownership?.current_gate === ownershipFixture.current_gate)
  gate('repro packet binds fixed ownership freshness bounds',
    packetFixture.ownership?.max_age_seconds === 3600 && packetFixture.ownership?.future_skew_seconds === 300)
  gate('repro ACK links packet, source, gate, writer, epoch, and delivery digest',
    ackFixture.schema === 'session-resume-ack/v1' && ackFixture.status === 'ACKNOWLEDGED' &&
    ackFixture.packet_digest === packetReceipts?.content?.digest &&
    ackFixture.source_ref === packetFixture.source_ref && ackFixture.current_gate === packetFixture.task?.current_gate &&
    ackFixture.writer === packetFixture.ownership?.active_writer && ackFixture.writer_epoch === packetFixture.ownership?.writer_epoch &&
    /^[a-f0-9]{64}$/u.test(ackDigest) && sha256(ackProjection) === ackDigest)
  gate('repro artifacts preserve machine and takeover boundaries',
    packetFixture.validation?.machine_status === 'REAL_MACHINE_UNVERIFIED' &&
    ackFixture.machine_status === 'REAL_MACHINE_UNVERIFIED' && ackFixture.takeover === false)
  gate('audit references reproducibility artifacts and exact receipt identity',
    has(audit,
      'docs/audits/fixtures/p2-muse-session-ownership.json',
      'docs/audits/fixtures/p2-muse-session-resume-packet.json',
      'docs/audits/fixtures/p2-muse-session-resume-ack.json',
      ownershipFixture.source_ref, ownershipFixture.current_gate, ownershipFixture.active_writer,
      String(ownershipFixture.writer_epoch), ackFixture.receiver, packetFixture.created_at, ackFixture.acknowledged_at))
} catch (error) {
  gate('reproducibility artifacts parse and link', false, error.message)
}

try {
  const schema = JSON.parse(schemaText)
  gate('schema identifies session-resume-packet/v1', schema?.$id?.includes('session-resume-packet-v1') || schema?.properties?.schema?.const === 'session-resume-packet/v1')
  gate('schema requires independent content and delivery receipts',
    Array.isArray(schema?.required) && schema.required.includes('receipts') &&
    Array.isArray(schema?.properties?.receipts?.required) &&
    schema.properties.receipts.required.includes('content') &&
    schema.properties.receipts.required.includes('delivery'))
  gate('schema fixes ownership maximum age and future skew',
    schema?.properties?.ownership?.properties?.max_age_seconds?.const === 3600 &&
    schema?.properties?.ownership?.properties?.future_skew_seconds?.const === 300 &&
    schema?.properties?.ownership?.required?.includes('max_age_seconds') &&
    schema?.properties?.ownership?.required?.includes('future_skew_seconds'))
} catch (error) {
  gate('schema parses', false, error.message)
}

gate('implementation exposes prepare verify and ack',
  has(implementation, 'prepare', 'verify', 'ack', 'session-resume-packet/v1'))
gate('implementation contains fail-closed and ownership boundaries',
  has(implementation, 'STALE', 'CONFLICTED', 'INDETERMINATE', "takeover: 'forbidden'"))
gate('implementation requires context, evidence, source, ownership, and external digest rebinding',
  has(implementation,
    "'evidence-root'", "'ownership-state'", "'source-ref'", "'expected-writer'", "'expected-writer-epoch'", "'expected-packet-digest'",
    'context_envelope_changed', 'source_ref_mismatch', 'dirty_repository'))
gate('implementation binds live ownership state and exact branch fail-closed',
  has(implementation,
    'session-ownership/v1', 'ownership_state_changed', 'ownership_liveness_unknown', 'branch_changed',
    'scoped_write', 'read_only_pending_ownership'))
gate('implementation fails indeterminate on stale or future ownership',
  has(implementation,
    'OWNERSHIP_MAX_AGE_SECONDS = 3600', 'OWNERSHIP_FUTURE_SKEW_SECONDS = 300',
    "fail('INDETERMINATE', 'ownership_stale'", "fail('INDETERMINATE', 'ownership_from_future'"))
gate('tests cover valid, stale, corrupt, conflict, secret, path, and writer cases',
  has(tests, 'valid', 'stale', 'corrupt', 'conflict', 'secret', 'path', 'writer'))
gate('tests reject omitted ownership, wrong digest, and arbitrary ACK source ref',
  has(tests,
    'verify requires ownership expectations', 'ACK requires explicit ownership expectations',
    'expected_packet_digest_mismatch', 'source_ref_mismatch'))
gate('tests reject dirty repositories and missing, changed, duplicate, or conflicting evidence',
  has(tests,
    'prepare rejects dirty repository', 'dirty mutation conflicts',
    'evidence_missing', 'evidence_content_changed', 'duplicate_evidence_tuple', 'conflicting_evidence_document'))
gate('tests bind context digest and volatile non-persisted provenance',
  has(tests, 'context_envelope_changed', 'context_provenance_invalid', 'volatile provenance is preserved', 'non-persisted provenance is preserved'))
gate('tests reject symlink or ADS paths and unknown options',
  has(tests, 'linked_path_component', 'unsafe_path_characters', 'unknown_option'))
gate('tests keep informational reasons out of blockers and ACK from one immutable read',
  has(tests, 'shared evidence reason is not a blocker', 'ACK uses one immutable stdin packet read'))
gate('tests cover ownership absence, digest, writer, epoch, liveness, gate, and source drift',
  has(tests,
    'ownership_state_missing', 'ownership_digest_mismatch',
    'changed ownership writer conflicts', 'changed ownership epoch conflicts', 'changed ownership liveness conflicts',
    'changed ownership gate conflicts', 'changed ownership source ref conflicts'))
gate('tests keep active ownership scoped and yielded or unknown ownership fail-closed',
  has(tests,
    'packet binds active ownership liveness', 'yielded ownership cannot produce scoped-write packet',
    'yielded ACK remains read-only pending ownership', 'ownership_liveness_unknown'))
gate('tests reject exact-branch drift and every ACK keeps takeover false',
  has(tests, 'branch_changed', 'ACK never performs takeover', 'yielded ACK does not take ownership', 'partial ACK cannot grant takeover'))
gate('tests bind fixed ownership freshness and reject stale or future state',
  has(tests,
    'packet binds fixed ownership maximum age', 'packet binds fixed ownership future skew',
    'stale active ownership is indeterminate', 'ownership_stale',
    'far-future active ownership is indeterminate', 'ownership_from_future'))

try {
  const fixture = JSON.parse(fixtureText)
  const serialized = JSON.stringify(fixture).toLowerCase()
  gate('adversarial fixture has versioned cases',
    fixture.schema === 'session-resume-test-cases/v1' && Array.isArray(fixture.cases) && fixture.cases.length >= 7)
  gate('fixture covers stale, corrupt, conflict, secret, path, and writer risks',
    ['stale', 'corrupt', 'conflict', 'secret', 'path', 'writer'].every((needle) => serialized.includes(needle)))
} catch (error) {
  gate('adversarial fixture parses', false, error.message)
}

gate('workflow handoff runs project-owned prepare verify ack',
  has(handoff,
    'node scripts/SessionResumePacket.mjs prepare',
    'node scripts/SessionResumePacket.mjs verify',
    'node scripts/SessionResumePacket.mjs ack',
    '--output .vhk/receipts/session-resume-packet.json',
    '--output .vhk/receipts/session-resume-ack.json'))
gate('workflow handoff keeps receipts separate and fails closed',
  has(handoff, 'Content receipt', 'Delivery receipt', 'fail-closed', '자동 생성하지 않는다'))
gate('workflow handoff rebinds clean repo, live evidence, context, source ref, and external digest',
  has(handoff,
    '<clean-git-root>', '--evidence-root <yohan-brain-root>', '--context <task-context.json|->',
    '--source-ref <same-relative-posix-ref-bound-by-prepare>', '--expected-packet-digest <externally-recorded-sha256>',
    'live rehash', 'canonical digest', '필수 외부 기대값'))
gate('workflow handoff requires ownership state for prepare verify and ack',
  (handoff.match(/--ownership-state \.vhk\/ownership\/current\.json/gu) || []).length === 3)
gate('workflow handoff documents active yielded unknown and branch boundaries',
  has(handoff, '`session-ownership/v1`', '`active`', '`scoped_write`', '`yielded`', '`read_only_pending_ownership`', '`unknown`', '`INDETERMINATE`', '`CONFLICTED`'))
gate('workflow handoff documents fixed ownership freshness fail-closed',
  has(handoff, '`max_age_seconds: 3600`', '`future_skew_seconds: 300`', '`ownership_stale`', '`ownership_from_future`', 'prepare·verify·ACK 모두 멈춘다'))
gate('workflow handoff keeps ACK single-read and takeover forbidden',
  has(handoff, '각각 한 번만 읽은 동일 immutable object', 'takeover는 이 절차의 자동 동작이 아니다', '항상 `takeover: false`'))
gate('workflow handoff reports single-device limitation', handoff.includes('REAL_MACHINE_UNVERIFIED'))

const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh'
try {
  const output = execFileSync(shell, [
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', 'tests/SessionResumePacket.Tests.ps1'
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: 5 * 60_000,
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024
  }).trim()
  gate('Session Resume packet PowerShell test', /^PASS: 74 assertions$/mu.test(output), output)
} catch (error) {
  gate('Session Resume packet PowerShell test', false,
    String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
}

for (const prior of [15]) {
  try {
    const priorArgs = [`scripts/check-goal-${prior}.mjs`]
    const output = execFileSync(process.execPath, priorArgs, {
      cwd: repoRoot,
      encoding: 'utf8',
      timeout: 6 * 60_000,
      windowsHide: true,
      maxBuffer: 16 * 1024 * 1024
    }).trim()
    gate(`goal ${prior} gate still passes`,
      new RegExp(`\\[goal ${prior}\\] gate passes`, 'u').test(output))
  } catch (error) {
    gate(`goal ${prior} gate still passes`, false,
      String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
  }
}

if (brainRoot && mcpRoot) {
  try {
    const output = execFileSync(process.execPath, [
      'scripts/check-goal-16.mjs', '--brain-root', brainRoot, '--mcp-root', mcpRoot
    ], {
      cwd: repoRoot,
      encoding: 'utf8',
      timeout: 6 * 60_000,
      windowsHide: true,
      maxBuffer: 16 * 1024 * 1024
    }).trim()
    gate('goal 16 gate still passes with supplied roots', /\[goal 16\] gate passes/u.test(output))
  } catch (error) {
    gate('goal 16 gate still passes with supplied roots', false,
      String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
  }
} else {
  const goal16Required = [
    'goals/16-retrieval-receipt-outcome-loop.md',
    'scripts/check-goal-16.mjs',
    'scripts/RetrievalEvidence.Common.ps1',
    'scripts/Record-RetrievalReceipt.ps1',
    'scripts/Record-RetrievalOutcome.ps1',
    'tests/RetrievalEvidence.Tests.ps1',
    'tests/RetrievalEvidence.CrossRepo.Tests.ps1'
  ]
  gate('goal 16 static artifacts remain present', goal16Required.every((path) => existsSync(join(repoRoot, path))))
  const goal16 = safeRead('goals/16-retrieval-receipt-outcome-loop.md')
  const goal16Gate = safeRead('scripts/check-goal-16.mjs')
  const retrievalCommon = safeRead('scripts/RetrievalEvidence.Common.ps1')
  const retrievalReceipt = safeRead('scripts/Record-RetrievalReceipt.ps1')
  const retrievalOutcome = safeRead('scripts/Record-RetrievalOutcome.ps1')
  gate('goal 16 static contract remains bound to explicit evidence and human outcomes',
    has(goal16, 'id: 16', '명시적 post-action') &&
    has(retrievalCommon, 'schema_bundle_digest', 'content_hash') &&
    has(retrievalReceipt, 'retrieval-diagnostics/v1', 'query_binding.digest') &&
    has(retrievalOutcome, 'human-explicit', 'requires a human actor'))
  gate('goal 16 full cross-repository gate remains available for supplied roots',
    has(goal16Gate, '--brain-root', '--mcp-root', 'actual MCP envelope cross-repository fixture'))
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
  gate('registry and catalog are consistent', false,
    String(error.stdout || error.stderr || `exit ${error.status ?? 'unknown'}`).trim())
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

console.log(pass ? '[goal 18] gate passes' : '[goal 18] gate failed')
process.exit(pass ? 0 : 1)
