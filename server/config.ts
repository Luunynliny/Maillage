// Where the vault is. One value, one file, no schema.

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'

const CONFIG_DIR = join(homedir(), '.config', 'maillage')
const CONFIG_FILE = join(CONFIG_DIR, 'config.json')

export const DEFAULT_VAULT_ROOT = join(homedir(), 'Documents', 'Maillage')

export interface Config {
  vaultRoot: string
}

export async function readConfig(): Promise<Config> {
  try {
    const parsed: unknown = JSON.parse(await readFile(CONFIG_FILE, 'utf8'))
    const root = (parsed as Config | null)?.vaultRoot
    if (typeof root === 'string' && root.trim()) return { vaultRoot: resolve(expandTilde(root)) }
  } catch {
    // No config yet, or an unreadable one. Either way the default is the right answer.
  }
  return { vaultRoot: DEFAULT_VAULT_ROOT }
}

export async function writeConfig(config: Config): Promise<Config> {
  const resolved: Config = { vaultRoot: resolve(expandTilde(config.vaultRoot)) }
  await mkdir(dirname(CONFIG_FILE), { recursive: true })
  await writeFile(CONFIG_FILE, `${JSON.stringify(resolved, null, 2)}\n`)
  return resolved
}

function expandTilde(path: string): string {
  return path.startsWith('~') ? join(homedir(), path.slice(1)) : path
}
