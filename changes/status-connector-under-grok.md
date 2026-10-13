### Fixed
- **Grok Build: `/kemory:status` no longer talks about the claude.ai
  connector.** On a machine that also has Claude Code it reported a claude.ai
  Kemory connector and told you to check `/mcp`. That connector never runs in a
  Grok session and Grok has no `/mcp`, so the check is now skipped under Grok.
