---
description: Sign in to Kemory in the browser — no CLI to install, no API key to paste
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/login.sh)
---

Sign the user in to Kemory.

!`${CLAUDE_PLUGIN_ROOT}/scripts/login.sh`

Give the user the URL from the output and ask them to open it and approve. The
command waits for that and then writes the credential itself, so there is
nothing for them to copy back.

When it succeeds, say who they signed in as and that the session needs a full
restart to pick the credential up. When it fails, give the one line it printed
— it names the remedy — and do not suggest exporting `KEMORY_API_KEY` unless
the failure was a missing browser or a headless environment.
