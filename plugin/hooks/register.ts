import type { Engine, Register } from 'claude-code'

// Kemory's status line, loaded by Claude Code 2.1.267 and later through the
// "modules" key in hooks.json. Older Claude Code builds and Grok ignore that
// key and run the command hooks beside it unchanged.
//
// Those hooks fail open, which is right for a session but means a dead
// credential or a stale install looks exactly like a working one. This puts
// that state where it is seen. It sources the plugin's own lib.sh, so the
// credential it checks, token refresh included, is the one the hooks use.

const LATEST_URL =
  'https://raw.githubusercontent.com/SeKondBrainAILabs/kemory-plugin/main/plugin/.claude-plugin/plugin.json'
const RECHECK_MS = 10 * 60 * 1000
const RECALL_TOOL = /^mcp__.*__kemory_(recall.*|ask|get_context|find_similar)$/

const CHECK = `
. "$1/scripts/lib.sh" 2>/dev/null || { echo nolib; exit 0; }
if ! kemory_resolve_auth; then
  if [ -n "\${KEMORY_CREDS_CORRUPT:-}" ]; then echo corrupt; else echo nocreds; fi
  exit 0
fi
[ "\${KEMORY_TOKEN_EXPIRED:-0}" = 1 ] && { echo expired; exit 0; }
curl -s -o /dev/null -w '%{http_code}' --max-time 6 \\
  -H "$KEMORY_AUTH_HEADER" "$KEMORY_BASE_URL/api/v1/namespaces" 2>/dev/null
`

const PROBLEMS: Record<string, string> = {
  nolib: 'plugin scripts missing',
  corrupt: 'credential file is corrupt',
  nocreds: 'no credential, hooks inert',
  expired: 'token expired',
  '401': 'credential rejected (401)',
  '403': 'credential rejected (403)',
  '000': 'API unreachable',
}

async function versionAt($: Engine, url: string): Promise<string | undefined> {
  try {
    const text = url.startsWith('/')
      ? await $.fs.read(url)
      : await $.http.fetch(url).then(r => (r.ok ? r.text : ''))

    return JSON.parse(text).version
  } catch {
    return undefined
  }
}

function isOlder(installed: string, latest: string): boolean {
  const a = installed.split('.').map(Number)
  const b = latest.split('.').map(Number)
  for (let i = 0; i < 3; i++) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) < (b[i] ?? 0)
  }
  return false
}

// Module state: a hot reload starts it over, and the next check refills it.
let problem: string | undefined
let stale: string | undefined
let recalls = 0

function draw($: Engine) {
  const parts = [problem ? `Kemory ✗ ${problem}, run /kemory:status` : 'Kemory ✓']
  if (!problem && recalls > 0) parts.push(`${recalls} recalls`)
  if (stale) parts.push(stale)
  $.ui.status(parts.join(' · '))
}

async function check($: Engine) {
  const root = $.plugin.root
  const [run, installed, latest] = await Promise.all([
    $.process
      .run(['bash', '-c', CHECK, 'kemory-status', root], { timeoutMs: 20000 })
      .catch(() => undefined),
    versionAt($, `${root}/.claude-plugin/plugin.json`),
    versionAt($, LATEST_URL),
  ])
  const code = run?.stdout.trim() || '000'
  const was = problem
  problem = code === '200' ? undefined : (PROBLEMS[code] ?? `API returned HTTP ${code}`)
  stale =
    installed && latest && isOlder(installed, latest)
      ? `plugin ${installed} → ${latest}, run /plugin update kemory@kemory`
      : undefined

  if (problem && problem !== was) $.ui.toast(`Kemory: ${problem}`)
  draw($)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    $.ui.status('Kemory …')
    void check($)
    $.clock.every(RECHECK_MS, () => void check($))

    return result
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (RECALL_TOOL.test(e.tool) && !('deny' in result)) {
      recalls += 1
      draw($)
    }

    return result
  })
}
