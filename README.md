# kemory-plugin

Persistent, cross-session memory for coding agents, powered by
[Kemory](https://kemory.sekondbrain.ai). Works with hosted Kemory and the
open-source [community edition](https://github.com/SeKondBrainAILabs/kemory-community).

One plugin, one tree, a manifest per host: `.claude-plugin/plugin.json` for
Claude Code, `.grok-plugin/plugin.json` for Grok Build and
`.muse-plugin/plugin.json` for Muse Code, all carrying the same version. It
installs and runs on all three today; the Grok Build catalog entry is in
review, so for now Grok installs it from this repository
([Grok Build](#grok-build)). Muse Code: [Muse Code](#muse-code).

An MCP server gives an agent memory *tools*. This plugin makes it actually use
them: relevant memories arrive under every prompt, a turn that settles
something durable does not end with it unwritten, recalls get rated so
retrieval improves instead of decaying, and nothing is sent that you did not
turn on.

## Features

- **Standing instruction** — ships with the plugin, so there is nothing to
  paste into `CLAUDE.md` and nothing to keep in sync per project
- **Prompt recall** — every prompt is searched against your vault and the
  matches arrive before the agent answers, without it deciding to look
- **Store nudge** — *opt-in.* When a turn reached a decision and stored
  nothing, the turn does not just end
- **Context injection** — your namespace summaries load at session start
- **Rate reminder** — the agent rates the memories it used, so retrieval keeps
  improving
- **Session capture** — *on by default, `KEMORY_AUTO_CAPTURE=0` to opt out.*
  A bounded, redacted digest of what the session was about, stored as the
  session goes, flushed before each `/compact` (manual or auto) and again at
  the end. It sends the text of your own turns, not your files or tool output
- **`/kemory:status`** — one command that says what is and is not working

## kemory and kemory-panel

This marketplace has two plugins. `kemory` is the memory itself. `kemory-panel`
is an optional add-on that shows that memory in Claude Code's interface.

| | `kemory` | `kemory-panel` |
|---|---|---|
| What it is | Memory: the MCP server, hooks and skills | Kemory in Claude Code's interface |
| What you get | The Kemory tools, prompt recall, session context, rate reminder, session capture, `/kemory:login`, `/kemory:status` | A status line that says whether Kemory works, the memories in context above the prompt, a card on each save and recall in the terminal, the `/kemory-panel:memories` panel (rate, delete, save the last reply, suggest memories), `/kemory-panel:remember`, `/kemory-panel:learned`, and auto-approval of read-only Kemory tools |
| Runs on | Claude Code, Grok Build and Muse Code | Claude Code 2.1.267 and later; older builds and Grok ignore it |
| Needs | A Kemory account | `kemory`, whose server and credential it uses |
| Source | This repository | [kemory-panel](https://github.com/SeKondBrainAILabs/kemory-panel) |

They are separate because the Claude plugin directory holds back plugins that
ship an interface module or a hook that approves tool calls. Both live in
`kemory-panel`, so `kemory` can be listed in the directory on its own. Without
`kemory-panel`, everything in the left column works the same, and read-only
Kemory tools ask for permission like any other tool.

The card Claude shows after a save or recall (the memory, its namespace, and
Undo or Forget) is neither plugin. The Kemory server attaches it to its save
and recall tools, so any app that supports MCP Apps, such as Claude desktop,
claude.ai or ChatGPT, shows it over any connection to Kemory, the claude.ai
connector included. kemory-panel draws its own card only in the Claude Code
terminal, which cannot show the server's.

## Install

In a Claude Code **terminal**:

```
/plugin marketplace add SeKondBrainAILabs/kemory-plugin
/plugin install kemory@kemory
/reload-plugins
```

`/reload-plugins` is not optional — `/plugin install` says so in its own output,
and until it runs the plugin's commands do not exist yet. Then:

```
/kemory:login
```

It prints one link. Open it, approve in the browser, and the credential is
written for you — nothing to install, nothing to paste. Restart Claude Code
fully, then run `/kemory:status`.

It signs you in the same way the Kemory CLI does and writes the same file, so
if you install the CLI later it finds you already signed in.

**Optional: `kemory-panel`**, for the interface described in
[kemory and kemory-panel](#kemory-and-kemory-panel). Install it after `kemory`:

```
/plugin install kemory-panel@kemory
```

<details>
<summary>Already reach Kemory another way?</summary>

| You have | Do this |
|----------|---------|
| The Kemory CLI, signed in with `kemory login` | Nothing at all — that is the same credential `/kemory:login` writes, and both halves read it. `kemory connect` is only needed for other MCP hosts. |
| The claude.ai Kemory connector | Tools already work; disable the bundled entry under `/mcp` so you are not running two. The hooks still need `export KEMORY_API_KEY="..."` — the connector's OAuth token lives inside Claude and a shell script cannot read it. |
| A self-hosted or community instance | `export KEMORY_URL=http://...` alongside `KEMORY_API_KEY`. One URL moves the whole plugin. |

CLI install and sign-in: [docs.sekondbrain.ai/kemory/cli](https://docs.sekondbrain.ai/kemory/cli/).
The hooks are `bash` scripts calling `curl` and `python3`; on Windows they need
Git Bash or WSL, which is untested.

</details>

### Grok Build

Once the xAI catalog entry is live, install Kemory from `/marketplace`. Until
then, install it from this repository in a terminal:

```
grok plugin install SeKondBrainAILabs/kemory-plugin
```

If `/kemory:login` is not offered afterwards, restart Grok: it does not always
pick up a new plugin's commands in a running session. Then sign in:

```
/kemory:login
```

Approve in the browser. There is no restart: under Grok the memory server
starts signed out, every `kemory_*` tool answers "run `/kemory:login`" until
you sign in, and the next call after signing in goes through.
`/kemory:status` confirms it, and if the tools are missing it says why.

Grok's MCP Servers tab cannot delete a server that a plugin provides. If the
Kemory server ends up disabled there, it is listed in `disabled_mcp_servers` in
`~/.grok/config.toml`, and `/kemory:status` reports it. Remove it from that
list and restart Grok to get the tools back. To remove Kemory altogether, run
`grok plugin uninstall kemory`.

### Muse Code

From the marketplace:

```
muse plugins marketplace add kemory https://github.com/SeKondBrainAILabs/kemory-plugin
muse plugins install kemory@kemory
muse plugins approve kemory
```

Or from a clone of this repository:

```
muse plugins install ./plugin --scope user
muse plugins approve kemory
```

Restart any running Muse session, then sign in with `/kemory:login` or, from a
terminal, `kemory login`.

Muse starts the hooks and the memory server with a cleared environment, so
`KEMORY_URL`, `KEMORY_API_KEY` and other `KEMORY_*` settings in your shell do
not reach them. Sign in with the credential file that `kemory login` writes;
a self-hosted instance is reached through the URL that file records.

### Which surface you are on

**Claude Code** and **Claude Desktop** are different products, and only one of
them has plugins at all. The one that trips people is the middle row: the
plugin works there, the command to manage it does not.

| Surface | Plugin (tools + hooks) | `/plugin` | How to install |
|---|---|---|---|
| Claude Code — terminal | yes | yes | `/plugin install kemory@kemory`, then `/reload-plugins` |
| Claude Code — Desktop app, IDE extensions | yes | **no** | `claude plugin marketplace add SeKondBrainAILabs/kemory-plugin && claude plugin install kemory@kemory` in a shell, then restart the app fully |
| Claude Desktop (the chat app) | **no plugins, no hooks** | — | `kemory mcp install --host claude-desktop`, or the Kemory connector |

The Desktop app and the IDE extensions read the same `~/.claude/plugins` as the
terminal, which is why installing from a shell is enough for them.

Claude Desktop is a different application with no plugin system: it takes MCP
servers through its own config, so you get the memory *tools* there and none of
the hooks. Claude Code on the web cannot install plugins either, and claude.ai
chat has no hooks — use the Kemory connector on both.

### Cursor

`plugins/cursor` is a separate Cursor plugin, listed in
`.cursor-plugin/marketplace.json`: the hosted MCP server with browser sign-in,
the `kemory` skill, and hooks that call the Kemory CLI's `kemory hook` to load
context and capture sessions. See [plugins/cursor/README.md](plugins/cursor/README.md),
including why it should not be combined with `kemory connect --host cursor`.

### Other tools

This plugin runs where a host loads plugin hooks: Claude Code, Grok Build and Muse Code.
Codex, Claude Desktop and other MCP clients do not load these hooks,
so they get Kemory's memory *tools* over MCP, without prompt recall, capture
or the in-app panel:

- **claude.ai, Claude Desktop, ChatGPT and other apps with connectors:** add
  the Kemory connector in that app's connector settings.
- **Continue, Warp:** `kemory mcp install --host continue` (or `warp`,
  `all`) writes the MCP entry for you.
- **Codex and other MCP clients:** add Kemory's MCP server to the client's own
  config by hand; `kemory mcp install --config <file>` writes it to a path you
  name.

## Staying current

Plugins do not update themselves; an install keeps the hook set from the day
you ran it.

```
/plugin update kemory@kemory
```

The desktop app has no `/plugin` command. There, run this in a terminal:

```
claude plugin update kemory@kemory
```

In Grok Build:

```
grok plugin update kemory
```

Restart the host afterwards to load the new hooks. `/kemory:status` prints
the version you are on, and [CHANGELOG.md](CHANGELOG.md) says what moved.

## How it works

| Hook | When | What it does | Leaves your machine | Default |
|------|------|--------------|---------------------|---------|
| context injection | `SessionStart` | Injects your namespace summaries; warns once if Kemory isn't set up | Your credential; reads summaries back | on |
| prompt recall | `UserPromptSubmit` | Searches your vault with the prompt you typed and injects what matches | **The text of your prompt** | on |
| rate reminder | `PostToolUse` | Prompts the agent to rate the memories it actually used | Nothing | on |
| consolidate reminder | `SessionStart` after compaction | Prompts the agent to store facts that would otherwise survive only as a summary | Nothing | on |
| store nudge | `Stop` | When the turn settled something durable and no Kemory write happened, asks for it before the turn ends | Nothing | **off** |
| session capture | `Stop`, `PreCompact`, `SessionEnd` | Stores a redacted digest of your own prompts: last 12 turns, 8000 characters. `PreCompact` flushes it before compaction; the hook runs in the background and never blocks `/compact` | Your prompts, redacted | on |

Auto-approval of read-only Kemory tools is in `kemory-panel`, not here.

If you pasted the instruction into `CLAUDE.md` before the plugin shipped one,
you can delete it — the plugin says so once a week until you do. Keeping both
is not harmful, but the pasted copy asks the agent to open each session with
`kemory_list_namespaces` and a recall, which the prompt-recall hook has already
done by then.

The instruction is injected on every session, including a brand-new vault and
a session whose context call failed. It is short on purpose: recall and the
write prompt are hooks now, so it says only what no hook can — what Kemory is,
and the standard for writing to it.

Plus a `kemory` skill on how to recall, rate, store and phrase memories so
semantic search finds them again, and a `kemory-setup` skill that walks the
agent through connecting Kemory when something is not working.

With no credential configured, every hook no-ops and nothing is sent.

## Slash commands from the Kemory server

The Kemory MCP server can offer MCP prompts, which Claude Code turns into slash
commands. The server comes bundled with this plugin, so Claude Code lists them
as `/plugin:kemory:kemory:<name> (MCP)`, and the typed form below also works.
They appear only when your Kemory server offers them.

- **`/mcp__plugin_kemory_kemory__enhance <request>`** returns your request with
  the related memories cited by id. When nothing matches, the request comes
  back unchanged.
- **`/mcp__plugin_kemory_kemory__save-session`**: run it before `/compact` or
  at the end of a session. It captures the decisions and durable facts from the
  session, then consolidates them.

## Privacy Policy

The plugin is a client. It sends data to one place — the Kemory instance you
point it at — and adds no telemetry, analytics or endpoint of its own. Prompt
recall skips prompts under 12 characters and anything starting with `/`, `!`
or `#`.

```bash
export KEMORY_PROMPT_RECALL=0   # stop sending prompt text
export KEMORY_AUTO_CAPTURE=0    # turn capture off (on by default)
export KEMORY_STORE_NUDGE=1     # turn the store nudge on (off by default)
```

The store nudge reads your transcript on this machine and sends nothing. It is
off by default anyway: a hook that continues a turn is disruptive when it is
wrong, so it ships off until the false-positive rate has been measured on real
sessions.

Storage, retention, deletion, sub-processors and who else can see a memory:
[PRIVACY.md](PRIVACY.md). The service itself is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/).

## Configuration

Every knob — recall limits and relevance floor, context depth and budget,
capture window and namespace, `KEMORY_URL`, `KEMORY_ENV` — is documented in
[plugin/README.md](plugin/README.md). [SECURITY.md](SECURITY.md) covers what
redaction does and does not guarantee.

## Development

```bash
./scripts/check.sh
```

Validates manifests, shell syntax, executable bits, plugin source paths, hook
script references, the version and content of the two manifests, the bundled
MCP entry, changelog fragments, leaked internal references, and the hook tests.
CI runs the same
script plus shellcheck. See [CONTRIBUTING.md](CONTRIBUTING.md).

```
plugin/
├── .claude-plugin/plugin.json
├── .grok-plugin/plugin.json
├── .muse-plugin/plugin.json
├── .mcp.json                     bundled MCP entry → scripts/mcp.sh
├── hooks/hooks.json
├── commands/login.md             /kemory:login
├── commands/status.md            /kemory:status
├── skills/                       kemory, setup
└── scripts/                      one script per hook, plus lib and redact
```

Everything here is the plugin itself — one tree, a manifest per host, rather
than a repository per host. Apache-2.0. The open-source server, MCP tools and
CLI are in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
