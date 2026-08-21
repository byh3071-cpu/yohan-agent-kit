#!/usr/bin/env node

const MAX_STDIN_BYTES = 1024 * 1024

function fail(message, code = 1) {
  process.stderr.write(`yohan-agent-kit hook: ${message}\n`)
  process.exit(code)
}

async function readBoundedStdin() {
  if (process.stdin.isTTY) return ''
  let size = 0
  const chunks = []
  for await (const chunk of process.stdin) {
    size += chunk.length
    if (size > MAX_STDIN_BYTES) fail('stdin exceeded 1 MiB', 2)
    chunks.push(chunk)
  }
  return Buffer.concat(chunks).toString('utf8')
}

const [vendor = 'unknown', event = 'unknown'] = process.argv.slice(2)

if (vendor === '--self-test') {
  process.stdout.write(`${JSON.stringify({ status: 'PASS', maxStdinBytes: MAX_STDIN_BYTES })}\n`)
  process.exit(0)
}

if (vendor === '--simulate-failure' || process.env.YOHAN_AGENT_KIT_HOOK_TEST_FAILURE === '1') {
  fail('intentional failure for host isolation verification', 17)
}

const input = await readBoundedStdin()
if (input.trim()) {
  try {
    JSON.parse(input)
  } catch {
    fail(`invalid JSON input for ${vendor}/${event}`, 2)
  }
}

// This adapter is intentionally observational: no files, network, secrets, or
// user configuration are read or written. Native hosts own failure handling.
process.exit(0)
