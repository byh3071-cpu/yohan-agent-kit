#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from 'node:fs'
import { basename, dirname, resolve, sep } from 'node:path'

const PACKET_SCHEMA = 'session-resume-packet/v1'
const ACK_SCHEMA = 'session-resume-ack/v1'
const MAX_INPUT_BYTES = 256 * 1024
const MAX_PACKET_BYTES = 32 * 1024
const MAX_STRING = 1024
const MAX_ITEMS = 16
const OWNERSHIP_MAX_AGE_SECONDS = 3600
const OWNERSHIP_FUTURE_SKEW_SECONDS = 300
const SHA256 = /^[a-f0-9]{64}$/
const GIT_SHA = /^[a-f0-9]{40,64}$/
const CLASSIFICATIONS = new Set(['INVALID', 'STALE', 'CONFLICTED', 'INDETERMINATE', 'VERIFIED'])
const REPEATED_OPTIONS = new Set(['allow', 'forbid', 'human-gate'])
const OPTIONS_BY_COMMAND = {
  prepare: new Set(['context', 'repo-root', 'evidence-root', 'ownership-state', 'source-ref', 'current-gate', 'writer', 'writer-epoch', 'allow', 'forbid', 'human-gate', 'next-action', 'resolution-next-action', 'max-age-seconds', 'now', 'output']),
  verify: new Set(['packet', 'context', 'repo-root', 'evidence-root', 'ownership-state', 'expected-writer', 'expected-writer-epoch', 'expected-packet-digest', 'now']),
  ack: new Set(['packet', 'context', 'repo-root', 'evidence-root', 'ownership-state', 'expected-writer', 'expected-writer-epoch', 'expected-packet-digest', 'receiver', 'owner-scope', 'source-ref', 'current-gate', 'next-action', 'now', 'output']),
}
const PARTIAL_REASON_CODES = new Set(['missing_project_goal', 'missing_next_action', 'shared_repository_evidence_included', 'other_repository_evidence_excluded'])
const BLOCKING_REASON_CODES = new Set(['missing_project_goal', 'missing_next_action'])

class ContractError extends Error {
  constructor(classification, code, message) {
    super(message)
    this.classification = classification
    this.code = code
  }
}

const fail = (classification, code, message) => { throw new ContractError(classification, code, message) }
const gitExecutable = process.platform === 'win32' ? 'git.exe' : 'git'
const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const utf8Bytes = (value) => Buffer.byteLength(value, 'utf8')

function strictJson(text, label) {
  if (utf8Bytes(text) > MAX_INPUT_BYTES) fail('INVALID', 'input_too_large', `${label} exceeds ${MAX_INPUT_BYTES} bytes`)
  let index = text.charCodeAt(0) === 0xFEFF ? 1 : 0
  const ws = () => { while (/\s/.test(text[index] || '')) index += 1 }
  const error = (message) => fail('INVALID', 'invalid_json', `${label}: ${message} at offset ${index}`)
  const string = () => {
    if (text[index++] !== '"') error('expected string')
    let out = ''
    while (index < text.length) {
      const char = text[index++]
      if (char === '"') return out
      if (char === '\\') {
        const escaped = text[index++]
        const simple = { '"': '"', '\\': '\\', '/': '/', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t' }
        if (Object.hasOwn(simple, escaped)) out += simple[escaped]
        else if (escaped === 'u') {
          const hex = text.slice(index, index + 4)
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) error('invalid unicode escape')
          out += String.fromCharCode(Number.parseInt(hex, 16))
          index += 4
        } else error('invalid escape')
      } else {
        if (char.charCodeAt(0) < 0x20) error('unescaped control character')
        out += char
      }
    }
    error('unterminated string')
  }
  const value = () => {
    ws()
    const char = text[index]
    if (char === '"') return string()
    if (char === '{') {
      index += 1
      const object = {}
      const keys = new Set()
      ws()
      if (text[index] === '}') { index += 1; return object }
      while (index < text.length) {
        ws()
        if (text[index] !== '"') error('expected object key')
        const key = string()
        if (keys.has(key)) fail('INVALID', 'duplicate_json_key', `${label}: duplicate JSON key ${JSON.stringify(key)}`)
        keys.add(key)
        ws()
        if (text[index++] !== ':') error('expected colon')
        object[key] = value()
        ws()
        const delimiter = text[index++]
        if (delimiter === '}') return object
        if (delimiter !== ',') error('expected comma or object end')
      }
      error('unterminated object')
    }
    if (char === '[') {
      index += 1
      const array = []
      ws()
      if (text[index] === ']') { index += 1; return array }
      while (index < text.length) {
        array.push(value())
        ws()
        const delimiter = text[index++]
        if (delimiter === ']') return array
        if (delimiter !== ',') error('expected comma or array end')
      }
      error('unterminated array')
    }
    const rest = text.slice(index)
    for (const [literal, result] of [['true', true], ['false', false], ['null', null]]) {
      if (rest.startsWith(literal)) { index += literal.length; return result }
    }
    const number = rest.match(/^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/)
    if (number) {
      index += number[0].length
      const parsed = Number(number[0])
      if (!Number.isFinite(parsed)) error('non-finite number')
      return parsed
    }
    error('expected JSON value')
  }
  const parsed = value()
  ws()
  if (index !== text.length) error('trailing content')
  return parsed
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]))
  }
  return value
}
const canonicalJson = (value) => JSON.stringify(stable(value))

function args(argv) {
  const command = argv[0]
  if (!Object.hasOwn(OPTIONS_BY_COMMAND, command)) fail('INVALID', 'unknown_command', 'Usage: SessionResumePacket.mjs <prepare|verify|ack> [options]')
  const options = {}
  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i]
    if (!token.startsWith('--')) fail('INVALID', 'invalid_argument', `Unexpected argument: ${token}`)
    const name = token.slice(2)
    if (!OPTIONS_BY_COMMAND[command].has(name)) fail('INVALID', 'unknown_option', `--${name} is not valid for ${command}`)
    const next = argv[i + 1]
    if (!next || next.startsWith('--')) fail('INVALID', 'missing_argument_value', `Missing value for --${name}`)
    i += 1
    if (REPEATED_OPTIONS.has(name)) {
      options[name] = [...(options[name] || []), next]
    } else {
      if (Object.hasOwn(options, name)) fail('INVALID', 'duplicate_argument', `Duplicate argument --${name}`)
      options[name] = next
    }
  }
  return { command, options }
}

function required(options, name) {
  const value = options[name]
  if (typeof value !== 'string' || !value.trim()) fail('INVALID', 'missing_argument', `--${name} is required`)
  return value.trim()
}

function boundedString(value, label, max = MAX_STRING) {
  if (typeof value !== 'string' || !value.trim()) fail('INVALID', 'invalid_field', `${label} must be a non-empty string`)
  if (value.length > max) fail('INVALID', 'field_too_large', `${label} exceeds ${max} characters`)
  return value.trim()
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('INVALID', 'invalid_schema', `${label} must be an object`)
  const actual = Object.keys(value).sort()
  const wanted = [...expected].sort()
  if (canonicalJson(actual) !== canonicalJson(wanted)) fail('INVALID', 'invalid_schema', `${label} fields differ from the allowlist`)
}

function safeRelativePath(value, label) {
  const path = boundedString(value, label, 512)
  if (/[\x00-\x1f\x7f]/.test(path) || path.includes(':')) fail('INVALID', 'unsafe_path_characters', `${label} contains a control character or colon`)
  if (/^[A-Za-z]:[\\/]/.test(path) || /^(?:\\\\|\/|~[\\/]|file:\/\/)/i.test(path) || path.includes('\\')) {
    fail('INVALID', 'absolute_or_native_path', `${label} must be a relative POSIX path`)
  }
  const parts = path.split('/')
  if (parts.some((part) => !part || part === '.' || part === '..')) fail('INVALID', 'unsafe_relative_path', `${label} must be normalized`)
  const reserved = /^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i
  if (parts.some((part) => reserved.test(part) || /[. ]$/.test(part))) fail('INVALID', 'unsafe_path_segment', `${label} contains a reserved or trailing-dot/space segment`)
  return path
}

function rejectSecrets(value, path = '$') {
  if (Array.isArray(value)) return value.forEach((item, index) => rejectSecrets(item, `${path}[${index}]`))
  if (value && typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      if (/(?:^|[_-])(secret|password|passwd|token|api[_-]?key|access[_-]?key|private[_-]?key|credential)(?:$|[_-])/i.test(key)) {
        fail('INVALID', 'secret_like_key', `${path}.${key} is secret-like material`)
      }
      rejectSecrets(item, `${path}.${key}`)
    }
    return
  }
  if (typeof value !== 'string') return
  const patterns = [
    /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
    /\b(?:sk|ghp|github_pat|glpat)-?[A-Za-z0-9_]{16,}\b/,
    /\bAKIA[0-9A-Z]{16}\b/,
    /\bBearer\s+[A-Za-z0-9._~+\/-]{16,}\b/i,
    /https?:\/\/[^\s/@:]+:[^\s/@]+@/i,
  ]
  if (patterns.some((pattern) => pattern.test(value))) fail('INVALID', 'secret_like_value', `${path} contains secret-like material`)
}

function readExplicit(path, label) {
  const text = path === '-'
    ? readFileSync(0, 'utf8')
    : readFileSync(resolve(path), 'utf8')
  return strictJson(text, label)
}

const comparablePath = (value) => process.platform === 'win32' ? value.toLowerCase() : value
const containedBy = (parent, child) => comparablePath(child) === comparablePath(parent) || comparablePath(child).startsWith(`${comparablePath(parent)}${sep}`)

function assertUnlinkedPath(root, relativePath, { requireFile = false, missingClassification = 'INVALID', missingCode = 'evidence_missing', nonFileCode = 'evidence_not_file', label = 'Evidence' } = {}) {
  const rootPath = resolve(root)
  if (!existsSync(rootPath)) fail(missingClassification, 'root_missing', `Root does not exist: ${basename(rootPath)}`)
  if (lstatSync(rootPath).isSymbolicLink()) fail('INVALID', 'linked_root', 'Root may not be a symbolic link or reparse-point link')
  const realRoot = realpathSync(rootPath)
  let current = rootPath
  for (const part of relativePath.split('/')) {
    current = resolve(current, part)
    if (!existsSync(current)) {
      if (requireFile) fail(missingClassification, missingCode, `${label} is missing: ${relativePath}`)
      break
    }
    if (lstatSync(current).isSymbolicLink()) fail('INVALID', 'linked_path_component', `Linked path component is forbidden: ${relativePath}`)
    const realCurrent = realpathSync(current)
    if (!containedBy(realRoot, realCurrent)) fail('INVALID', 'path_escape', `Path escapes its declared root: ${relativePath}`)
  }
  if (requireFile) {
    if (!lstatSync(current).isFile()) fail('INDETERMINATE', nonFileCode, `${label} is not a regular file: ${relativePath}`)
    return current
  }
  return { rootPath, realRoot, targetPath: resolve(rootPath, ...relativePath.split('/')) }
}

function evidenceRoot(input) {
  const root = resolve(input)
  if (basename(root).toLowerCase() !== 'yohan-brain') fail('CONFLICTED', 'evidence_root_identity_mismatch', '--evidence-root basename must be yohan-brain')
  assertUnlinkedPath(root, '', { missingClassification: 'INDETERMINATE' })
  return root
}

function evidenceFileDigest(path) {
  const bytes = readFileSync(path)
  const normalized = bytes.toString('utf8').replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  return sha256(Buffer.from(normalized, 'utf8'))
}

function buildEvidence(taskContext, rootInput) {
  const root = evidenceRoot(rootInput)
  const inputs = Array.isArray(taskContext.evidence_refs) ? taskContext.evidence_refs : []
  if (!inputs.length || inputs.length > MAX_ITEMS) fail('INDETERMINATE', 'evidence_count_invalid', `Evidence count must be 1-${MAX_ITEMS}`)
  const tuples = new Set()
  const documents = new Map()
  const result = []
  for (const [indexValue, item] of inputs.entries()) {
    const locator = safeRelativePath(item?.locator, `evidence[${indexValue}].locator`)
    const documentId = boundedString(item?.document_id, `evidence[${indexValue}].document_id`, 128)
    const declaredHash = boundedString(item?.content_hash, `evidence[${indexValue}].content_hash`, 64).toLowerCase()
    if (!SHA256.test(declaredHash)) fail('INDETERMINATE', 'evidence_hash_missing', `evidence[${indexValue}] requires a SHA-256 content hash`)
    const tuple = `${documentId}\0${locator}\0${declaredHash}`
    if (tuples.has(tuple)) fail('INVALID', 'duplicate_evidence_tuple', `Duplicate evidence tuple: ${documentId}`)
    tuples.add(tuple)
    const prior = documents.get(documentId)
    if (prior && prior !== tuple) fail('CONFLICTED', 'conflicting_evidence_document', `Conflicting evidence document id: ${documentId}`)
    documents.set(documentId, tuple)
    if (documentId !== `brain:${locator}`) fail('INVALID', 'evidence_document_id_mismatch', `Evidence document id must equal brain:${locator}`)
    const path = assertUnlinkedPath(root, locator, { requireFile: true, missingClassification: 'INDETERMINATE' })
    const observedHash = evidenceFileDigest(path)
    if (observedHash !== declaredHash) fail('STALE', 'evidence_content_changed', `Evidence content changed: ${locator}`)
    result.push({ document_id: documentId, locator, content_hash: declaredHash })
  }
  return result.sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)))
}

function ownershipDigest(state) {
  const { content_digest: _digest, ...content } = state
  return sha256(canonicalJson(content))
}

function readOwnershipState(repoRootInput, relativeInput) {
  const repoRoot = resolve(repoRootInput)
  const sourcePath = safeRelativePath(relativeInput, '--ownership-state')
  const path = assertUnlinkedPath(repoRoot, sourcePath, {
    requireFile: true,
    missingClassification: 'INDETERMINATE',
    missingCode: 'ownership_state_missing',
    nonFileCode: 'ownership_state_not_file',
    label: 'Ownership state',
  })
  const state = strictJson(readFileSync(path, 'utf8'), 'ownership state')
  exactKeys(state, ['schema', 'active_writer', 'writer_epoch', 'liveness', 'source_ref', 'current_gate', 'updated_at', 'content_digest'], 'ownership state')
  if (state.schema !== 'session-ownership/v1') fail('INVALID', 'ownership_schema_invalid', 'Ownership state schema is invalid')
  boundedString(state.active_writer, 'ownership state.active_writer', 128)
  if (!Number.isSafeInteger(state.writer_epoch) || state.writer_epoch < 1) fail('INVALID', 'ownership_epoch_invalid', 'Ownership state epoch must be a positive integer')
  if (!['active', 'yielded', 'unknown'].includes(state.liveness)) fail('INVALID', 'ownership_liveness_invalid', 'Ownership state liveness is invalid')
  safeRelativePath(state.source_ref, 'ownership state.source_ref')
  boundedString(state.current_gate, 'ownership state.current_gate', 280)
  iso(state.updated_at, 'ownership state.updated_at')
  if (!SHA256.test(String(state.content_digest || '')) || ownershipDigest(state) !== state.content_digest) fail('INVALID', 'ownership_digest_mismatch', 'Ownership state content digest is invalid')
  return { source_path: sourcePath, state }
}

function boundOwnership(liveOwnership) {
  const state = liveOwnership.state
  return {
    source_path: liveOwnership.source_path,
    content_digest: state.content_digest,
    active_writer: state.active_writer,
    writer_epoch: state.writer_epoch,
    liveness: state.liveness,
    source_ref: state.source_ref,
    current_gate: state.current_gate,
    updated_at: state.updated_at,
    max_age_seconds: OWNERSHIP_MAX_AGE_SECONDS,
    future_skew_seconds: OWNERSHIP_FUTURE_SKEW_SECONDS,
    takeover: 'forbidden',
  }
}

function assertOwnershipFresh(liveOwnership, now) {
  const ageSeconds = (now - new Date(liveOwnership.state.updated_at)) / 1000
  if (ageSeconds < -OWNERSHIP_FUTURE_SKEW_SECONDS) fail('INDETERMINATE', 'ownership_from_future', 'Ownership state is beyond the allowed future clock skew')
  if (ageSeconds > OWNERSHIP_MAX_AGE_SECONDS) fail('INDETERMINATE', 'ownership_stale', 'Ownership state is older than the fixed freshness window')
}

function persistExplicit(result, options) {
  if (!options.output) return
  const repoRoot = resolve(required(options, 'repo-root'))
  const relativeOutput = safeRelativePath(options.output, '--output')
  if (!relativeOutput.startsWith('.vhk/receipts/')) {
    fail('INVALID', 'output_outside_receipts', '--output must be under .vhk/receipts/')
  }
  const receiptRoot = resolve(repoRoot, '.vhk', 'receipts')
  const outputPath = resolve(repoRoot, ...relativeOutput.split('/'))
  if (outputPath !== receiptRoot && !outputPath.startsWith(`${receiptRoot}${sep}`)) {
    fail('INVALID', 'output_outside_receipts', '--output escaped the project receipt directory')
  }
  assertUnlinkedPath(repoRoot, relativeOutput)
  if (existsSync(outputPath)) fail('CONFLICTED', 'output_already_exists', 'Receipt output is immutable and already exists')
  mkdirSync(dirname(outputPath), { recursive: true })
  const realRoot = realpathSync(repoRoot)
  const realParent = realpathSync(dirname(outputPath))
  if (!containedBy(realRoot, realParent)) fail('INVALID', 'output_path_escape', 'Receipt output parent escapes the repository')
  assertUnlinkedPath(repoRoot, relativeOutput)
  const temporary = `${outputPath}.tmp-${process.pid}`
  writeFileSync(temporary, `${canonicalJson(result)}\n`, { encoding: 'utf8', flag: 'wx' })
  renameSync(temporary, outputPath)
}

function git(root, gitArgs) {
  try {
    return execFileSync(gitExecutable, ['-C', root, ...gitArgs], { encoding: 'utf8', windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }).trim()
  } catch (error) {
    fail('INDETERMINATE', 'git_unavailable', `Cannot inspect repository: ${String(error.stderr || error.message).trim()}`)
  }
}

function gitOptional(root, gitArgs) {
  try {
    return execFileSync(gitExecutable, ['-C', root, ...gitArgs], { encoding: 'utf8', windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return null
  }
}

function liveGit(rootInput) {
  const root = resolve(rootInput)
  const top = resolve(git(root, ['rev-parse', '--show-toplevel']))
  const comparable = (value) => process.platform === 'win32' ? value.toLowerCase() : value
  if (comparable(top) !== comparable(root)) fail('CONFLICTED', 'repo_root_mismatch', '--repo-root must be the Git top-level directory')
  const sha = git(root, ['rev-parse', 'HEAD']).toLowerCase()
  if (!GIT_SHA.test(sha)) fail('INDETERMINATE', 'invalid_live_git_sha', 'Git returned an unsupported object ID')
  const branch = gitOptional(root, ['symbolic-ref', '--quiet', '--short', 'HEAD']) || null
  const dirty = Boolean(git(root, ['status', '--porcelain=v1', '--untracked-files=normal']))
  return { root, sha, branch, dirty }
}

function iso(value, label) {
  const parsed = new Date(value)
  if (!value || Number.isNaN(parsed.valueOf()) || !/Z$/.test(value)) fail('INVALID', 'invalid_time', `${label} must be an ISO-8601 UTC timestamp`)
  return parsed.toISOString()
}

function digestProjection(packet) {
  const { receipts: _receipts, ...content } = packet
  return content
}

function contentDigest(packet) { return sha256(canonicalJson(digestProjection(packet))) }

function sourceRef(item, label) {
  const source = item?.source_ref
  if (!source || typeof source !== 'object' || Array.isArray(source)) fail('INVALID', 'invalid_source_ref', `${label}.source_ref is required`)
  const locator = safeRelativePath(source.locator, `${label}.source_ref.locator`)
  const contentHash = boundedString(source.content_hash, `${label}.source_ref.content_hash`, 64).toLowerCase()
  if (!SHA256.test(contentHash)) fail('INVALID', 'invalid_content_hash', `${label}.source_ref.content_hash must be SHA-256`)
  return { locator, content_hash: contentHash }
}

function prepare(options) {
  const context = readExplicit(required(options, 'context'), 'context envelope')
  rejectSecrets(context)
  const contextEnvelopeDigest = sha256(canonicalJson(context))
  const diagnostics = context?.data?.retrieval_diagnostics
  if (!diagnostics || diagnostics.schema !== 'retrieval-diagnostics/v1') fail('INDETERMINATE', 'retrieval_lineage_missing', 'retrieval-diagnostics/v1 is required')
  if (diagnostics.volatile !== true || diagnostics.persisted !== false) fail('INVALID', 'context_provenance_invalid', 'P1 context must declare volatile:true and persisted:false')
  const taskContext = context?.data?.task_context
  if (!taskContext || taskContext.schema !== 'task-context/v1') fail('INDETERMINATE', 'task_context_missing', 'P1 task-context/v1 is required')
  if (!['complete', 'partial'].includes(taskContext.status)) fail('INDETERMINATE', 'task_context_not_resumable', `P1 task context status is ${String(taskContext.status)}`)
  const partial = taskContext.status === 'partial'
  const reasonCodes = Array.isArray(taskContext.reason_codes)
    ? taskContext.reason_codes.map((item, index) => boundedString(item, `task_context.reason_codes[${index}]`, 128))
    : []
  if (new Set(reasonCodes).size !== reasonCodes.length) fail('INVALID', 'duplicate_reason_code', 'P1 reason codes must be unique')
  if (partial && (!reasonCodes.includes('missing_project_goal') || !reasonCodes.includes('missing_next_action') || reasonCodes.some((code) => !PARTIAL_REASON_CODES.has(code)))) {
    fail('INDETERMINATE', 'unsupported_partial_reason', 'Partial resume requires only the supported missing-goal resolution reasons')
  }
  const repository = taskContext.repository
  if (!repository || taskContext.source_refs?.repository_manifest?.status !== 'loaded') {
    fail('INDETERMINATE', 'repository_unregistered', 'P1 did not bind a registered repository')
  }
  const repoId = boundedString(repository.id, 'repository.id', 128)
  const canonicalPath = safeRelativePath(repository.canonical_path, 'repository.canonical_path')
  const now = options.now ? iso(options.now, '--now') : new Date().toISOString()
  const operationNow = new Date(now)
  const live = liveGit(required(options, 'repo-root'))
  if (live.dirty) fail('CONFLICTED', 'dirty_repository', 'Prepare requires a clean Git repository')
  if (basename(live.root).toLowerCase() !== repoId.toLowerCase()) {
    fail('CONFLICTED', 'repository_identity_mismatch', 'Git root basename does not match the registered repository id')
  }
  const requestedWriter = boundedString(required(options, 'writer'), '--writer', 128)
  const requestedEpoch = Number.parseInt(required(options, 'writer-epoch'), 10)
  if (!Number.isSafeInteger(requestedEpoch) || requestedEpoch < 1) fail('INVALID', 'invalid_writer_epoch', '--writer-epoch must be a positive integer')
  const requestedSourceRef = safeRelativePath(required(options, 'source-ref'), '--source-ref')
  const requestedGate = boundedString(required(options, 'current-gate'), '--current-gate', 280)
  const liveOwnership = readOwnershipState(live.root, required(options, 'ownership-state'))
  if (liveOwnership.state.liveness === 'unknown') fail('INDETERMINATE', 'ownership_liveness_unknown', 'Ownership liveness is unknown')
  assertOwnershipFresh(liveOwnership, operationNow)
  if (liveOwnership.state.active_writer !== requestedWriter || liveOwnership.state.writer_epoch !== requestedEpoch || liveOwnership.state.source_ref !== requestedSourceRef || liveOwnership.state.current_gate !== requestedGate) {
    fail('CONFLICTED', 'ownership_arguments_mismatch', 'Prepare arguments differ from the live ownership state')
  }
  const goals = Array.isArray(taskContext.goals) ? taskContext.goals : []
  if ((!partial && goals.length !== 1) || (partial && goals.length !== 0)) fail('INDETERMINATE', 'goal_state_inconsistent', 'P1 goal state is inconsistent with task context status')
  const goal = partial ? null : goals[0]
  const actions = Array.isArray(taskContext.next_actions) ? taskContext.next_actions : []
  const selectedAction = partial
    ? options['resolution-next-action']
    : (options['next-action'] || (actions.length === 1 ? actions[0] : null))
  if (partial && !selectedAction) fail('INDETERMINATE', 'resolution_next_action_missing', '--resolution-next-action is required for a partial task context')
  if (!partial && (!selectedAction || !actions.includes(selectedAction))) fail('INDETERMINATE', 'next_action_not_exact', 'An exact P1 next action is required')
  const runtime = diagnostics.runtime
  const index = diagnostics.index
  const catalogRevision = diagnostics.entity_catalog?.revision || context?.data?.diagnostics?.entity_catalog?.revision
  if (!runtime || !index || !catalogRevision) fail('INDETERMINATE', 'retrieval_lineage_incomplete', 'runtime, index, and catalog lineage are required')
  if (!SHA256.test(String(runtime.implementation_digest || ''))) fail('INDETERMINATE', 'runtime_digest_missing', 'Runtime implementation digest is required')
  if (!GIT_SHA.test(String(runtime.source_revision || ''))) fail('INDETERMINATE', 'runtime_revision_missing', 'Runtime source revision is required')
  if (!SHA256.test(String(index.revision || '')) || !SHA256.test(String(index.generation_id || '')) || !SHA256.test(String(catalogRevision))) {
    fail('INDETERMINATE', 'retrieval_revision_missing', 'Index, generation, and catalog SHA-256 revisions are required')
  }
  const evidence = buildEvidence(taskContext, required(options, 'evidence-root'))
  const maxAgeSeconds = Number.parseInt(options['max-age-seconds'] || '86400', 10)
  if (!Number.isSafeInteger(maxAgeSeconds) || maxAgeSeconds < 60 || maxAgeSeconds > 604800) fail('INVALID', 'invalid_max_age', '--max-age-seconds must be 60-604800')
  const created = new Date(now)
  const packet = {
    schema: PACKET_SCHEMA,
    source_ref: requestedSourceRef,
    created_at: created.toISOString(),
    expires_at: new Date(created.valueOf() + maxAgeSeconds * 1000).toISOString(),
    repository: {
      id: repoId,
      canonical_path: canonicalPath,
      manifest_source: safeRelativePath(taskContext.source_refs.repository_manifest.source, 'repository.manifest_source'),
      git: { sha: live.sha, branch: live.branch, dirty: false },
    },
    task: {
      goal: partial ? {
        state: 'missing', id: null, status: null, title: null, source_ref: null,
      } : {
        state: 'selected',
        id: boundedString(goal.id, 'task.goal.id', 128),
        status: boundedString(goal.status, 'task.goal.status', 64),
        title: boundedString(goal.title || goal.id, 'task.goal.title', 280),
        source_ref: sourceRef(goal, 'task.goal'),
      },
      current_gate: requestedGate,
      next_action: boundedString(selectedAction, 'task.next_action'),
      next_action_source: partial ? 'explicit_resolution' : 'p1_task_context',
      blockers: [...new Set([
        ...(Array.isArray(taskContext.blockers) ? taskContext.blockers : []),
        ...(partial ? reasonCodes.filter((code) => BLOCKING_REASON_CODES.has(code)) : []),
      ])].slice(0, MAX_ITEMS).map((item, i) => boundedString(item, `task.blockers[${i}]`, 280)),
    },
    ownership: boundOwnership(liveOwnership),
    policy: {
      execution_mode: partial ? 'read_only_until_goal_selected' : (liveOwnership.state.liveness === 'active' ? 'scoped_write' : 'read_only_pending_ownership'),
      goal_selection_required: partial,
      allowed_work: partial
        ? ['inspect_context', 'select_project_goal', 'prepare_resolution_evidence']
        : (liveOwnership.state.liveness === 'yielded'
            ? ['inspect_context', 'await_ownership']
            : (options.allow || []).map((item, i) => boundedString(item, `policy.allowed_work[${i}]`, 280))),
      forbidden_work: partial
        ? ['implementation', 'repository_writes', 'writer_takeover', ...(options.forbid || []).map((item, i) => boundedString(item, `policy.forbidden_work[${i}]`, 280))]
        : (liveOwnership.state.liveness === 'yielded'
            ? ['implementation', 'repository_writes', 'writer_takeover', ...(options.forbid || []).map((item, i) => boundedString(item, `policy.forbidden_work[${i}]`, 280))]
            : (options.forbid || []).map((item, i) => boundedString(item, `policy.forbidden_work[${i}]`, 280))),
      human_gates: (options['human-gate'] || []).map((item, i) => boundedString(item, `policy.human_gates[${i}]`, 280)),
    },
    lineage: {
      context_envelope: { digest: contextEnvelopeDigest, volatile: true, persisted: false },
      task_context: { schema: taskContext.schema, status: taskContext.status, reason_codes: reasonCodes },
      runtime: {
        repository: boundedString(runtime.repository, 'lineage.runtime.repository', 128),
        implementation_digest: runtime.implementation_digest,
        source_revision: runtime.source_revision.toLowerCase(),
      },
      index: {
        revision: index.revision,
        generation_id: index.generation_id,
        observed_at: iso(index.observed_at, 'lineage.index.observed_at'),
        fresh: index.fresh,
        reason_code: boundedString(index.reason_code || 'unknown', 'lineage.index.reason_code', 128),
        max_age_seconds: maxAgeSeconds,
      },
      catalog: { revision: String(catalogRevision) },
      evidence,
    },
    validation: {
      machine_status: 'REAL_MACHINE_UNVERIFIED',
      reason_code: 'single_device_fixture_only',
    },
    receipts: {
      content: { algorithm: 'sha256', canonicalization: 'sorted-json-utf8-v1', digest: '' },
      delivery: null,
    },
  }
  if (!partial) {
    const ref = packet.task.goal.source_ref
    if (!evidence.some((item) => item.locator === ref.locator && item.content_hash === ref.content_hash)) fail('INDETERMINATE', 'goal_evidence_missing', 'Selected goal source must be present in verified evidence')
  }
  if (![packet.policy.allowed_work, packet.policy.forbidden_work, packet.policy.human_gates].every((items) => items.length > 0 && items.length <= MAX_ITEMS)) {
    fail('INVALID', 'policy_incomplete', 'At least one and at most 16 --allow, --forbid, and --human-gate value is required')
  }
  if (index.fresh !== true) fail('STALE', 'p1_index_not_fresh', 'P1 index must be explicitly fresh')
  packet.receipts.content.digest = contentDigest(packet)
  validatePacket(packet)
  const output = canonicalJson(packet)
  if (utf8Bytes(output) > MAX_PACKET_BYTES) fail('INVALID', 'packet_too_large', `Packet exceeds ${MAX_PACKET_BYTES} bytes`)
  return packet
}

function validatePacket(packet) {
  exactKeys(packet, ['schema', 'source_ref', 'created_at', 'expires_at', 'repository', 'task', 'ownership', 'policy', 'lineage', 'validation', 'receipts'], '$')
  if (packet.schema !== PACKET_SCHEMA) fail('INVALID', 'unsupported_schema', `Expected ${PACKET_SCHEMA}`)
  safeRelativePath(packet.source_ref, 'source_ref')
  exactKeys(packet.repository, ['id', 'canonical_path', 'manifest_source', 'git'], 'repository')
  exactKeys(packet.repository.git, ['sha', 'branch', 'dirty'], 'repository.git')
  exactKeys(packet.task, ['goal', 'current_gate', 'next_action', 'next_action_source', 'blockers'], 'task')
  exactKeys(packet.task.goal, ['state', 'id', 'status', 'title', 'source_ref'], 'task.goal')
  if (packet.task.goal.source_ref !== null) exactKeys(packet.task.goal.source_ref, ['locator', 'content_hash'], 'task.goal.source_ref')
  exactKeys(packet.ownership, ['source_path', 'content_digest', 'active_writer', 'writer_epoch', 'liveness', 'source_ref', 'current_gate', 'updated_at', 'max_age_seconds', 'future_skew_seconds', 'takeover'], 'ownership')
  exactKeys(packet.policy, ['execution_mode', 'goal_selection_required', 'allowed_work', 'forbidden_work', 'human_gates'], 'policy')
  exactKeys(packet.lineage, ['context_envelope', 'task_context', 'runtime', 'index', 'catalog', 'evidence'], 'lineage')
  exactKeys(packet.lineage.context_envelope, ['digest', 'volatile', 'persisted'], 'lineage.context_envelope')
  exactKeys(packet.lineage.task_context, ['schema', 'status', 'reason_codes'], 'lineage.task_context')
  exactKeys(packet.lineage.runtime, ['repository', 'implementation_digest', 'source_revision'], 'lineage.runtime')
  exactKeys(packet.lineage.index, ['revision', 'generation_id', 'observed_at', 'fresh', 'reason_code', 'max_age_seconds'], 'lineage.index')
  exactKeys(packet.lineage.catalog, ['revision'], 'lineage.catalog')
  exactKeys(packet.validation, ['machine_status', 'reason_code'], 'validation')
  exactKeys(packet.receipts, ['content', 'delivery'], 'receipts')
  exactKeys(packet.receipts.content, ['algorithm', 'canonicalization', 'digest'], 'receipts.content')
  if (packet.receipts.delivery !== null) fail('INVALID', 'embedded_delivery_receipt', 'Delivery receipt must remain independent of packet content')
  for (const [index, item] of (packet.lineage.evidence || []).entries()) exactKeys(item, ['document_id', 'locator', 'content_hash'], `lineage.evidence[${index}]`)
  boundedString(packet.repository.id, 'repository.id', 128)
  safeRelativePath(packet.repository.canonical_path, 'repository.canonical_path')
  safeRelativePath(packet.repository.manifest_source, 'repository.manifest_source')
  if (packet.repository.git.branch !== null) boundedString(packet.repository.git.branch, 'repository.git.branch', 256)
  boundedString(packet.task.current_gate, 'task.current_gate', 280)
  boundedString(packet.task.next_action, 'task.next_action', MAX_STRING)
  if (packet.task.goal.source_ref !== null) safeRelativePath(packet.task.goal.source_ref.locator, 'task.goal.source_ref.locator')
  for (const [index, item] of (packet.lineage.evidence || []).entries()) {
    boundedString(item.document_id, `lineage.evidence[${index}].document_id`, 128)
    safeRelativePath(item.locator, `lineage.evidence[${index}].locator`)
    if (item.document_id !== `brain:${item.locator}`) fail('INVALID', 'evidence_document_id_mismatch', `lineage.evidence[${index}] has an invalid document id`)
  }
  if (!GIT_SHA.test(String(packet.repository.git.sha || ''))) fail('INVALID', 'invalid_git_sha', 'repository.git.sha is invalid')
  if (packet.repository.git.dirty !== false) fail('INVALID', 'invalid_dirty_state', 'Resume packets require a clean repository')
  safeRelativePath(packet.ownership.source_path, 'ownership.source_path')
  if (!SHA256.test(String(packet.ownership.content_digest || ''))) fail('INVALID', 'invalid_ownership_digest', 'Ownership content digest is invalid')
  boundedString(packet.ownership.active_writer, 'ownership.active_writer', 128)
  if (!Number.isSafeInteger(packet.ownership.writer_epoch) || packet.ownership.writer_epoch < 1 || !['active', 'yielded'].includes(packet.ownership.liveness) || packet.ownership.takeover !== 'forbidden') fail('INVALID', 'invalid_ownership', 'Ownership contract is invalid')
  safeRelativePath(packet.ownership.source_ref, 'ownership.source_ref')
  boundedString(packet.ownership.current_gate, 'ownership.current_gate', 280)
  iso(packet.ownership.updated_at, 'ownership.updated_at')
  if (packet.ownership.max_age_seconds !== OWNERSHIP_MAX_AGE_SECONDS || packet.ownership.future_skew_seconds !== OWNERSHIP_FUTURE_SKEW_SECONDS) fail('INVALID', 'invalid_ownership_freshness_policy', 'Ownership freshness policy must use the fixed bounds')
  if (packet.source_ref !== packet.ownership.source_ref || packet.task.current_gate !== packet.ownership.current_gate) fail('INVALID', 'ownership_binding_mismatch', 'Packet source ref or gate differs from ownership state binding')
  if (!SHA256.test(String(packet.lineage.context_envelope.digest || '')) || packet.lineage.context_envelope.volatile !== true || packet.lineage.context_envelope.persisted !== false) fail('INVALID', 'invalid_context_provenance', 'Context envelope provenance is invalid')
  if (packet.lineage.task_context.schema !== 'task-context/v1' || !['complete', 'partial'].includes(packet.lineage.task_context.status) || !Array.isArray(packet.lineage.task_context.reason_codes)) fail('INVALID', 'invalid_task_context_lineage', 'Task context lineage is invalid')
  if (packet.lineage.task_context.reason_codes.length > MAX_ITEMS || packet.lineage.task_context.reason_codes.some((item, index) => boundedString(item, `lineage.task_context.reason_codes[${index}]`, 128) !== item)) fail('INVALID', 'invalid_task_context_reasons', 'Task context reason codes are invalid')
  if (new Set(packet.lineage.task_context.reason_codes).size !== packet.lineage.task_context.reason_codes.length) fail('INVALID', 'duplicate_reason_code', 'Task context reason codes must be unique')
  if (!Array.isArray(packet.task.blockers) || packet.task.blockers.length > MAX_ITEMS) fail('INVALID', 'invalid_blockers', 'Task blockers are invalid')
  packet.task.blockers.forEach((item, index) => boundedString(item, `task.blockers[${index}]`, 280))
  if (packet.lineage.task_context.status === 'complete') {
    const expectedMode = packet.ownership.liveness === 'active' ? 'scoped_write' : 'read_only_pending_ownership'
    if (packet.task.goal.state !== 'selected' || !packet.task.goal.id || !packet.task.goal.status || !packet.task.goal.title || packet.task.goal.source_ref === null || packet.task.next_action_source !== 'p1_task_context' || packet.policy.execution_mode !== expectedMode || packet.policy.goal_selection_required !== false) {
      fail('INVALID', 'complete_context_state_mismatch', 'Complete context requires a selected goal and P1 next action')
    }
    boundedString(packet.task.goal.id, 'task.goal.id', 128)
    boundedString(packet.task.goal.status, 'task.goal.status', 64)
    boundedString(packet.task.goal.title, 'task.goal.title', 280)
  } else {
    const reasons = packet.lineage.task_context.reason_codes
    if (!reasons.includes('missing_project_goal') || !reasons.includes('missing_next_action') || reasons.some((code) => !PARTIAL_REASON_CODES.has(code)) || packet.task.goal.state !== 'missing' || packet.task.goal.id !== null || packet.task.goal.status !== null || packet.task.goal.title !== null || packet.task.goal.source_ref !== null || packet.task.next_action_source !== 'explicit_resolution' || packet.policy.execution_mode !== 'read_only_until_goal_selected' || packet.policy.goal_selection_required !== true) {
      fail('INVALID', 'partial_context_state_mismatch', 'Partial context must preserve the missing goal and read-only resolution state')
    }
    if (![...BLOCKING_REASON_CODES].every((reason) => packet.task.blockers.includes(reason))) fail('INVALID', 'partial_context_blockers_missing', 'Actual blocking reason codes must remain explicit blockers')
    if (packet.task.blockers.includes('shared_repository_evidence_included') || packet.task.blockers.includes('other_repository_evidence_excluded')) fail('INVALID', 'informational_reason_promoted', 'Informational reason codes may not become blockers')
    if (!packet.policy.forbidden_work.includes('implementation') || !packet.policy.forbidden_work.includes('repository_writes') || !packet.policy.forbidden_work.includes('writer_takeover')) {
      fail('INVALID', 'partial_context_policy_unsafe', 'Partial context must prohibit implementation, writes, and takeover')
    }
  }
  if (packet.policy.execution_mode !== 'scoped_write' && (!packet.policy.forbidden_work.includes('implementation') || !packet.policy.forbidden_work.includes('repository_writes') || !packet.policy.forbidden_work.includes('writer_takeover'))) fail('INVALID', 'read_only_policy_unsafe', 'Read-only packets must prohibit implementation, writes, and takeover')
  if (packet.validation.machine_status !== 'REAL_MACHINE_UNVERIFIED' || packet.validation.reason_code !== 'single_device_fixture_only') fail('INVALID', 'invalid_machine_validation', 'This implementation must fail-loud as REAL_MACHINE_UNVERIFIED until a cross-machine verifier exists')
  if (packet.lineage.index.fresh !== true) fail('STALE', 'p1_index_not_fresh', 'P1 index is stale')
  const hashes = [packet.lineage.runtime.implementation_digest, packet.lineage.index.revision, packet.lineage.index.generation_id, packet.lineage.catalog.revision, ...(packet.task.goal.source_ref ? [packet.task.goal.source_ref.content_hash] : []), ...(packet.lineage.evidence || []).map((item) => item.content_hash)]
  if (!hashes.every((hash) => SHA256.test(String(hash || '')))) fail('INVALID', 'invalid_sha256', 'A required SHA-256 field is invalid')
  if (!GIT_SHA.test(String(packet.lineage.runtime.source_revision || ''))) fail('INVALID', 'invalid_runtime_revision', 'Runtime source revision is invalid')
  boundedString(packet.lineage.runtime.repository, 'lineage.runtime.repository', 128)
  boundedString(packet.lineage.index.reason_code, 'lineage.index.reason_code', 128)
  if (!Number.isSafeInteger(packet.lineage.index.max_age_seconds) || packet.lineage.index.max_age_seconds < 60 || packet.lineage.index.max_age_seconds > 604800) fail('INVALID', 'invalid_max_age', 'Index max age is invalid')
  if (!Array.isArray(packet.lineage.evidence) || packet.lineage.evidence.length < 1 || packet.lineage.evidence.length > MAX_ITEMS) fail('INVALID', 'invalid_evidence', 'Evidence count is invalid')
  const evidenceCanonical = packet.lineage.evidence.map(canonicalJson)
  if (new Set(evidenceCanonical).size !== evidenceCanonical.length || canonicalJson([...packet.lineage.evidence].sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)))) !== canonicalJson(packet.lineage.evidence)) fail('INVALID', 'evidence_order_or_duplicate', 'Evidence must be unique and deterministically sorted')
  const evidenceDocuments = new Map()
  for (const item of packet.lineage.evidence) {
    const prior = evidenceDocuments.get(item.document_id)
    const tuple = canonicalJson(item)
    if (prior && prior !== tuple) fail('CONFLICTED', 'conflicting_evidence_document', `Conflicting evidence document id: ${item.document_id}`)
    evidenceDocuments.set(item.document_id, tuple)
  }
  if (packet.task.goal.source_ref && !packet.lineage.evidence.some((item) => item.locator === packet.task.goal.source_ref.locator && item.content_hash === packet.task.goal.source_ref.content_hash)) fail('INVALID', 'goal_evidence_missing', 'Selected goal source must be present in packet evidence')
  for (const key of ['allowed_work', 'forbidden_work', 'human_gates']) {
    if (!Array.isArray(packet.policy[key]) || packet.policy[key].length < 1 || packet.policy[key].length > MAX_ITEMS) fail('INVALID', 'invalid_policy', `${key} is invalid`)
    packet.policy[key].forEach((item, index) => boundedString(item, `policy.${key}[${index}]`, 280))
    if (new Set(packet.policy[key]).size !== packet.policy[key].length) fail('INVALID', 'duplicate_policy_item', `${key} contains duplicates`)
  }
  const createdAt = new Date(iso(packet.created_at, 'created_at'))
  const expiresAt = new Date(iso(packet.expires_at, 'expires_at'))
  iso(packet.lineage.index.observed_at, 'lineage.index.observed_at')
  if ((expiresAt - createdAt) / 1000 !== packet.lineage.index.max_age_seconds) fail('INVALID', 'expiry_duration_mismatch', 'expires_at must equal created_at plus max_age_seconds')
  rejectSecrets(packet)
  const serialized = canonicalJson(packet)
  if (utf8Bytes(serialized) > MAX_PACKET_BYTES) fail('INVALID', 'packet_too_large', `Packet exceeds ${MAX_PACKET_BYTES} bytes`)
  if (packet.receipts.content.algorithm !== 'sha256' || packet.receipts.content.canonicalization !== 'sorted-json-utf8-v1' || !SHA256.test(String(packet.receipts.content.digest || ''))) fail('INVALID', 'invalid_content_receipt', 'Content receipt is invalid')
}

function assertContextMatches(packet, context, evidenceRootInput) {
  rejectSecrets(context)
  if (sha256(canonicalJson(context)) !== packet.lineage.context_envelope.digest) fail('STALE', 'context_envelope_changed', 'P1 context envelope digest differs')
  const diagnostics = context?.data?.retrieval_diagnostics
  const taskContext = context?.data?.task_context
  if (!diagnostics || diagnostics.schema !== 'retrieval-diagnostics/v1' || diagnostics.volatile !== true || diagnostics.persisted !== false || !taskContext || taskContext.schema !== 'task-context/v1') fail('INVALID', 'context_provenance_invalid', 'P1 context provenance or schema is invalid')
  const catalogRevision = diagnostics.entity_catalog?.revision || context?.data?.diagnostics?.entity_catalog?.revision
  const expectedTask = { schema: taskContext.schema, status: taskContext.status, reason_codes: taskContext.reason_codes || [] }
  const expectedRuntime = { repository: diagnostics.runtime?.repository, implementation_digest: diagnostics.runtime?.implementation_digest, source_revision: diagnostics.runtime?.source_revision?.toLowerCase() }
  const expectedIndex = {
    revision: diagnostics.index?.revision,
    generation_id: diagnostics.index?.generation_id,
    observed_at: iso(diagnostics.index?.observed_at, 'context.index.observed_at'),
    fresh: diagnostics.index?.fresh,
    reason_code: diagnostics.index?.reason_code || 'unknown',
    max_age_seconds: packet.lineage.index.max_age_seconds,
  }
  if (canonicalJson(expectedTask) !== canonicalJson(packet.lineage.task_context) || canonicalJson(expectedRuntime) !== canonicalJson(packet.lineage.runtime) || canonicalJson(expectedIndex) !== canonicalJson(packet.lineage.index) || catalogRevision !== packet.lineage.catalog.revision) {
    fail('STALE', 'context_lineage_changed', 'P1 runtime/index/catalog/task-context lineage differs')
  }
  const expectedEvidence = buildEvidence(taskContext, evidenceRootInput)
  if (canonicalJson(expectedEvidence) !== canonicalJson(packet.lineage.evidence)) fail('STALE', 'evidence_lineage_changed', 'P1 evidence lineage differs')
  const contextBlockers = Array.isArray(taskContext.blockers) ? taskContext.blockers : []
  const expectedBlockers = [...new Set([...contextBlockers, ...(taskContext.status === 'partial' ? (taskContext.reason_codes || []).filter((code) => BLOCKING_REASON_CODES.has(code)) : [])])].slice(0, MAX_ITEMS)
  if (canonicalJson(expectedBlockers) !== canonicalJson(packet.task.blockers)) fail('STALE', 'task_blockers_changed', 'P1 task blockers differ')
}

function verifyPacket(packet, context, options) {
  validatePacket(packet)
  if (contentDigest(packet) !== packet.receipts.content.digest) fail('INVALID', 'content_digest_mismatch', 'Packet content digest does not match')
  const expectedDigest = required(options, 'expected-packet-digest').toLowerCase()
  if (!SHA256.test(expectedDigest) || expectedDigest !== packet.receipts.content.digest) fail('CONFLICTED', 'expected_packet_digest_mismatch', 'Expected packet digest differs')
  assertContextMatches(packet, context, required(options, 'evidence-root'))
  const now = new Date(options.now ? iso(options.now, '--now') : new Date().toISOString())
  if (now > new Date(packet.expires_at)) fail('STALE', 'packet_expired', 'Packet has expired')
  const observedAge = (now - new Date(packet.lineage.index.observed_at)) / 1000
  if (observedAge < -300 || observedAge > packet.lineage.index.max_age_seconds) fail('STALE', 'index_observation_stale', 'Index observation is outside the permitted age')
  const live = liveGit(required(options, 'repo-root'))
  if (basename(live.root).toLowerCase() !== packet.repository.id.toLowerCase()) fail('CONFLICTED', 'repository_identity_mismatch', 'Live repository identity differs')
  if (live.sha !== packet.repository.git.sha) fail('STALE', 'git_sha_changed', 'Live Git SHA differs from the packet')
  if (live.branch !== packet.repository.git.branch) fail('CONFLICTED', 'branch_changed', 'Live Git branch differs from the packet')
  if (live.dirty) fail('CONFLICTED', 'dirty_repository', 'Verify requires a clean Git repository')
  const liveOwnership = readOwnershipState(live.root, required(options, 'ownership-state'))
  if (liveOwnership.state.liveness === 'unknown') fail('INDETERMINATE', 'ownership_liveness_unknown', 'Ownership liveness is unknown')
  assertOwnershipFresh(liveOwnership, now)
  if (canonicalJson(boundOwnership(liveOwnership)) !== canonicalJson(packet.ownership)) fail('CONFLICTED', 'ownership_state_changed', 'Live ownership state differs from the packet')
  const expectedWriter = required(options, 'expected-writer')
  if (expectedWriter !== packet.ownership.active_writer || expectedWriter !== liveOwnership.state.active_writer) fail('CONFLICTED', 'active_writer_changed', 'Active writer differs from expectation')
  const expectedEpoch = Number.parseInt(required(options, 'expected-writer-epoch'), 10)
  if (!Number.isSafeInteger(expectedEpoch) || expectedEpoch !== packet.ownership.writer_epoch || expectedEpoch !== liveOwnership.state.writer_epoch) fail('CONFLICTED', 'writer_epoch_changed', 'Writer epoch differs from expectation')
  if (packet.policy.execution_mode === 'scoped_write' && (liveOwnership.state.liveness !== 'active' || expectedWriter !== liveOwnership.state.active_writer)) fail('CONFLICTED', 'write_ownership_inactive', 'Scoped writes require the active expected writer')
  return { schema: 'session-resume-verification/v1', classification: 'VERIFIED', packet_digest: packet.receipts.content.digest, repository: packet.repository.id, git_sha: live.sha, dirty: live.dirty, writer: packet.ownership.active_writer, writer_epoch: packet.ownership.writer_epoch }
}

function verify(options) {
  const packet = readExplicit(required(options, 'packet'), 'resume packet')
  const context = readExplicit(required(options, 'context'), 'context envelope')
  return verifyPacket(packet, context, options)
}

function acknowledge(options) {
  const packet = readExplicit(required(options, 'packet'), 'resume packet')
  const context = readExplicit(required(options, 'context'), 'context envelope')
  const verification = verifyPacket(packet, context, options)
  const receiver = boundedString(required(options, 'receiver'), 'receiver', 128)
  const ownerScope = boundedString(required(options, 'owner-scope'), 'owner_scope', 128)
  const sourceRefValue = safeRelativePath(required(options, 'source-ref'), 'source_ref')
  const currentGate = required(options, 'current-gate')
  const nextAction = required(options, 'next-action')
  if (ownerScope !== packet.repository.id) fail('CONFLICTED', 'owner_scope_mismatch', 'Receiver owner scope differs from packet repository')
  if (sourceRefValue !== packet.source_ref) fail('CONFLICTED', 'source_ref_mismatch', 'Receiver source ref differs from the packet')
  if (currentGate !== packet.task.current_gate) fail('CONFLICTED', 'current_gate_mismatch', 'Receiver did not acknowledge the exact current gate')
  if (nextAction !== packet.task.next_action) fail('CONFLICTED', 'next_action_mismatch', 'Receiver did not acknowledge the exact next action')
  const acknowledgedAt = options.now ? iso(options.now, '--now') : new Date().toISOString()
  const delivery = {
    schema: ACK_SCHEMA,
    status: 'ACKNOWLEDGED',
    packet_digest: verification.packet_digest,
    receiver,
    owner_scope: ownerScope,
    source_ref: sourceRefValue,
    current_gate: currentGate,
    next_action: nextAction,
    writer: packet.ownership.active_writer,
    writer_epoch: packet.ownership.writer_epoch,
    takeover: false,
    execution_mode: packet.policy.execution_mode,
    machine_status: packet.validation.machine_status,
    acknowledged_at: acknowledgedAt,
  }
  delivery.delivery_digest = sha256(canonicalJson(delivery))
  return delivery
}

function errorResult(error) {
  const classification = error instanceof ContractError && CLASSIFICATIONS.has(error.classification) ? error.classification : 'INVALID'
  return { schema: 'session-resume-result/v1', classification, reason_code: error.code || 'unexpected_error', message: error.message || String(error) }
}

try {
  const parsed = args(process.argv.slice(2))
  let result
  if (parsed.command === 'prepare') result = prepare(parsed.options)
  else if (parsed.command === 'verify') result = verify(parsed.options)
  else if (parsed.command === 'ack') result = acknowledge(parsed.options)
  else fail('INVALID', 'unknown_command', 'Usage: SessionResumePacket.mjs <prepare|verify|ack> [options]')
  if (parsed.command === 'prepare' || parsed.command === 'ack') persistExplicit(result, parsed.options)
  process.stdout.write(`${canonicalJson(result)}\n`)
} catch (error) {
  process.stdout.write(`${canonicalJson(errorResult(error))}\n`)
  process.exitCode = 2
}
