import { readFileSync } from 'node:fs'

function readJson(path) {
  const text = readFileSync(path, 'utf8').replace(/^\uFEFF/, '')
  return JSON.parse(text)
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

const settings = readJson('dotfiles/claude/settings.json')
const marketplace = readJson('.claude-plugin/marketplace.json')
const plugin = readJson('plugins/yohan-core/.claude-plugin/plugin.json')
const claude = readFileSync('CLAUDE.md', 'utf8')

const source = settings.extraKnownMarketplaces?.['yohan-cc-skills']
assert(source?.autoUpdate === true, 'yohan-cc-skills marketplace must set autoUpdate=true')

const entry = marketplace.plugins?.find((candidate) => candidate.name === 'yohan-core')
assert(entry, 'marketplace is missing yohan-core')
assert(entry.version === plugin.version, 'yohan-core version differs between marketplace.json and plugin.json')
assert(/^\d+\.\d+\.\d+$/.test(plugin.version), 'yohan-core version must be stable semver')
assert(!/(?:Phase|다음 액션):?\s*\*{0,2}FILL\b/.test(claude), 'CLAUDE.md contains an unresolved FILL status')

console.log(`context contract OK: yohan-core ${plugin.version}, marketplace auto-update enabled`)
