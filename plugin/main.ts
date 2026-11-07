// Worker: palette commands that run the recipe's setup scripts (plugin/vm/) in a terminal of the
// focused local workspace, and copy the dev.Dockerfile prompt. The recipe itself
// (recipes/docker.json) does not need the worker.
import type { OrcaWorkerApi } from 'orca/worker'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const vm = fileURLToPath(new URL('./vm/', import.meta.url))
const prompt = fileURLToPath(new URL('./prompts/dev-dockerfile.md', import.meta.url))

// Command id → [terminal title, script in plugin/vm]. Interactive steps (token, logins) need a terminal.
const scripts: Record<string, [string, string]> = {
  prepare: ['Local Docker: prepare', 'prepare.sh'],
  'git-token': ['Local Docker: git token', 'git-token-setup.sh'],
  'base-image': ['Local Docker: rebuild image', 'docker-base-image.sh'],
  'login.claude': ['Local Docker: log in Claude Code', 'claude-login.sh'],
  'login.cursor': ['Local Docker: log in Cursor Agent', 'cursor-login.sh'],
  'login.opencode': ['Local Docker: log in OpenCode', 'opencode-login.sh']
}

const q = (s: string) => `'${s.replaceAll("'", "'\\''")}'`

// readContext has no workspace id: match it in the list by name and branch. Only local ones: a
// Local Docker workspace is an SSH host, and the scripts must run on this machine.
async function focusedLocalWorkspace(orca: OrcaWorkerApi) {
  const context = await orca.host.call('workspace.readContext', {})
  if (!context) return null
  const { workspaces } = await orca.host.call('workspace.list', {})
  const local = workspaces.filter((w) => w.hostId === null && w.branch === context.branch)
  return local.find((w) => w.name === context.displayName) ?? local[0] ?? null
}

// Clipboard tools in order; the first one present wins.
const clipboards: [string, string[]][] = [
  ['pbcopy', []],
  ['wl-copy', []],
  ['xclip', ['-selection', 'clipboard']],
  ['xsel', ['--clipboard', '--input']]
]

export default function activate(orca: OrcaWorkerApi) {
  for (const [id, [title, script]] of Object.entries(scripts)) {
    orca.commands.register(id, async () => {
      const ws = await focusedLocalWorkspace(orca)
      if (!ws) return 'Open a local workspace of the repository first (not a Local Docker one).'
      if (!existsSync(join(ws.path, 'dev.Dockerfile')))
        return `No dev.Dockerfile in ${ws.path}: run "Local Docker: copy dev.Dockerfile prompt" and give the prompt to an agent.`
      const command = `cd ${q(ws.path)} && bash ${q(join(vm, script))}`
      await orca.host.call('terminal.create', { workspaceId: ws.id, title, command })
      return `Started in a terminal of ${ws.name}.`
    })
  }

  orca.commands.register('copy-prompt', async () => {
    const text = readFileSync(prompt, 'utf8')
    for (const [cmd, args] of clipboards) {
      try {
        execFileSync(cmd, args, { input: text, stdio: ['pipe', 'ignore', 'ignore'] })
        return 'dev.Dockerfile prompt copied. Paste it to an agent in the repository.'
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') orca.log(`${cmd}: ${error}`)
      }
    }
    return `No clipboard tool (pbcopy, wl-copy, xclip, xsel). The prompt is in ${prompt}`
  })
}
