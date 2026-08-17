const quoteYamlString = (value) => JSON.stringify(String(value))

function decodeScalar(value, label) {
  const trimmed = value.trim()
  if (!trimmed) throw new Error(`${label} must not be empty`)
  if (trimmed.startsWith('"')) {
    try {
      const decoded = JSON.parse(trimmed)
      if (typeof decoded !== 'string') throw new Error('not a string')
      return decoded
    } catch (error) {
      throw new Error(`${label} has invalid quoted YAML: ${error.message}`)
    }
  }
  if (trimmed.startsWith("'")) {
    if (!trimmed.endsWith("'") || trimmed.length < 2) throw new Error(`${label} has an unterminated single-quoted value`)
    return trimmed.slice(1, -1).replaceAll("''", "'")
  }
  return trimmed
}

function foldBlock(lines, style) {
  const normalized = lines.map((line) => line.replace(/^\s{1,}/, ''))
  if (style.startsWith('|')) return normalized.join('\n').replace(/\n+$/, '')
  const paragraphs = []
  let current = []
  for (const line of normalized) {
    if (!line.trim()) {
      if (current.length) paragraphs.push(current.join(' '))
      current = []
    } else current.push(line.trim())
  }
  if (current.length) paragraphs.push(current.join(' '))
  return paragraphs.join('\n')
}

export function parseFrontmatter(markdown, label = 'Markdown asset') {
  const text = String(markdown).replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').replaceAll('\r', '\n')
  const lines = text.split('\n')
  if (lines[0] !== '---') throw new Error(`${label} must start with YAML frontmatter`)
  const closing = lines.indexOf('---', 1)
  if (closing < 0) throw new Error(`${label} has unclosed YAML frontmatter`)

  const header = lines.slice(1, closing)
  const fields = new Map()
  for (let index = 0; index < header.length; index++) {
    const line = header[index]
    if (!line.trim() || /^\s/.test(line)) continue
    const match = line.match(/^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$/)
    if (!match) throw new Error(`${label} has invalid frontmatter line: ${line}`)
    const [, key, rawValue = ''] = match
    if (fields.has(key)) throw new Error(`${label} has duplicate frontmatter field: ${key}`)
    if (/^[>|][+-]?$/.test(rawValue.trim())) {
      const block = []
      while (index + 1 < header.length && (/^\s/.test(header[index + 1]) || !header[index + 1].trim())) {
        block.push(header[++index])
      }
      if (!block.some((item) => item.trim())) throw new Error(`${label} frontmatter field is empty: ${key}`)
      fields.set(key, foldBlock(block, rawValue.trim()))
    } else fields.set(key, decodeScalar(rawValue, `${label} frontmatter field ${key}`))
  }
  return { fields, body: lines.slice(closing + 1).join('\n') }
}

function requiredField(parsed, key, label) {
  const value = parsed.fields.get(key)
  if (!value || !String(value).trim()) throw new Error(`${label} is missing required frontmatter field: ${key}`)
  return String(value).trim()
}

function renderFrontmatter(lines, body) {
  return `---\n${lines.join('\n')}\n---\n${body}`
}

export function renderAntigravitySkill(markdown, label = 'Antigravity skill') {
  const parsed = parseFrontmatter(markdown, label)
  const name = requiredField(parsed, 'name', label)
  const description = requiredField(parsed, 'description', label)
  return renderFrontmatter([
    `name: ${quoteYamlString(name)}`,
    `description: ${quoteYamlString(description)}`
  ], parsed.body)
}

const toolMap = new Map([
  ['Read', 'view_file'],
  ['Grep', 'grep_search'],
  ['Glob', 'grep_search'],
  ['Bash', 'run_command'],
  ['Edit', 'replace_file_content'],
  ['Write', 'replace_file_content']
])
const intentionallyOmittedTools = new Set(['WebFetch', 'WebSearch'])

export function renderAntigravityAgent(markdown, label = 'Antigravity agent') {
  const parsed = parseFrontmatter(markdown, label)
  const name = requiredField(parsed, 'name', label)
  const description = requiredField(parsed, 'description', label)
  const sourceTools = String(parsed.fields.get('tools') ?? '').split(',').map((item) => item.trim()).filter(Boolean)
  const unsupportedTools = sourceTools.filter((tool) => !toolMap.has(tool) && !intentionallyOmittedTools.has(tool))
  if (unsupportedTools.length) throw new Error(`${label} has unsupported Claude tools: ${unsupportedTools.join(', ')}`)
  const tools = [...new Set(sourceTools.map((tool) => toolMap.get(tool)).filter(Boolean))]
  if (!tools.length) tools.push('view_file', 'grep_search')
  const lines = [
    `name: ${quoteYamlString(name)}`,
    `description: ${quoteYamlString(description)}`,
    'tools:',
    ...tools.map((tool) => `  - ${tool}`),
    'mainAgent: false',
    'subagent: true',
    'model: inherit',
    'commandExecutionPolicy: sandbox'
  ]
  return renderFrontmatter(lines, parsed.body)
}

function ruleDescription(markdown, label) {
  const lines = String(markdown).replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').split('\n')
  for (const line of lines) {
    const heading = line.match(/^#{1,6}\s+(.+?)\s*$/)
    if (heading) return heading[1]
  }
  throw new Error(`${label} must contain a Markdown heading for its description`)
}

export function renderAntigravityRule(markdown, label = 'Antigravity rule') {
  const text = String(markdown).replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').replaceAll('\r', '\n')
  const parsed = text.startsWith('---\n') ? parseFrontmatter(text, label) : null
  const body = parsed?.body ?? text
  const description = String(parsed?.fields.get('description') ?? '').trim() || ruleDescription(body, label)
  return renderFrontmatter([`description: ${quoteYamlString(description)}`], body)
}
