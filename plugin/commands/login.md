---
description: Sign in to Kemory in the browser — no CLI to install, no API key to paste
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/login.sh)
---

Sign the user in to Kemory.

!`${CLAUDE_PLUGIN_ROOT}/scripts/login.sh`

If the sign-in output is not shown above — some hosts, Grok Build among them,
do not run that line — start `${CLAUDE_PLUGIN_ROOT}/scripts/login.sh` yourself
as a background task, straight away. It prints a sign-in link and then waits
for approval. Do not read or search any files first.

Give the user the URL from the output as soon as it appears and ask them to
open it and approve. The command waits for that and then writes the credential
itself, so there is nothing for them to copy back.

When it succeeds, say who they signed in as, and pass on what the output says
about restarting. When it fails, give the one line it printed
— it names the remedy — and do not suggest exporting `KEMORY_API_KEY` unless
the failure was a missing browser or a headless environment.
