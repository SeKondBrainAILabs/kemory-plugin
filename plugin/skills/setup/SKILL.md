---
name: kemory-setup
description: Get Kemory connected after installing the plugin, or diagnose it when the kemory_* tools are missing, the MCP server is unauthorised, or context injection is silent. Load when the user installs this plugin, asks how to set Kemory up, or reports that Kemory is not working.
---

# Connecting Kemory

Run `/kemory:status` first. It reports on both halves of the plugin and names
the specific failure; the steps below act on what it says.

## One variable turns on everything

The bundled MCP entry and the hooks resolve a credential the same way, in this
order: `KEMORY_API_KEY`, then `KEMORY_TOKEN`, then a stored browser login. Any
one of them turns on both halves, and the plugin can obtain the last one
itself:

```
/kemory:login
```

It prints one link, waits while the user approves it in their browser, and
writes `~/.kemory/credentials-<env>` — the same file the Kemory CLI writes, so
a CLI installed later finds them already signed in. Restart the client fully
afterwards; closing the window is not enough.

**`Unknown command: /kemory:login` means the plugin is installed but not loaded
yet**, not that the install failed — `/plugin install` prints "Run
/reload-plugins to apply" and the commands appear only after that.

Check which surface the user is on before answering, because two of the three
cannot do what the first one does:

- **Claude Code, terminal** — `/plugin` works; `/reload-plugins` after install.
- **Claude Code, Desktop app or IDE extension** — the plugin runs, but there is
  no `/plugin`. They install with `claude plugin install kemory@kemory` in a
  shell and restart the app fully; it reads the same `~/.claude/plugins`.
- **Claude Desktop, the chat app** — a different product with no plugin system
  and no hooks at all. Do not send them to `/plugin` or `/kemory:login`; they
  want `kemory mcp install --host claude-desktop` or the Kemory connector, and
  they get the memory tools without any of the hooks.

With none of them, the bundled server does not start and says why on stderr.
`/kemory:status` reports the same thing without reading logs.

Self-hosted or community edition: set `KEMORY_URL` to your API base, no
trailing slash and no path. Both the MCP entry and the hooks honour it.

## The other routes, and when they are the right one

`KEMORY_API_KEY` is the headless route — CI, a container, any machine with no
browser to approve a sign-in in. It is a long-lived secret, so prefer
`/kemory:login` anywhere a browser exists.

The Kemory CLI's `kemory login` does the same thing from a terminal and writes
the same file; either is enough for the bundled server. `kemory connect` is a
different job — it registers Kemory with *other* MCP hosts (Cursor, Warp,
Claude Desktop). Running it for Claude Code as well leaves two servers, so
**disable the bundled one** if you do. `/mcp` shows what is actually connected.

Getting the CLI is a separate step; the root README covers Homebrew and the
direct download.

## Why the tools can work while nothing else does

**A key inside an MCP config file authenticates the tools and is invisible to
the hooks.** They never read MCP config. That is the most common way to end up
with working `kemory_*` tools and no context injection. `/kemory:status`
detects it and says so — export the same key as `KEMORY_API_KEY` to fix it.

## Signed in is not the same as connected

A working sign-in proves the hooks work, nothing more. If `/kemory:status`
reports that the Kemory server has never seen the memory tools connect from
Claude Code, the setup is NOT done, however healthy the credential lines look:
the `kemory_*` tools are missing and the dashboard shows Claude Code as not
connected. Do not tell the user they are already set up. Have them open `/mcp`
and act on what the kemory entry says there.

## Confirm, and know what silence means

Re-run `/kemory:status`. From the next session, namespace summaries are
injected at start and recalls get rated.

Every hook is best-effort by design: no credential, an unreachable server, or a
malformed transcript all exit cleanly. Nothing breaks, but nothing happens
either — so a quiet session is a setup problem, not a healthy one.

Before enabling session capture (`KEMORY_AUTO_CAPTURE=1`), read the Privacy
Policy in the plugin README. It uploads your own turns.
