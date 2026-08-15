import { delimiter, join } from 'node:path'

const readEnvironmentValue = (environment, name) => {
  const key = Object.keys(environment).find((candidate) => candidate.toLowerCase() === name.toLowerCase())
  return key ? environment[key] : undefined
}

export function getWindowsPowerShellEnv(baseEnvironment) {
  const environment = { ...baseEnvironment }
  if (process.platform !== 'win32') return environment

  for (const key of Object.keys(environment)) {
    if (key.toLowerCase() === 'psmodulepath') delete environment[key]
  }

  const modulePaths = []
  const programFiles = readEnvironmentValue(environment, 'ProgramFiles')
  const systemRoot = readEnvironmentValue(environment, 'SystemRoot') || readEnvironmentValue(environment, 'WINDIR')
  if (programFiles) modulePaths.push(join(programFiles, 'WindowsPowerShell', 'Modules'))
  if (systemRoot) modulePaths.push(join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules'))
  if (modulePaths.length > 0) environment.PSModulePath = modulePaths.join(delimiter)

  return environment
}
