# Kemory for Cursor

Persistent, cross-session memory for the Cursor agent, powered by
[Kemory](https://kemory.sekondbrain.ai).

## What it adds

| Component | What it does | Needs |
|---|---|---|
| MCP server `kemory` | The `kemory_*` tools, served by the hosted Kemory API (`https://api.kemory.s9n.ai/mcp/v1`) | A Kemory account. Cursor signs in through the browser; nothing is stored in this plugin |
| Skill `kemory` | How to use memory well: recall before re-deriving, rate what you use, store durable facts | Nothing |
| Hooks | Load your namespace summaries when an agent session starts; capture the session on `stop`, `preCompact` and `sessionEnd` | The [Kemory CLI](https://github.com/SeKondBrainAILabs/kemory-cli) on `PATH`, signed in with `kemory login` |

The hooks run `kemory --env prod hook session-start --agent cursor` and
`kemory --env prod hook capture --agent cursor`, the same commands
`kemory connect --host cursor` installs. Without `kemory` on `PATH` they do
nothing and print nothing, and the MCP server and skill work on their own.

## Install

From the Cursor Marketplace: open **Customize**, search for Kemory, install.

To try it from this repository:

```bash
mkdir -p ~/.cursor/plugins/local
cp -R plugins/cursor ~/.cursor/plugins/local/kemory
```

Then run **Developer: Reload Window** and check **Customize** for the `kemory`
MCP server, skill and hooks. Copy the folder rather than symlinking it: Cursor
only follows symlinks that resolve inside `~/.cursor/plugins/local`.

## Use one Kemory integration per Cursor

Cursor loads every source of hooks and MCP servers side by side, so two
Kemory integrations give the agent every tool twice and capture each session
twice. Pick one:

- **This plugin**, or
- **`kemory connect --host cursor`**, which writes `~/.cursor/mcp.json` and
  `~/.cursor/hooks.json`. If you ran it before installing the plugin, remove
  the `kemory` server from `~/.cursor/mcp.json` and the `kemory ... hook`
  commands from `~/.cursor/hooks.json`.

Cursor also loads plugins installed in Claude Code. If the Claude Code
`kemory` plugin is installed on the same machine, Cursor already runs it.

## Known issues

- **Older Cursor CLI (`cursor-agent`) builds ignore plugin hooks.** Cursor
  confirmed the bug and reported it fixed on 2026-08-27
  ([forum thread](https://forum.cursor.com/t/cursor-cli-ignores-hooks-from-marketplace-plugin/163890)).
  On an older CLI you get the MCP server and skill but no context at session
  start and no capture: update the CLI, or use `kemory connect --host cursor`,
  whose hooks live in `~/.cursor/hooks.json`, which the CLI reads.
- **Sign-in does not start on its own yet.** The Kemory server lists its tools
  before you sign in, and Cursor only offers sign-in when a server refuses the
  connection. Until the server changes, the tools appear but each call answers
  "Authentication required".
- **Hooks need `bash`.** They run through `bash`, so on Windows they need Git
  Bash or WSL on `PATH`.
