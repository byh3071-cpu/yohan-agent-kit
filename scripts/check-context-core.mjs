import { loadCore, validateCore, checkPointers } from './context-core.mjs'
validateCore(loadCore())
checkPointers()
console.log('Context Core schema, temporal validity, sources and instruction pointers OK')
