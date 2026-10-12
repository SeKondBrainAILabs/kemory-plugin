### Fixed
- **The plugin no longer calls every host "Claude Code".** `/kemory:login`,
  `/kemory:status` and the MCP server named Claude Code wherever they ran, so
  under Grok Build they reported on, and gave remedies for, a product that was
  not running. They now describe the host they are actually in.
- **"How to update the plugin" names a command you can run.** Under Grok Build
  that is `grok plugin update kemory`; it was `/plugin update kemory@kemory`,
  which Grok has no such command for.
- **The claude.ai connector check is skipped where there is no Claude.** With
  no `~/.claude.json` the status output said it could not read the file; it now
  says nothing, rather than reporting on a product you may not use.
