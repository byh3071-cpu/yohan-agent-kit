import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, cpSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { root, loadCore, validateCore, validateSchema, readCurrent, checkPointers } from './context-core.mjs'

const asOf = '2026-09-09'
const core = () => loadCore()
test('fresh process reads current workplace from disk, not session memory', () => {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import {loadCore,readCurrent} from './scripts/context-core.mjs'; console.log(readCurrent(loadCore(),'yohan','workplace',{asOf:'${asOf}'}).fact.value)`], { cwd: root, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  assert.equal(result.stdout.trim(), '카페레이브')
})
test('previous workplace is preserved as historical with unknown dates', () => {
  const data = validateCore(core(), asOf)
  const fact = data.TIMELINE.facts.find(f => f.value === '카페사이')
  assert.equal(fact.status, 'historical')
  assert.equal(fact.valid_from, null)
  assert.equal(fact.valid_to, null)
})
test('stale copies and high-ranked inferred results cannot override current or mutate data', () => {
  const data = core(), before = structuredClone(data)
  const copies = [
    {...data.CURRENT.facts[0], value:'카페사이', last_verified_at:'2026-08-01'},
    {...data.CURRENT.facts[0], value:'카페사이', source:'inferred', score:1, last_verified_at:'2099-01-01'}
  ]
  const answer = readCurrent(data, 'yohan', 'workplace', {asOf, copies})
  assert.equal(answer.fact.value, '카페레이브')
  assert.equal(answer.ignoredCopies, 2)
  answer.fact.value = 'changed'
  assert.deepEqual(data, before)
})
for (const [name, mutate] of [
  ['missing metadata', d => delete d.CURRENT.facts[0].source],
  ['unknown field', d => d.CURRENT.facts[0].confidence = 1],
  ['unknown source', d => d.CURRENT.facts[0].source = 'missing'],
  ['duplicate ID', d => d.TIMELINE.facts[0].id = d.CURRENT.facts[0].id],
  ['duplicate source', d => d.SOURCES.sources.push({...d.SOURCES.sources[0]})],
  ['conflicting current', d => d.CURRENT.facts.push({...d.CURRENT.facts[0],id:'another',value:'카페사이'})],
  ['current in history', d => d.TIMELINE.facts[0].status = 'current'],
  ['historical in current', d => d.CURRENT.facts[0].status = 'historical'],
  ['future valid_from', d => d.CURRENT.facts[0].valid_from = '2026-09-10'],
  ['exclusive end', d => { d.CURRENT.facts[0].valid_from = '2026-09-08'; d.CURRENT.facts[0].valid_to = asOf }],
  ['reversed interval', d => d.CURRENT.facts[0].valid_to = '2026-09-08'],
  ['invalid calendar date', d => d.CURRENT.facts[0].valid_from = '2026-02-30'],
  ['future verification', d => d.CURRENT.facts[0].last_verified_at = '2099-01-01'],
  ['inferred current', d => d.SOURCES.sources[0].authority = 'inferred'],
  ['swapped documents', d => d.CURRENT.kind = 'profile'],
  ['unknown schema version', d => d.CURRENT.schema_version = 2],
]) test(`reject ${name}`, () => { const data = core(); mutate(data); assert.throws(() => validateCore(data, asOf)) })
test('start is inclusive and missing canonical facts never fall back to copies', () => {
  assert.equal(readCurrent(core(),'yohan','workplace',{asOf}).fact.value,'카페레이브')
  const data = core(); data.CURRENT.facts = []
  assert.throws(() => readCurrent(data,'yohan','workplace',{asOf,copies:[{value:'카페사이'}]}), /unavailable/)
})
test('schema extensions fail closed', () => assert.throws(() => validateSchema('x',{pattern:'x'}), /unsupported/))
test('Codex, Claude and Cursor share generated context instructions; drift is rejected', () => {
  checkPointers()
  const directory = mkdtempSync(join(tmpdir(), 'context-pointers-'))
  try {
    for (const file of ['RULES.md','AGENTS.md','CLAUDE.md','.cursorrules','.cursor']) cpSync(join(root,file),join(directory,file),{recursive:true})
    for (const file of ['AGENTS.md','CLAUDE.md','.cursorrules']) {
      const path = join(directory,file), original = readFileSync(path,'utf8')
      writeFileSync(path,original.replace('context/CURRENT.yaml','context/STALE.yaml'))
      assert.throws(() => checkPointers(directory), /drift/)
      writeFileSync(path,original)
    }
  } finally { rmSync(directory,{recursive:true,force:true}) }
})
