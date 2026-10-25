import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const root = fileURLToPath(new URL('../', import.meta.url))
export const files = ['CURRENT', 'PROFILE', 'TIMELINE', 'PROJECTS', 'SOURCES']
const fail = (message) => { throw new Error(message) }
const dateOK = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value

// Context Core deliberately uses JSON-compatible YAML 1.2: no parser dependency,
// tags, aliases, implicit dates, or executable extensions. Not a general YAML API.
export function loadCore(directory = resolve(root, 'context')) {
  return Object.fromEntries(files.map(name => [name, JSON.parse(readFileSync(resolve(directory, `${name}.yaml`), 'utf8'))]))
}

// Only the JSON Schema keywords used by schema.json are supported. Unknown
// keywords fail closed so a future schema cannot silently weaken validation.
export function validateSchema(value, schema, document = schema, path = '$') {
  const supported = ['$schema', 'title', '$defs', '$ref', 'oneOf', 'type', 'const', 'enum', 'required',
    'additionalProperties', 'properties', 'items', 'minItems', 'minLength', 'minimum', 'maximum', 'format']
  for (const key of Object.keys(schema)) if (!supported.includes(key)) fail(`unsupported schema keyword: ${key}`)
  if (schema.$ref) {
    const target = schema.$ref.split('/').slice(1).reduce((node, key) => node?.[key], document)
    if (!target) fail(`unknown reference ${schema.$ref}`)
    return validateSchema(value, target, document, path)
  }
  if (schema.oneOf) {
    const matches = schema.oneOf.filter(option => {
      try { validateSchema(value, option, document, path); return true } catch { return false }
    })
    if (matches.length !== 1) fail(`${path}: expected exactly one schema variant`)
  }
  const type = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value
  if (schema.type && ![schema.type].flat().includes(type)) fail(`${path}: wrong type ${type}`)
  if ('const' in schema && value !== schema.const) fail(`${path}: invalid constant`)
  if (schema.enum && !schema.enum.includes(value)) fail(`${path}: invalid enum`)
  if (type === 'object') {
    for (const key of schema.required ?? []) if (!Object.hasOwn(value, key)) fail(`${path}: missing ${key}`)
    for (const [key, entry] of Object.entries(value)) {
      if (schema.additionalProperties === false && !Object.hasOwn(schema.properties ?? {}, key)) fail(`${path}: unexpected ${key}`)
      if (schema.properties?.[key]) validateSchema(entry, schema.properties[key], document, `${path}.${key}`)
    }
  }
  if (type === 'array') {
    if (value.length < (schema.minItems ?? 0)) fail(`${path}: too few items`)
    value.forEach((entry, index) => validateSchema(entry, schema.items, document, `${path}[${index}]`))
  }
  if (type === 'string') {
    if (value.trim().length < (schema.minLength ?? 0)) fail(`${path}: empty string`)
    if (schema.format === 'date' && !dateOK(value)) fail(`${path}: invalid date`)
  }
  if (type === 'number' && (!Number.isFinite(value) || value < (schema.minimum ?? -Infinity) || value > (schema.maximum ?? Infinity))) fail(`${path}: invalid number`)
}

export function validateCore(core, asOf = new Date().toISOString().slice(0, 10)) {
  if (!dateOK(asOf)) fail('invalid asOf date')
  const schema = JSON.parse(readFileSync(resolve(root, 'context/schema.json'), 'utf8'))
  for (const name of files) {
    validateSchema(core[name], schema)
    if (core[name].kind !== ({CURRENT:'current',PROFILE:'profile',TIMELINE:'timeline',PROJECTS:'projects',SOURCES:'sources'})[name]) fail(`${name}: wrong document kind`)
  }
  const sources = new Map()
  for (const source of core.SOURCES.sources) {
    if (sources.has(source.id)) fail(`duplicate source ${source.id}`)
    if (source.last_verified_at > asOf) fail(`future source verification ${source.id}`)
    sources.set(source.id, source)
  }
  const ids = new Set(), currentKeys = new Set()
  for (const name of files.filter(name => name !== 'SOURCES')) {
    for (const fact of core[name].facts) {
      if (ids.has(fact.id)) fail(`duplicate fact ${fact.id}`)
      ids.add(fact.id)
      const source = sources.get(fact.source)
      if (!source) fail(`unknown source ${fact.source}`)
      if (fact.last_verified_at > asOf || fact.last_verified_at > source.last_verified_at) fail(`invalid verification ${fact.id}`)
      if (fact.valid_from && fact.valid_to && fact.valid_from >= fact.valid_to) fail(`invalid interval ${fact.id}`)
      if (name === 'TIMELINE') {
        if (fact.status === 'current') fail('timeline cannot declare current facts')
        if (fact.status === 'historical' && ((fact.valid_from && fact.valid_from > asOf) || (fact.valid_to && fact.valid_to > asOf))) fail(`future history ${fact.id}`)
      } else {
        if (fact.status !== 'current') fail(`${name} requires current facts`)
        if (!['user_explicit','project_sot'].includes(source.authority)) fail(`untrusted current source ${fact.id}`)
        if (!fact.valid_from || fact.valid_from > asOf || fact.valid_from > fact.last_verified_at || (fact.valid_to && asOf >= fact.valid_to)) fail(`inactive current fact ${fact.id}`)
        const key = `${fact.subject}\0${fact.predicate}`
        if (currentKeys.has(key)) fail(`conflicting current facts ${fact.subject}/${fact.predicate}`)
        currentKeys.add(key)
      }
    }
  }
  return core
}

// Offline acceptance reader, not an MCP, router, or writable memory store.
// External copies are explicitly a separate input; never merged into the core.
export function readCurrent(core, subject, predicate, { asOf, copies = [] } = {}) {
  validateCore(core, asOf)
  const fact = core.CURRENT.facts.find(item => item.subject === subject && item.predicate === predicate)
  if (!fact) fail(`current fact unavailable: ${subject}/${predicate}`)
  return { fact: structuredClone(fact), ignoredCopies: copies.length }
}

export function checkPointers(directory = root) {
  const source = readFileSync(resolve(directory, 'RULES.md'), 'utf8').replace(/\r\n/g, '\n')
  const section = source.match(/## 세션 시작 필독\n([\s\S]*?)(?=\n## |$)/)?.[1].trim()
  if (!section || !section.includes('context/README.md') || !section.includes('context/CURRENT.yaml')) fail('missing canonical context pointer')
  for (const name of ['AGENTS.md','CLAUDE.md','.cursorrules']) {
    const text = readFileSync(resolve(directory, name), 'utf8').replace(/\r\n/g, '\n')
    if (!text.includes(section)) fail(`context instruction drift: ${name}`)
    if (/카페(?:레이브|사이)/.test(text)) fail(`user fact copied into ${name}`)
  }
  const cursor = readFileSync(resolve(directory, '.cursor/rules/ecosystem.mdc'), 'utf8')
  if (!cursor.includes('AGENTS.md') || !cursor.includes('RULES.md')) fail('Cursor bootstrap lost canonical rules pointers')
}
