import type { EngineInterface as Engine, Register } from 'claude-code'

// Kemory's status line, the band of memories in context above the prompt, and
// a toast for each save, loaded by Claude Code 2.1.267 and later through the
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
const STORE_TOOL = /^mcp__.*__kemory_store_(memory|skill)$/
// prompt-recall.sh lists each injected memory as one line,
// "- [<namespace>] <content>", then "  (memory_id: <uuid>)" on the next.
const INJECTED = /^- (?:\[([^\]\n]+)\] )?(.+)\n {2}\(memory_id: ([0-9a-f-]{36})\)$/gm
const BAND_ROWS = 3

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
const recalled = new Set<string>()
let saved = 0
// What the last prompt's recall put in front of the model, for the band.
let inContext: { namespace: string; title: string }[] = []
let isBandHidden = false

// Memories are written to open with the question they answer, so the first
// sentence is the best title; a long one is cut.
function titleOf(content: string): string {
  const first = content.match(/^(.{8,100}?[?.!])(\s|$)/)?.[1] ?? content

  return first.length > 100 ? `${first.slice(0, 99)}…` : first
}

// The surface already labels the line with the plugin's name, so the text
// leads with the state alone.
function draw($: Engine) {
  const parts = [problem ? `✗ ${problem}, run /kemory:status` : '✓']
  if (!problem && recalled.size > 0) parts.push(`${recalled.size} recalled`)
  if (!problem && saved > 0) parts.push(`${saved} saved`)
  if (stale) parts.push(stale)
  $.ui.status(parts.join(' · '))
}

// A recall tool's text is JSON with a top-level `memories` list. Other lists in
// it (cross_agent_context, shared_chats) are not what was asked for, so only
// that one counts.
function recalledIn(text: string | undefined): string[] {
  try {
    const memories = JSON.parse(text ?? '').memories

    return Array.isArray(memories)
      ? memories.map(m => m?.memory_id).filter((id): id is string => typeof id === 'string')
      : []
  } catch {
    return []
  }
}

// The store tools answer "Namespace: <ns>" and "Version: <n>"; a version past 1
// means a near-duplicate was updated in place rather than a new memory added.
function saveNotice(input: Record<string, unknown>, text: string): string {
  const namespace = text.match(/Namespace: (\S+)/)?.[1] ?? String(input.namespace ?? '')
  const version = Number(text.match(/Version: (\d+)/)?.[1] ?? 1)
  const subject = [input.content, input.name, input.trigger].find(v => typeof v === 'string')
  const what = version > 1 ? `Updated in ${namespace} (v${version})` : `Saved to ${namespace}`

  return subject ? `${what}: "${titleOf(subject as string)}"` : what
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
    $.ui.status('…')
    void check($)
    $.clock.every(RECHECK_MS, () => void check($))

    return result
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    const result = await next(e)
    const before = recalled.size
    inContext = []
    for (const context of result.additionalContext ?? []) {
      for (const [, namespace = '', content, id] of context.matchAll(INJECTED)) {
        if (!content || !id) continue
        recalled.add(id)
        inContext.push({ namespace, title: titleOf(content) })
      }
    }
    if (recalled.size !== before) draw($)
    $.ui.invalidate('ui.render')

    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (e.props.hasSurvey || isBandHidden || inContext.length === 0) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const more = inContext.length - BAND_ROWS
    const noun = inContext.length === 1 ? 'memory' : 'memories'

    return (
      <Box flexDirection="column">
        <Box>
          <Text dimColor>
            Kemory put {inContext.length} {noun} in context{' '}
          </Text>
          <Button
            key="hide"
            label="Hide"
            dimColor
            onPress={() => {
              isBandHidden = true
              $.ui.invalidate('ui.render')
            }}
          />
        </Box>
        {inContext.slice(0, BAND_ROWS).map(m => (
          <Text wrap="truncate-end">
            <Text dimColor>· {m.namespace ? `${m.namespace}  ` : ''}</Text>
            {m.title}
          </Text>
        ))}
        {more > 0 && <Text dimColor>  +{more} more</Text>}
      </Box>
    )
  })

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (result.deny !== undefined || result.isError) return result

    if (RECALL_TOOL.test(e.tool)) {
      const before = recalled.size
      for (const id of recalledIn(result.text)) recalled.add(id)
      if (recalled.size !== before) draw($)
    } else if (STORE_TOOL.test(e.tool)) {
      saved += 1
      draw($)
      $.ui.toast(saveNotice(e as Record<string, unknown>, result.text ?? ''), { timeoutMs: 6000 })
    }

    return result
  })
}
