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
  console.log(`[goal 14] ${label}: ${ok ? 'PASS' : 'FAIL'}${detail ? ` (${detail})` : ''}`)
  if (!ok) pass = false
}
const read = (path) => readFileSync(join(repoRoot, path), 'utf8').replace(/^﻿/u, '')
const sha256 = (value) => createHash('sha256').update(value).digest('hex').toUpperCase()
const has = (text, ...needles) => needles.every((needle) => text.includes(needle))

if (existsSync(join(repoRoot, '.vhk', 'HARD_STOP'))) {
  console.log('[goal 14] HARD_STOP detected: FAIL')
  process.exit(1)
}

for (const path of [
  'goals/14-design-team-session-continuity.md',
  'docs/audits/design-team-session-continuity-2026-08-23.md',
  'skills/design-team/references/session-continuity.md'
]) gate(`required artifact ${path}`, existsSync(join(repoRoot, path)))

const skill = read('skills/design-team/SKILL.md')
gate('skill routes resumed work to the continuation contract',
  has(skill, '**Resume**', 'session-continuity.md', 'exact next gate'))
gate('skill separates acknowledgement from final acceptance',
  has(skill, 'short acknowledgement', 'final design acceptance', 'production authorization'))
gate('skill requires visual delivery before choice',
  has(skill, 'exact artifact revision is rendered or attached', 'Tool success alone does not prove'))
gate('skill requires target acknowledgement',
  has(skill, 'target acknowledges the project, source ref, current gate, and next action'))

const continuity = read('skills/design-team/references/session-continuity.md')
gate('continuation bundle has identity, taste, artifact, gate, and receipt',
  has(continuity, 'Project-owned continuation bundle', 'confirmed taste rules', 'exact next human decision', 'transfer receipt'))
gate('approval states are distinct',
  has(continuity, '| continue |', '| direction selected |', '| final design accepted |', '| production authorized |'))
gate('visual receipt stops invisible selection',
  has(continuity, 'Visual delivery receipt', 'If the director reports that an image is missing', 'director-visible'))
gate('delivery states do not overclaim receipt',
  has(continuity, '**prepared**', '**sent**', '**acknowledged**', '**failed**', 'A send command is not an acknowledgement'))
gate('receiving handshake resumes at the exact gate',
  has(continuity, 'Starting the next session', 'Do not repeat resolved taste questions', 'exact next gate'))
gate('failure recovery is explicit',
  has(continuity, 'Missing bundle:', 'Missing artifact:', 'Missing acknowledgement:', 'Wrong target session:'))

const context = read('skills/design-team/references/context-contract.md')
gate('context close records continuation receipt',
  has(context, 'continuation bundle', 'artifact visibility', 'session-continuity.md'))

const manual = read('skills/design-team/references/operating-manual.md')
gate('director manual explains resume acknowledgement',
  has(manual, 'When a new session takes over', 'The conversation rhythm', 'When the session closes or moves'))
gate('director manual covers invisible artifacts and false transfer',
  has(manual, 'no image appears', 'writing was mistaken for receiving', 'Continue” was treated as final approval'))

const report = read('skills/design-team/references/report-contract.md')
gate('report separates transfer states',
  has(report, 'Session transfer receipt', '`prepared`, `sent`, `acknowledged`, or `failed`'))

const team = read('skills/design-team/references/team-contract.md')
gate('one conductor owns resumed dialogue',
  has(team, 'session continuity', "director's confirmed language and vocabulary", 'receiving conductor to acknowledge'))

const openai = read('skills/design-team/agents/openai.yaml')
gate('default prompt restores context and taste',
  has(openai, 'DesignContext·취향·세션 인수인계를 복원'))

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
gate('no project, vendor, or fixed-model coupling',
  skillFiles.every((path) => !/(?:yohan|control-tower|\bMOVA\b|\bGPT-5\.6\b|\bLuna\b|\bSol\b|\bTerra\b|lazyweb|linear\.app|\bVHK\b)/iu.test(readFileSync(path, 'utf8'))))
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

for (const prior of ['scripts/check-goal-11.mjs', 'scripts/check-goal-12.mjs', 'scripts/check-goal-13.mjs']) {
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

console.log(pass ? '[goal 14] gate passes' : '[goal 14] gate failed')
process.exit(pass ? 0 : 1)
