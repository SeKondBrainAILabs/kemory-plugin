### Notes
- Tests now hold every Kemory tool matcher to Grok Build's tool names
  (`kemory__kemory_*`, no `mcp__` prefix) as well as Claude Code's, so a new
  hook cannot silently skip Grok. The store nudge is tested with a Grok store
  call too.
