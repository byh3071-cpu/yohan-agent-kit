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
  console.log(`[goal 12] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^\uFEFF/u, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 12] HARD_STOP detected: FAIL')
  process.exit(1)
}

const required = [
  'goals/12-design-team-taste-workflow.md',
  'skills/design-team/references/taste-interview.md',
  'skills/design-team/references/reference-intake.md',
  'skills/design-team/references/verification-contract.md',
  'skills/design-team/references/operating-manual.md',
  'docs/audits/design-team-taste-workflow-2026-08-22.md'
]
for (const path of required) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const taste = read('skills/design-team/references/taste-interview.md')
gate('taste: candidates are real, never invented', has(taste, 'source candidates, never invent them', 'Director-approved existing work', 'Real shipped artifacts', "controlled pair built from the project's own content"))
gate('taste: axis cap and one axis at a time', has(taste, 'four to seven axes', 'Vary exactly one axis'))
gate('taste: axis is a choice, not a quality scale', has(taste, 'two defensible ends, not a quality scale'))
gate('taste: mandatory read-back before recording', has(taste, 'Step 4 — read back and confirm', 'Only confirmed statements become taste records'))
gate('taste: unconfirmed inference is not approved', has(taste, 'must not be used as if approved'))
gate('taste: forbidden patterns need an observable test', has(taste, 'observable test that a reviewer can apply without the director present'))
gate('taste: session budget and fatigue stop', has(taste, 'Session budget', 'fatigue'))
gate('taste: values live in the owner project', has(taste, 'shared skill repository holds this method only'))

const intake = read('skills/design-team/references/reference-intake.md')
gate('intake: question precedes collection', has(intake, 'state the question first', 'Collect against questions'))
gate('intake: ranked sources', has(intake, 'collect from ranked sources', 'Owner-supplied artifacts', 'Secondary commentary'))
gate('intake: human adoption gate', has(intake, 'human adoption gate', 'never promotes its own recommendation'))
gate('intake: rejections recorded with reason', has(intake, 'Rejected references stay in the record with their reason'))
gate('intake: transfer stated as mechanism', has(intake, 'mechanism, not an adjective'))
gate('intake: forbidden patterns collected equally', has(intake, 'Forbidden patterns', 'same rigor as admired work'))
gate('intake: rights, privacy, and pointer-only sharing', has(intake, 'Storage and rights', 'Never duplicate a binary into the shared skill repository'))

const verification = read('skills/design-team/references/verification-contract.md')
gate('verification: measurement not impression', has(verification, 'measurement, not impression', '"Looks right" is not a result'))
gate('verification: six recorded fields', has(verification, '| Check |', '| Condition |', '| Threshold |', '| Reading |', '| Verdict |', '| Evidence |'))
gate('verification: gate validated against a broken sample', has(verification, 'validate the gate itself against a deliberately broken sample'))
gate('verification: baseline contrast thresholds', has(verification, '4.5:1 body', '3:1 for large text'))
gate('verification: media beyond screen', has(verification, 'Print and produced media', 'Spatial, hardware, and service'))
gate('verification: anti-pattern scan on directions too', has(verification, 'Anti-pattern scan', 'not only on the final artifact'))
gate('verification: adversarial critic is not told the rationale', has(verification, 'A critic told why a decision was made will rationalize it'))
gate('verification: failures are fixed, not annotated', has(verification, 'fixed and re-measured, not annotated and shipped'))
gate('verification: separate from regulatory validation', has(verification, 'not regulatory validation, safety certification, or compliance evidence'))

const context = read('skills/design-team/references/context-contract.md')
gate('context: taste field exists', has(context, '## Taste, forbidden patterns, and reference set'))
gate('context: three record shapes', has(context, '**Confirmed taste rule**', '**Forbidden pattern**', '**Reference**'))
gate('context: open axes and unconfirmed inference guard', has(context, 'open axes', 'never be applied as if approved'))
gate('context: reversal is kept as evidence', has(context, 'A reversal is evidence'))

const manual = read('skills/design-team/references/operating-manual.md')
gate('manual: addressed to the design director', has(manual, 'For the design director'))
gate('manual: run table with director actions', has(manual, '| Stage | The team does | You do |'))
gate('manual: gates that stay with the human', has(manual, 'Gates that are always yours'))
gate('manual: symptom to cause troubleshooting', has(manual, 'When it comes back wrong', 'Generic, could be any product'))

const skill = read('skills/design-team/SKILL.md')
gate('skill: elicit mode', has(skill, '**Elicit** — establish or refresh the taste model'))
gate('skill: elicit and gather loop stages', has(skill, '2. **Elicit**', '3. **Gather**'))
gate('skill: no directions without a taste record', has(skill, 'Do not create visual directions against an empty or stale taste record'))
gate('skill: unconfirmed taste is not presented as approved', has(skill, 'Do not present taste inferences the director has not confirmed'))
gate('skill: forbidden-pattern check before showing work', has(skill, 'Check it against the recorded forbidden patterns before showing it'))
gate('skill: references the four new contracts', has(skill, 'references/taste-interview.md', 'references/reference-intake.md', 'references/verification-contract.md', 'references/operating-manual.md'))

const team = read('skills/design-team/references/team-contract.md')
gate('team: taste elicitor role', has(team, '| Taste elicitor |', 'taste-interview.md'))
gate('team: single director dialogue owner', has(team, 'Only one role holds the director dialogue'))

const report = read('skills/design-team/references/report-contract.md')
gate('report: taste elicitation stage', has(report, '| Taste elicitation |', 'confirms each read-back statement'))
gate('report: verification stage requires readings', has(report, 'measured readings per the verification contract'))

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
gate('no product or fixed-model coupling', skillFiles.every((path) => !/(?:yohan-control-tower|MOVA|\bGPT-5\.6\b|\bLuna\b|\bSol\b|\bTerra\b|lazyweb)/iu.test(readFileSync(path, 'utf8'))))
gate('no hardcoded aesthetic preference', skillFiles.every((path) => !/(?:use\s+(?:a\s+)?(?:dark|light)\s+theme|prefer\s+(?:sans-serif|serif)|brand\s+color\s+is)/iu.test(readFileSync(path, 'utf8'))))

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
  gate('manifest covers every skill file', JSON.stringify(manifest.files) === JSON.stringify(rows))
  gate('manifest digest', manifest.digest === sha256(Buffer.from(digestInput, 'utf8')), manifest.digest)
} catch (error) {
  gate('manifest parse and integrity', false, error.message)
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
  const output = execFileSync(process.execPath, ['scripts/check-goal-11.mjs'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 120_000, windowsHide: true
  }).trim()
  gate('goal 11 gate still passes', output.includes('[goal 11] gate passes'))
} catch (error) {
  gate('goal 11 gate still passes', false, `exit ${error.status ?? 'unknown'}`)
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], {
    cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true
  })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 12] gate passes' : '[goal 12] gate failed')
process.exit(pass ? 0 : 1)
