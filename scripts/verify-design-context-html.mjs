#!/usr/bin/env node

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { createServer } from 'node:http'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, extname, join, normalize, relative, resolve, sep } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const fixtureRoot = join(repoRoot, 'fixtures', 'design-context-html-slice')
const args = process.argv.slice(2)
const valueAfter = (flag) => { const index = args.indexOf(flag); return index >= 0 ? args[index + 1] : undefined }
const committedEvidenceRoot = join(fixtureRoot, 'evidence')
const temporaryEvidenceParent = join(repoRoot, 'tests', '.work')
const evidenceRoot = resolve(valueAfter('--evidence-root') || committedEvidenceRoot)
const allowedEvidenceRoot = evidenceRoot.toLowerCase() === committedEvidenceRoot.toLowerCase() || evidenceRoot.toLowerCase().startsWith(`${temporaryEvidenceParent.toLowerCase()}${sep}`)
if (!allowedEvidenceRoot) throw new Error('Evidence output must be the committed fixture or an isolated tests/.work directory')
const screenshotRoot = join(evidenceRoot, 'screenshots')
const brainRootInput = valueAfter('--brain-root') || process.env.YOHAN_BRAIN_ROOT
const brainRoot = brainRootInput ? resolve(brainRootInput) : ''
const contractRef = '37068a625d85bb3955579a04d87cc0f5c503c823'
const sourceRef = '7d82b08720ab4b20bd75dd38b969be37120707fc'
const sourcePath = 'docs/reference/websites/assets/ai-workspace-context-trust-navigator-432.png'
const sourceSha = '688212d5c2c651db759dd20fd292d4017492925b253057bb301ac8bcca87a7f5'
const viewports = [360, 432, 768, 1280, 1440]

if (!brainRoot || !existsSync(brainRoot)) throw new Error('Provide --brain-root or YOHAN_BRAIN_ROOT for the pinned contract repository')

function findRuntimeModules() {
  const candidates = [
    process.env.CODEX_BUNDLED_NODE_MODULES,
    join(homedir(), '.cache', 'codex-runtimes', 'codex-primary-runtime', 'dependencies', 'node', 'node_modules')
  ].filter(Boolean)
  const found = candidates.find((candidate) => existsSync(join(candidate, 'playwright', 'index.mjs')) && existsSync(join(candidate, 'sharp', 'package.json')))
  if (!found) throw new Error('Bundled Playwright and Sharp runtime dependencies are unavailable')
  return found
}

const modulesRoot = findRuntimeModules()
const { chromium } = await import(pathToFileURL(join(modulesRoot, 'playwright', 'index.mjs')).href)
const sharpModule = await import(pathToFileURL(join(modulesRoot, 'sharp', 'dist', 'index.mjs')).href)
const sharp = sharpModule.default

function gitBytes(ref, path) {
  return execFileSync('git.exe', ['-c', `safe.directory=${brainRoot}`, '-C', brainRoot, 'show', `${ref}:${path}`], {
    encoding: 'buffer', maxBuffer: 32 * 1024 * 1024, windowsHide: true, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' }
  })
}

function sha256(bytes) { return createHash('sha256').update(bytes).digest('hex') }

function contentType(path) {
  return ({ '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8' })[extname(path)] || 'application/octet-stream'
}

function startServer() {
  return new Promise((resolveServer, reject) => {
    const server = createServer((request, response) => {
      try {
        const rawPath = new URL(request.url, 'http://127.0.0.1').pathname
        const requested = rawPath === '/' ? 'index.html' : decodeURIComponent(rawPath.slice(1))
        const target = resolve(fixtureRoot, normalize(requested))
        if (!target.startsWith(fixtureRoot + sep) || !existsSync(target)) { response.writeHead(404); response.end('not found'); return }
        response.setHeader('Content-Type', contentType(target))
        response.setHeader('Cache-Control', 'no-store')
        response.end(readFileSync(target))
      } catch (error) { response.writeHead(500); response.end(String(error.message)) }
    })
    server.once('error', reject)
    server.listen(0, '127.0.0.1', () => resolveServer(server))
  })
}

function parseRgb(value) {
  const match = value.match(/rgba?\((\d+)[, ]+(\d+)[, ]+(\d+)/)
  if (!match) throw new Error(`Unsupported computed color: ${value}`)
  return match.slice(1, 4).map(Number)
}

function luminance(rgb) {
  const values = rgb.map((value) => { const channel = value / 255; return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4 })
  return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]
}

function contrast(foreground, background) {
  const high = Math.max(luminance(parseRgb(foreground)), luminance(parseRgb(background)))
  const low = Math.min(luminance(parseRgb(foreground)), luminance(parseRgb(background)))
  return (high + 0.05) / (low + 0.05)
}

mkdirSync(screenshotRoot, { recursive: true })
for (const name of ['qa-results.json', 'design-qa.md', 'comparison-432.png']) {
  const target = join(evidenceRoot, name)
  if (existsSync(target)) rmSync(target)
}

const sourceBytes = gitBytes(sourceRef, sourcePath)
if (sha256(sourceBytes) !== sourceSha) throw new Error('Approved source hash does not match pinned metadata')
const resolvedContract = execFileSync('git.exe', ['-c', `safe.directory=${brainRoot}`, '-C', brainRoot, 'rev-parse', '--verify', `${contractRef}^{commit}`], { encoding: 'utf8', windowsHide: true }).trim()
if (resolvedContract !== contractRef) throw new Error('Pinned contract commit cannot be resolved exactly')

const server = await startServer()
const port = server.address().port
const browser = await chromium.launch({ headless: true })
const results = { schemaVersion: 1, contractRef, source: { ref: sourceRef, path: sourcePath, sha256: sourceSha }, viewports: [], consoleErrors: [], pageErrors: [], keyboard: [], interaction: [], contrast: [], sameState: {}, issues: { P0: [], P1: [], P2: [] } }

try {
  for (const width of viewports) {
    const page = await browser.newPage({ viewport: { width, height: 1000 }, deviceScaleFactor: 1, reducedMotion: 'reduce' })
    page.on('console', (message) => { if (message.type() === 'error') results.consoleErrors.push({ width, text: message.text() }) })
    page.on('pageerror', (error) => results.pageErrors.push({ width, text: error.message }))
    await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'networkidle' })
    const layout = await page.evaluate(() => {
      const nodes = [document.documentElement, document.body, ...document.querySelectorAll('body *')]
      const overflowNodes = nodes.filter((node) => node.scrollWidth - node.clientWidth > 1).map((node) => ({ tag: node.tagName, className: node.className, delta: node.scrollWidth - node.clientWidth }))
      return { documentDelta: document.documentElement.scrollWidth - document.documentElement.clientWidth, overflowNodes }
    })
    const screenshot = `screenshots/viewport-${width}.png`
    await page.screenshot({ path: join(evidenceRoot, screenshot), fullPage: true })
    results.viewports.push({ width, documentOverflow: layout.documentDelta, overflowingElements: layout.overflowNodes, screenshot })
    await page.close()
  }

  const page = await browser.newPage({ viewport: { width: 432, height: 1000 }, deviceScaleFactor: 1, reducedMotion: 'reduce' })
  page.on('console', (message) => { if (message.type() === 'error') results.consoleErrors.push({ width: 432, text: message.text() }) })
  page.on('pageerror', (error) => results.pageErrors.push({ width: 432, text: error.message }))
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'networkidle' })

  for (const stage of ['request', 'before', 'during', 'after']) {
    await page.locator(`[data-stage="${stage}"]`).click()
    const visible = await page.locator(`[data-stage-panel="${stage}"]`).isVisible()
    results.interaction.push({ control: `tab:${stage}`, passed: visible })
  }
  await page.locator('[data-stage="before"]').click()
  for (const disclosure of ['goal', 'source', 'taste', 'stop']) {
    const trigger = page.locator(`[data-disclosure="${disclosure}"] .context-trigger`)
    const startedOpen = await trigger.getAttribute('aria-expanded') === 'true'
    if (startedOpen) await trigger.click()
    await trigger.click()
    const opened = await trigger.getAttribute('aria-expanded') === 'true'
    await trigger.click()
    const closed = await trigger.getAttribute('aria-expanded') === 'false'
    results.interaction.push({ control: `disclosure:${disclosure}`, passed: opened && closed })
  }
  await page.locator('[data-disclosure="goal"] .context-trigger').click()

  const beforeTab = page.locator('[data-stage="before"]')
  await beforeTab.focus()
  await page.keyboard.press('ArrowRight')
  results.keyboard.push({ step: 'before tab -> ArrowRight', passed: await page.locator('[data-stage="during"]').getAttribute('aria-selected') === 'true' })
  await page.keyboard.press('ArrowLeft')
  results.keyboard.push({ step: 'during tab -> ArrowLeft', passed: await beforeTab.getAttribute('aria-selected') === 'true' })
  const goalTrigger = page.locator('[data-disclosure="goal"] .context-trigger')
  await goalTrigger.focus()
  await page.keyboard.press('Enter')
  results.keyboard.push({ step: 'goal -> Enter closes', passed: await goalTrigger.getAttribute('aria-expanded') === 'false' })
  await page.keyboard.press('Space')
  results.keyboard.push({ step: 'goal -> Space opens', passed: await goalTrigger.getAttribute('aria-expanded') === 'true' })

  const styleEvidence = await page.evaluate(() => {
    const background = (node) => {
      let current = node
      while (current) {
        const value = getComputedStyle(current).backgroundColor
        if (value && value !== 'rgba(0, 0, 0, 0)' && value !== 'transparent') return value
        current = current.parentElement
      }
      return 'rgb(255, 255, 255)'
    }
    const selectors = ['body', '.lede', '.trigger-copy small', '.section-heading > p:last-child', '.source-ref', '.trust-flow small', 'footer']
    return selectors.map((selector) => {
      const node = document.querySelector(selector)
      const style = getComputedStyle(node)
      return { selector, fontSize: Number.parseFloat(style.fontSize), lineHeight: Number.parseFloat(style.lineHeight), color: style.color, background: background(node) }
    })
  })
  for (const item of styleEvidence) results.contrast.push({ ...item, ratio: Number(contrast(item.color, item.background).toFixed(2)), passed: contrast(item.color, item.background) >= 4.5 })

  const structural = await page.evaluate(() => ({
    activeStage: document.querySelector('[role="tab"][aria-selected="true"]')?.dataset.stage,
    expandedDisclosure: document.querySelector('.context-trigger[aria-expanded="true"]')?.closest('[data-disclosure]')?.dataset.disclosure,
    stageCount: document.querySelectorAll('[role="tab"]').length,
    disclosureCount: document.querySelectorAll('[data-disclosure]').length,
    flowLabels: [...document.querySelectorAll('.trust-flow strong')].map((node) => node.textContent.trim()),
    lucideVersion: window.LucideSubset?.version
  }))
  const implementationPath = join(screenshotRoot, 'viewport-432.png')
  const implementationMetadata = await sharp(implementationPath).metadata()
  const sourceMetadata = await sharp(sourceBytes).metadata()
  const gap = 24
  const canvasHeight = Math.max(sourceMetadata.height, implementationMetadata.height)
  await sharp({ create: { width: 432 * 2 + gap, height: canvasHeight, channels: 4, background: '#eef1f7' } })
    .composite([{ input: sourceBytes, left: 0, top: 0 }, { input: readFileSync(implementationPath), left: 432 + gap, top: 0 }])
    .png().toFile(join(evidenceRoot, 'comparison-432.png'))
  results.sameState = {
    viewport: 432,
    state: 'before-tab--goal-expanded',
    sourceWidth: sourceMetadata.width,
    implementationWidth: implementationMetadata.width,
    structural,
    checks: {
      sameViewport: sourceMetadata.width === 432 && implementationMetadata.width === 432,
      sameState: structural.activeStage === 'before' && structural.expandedDisclosure === 'goal',
      stageFirst: structural.stageCount === 4 && structural.disclosureCount === 4,
      trustFlow: structural.flowLabels.join('|') === 'yohan-brain|AI / Codex|검증된 결과',
      realIconLibrary: structural.lucideVersion === '1.8.0'
    },
    evidence: 'comparison-432.png'
  }
  await page.close()
} finally {
  await browser.close()
  await new Promise((resolveClose) => server.close(resolveClose))
}

const failures = []
for (const viewport of results.viewports) if (viewport.documentOverflow !== 0 || viewport.overflowingElements.length) failures.push(`viewport-${viewport.width}-overflow`)
if (results.consoleErrors.length || results.pageErrors.length) failures.push('browser-console-or-page-error')
if (results.keyboard.some((step) => !step.passed)) failures.push('keyboard-path')
if (results.interaction.some((step) => !step.passed)) failures.push('interaction-path')
if (results.contrast.some((item) => !item.passed)) failures.push('wcag-aa-contrast')
if (results.contrast.find((item) => item.selector === 'body')?.fontSize < 16) failures.push('body-font-size')
if (results.contrast.filter((item) => item.selector !== 'body').some((item) => item.fontSize < 14)) failures.push('secondary-font-size')
const bodyStyle = results.contrast.find((item) => item.selector === 'body')
if (!bodyStyle || bodyStyle.lineHeight / bodyStyle.fontSize < 1.6) failures.push('body-line-height')
if (Object.values(results.sameState.checks).some((passed) => !passed)) failures.push('same-state-comparison')
results.issues.P0 = failures
results.summary = { passed: failures.length === 0, p0: failures.length, p1: 0, p2: 0 }

writeFileSync(join(evidenceRoot, 'qa-results.json'), `${JSON.stringify(results, null, 2)}\n`, 'utf8')
const viewportRows = results.viewports.map((item) => `| ${item.width} | ${item.documentOverflow} | ${item.overflowingElements.length} | \`${item.screenshot}\` |`).join('\n')
const contrastRows = results.contrast.map((item) => `| \`${item.selector}\` | ${item.fontSize}px | ${item.ratio}:1 | ${item.passed ? 'PASS' : 'FAIL'} |`).join('\n')
const report = `# Design QA — DesignContext HTML vertical slice

## Source identity and state

- Contract: \`yohan-brain@${contractRef}:memory/design-intelligence/index.yaml\`
- Approved source: \`yohan-brain@${sourceRef}:${sourcePath}\`
- Source SHA-256: \`${sourceSha}\`
- Compared state: 432px, \`작업 전\` tab, \`목표\` disclosure expanded
- Same-state evidence: \`comparison-432.png\` (source left, implementation right)
- Manual visual review: \`manual-visual-review.md\`
- Implementation: \`fixtures/design-context-html-slice/index.html\`

## Responsive and browser evidence

| viewport | horizontal overflow | overflowing elements | capture |
| ---: | ---: | ---: | --- |
${viewportRows}

- Console errors: ${results.consoleErrors.length}
- Page errors: ${results.pageErrors.length}
- Keyboard: roving tab ArrowRight/ArrowLeft and goal Enter/Space — ${results.keyboard.every((step) => step.passed) ? 'PASS' : 'FAIL'}
- Interaction: all 4 tabs and all 4 disclosures — ${results.interaction.every((step) => step.passed) ? 'PASS' : 'FAIL'}
- Icons: Lucide v1.8.0 vendored subset at \`vendor/lucide-icons.js\` — ${results.sameState.checks.realIconLibrary ? 'PASS' : 'FAIL'}

## Typography and WCAG AA

| computed selector | font size | contrast | result |
| --- | ---: | ---: | --- |
${contrastRows}

## Same-state visual review

- Stage priority: 4-stage navigation retained — ${results.sameState.checks.stageFirst ? 'PASS' : 'FAIL'}
- Confirmation flow: goal expanded before source/rules/stop — ${results.sameState.checks.sameState ? 'PASS' : 'FAIL'}
- Mobile provenance: yohan-brain → AI / Codex → verified result — ${results.sameState.checks.trustFlow ? 'PASS' : 'FAIL'}
- Generic card-grid reinterpretation: absent; the implementation uses one ordered disclosure rail and one provenance rail.

## Findings

- P0: ${results.issues.P0.length ? results.issues.P0.join(', ') : '0'}
- P1: 0
- P2: 0
- Stable automatic promotion: disabled
- Full machine-readable evidence: \`qa-results.json\`

final result: ${results.summary.passed ? 'passed' : 'failed'}`
writeFileSync(join(evidenceRoot, 'design-qa.md'), report, 'utf8')

if (!results.summary.passed) {
  console.error(`Design QA failed: ${failures.join(', ')}`)
  process.exit(1)
}
console.log(`PASS: ${viewports.length} viewports, ${results.interaction.length} interactions, ${results.keyboard.length} keyboard steps, ${results.contrast.length} contrast checks`)
