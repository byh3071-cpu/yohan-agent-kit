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
  console.log(`[goal 13] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^﻿/u, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 13] HARD_STOP detected: FAIL')
  process.exit(1)
}

for (const path of ['goals/13-design-team-elicitation-hardening.md', 'docs/audits/design-team-elicitation-hardening-2026-08-22.md']) {
  gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))
}

const skill = read('skills/design-team/SKILL.md')
gate('gap 1 — no visuals before references are gathered',
  has(skill, 'Do not create visual directions before references have been gathered', 'anchored to that single accident'))
gate('gap 6 — unstated purpose yields competing purposes',
  has(skill, 'cannot be stated in one sentence', 'differing in what is present rather than in styling'))
gate('gap 8c — team artifacts are scanned too',
  has(skill, "the team's own comparison sheets and candidates"))
gate('reduce stage asks the director to rank usage',
  has(skill, 'used constantly, occasionally, and never', 'weights everything evenly'))

const taste = read('skills/design-team/references/taste-interview.md')
gate('gap 2 — candidate quality bar',
  has(taste, 'The candidate itself must clear the bar', 'cruder than what the project already ships', "the project's existing quality floor"))
gate('gap 2b — fall back to real artifacts instead of lowering the bar',
  has(taste, 'do not lower the bar'))
gate('gap 8a — borrow skeletons rather than inventing layout',
  has(taste, 'Borrow proven skeletons'))
gate('gap 4 — both-rejected means the axis was framed wrong',
  has(taste, 'When both options are rejected', 'shared an assumption', 'Do not re-ask the same axis'))
gate('gap 4b — twice rejected after reframing leaves scope',
  has(taste, 'does not belong in this project'))
gate('gap 5 — removal ranking procedure',
  has(taste, 'Deciding what to remove', 'used constantly / used occasionally / never used', 'if only one element could stay'))
gate('gap 5b — contrast comes from removal',
  has(taste, 'Contrast comes from killing things'))
gate('gap 6b — undefined purpose halts visual work',
  has(taste, 'When the purpose is unclear', 'competing purposes rather than competing styles'))
gate('gap 6c — documented purpose contradicting implementation is the finding',
  has(taste, 'contradicts the live implementation is itself the finding'))
gate('gap 7 — comparison sheet uses provided tooling',
  has(taste, 'Building the comparison sheet', 'authoring skills, templates, and asset libraries the runtime and the project already provide'))
gate('gap 7b — choices must have a way back',
  has(taste, 'Give the choices a way back', 'Verify the return path works before sending it'))

const intake = read('skills/design-team/references/reference-intake.md')
gate('gap 8a2 — take the skeleton, not only the rules',
  has(intake, 'Take the structure, not only the rules', 'the skeleton is what makes it read', 'size ratio between the largest and smallest'))
gate('gap 8a3 — flat result signals rules without structure',
  has(intake, 'rules taken without structure'))
gate('gap 3 — empty forbidden list makes the scan a no-op',
  has(intake, 'An empty forbidden list makes the scan a no-op', 'treat the scan as unrun'))

const verification = read('skills/design-team/references/verification-contract.md')
gate('gap 8c2 — working artifacts are in scope',
  has(verification, 'Everything the team shows the director is in scope', 'comparison sheets, elicitation candidates'))
gate('gap 8b — calibrate tests against the rejected artifact',
  has(verification, 'Calibrate each observable test against the artifact that was actually rejected', 'has not been calibrated at all'))

const report = read('skills/design-team/references/report-contract.md')
gate('reduction stage recorded in artifact sequence',
  has(report, '| Reduction (existing surface) |', "the director's ranking, not the team's guess"))
gate('adopted skeletons recorded in research stage',
  has(report, 'adopted skeletons'))

const manual = read('skills/design-team/references/operating-manual.md')
gate('manual covers flatness, unclear purpose, and lost choices',
  has(manual, 'Nothing stands out', 'what is this screen even for', 'get asked the same questions again'))

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
gate('no product, vendor, or fixed-model coupling',
  skillFiles.every((path) => !/(?:yohan|control-tower|\bMOVA\b|\bGPT-5\.6\b|\bLuna\b|\bSol\b|\bTerra\b|lazyweb|linear\.app|shrimp|\bVHK\b|html-doc)/iu.test(readFileSync(path, 'utf8'))))
gate('no hardcoded aesthetic preference',
  skillFiles.every((path) => !/(?:use\s+(?:a\s+)?(?:dark|light)\s+theme|prefer\s+(?:sans-serif|serif)|brand\s+color\s+is|#[0-9a-f]{6})/iu.test(readFileSync(path, 'utf8'))))

try {
  const manifest = JSON.parse(read('distribution/manifests/design-team.json'))
  const rows = skillFiles.map((path) => {
    const bytes = readFileSync(path)
    return { path: relative(skillRoot, path).replaceAll('\\', '/'), bytes: bytes.length, sha256: sha256(bytes) }
  }).sort((a, b) => a.path.localeCompare(b.path, 'en', { sensitivity: 'base' }) || a.path.localeCompare(b.path, 'en'))
  const digestInput = rows.map((row) => `${row.path}\0${row.bytes}\0${row.sha256}`).join('\n')
  gate('manifest covers every skill file', JSON.stringify(manifest.files) === JSON.stringify(rows))
  gate('manifest digest', manifest.digest === sha256(Buffer.from(digestInput, 'utf8')), manifest.digest)
} catch (error) {
  gate('manifest parse and integrity', false, error.message)
}

for (const prior of ['scripts/check-goal-11.mjs', 'scripts/check-goal-12.mjs']) {
  try {
    const output = execFileSync(process.execPath, [prior], { cwd: repoRoot, encoding: 'utf8', timeout: 180_000, windowsHide: true }).trim()
    gate(`${prior.replace('scripts/check-goal-', 'goal ').replace('.mjs', '')} gate still passes`, /gate passes/u.test(output))
  } catch (error) {
    gate(`${prior} still passes`, false, `exit ${error.status ?? 'unknown'}`)
  }
}

try {
  execFileSync(process.platform === 'win32' ? 'git.exe' : 'git', ['diff', '--check'], { cwd: repoRoot, encoding: 'utf8', timeout: 30_000, windowsHide: true })
  gate('git diff --check', true)
} catch {
  gate('git diff --check', false)
}

console.log(pass ? '[goal 13] gate passes' : '[goal 13] gate failed')
process.exit(pass ? 0 : 1)
