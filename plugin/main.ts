// Worker: palette commands that run the recipe's setup scripts (plugin/vm/) in a focused terminal of
// the focused local workspace, a status bar item with that workspace's next setup step, and the
// dev.Dockerfile prompt. The recipe itself (recipes/docker.json) does not need the worker.
import type { OrcaWorkerApi } from 'orca/worker'
import { execFile } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const run = promisify(execFile)
const vm = fileURLToPath(new URL('./vm/', import.meta.url))
const prompt = fileURLToPath(new URL('./prompts/dev-dockerfile.md', import.meta.url))

// Command id → [terminal title, script in plugin/vm]. Interactive steps (token, logins) need a terminal.
const scripts: Record<string, [string, string]> = {
  prepare: ['Docker VM: prepare', 'prepare.sh'],
  'git-token': ['Docker VM: git token', 'git-token-setup.sh'],
  'base-image': ['Docker VM: rebuild image', 'docker-base-image.sh']
}

// Status bar per state from vm/status.sh: label, tone, tooltip, command run on click (none: just shown).
type State = { text: string; tone: 'success' | 'warning' | 'danger'; tooltip: string; next?: string }
const states: Record<string, State> = {
  'no-origin': { text: 'no origin', tone: 'danger', tooltip: 'The repository needs an origin remote on GitHub or GitLab.' },
  'no-dockerfile': { text: 'add dev.Dockerfile', tone: 'warning', tooltip: 'Click: copy a prompt that tells an agent to write dev.Dockerfile.', next: 'copy-prompt' },
  'no-docker': { text: 'Docker is not running', tone: 'danger', tooltip: 'Start Docker (or OrbStack).' },
  'no-image': { text: 'set up', tone: 'warning', tooltip: 'No workspace image yet. Click: prepare (git token, image, agent logins).', next: 'prepare' },
  'no-token': { text: 'set up', tone: 'warning', tooltip: 'No git token. Click: prepare.', next: 'prepare' },
  'no-agents': { text: 'set up', tone: 'warning', tooltip: 'No agent is set up. Click: prepare.', next: 'prepare' },
  stale: { text: 'rebuild image', tone: 'warning', tooltip: 'dev.Dockerfile changed after the image was built. Click: rebuild image.', next: 'base-image' },
  ready: { text: 'ready', tone: 'success', tooltip: 'Run on > Per-Workspace Environment > Docker VM. Click: check again (prepare).', next: 'prepare' }
}

const q = (s: string) => `'${s.replaceAll("'", "'\\''")}'`

// The Orca CLI (`orca` on macOS, `orca-ide` on Linux). A Dock-launched Orca gives the worker no shell
// PATH, so the macOS app path is tried too.
const orcaClis = ['orca-ide', 'orca', '/Applications/Orca.app/Contents/Resources/bin/orca']
async function orcaCli(orca: OrcaWorkerApi, args: string[]): Promise<string | null> {
  for (const cli of orcaClis) {
    try {
      return (await run(cli, args)).stdout
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') {
        orca.log(`${cli} ${args.slice(0, 2).join(' ')}: ${error}`)
        return null
      }
    }
  }
  return null
}

type Workspace = { id: string; name: string; path: string }

// The palette gives a command no workspace, and readContext has no workspace id. Candidates: local
// workspaces (hostId "local"; a Docker VM workspace is an SSH host, and the scripts must run on
// this machine) with the focused name and branch. Several (many repos have a "main"): the one that
// owns a terminal of the focused workspace, from `orca terminal list` (the host API has no such map).
async function focusedLocalWorkspace(orca: OrcaWorkerApi): Promise<Workspace | null> {
  const context = await orca.host.call('workspace.readContext', {})
  if (!context) return null
  const { workspaces } = await orca.host.call('workspace.list', {})
  const local = workspaces.filter(
    (w) => (w.hostId === 'local' || w.hostId === null) && w.branch === context.branch && w.name === context.displayName
  )
  if (local.length <= 1) return local[0] ?? null
  const out = await orcaCli(orca, ['terminal', 'list', '--json'])
  const terminals: { handle: string; worktreePath?: string }[] = out ? (JSON.parse(out).result?.terminals ?? []) : []
  const ids = new Set(context.terminals.map((t) => t.id))
  const path = terminals.find((t) => ids.has(t.handle))?.worktreePath
  return local.find((w) => w.path === path) ?? null
}

async function stateOf(path: string): Promise<string> {
  try {
    const { stdout } = await run('bash', [join(vm, 'status.sh')], { env: { ...process.env, ORCA_REPO_PATH: path } })
    const [state, created, changed] = stdout.trim().split('\t')
    // Docker prints nanoseconds; Date.parse wants at most milliseconds.
    const time = (s?: string) => Date.parse((s ?? '').replace(/(\.\d{3})\d+/, '$1'))
    return state === 'ready' && time(changed) > time(created) ? 'stale' : state
  } catch {
    return 'no-origin' // config.sh exits when the repo has no origin remote
  }
}

// Clipboard tools in order; the first one present wins.
const clipboards: [string, string[]][] = [
  ['pbcopy', []],
  ['wl-copy', []],
  ['xclip', ['-selection', 'clipboard']],
  ['xsel', ['--clipboard', '--input']]
]

export default function activate(orca: OrcaWorkerApi) {
  // The palette does not show a command's return value: tell the person with a notification.
  const say = async (body: string) => {
    orca.log(body)
    await orca.host.call('notifications.show', { title: 'Docker VM', body })
    return body
  }

  // A focused, visible tab (the CLI's --focus); the host API's terminal.create opens it in the background.
  const openTerminal = async (ws: Workspace, title: string, script: string) => {
    const command = `bash ${q(join(vm, script))}`
    const out = await orcaCli(orca, ['terminal', 'create', '--worktree', `path:${ws.path}`, '--title', title, '--command', command, '--focus', '--json'])
    if (out === null) {
      await orca.host.call('terminal.create', { workspaceId: ws.id, title, command: `cd ${q(ws.path)} && ${command}` })
      return say(`Started in a background terminal tab "${title}" of ${ws.path} (no Orca CLI to focus it).`)
    }
    return say(`Started "${title}" in ${ws.path}`)
  }

  const runScript = async (id: string) => {
    const [title, script] = scripts[id]
    const ws = await focusedLocalWorkspace(orca)
    if (!ws) return say('No focused local workspace found. Open the repository workspace (not a Docker VM one) with a terminal tab, then retry.')
    if (!existsSync(join(ws.path, 'dev.Dockerfile')))
      return say(`No dev.Dockerfile in ${ws.path}: run "Docker VM: copy dev.Dockerfile prompt" and give the prompt to an agent.`)
    return openTerminal(ws, title, script)
  }
  for (const id of Object.keys(scripts)) orca.commands.register(id, () => runScript(id))

  const copyPrompt = async () => {
    const text = readFileSync(prompt, 'utf8')
    for (const [cmd, args] of clipboards) {
      try {
        const child = execFile(cmd, args)
        child.stdin?.end(text)
        await new Promise((resolve, reject) => child.on('close', (code) => (code === 0 ? resolve(code) : reject(new Error(`exit ${code}`)))).on('error', reject))
        return say('dev.Dockerfile prompt copied. Paste it to an agent in the repository.')
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') orca.log(`${cmd}: ${error}`)
      }
    }
    return say(`No clipboard tool (pbcopy, wl-copy, xclip, xsel). The prompt is in ${prompt}`)
  }
  orca.commands.register('copy-prompt', copyPrompt)

  // Status bar: the focused local workspace's next step; clicking it runs that step.
  let next: string | undefined
  let busy = false
  const refresh = async () => {
    if (busy) return
    busy = true
    try {
      const ws = await focusedLocalWorkspace(orca)
      if (!ws) {
        next = undefined
        await orca.host.call('statusBar.update', { id: 'status', visible: false })
        return
      }
      const state = states[await stateOf(ws.path)] ?? states['no-origin']
      next = state.next
      await orca.host.call('statusBar.update', {
        id: 'status',
        visible: true,
        text: `Docker VM: ${state.text}`,
        tone: state.tone,
        icon: state.tone === 'success' ? 'check' : state.tone === 'danger' ? 'error' : 'warning',
        tooltip: `${state.tooltip}\n${ws.path}`
      })
    } catch (error) {
      orca.log(`status: ${error}`)
    } finally {
      busy = false
    }
  }
  orca.commands.register('next', async () => {
    await refresh()
    if (!next) return say('Nothing to run here: see the status bar tooltip.')
    return next === 'copy-prompt' ? copyPrompt() : runScript(next)
  })
  orca.events.on('workspace.changed', () => void refresh())
  // ponytail: polls every 15 s to notice a finished prepare or a new image; an event from the scripts if this costs too much.
  setInterval(() => void refresh(), 15_000)
  void refresh()
}
