import type { EngineInterface as Engine, Register } from 'claude-code'

// Kemory inside Claude Code, loaded by 2.1.267 and later through the "modules"
// key in hooks.json. Older Claude Code builds and Grok ignore that key and run
// the command hooks beside it unchanged.
//
// The status line says whether Kemory works: the hooks fail open, so a dead
// credential or a stale install would otherwise look like a working one. It
// sources the plugin's own lib.sh, so the credential it checks, token refresh
// included, is the one the hooks use.
//
// The rest puts memory where a person can act on it: a brief for the repo and
// the memories in context above the prompt, a card on each save and recall in
// the transcript, a panel listing them with Helpful, Outdated and Delete, saving
// a note or the last reply, and suggested memories when the session goes quiet.

const LATEST_URL =
  'https://raw.githubusercontent.com/SeKondBrainAILabs/kemory-plugin/main/plugin/.claude-plugin/plugin.json'
const RECHECK_MS = 10 * 60 * 1000
const RECALL_TOOL = /^mcp__.*__kemory_(recall.*|ask|get_context|find_similar)$/
const STORE_TOOL = /^mcp__.*__kemory_store_(memory|skill)$/
// prompt-recall.sh lists each injected memory as one line,
// "- [<namespace>] <content>", then "  (memory_id: <uuid>)" on the next.
const INJECTED = /^- (?:\[([^\]\n]+)\] )?(.+)\n {2}\(memory_id: ([0-9a-f-]{36})\)$/gm
const BAND_ROWS = 3
const PANE = 'kemory-memories'
// The plugin's own MCP server, which the panel's actions go through.
const SERVER = 'plugin:kemory:kemory'
const NAMESPACE = 'shared'
// The repo brief shows only strong matches: a folder name alone is a weak query,
// and below this a search returns whatever happens to be nearest.
const BRIEF_MIN_SIMILARITY = 0.55
// Automatic session summaries say what a session was about, not what is true.
const BRIEF_SKIP_NAMESPACE = /^user:sessions/
const IDLE_MS = 5 * 60 * 1000
const MIN_TURNS_FOR_SUGGESTIONS = 3

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

type Kind = 'saved' | 'updated' | 'recalled' | 'brief'
type Entry = {
  key: string
  id?: string
  kind: Kind
  namespace: string
  title: string
  text: string
  rating?: 'up' | 'down'
  isDeleted?: boolean
  isConfirmingDelete?: boolean
}
type Suggestion = { key: string; text: string; state: 'new' | 'saving' | 'saved' | 'skipped' }

// Module state: a hot reload starts it over, and the next check refills it.
let problem: string | undefined
let stale: string | undefined
// The version the full update command was last shown for, so the toast that
// carries it appears once per session per release, not on every recheck.
let toldUpdateFor: string | undefined
const entries: Entry[] = []
const byCall = new Map<string, string[]>()
const isOpen = new Set<string>()
// What the last prompt's recall put in front of the model, for the band.
let inContext: string[] = []
let isBandHidden = false
let hasPrompted = false
let repoName = ''
let suggestions: Suggestion[] = []
let isSuggesting = false
let turnsSinceSuggestion = 0
let idleTimer: { cancel: () => void } | undefined

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

// Memories are written to open with the question they answer, so the first
// sentence is the best title; a long one is cut.
function titleOf(content: string): string {
  const flat = content.split(/\s+/).join(' ').trim()
  const first = flat.match(/^(.{8,100}?[?.!])(\s|$)/)?.[1] ?? flat

  return first.length > 100 ? `${first.slice(0, 99)}…` : first
}

function find(key: string): Entry | undefined {
  return entries.find(e => e.key === key)
}

function add(entry: Entry): string {
  if (!find(entry.key)) entries.push(entry)

  return entry.key
}

function count(kinds: Kind[]): number {
  return entries.filter(e => kinds.includes(e.kind)).length
}

// The surface already labels the line with the plugin's name, so the text
// leads with the state alone.
function draw($: Engine) {
  const recalled = count(['recalled'])
  const saved = count(['saved', 'updated'])
  const parts = [problem ? `✗ ${problem}, run /kemory:status` : '✓']
  if (!problem && recalled > 0) parts.push(`${recalled} recalled`)
  if (!problem && saved > 0) parts.push(`${saved} saved`)
  if (stale) parts.push(stale)
  $.ui.status(parts.join(' · '))
}

function redraw($: Engine) {
  draw($)
  $.ui.invalidate('ui.render')
}

function toggle($: Engine, key: string) {
  if (isOpen.has(key)) isOpen.delete(key)
  else isOpen.add(key)
  redraw($)
}

function textOf(result: { content: unknown[] }): string {
  return (result.content as { type?: string; text?: unknown }[])
    .map(b => (b.type === 'text' && typeof b.text === 'string' ? b.text : ''))
    .join('')
}

// A recall tool's text is JSON with a top-level `memories` list. Other lists in
// it (cross_agent_context, shared_chats) are not what was asked for, so only
// that one counts.
function memoriesIn(text: string | undefined): { namespace: string; content: string; id: string; similarity: number }[] {
  try {
    const memories = JSON.parse(text ?? '').memories
    if (!Array.isArray(memories)) return []

    return memories
      .filter(m => typeof m?.memory_id === 'string' && typeof m?.content === 'string')
      .map(m => ({
        namespace: String(m.namespace ?? ''),
        content: m.content as string,
        id: m.memory_id as string,
        similarity: typeof m.similarity_score === 'number' ? m.similarity_score : 0,
      }))
  } catch {
    return []
  }
}

// The store tools answer "ID: <id>", "Namespace: <ns>" and "Version: <n>"; a
// version past 1 means a near-duplicate was updated in place.
function stored(text: string, content: string, fallbackKey: string, fallbackNamespace: string): Entry {
  const id = text.match(/ID: (\S+)/)?.[1]
  const version = Number(text.match(/Version: (\d+)/)?.[1] ?? 1)

  return {
    key: id ?? fallbackKey,
    id,
    kind: version > 1 ? 'updated' : 'saved',
    namespace: text.match(/Namespace: (\S+)/)?.[1] ?? fallbackNamespace,
    title: titleOf(content || '(no text)'),
    text: content,
  }
}

function saveNotice(e: Entry): string {
  const what = e.kind === 'updated' ? `Updated in ${e.namespace}` : `Saved to ${e.namespace}`

  return `${what}: "${e.title}"`
}

// What the last update put on disk. The running session keeps the version it
// loaded until a new session starts, so the two can differ.
async function versionOnDisk($: Engine): Promise<string | undefined> {
  try {
    const home = await $.env.get('HOME')
    const plugins = JSON.parse(await $.fs.read(`${home}/.claude/plugins/installed_plugins.json`)).plugins ?? {}
    const key = Object.keys(plugins).find(k => k.startsWith('kemory@'))
    const installs = key ? plugins[key] : undefined

    return Array.isArray(installs) ? installs[0]?.version : undefined
  } catch {
    return undefined
  }
}

// `/plugin` is a terminal dialog. The desktop app has no such command, so a
// session drawn only there is told to use the CLI.
async function updateHint($: Engine): Promise<string> {
  const surfaces = await $.session.surfaces()

  return surfaces.includes('terminal')
    ? 'Run /plugin update kemory@kemory, then restart.'
    : "Run 'claude plugin update kemory@kemory' in a terminal, then open a new session."
}

async function check($: Engine) {
  const root = $.plugin.root
  const [run, installed, latest, onDisk] = await Promise.all([
    $.process
      .run(['bash', '-c', CHECK, 'kemory-status', root], { timeoutMs: 20000 })
      .catch(() => undefined),
    versionAt($, `${root}/.claude-plugin/plugin.json`),
    versionAt($, LATEST_URL),
    versionOnDisk($),
  ])
  const code = run?.stdout.trim() || '000'
  const was = problem
  problem = code === '200' ? undefined : (PROBLEMS[code] ?? `API returned HTTP ${code}`)
  // The status line is narrow and cannot be clicked, so it carries only the
  // fact; the command, which does not fit there, goes in a toast.
  if (!installed || !latest || !isOlder(installed, latest)) stale = undefined
  else if (onDisk && !isOlder(onDisk, latest)) stale = `${onDisk} installed, new session to apply`
  else {
    stale = `↑ ${latest} available`
    if (toldUpdateFor !== latest) {
      toldUpdateFor = latest
      $.ui.toast(`Kemory ${latest} is out (you have ${installed}). ${await updateHint($)}`, { timeoutMs: 12000 })
    }
  }

  if (problem && problem !== was) $.ui.toast(`Kemory: ${problem}`)
  draw($)
}

// A person's verdict on a memory, sent through the plugin's server.
async function rate($: Engine, key: string, rating: 'up' | 'down') {
  const e = find(key)
  if (!e?.id) return
  const reason = rating === 'up' ? 'correct' : 'outdated'
  const result = await $.mcp.call(SERVER, 'kemory_rate_memory', { target_id: e.id, rating, reason })
  if (result.isError) {
    $.ui.toast('Kemory: rating failed')
    return
  }
  e.rating = rating
  $.ui.toast(rating === 'up' ? 'Kemory: marked helpful' : 'Kemory: marked outdated')
  redraw($)
}

// Delete takes two presses, the second labelled "Confirm delete".
async function remove($: Engine, key: string) {
  const e = find(key)
  if (!e?.id) return
  if (!e.isConfirmingDelete) {
    e.isConfirmingDelete = true
    redraw($)
    return
  }
  const result = await $.mcp.call(SERVER, 'kemory_delete_memory', { memory_id: e.id })
  e.isConfirmingDelete = false
  if (result.isError) {
    $.ui.toast('Kemory: delete failed')
  } else {
    e.isDeleted = true
    $.ui.toast(`Kemory: deleted "${e.title}"`)
  }
  redraw($)
}

// A save a person asked for: /remember, "Save last reply", or a suggestion.
async function save($: Engine, content: string): Promise<boolean> {
  const result = await $.mcp.call(SERVER, 'kemory_store_memory', {
    content,
    namespace: NAMESPACE,
    content_type: 'fact',
  })
  if (result.isError) {
    $.ui.toast('Kemory: save failed')
    return false
  }
  const entry = stored(textOf(result), content, `save-${entries.length}`, NAMESPACE)
  add(entry)
  $.ui.toast(saveNotice(entry), { timeoutMs: 6000 })
  redraw($)
  return true
}

async function lastReply($: Engine): Promise<string | undefined> {
  const messages = await $.session.messages()
  const last = [...messages].reverse().find(m => m.role === 'assistant' && m.text.trim())

  return last?.text.trim().slice(0, 4000)
}

async function saveLastReply($: Engine) {
  const text = await lastReply($)
  if (text) await save($, text)
}

// The model reads the session it is in (a fork, served from the prompt cache)
// and proposes memories. Nothing is stored until a person saves one.
async function suggest($: Engine, isAsked: boolean) {
  if (isSuggesting) return
  isSuggesting = true
  redraw($)
  const r = await $.model.fork({
    prompt:
      'From this conversation, pick at most 3 durable facts worth keeping in long-term memory: decisions, preferences, ' +
      'non-obvious gotchas with their fix. Skip anything transient or already saved. Write each so it opens with the ' +
      'question someone would later ask, in plain words, then the answer with exact identifiers. ' +
      'Reply with only a JSON array of strings, [] if nothing qualifies.',
  })
  isSuggesting = false
  turnsSinceSuggestion = 0
  if (!r.isAnswered) {
    if (isAsked) $.ui.toast(`Kemory: no suggestions (${r.reason})`)
    redraw($)
    return
  }
  let list: unknown = []
  try {
    list = JSON.parse(r.text.match(/\[[\s\S]*\]/)?.[0] ?? '[]')
  } catch {
    list = []
  }
  const fresh = (Array.isArray(list) ? list : []).filter((s): s is string => typeof s === 'string' && s.trim().length > 20)
  suggestions = [
    ...suggestions,
    ...fresh.map((text, i) => ({ key: `s-${suggestions.length + i}`, text: text.trim(), state: 'new' as const })),
  ]
  if (fresh.length > 0) {
    const noun = fresh.length === 1 ? 'memory' : 'memories'
    $.ui.toast(`Kemory: ${fresh.length} suggested ${noun}, see /kemory:memories`, { timeoutMs: 8000 })
  } else if (isAsked) {
    $.ui.toast('Kemory: nothing new worth saving')
  }
  redraw($)
}

async function saveSuggestion($: Engine, key: string) {
  const s = suggestions.find(x => x.key === key)
  if (!s || s.state !== 'new') return
  s.state = 'saving'
  redraw($)
  s.state = (await save($, s.text)) ? 'saved' : 'new'
  redraw($)
}

function skipSuggestion($: Engine, key: string) {
  const s = suggestions.find(x => x.key === key)
  if (s) s.state = 'skipped'
  redraw($)
}

// What Kemory already knows about the repo this session runs in.
async function brief($: Engine) {
  const root = await $.session.root()
  repoName = root.split('/').filter(Boolean).pop() ?? ''
  if (!repoName) return
  const result = await $.mcp.call(SERVER, 'kemory_recall_memory', {
    query: `${repoName} repository: how it is set up, decisions and gotchas`,
    limit: 8,
  })
  if (result.isError) return
  const strong = memoriesIn(textOf(result))
    .filter(m => m.similarity >= BRIEF_MIN_SIMILARITY && !BRIEF_SKIP_NAMESPACE.test(m.namespace))
    .slice(0, 3)
  for (const m of strong) {
    add({ key: m.id, id: m.id, kind: 'brief', namespace: m.namespace, title: titleOf(m.content), text: m.content })
  }
  redraw($)
}

// Look and feel. Kemory's accent, and one stable color per namespace so the
// same namespace reads the same everywhere.
const ACCENT = '#a78bfa'
const CHIP_COLORS = ['#a78bfa', '#60a5fa', '#34d399', '#fbbf24', '#f472b6', '#22d3ee']
// The dashboard has no page for a single memory; its memories view filters
// by namespace, so a memory links to its namespace there.
const DASHBOARD = 'https://app.kemory.ai/memories'

function chipColor(namespace: string): string {
  let hash = 0
  for (const c of namespace) hash = (hash * 31 + c.charCodeAt(0)) >>> 0

  return CHIP_COLORS[hash % CHIP_COLORS.length] ?? ACCENT
}

function dashboardLink(namespace: string): string {
  return namespace ? `${DASHBOARD}?ns=${encodeURIComponent(namespace)}` : DASHBOARD
}

function verb(e: Entry): string {
  if (e.isDeleted) return 'Deleted'

  return { saved: 'Saved', updated: 'Updated', recalled: 'Recalled', brief: 'About this repo' }[e.kind]
}

// The session's activity as three rings (saved, recalled, rated), drawn
// where the surface takes SVG.
function activityRing(saved: number, recalled: number, rated: number): string {
  const ring = (r: number, value: number, color: string) => {
    const length = 2 * Math.PI * r
    const share = Math.min(1, value / Math.max(10, saved + recalled + rated))
    return (
      `<circle cx="36" cy="36" r="${r}" fill="none" stroke="${color}" stroke-opacity="0.18" stroke-width="6"/>` +
      `<circle cx="36" cy="36" r="${r}" fill="none" stroke="${color}" stroke-width="6" stroke-linecap="round" ` +
      `stroke-dasharray="${(share * length).toFixed(1)} ${length.toFixed(1)}" transform="rotate(-90 36 36)"/>`
    )
  }

  return (
    '<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 72 72">' +
    ring(30, saved, '#a78bfa') +
    ring(21, recalled, '#60a5fa') +
    ring(12, rated, '#34d399') +
    '</svg>'
  )
}

// One memory as a card: a header line that opens and closes it, and when
// open, its text as Markdown, its actions, and a link to it in Kemory.
// Elements are the drawing surface's own, passed in by the hook.
// biome-ignore lint/suspicious/noExplicitAny: the element table differs per surface
function memoryCard($: Engine, els: Record<string, any>, m: Entry, at: string) {
  const { Box, Button, Text, Markdown, Link } = els
  const isShown = isOpen.has(m.key) && !m.isDeleted

  return (
    <Box
      key={`box-${at}-${m.key}`}
      flexDirection="column"
      borderStyle="round"
      borderColor={m.isDeleted ? undefined : ACCENT}
      borderDimColor={m.isDeleted}
      paddingX={1}
      marginY={0}
    >
      <Box gap={1}>
        <Text color={ACCENT}>◆</Text>
        <Text dimColor>{verb(m)}</Text>
        <Box backgroundColor={chipColor(m.namespace)} paddingX={1}>
          <Text color="#111111">{m.namespace || 'kemory'}</Text>
        </Box>
        <Button
          key={`open-${at}-${m.key}`}
          plain
          dimColor={m.isDeleted}
          label={`${isOpen.has(m.key) ? '▾' : '▸'} ${m.title}`}
          onPress={() => toggle($, m.key)}
        />
      </Box>
      {isShown && <Markdown key={`md-${at}-${m.key}`} text={m.text.slice(0, 9000)} />}
      {isShown && (
        <Box gap={1}>
          {m.id && m.kind !== 'saved' && m.kind !== 'updated' && (
            <Button
              key={`up-${at}-${m.key}`}
              label={m.rating === 'up' ? '✓ Helpful' : 'Helpful'}
              onPress={() => rate($, m.key, 'up')}
            />
          )}
          {m.id && (
            <Button
              key={`down-${at}-${m.key}`}
              label={m.rating === 'down' ? '✓ Outdated' : 'Outdated'}
              onPress={() => rate($, m.key, 'down')}
            />
          )}
          {m.id && (
            <Button
              key={`del-${at}-${m.key}`}
              label={m.isConfirmingDelete ? 'Confirm delete' : 'Delete'}
              onPress={() => remove($, m.key)}
            />
          )}
          <Link key={`link-${at}-${m.key}`} href={dashboardLink(m.namespace)} label="Open in Kemory ↗" />
        </Box>
      )}
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    $.ui.status('…')
    void check($)
    $.clock.every(RECHECK_MS, () => void check($))
    void brief($)

    return result
  })

  // The plugin's own commands (commands/*.md), answered here where the module
  // runs; elsewhere their files run as prompts. Shipping them as files is what
  // lists them in the command picker, which runtime-registered commands miss.
  on('command.run', { command: 'kemory:memories' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Kemory' })

    return { text: 'Kemory panel opened.' }
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'kemory:remember' }, async ($, e) => {
    const text = e.args.trim() || (await lastReply($))
    if (!text) return { text: 'Nothing to save: no text given and no reply yet.' }

    return { text: (await save($, text)) ? `Saved to ${NAMESPACE}: ${titleOf(text)}` : 'Save failed.' }
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'kemory:learned' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Kemory' })
    await suggest($, true)

    return { text: 'Suggested memories are in the Kemory panel.' }
  }).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    idleTimer?.cancel()
    if (!hasPrompted) {
      hasPrompted = true
      redraw($)
    }

    return next(e)
  }).catch(($, e, next) => next(e))

  // After a quiet spell with enough new turns, propose memories unasked.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    turnsSinceSuggestion += 1
    idleTimer?.cancel()
    if (turnsSinceSuggestion >= MIN_TURNS_FOR_SUGGESTIONS) {
      idleTimer = $.clock.after(IDLE_MS, () => void suggest($, false))
    }

    return result
  })

  // A display must never cost the prompt or the tool call it watches: if a
  // hook below throws, its catch hands back what `next` settled to (replayed,
  // never run twice).
  on('classic.UserPromptSubmit', async ($, e, next) => {
    const result = await next(e)
    // A prompt ends the repo brief. Marked here as well as at prompt.submit,
    // which a session hosted by the desktop app was seen not to raise.
    hasPrompted = true
    inContext = []
    for (const context of result.additionalContext ?? []) {
      for (const [, namespace = '', content, id] of context.matchAll(INJECTED)) {
        if (!content || !id) continue
        inContext.push(add({ key: id, id, kind: 'recalled', namespace, title: titleOf(content), text: content }))
      }
    }
    redraw($)

    return result
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (result.deny !== undefined || result.isError) return result
    const input = e as Record<string, unknown>
    const text = result.text ?? ''

    if (STORE_TOOL.test(e.tool)) {
      const content = [input.content, input.name, input.trigger].find(v => typeof v === 'string') as string | undefined
      const entry = stored(text, content ?? '', e.tool_use_id, String(input.namespace ?? ''))
      byCall.set(e.tool_use_id, [add(entry)])
      $.ui.toast(saveNotice(entry), { timeoutMs: 6000 })
    } else if (RECALL_TOOL.test(e.tool)) {
      const keys = memoriesIn(text).map(m =>
        add({ key: m.id, id: m.id, kind: 'recalled', namespace: m.namespace, title: titleOf(m.content), text: m.content }),
      )
      byCall.set(e.tool_use_id, keys)
    }
    redraw($)

    return result
  }).catch(($, e, next) => next(e))

  // Above the prompt: the repo brief until the first prompt, then what each
  // prompt's recall put in context, as a row of namespace chips and titles.
  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (e.props.hasSurvey || isBandHidden) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const briefs = entries.filter(m => m.kind === 'brief')
    const shown = hasPrompted ? inContext.map(find).filter((x): x is Entry => !!x) : briefs
    if (shown.length === 0) return next(e)
    const noun = shown.length === 1 ? 'memory' : 'memories'
    const heading = hasPrompted ? `${shown.length} ${noun} in context` : `knows this about ${repoName}`
    const more = shown.length - BAND_ROWS

    return (
      <Box flexDirection="column" borderStyle="round" borderColor={ACCENT} paddingX={1}>
        <Box gap={1}>
          <Text color={ACCENT} bold>
            ◆ Kemory
          </Text>
          <Text dimColor>{heading}</Text>
          <Button key="band-open" label="Open" dimColor onPress={() => $.ui.open({ id: PANE, title: 'Kemory' })} />
          <Button
            key="band-hide"
            label="Hide"
            dimColor
            onPress={() => {
              isBandHidden = true
              $.ui.invalidate('ui.render')
            }}
          />
        </Box>
        {shown.slice(0, BAND_ROWS).map(m => (
          <Box key={`band-${m.key}`} gap={1}>
            <Box backgroundColor={chipColor(m.namespace)} paddingX={1}>
              <Text color="#111111">{m.namespace || 'kemory'}</Text>
            </Box>
            <Text wrap="truncate-end">{m.title}</Text>
          </Box>
        ))}
        {more > 0 && <Text dimColor>+{more} more in the panel</Text>}
      </Box>
    )
  })

  // A group of calls draws as one count line ("Used 2 tools"). Unfolded, each
  // call is its own row, and a Kemory call's row can draw as a card.
  on('ui.render', { component: 'ToolGroup' }, ($, e, next) => {
    const holdsKemory = e.props.calls.some(c => !!c.tool_use_id && byCall.has(c.tool_use_id))
    if (!holdsKemory || e.props.isExpanded) return next(e)

    return next({ ...e, props: { ...e.props, isExpanded: true } })
  })

  // The transcript row of a save or recall becomes one card per memory.
  on('ui.render', { component: 'ToolUse' }, ($, e, next) => {
    const keys = byCall.get(e.props.tool_use_id)
    if (!keys || keys.length === 0) return next(e)
    const els = $.ui.resolve(e)
    const { Box } = els
    const shown = keys.map(find).filter((x): x is Entry => !!x)

    return <Box flexDirection="column">{shown.map(m => memoryCard($, els, m, e.props.tool_use_id))}</Box>
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, ($, e) => {
    const els = $.ui.resolve(e)
    const { Box, Button, Text } = els
    const saved = count(['saved', 'updated'])
    const recalled = count(['recalled'])
    const rated = entries.filter(m => m.rating).length
    const open = suggestions.filter(s => s.state !== 'skipped')
    const svg = 'Svg' in els ? (els as unknown as { Svg: (p: Record<string, unknown>) => never }).Svg : undefined

    return (
      <Box flexDirection="column" gap={1}>
        <Box gap={2} alignItems="center" borderStyle="round" borderColor={ACCENT} paddingX={1}>
          {svg &&
            svg({
              key: 'ring',
              source: activityRing(saved, recalled, rated),
              alt: `This session: ${saved} saved, ${recalled} recalled, ${rated} rated`,
              width: 72,
              height: 72,
            })}
          <Box flexDirection="column">
            <Text color={ACCENT} bold>
              ◆ Kemory · this session
            </Text>
            <Text>
              <Text color="#a78bfa">● {saved} saved</Text>
              {'   '}
              <Text color="#60a5fa">● {recalled} recalled</Text>
              {'   '}
              <Text color="#34d399">● {rated} rated</Text>
            </Text>
            <Box gap={1}>
              <Button
                key="pane-learn"
                variant="primary"
                label={isSuggesting ? 'Thinking…' : 'What did we learn?'}
                onPress={() => suggest($, true)}
              />
              <Button key="pane-save-reply" label="Save last reply" onPress={() => saveLastReply($)} />
            </Box>
          </Box>
        </Box>
        {open.length > 0 && (
          <Box flexDirection="column" borderStyle="round" borderColor="#fbbf24" paddingX={1}>
            <Text color="#fbbf24" bold>
              ✦ Suggested memories
            </Text>
            {open.map(s => (
              <Box key={`sug-${s.key}`} flexDirection="column">
                <Text dimColor={s.state === 'saved'}>
                  {s.state === 'saved' ? '✓ ' : '· '}
                  {titleOf(s.text)}
                </Text>
                {s.state !== 'saved' && (
                  <Box gap={1}>
                    <Button
                      key={`sug-save-${s.key}`}
                      label={s.state === 'saving' ? 'Saving…' : 'Save'}
                      variant="primary"
                      onPress={() => saveSuggestion($, s.key)}
                    />
                    <Button key={`sug-skip-${s.key}`} label="Skip" onPress={() => skipSuggestion($, s.key)} />
                  </Box>
                )}
              </Box>
            ))}
          </Box>
        )}
        {entries.length === 0 && <Text dimColor>Nothing saved or recalled yet.</Text>}
        {[...entries].reverse().map(m => memoryCard($, els, m, 'pane'))}
      </Box>
    )
  })
}
