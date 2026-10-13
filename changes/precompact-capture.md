### Added
- **Session capture now flushes before `/compact`.** A `PreCompact` hook runs
  the same capture as `Stop` and `SessionEnd`, for a manual `/compact` and for
  auto-compact, so turns not yet stored are captured before the context is
  summarised away instead of waiting for the session to end. It sends the same
  bounded, redacted digest of your own turns, not your files or tool output,
  and `KEMORY_AUTO_CAPTURE=0` still turns it off. The hook runs in the
  background, prints nothing and always exits 0, so it can never block
  compaction.
- **The READMEs document the Kemory server's slash commands.**
  `/mcp__plugin_kemory_kemory__enhance <request>` returns your request with
  related memories cited by id, and `/mcp__plugin_kemory_kemory__save-session`
  captures a session's decisions and durable facts before `/compact` or at the
  end of a session. They appear when your Kemory server offers them; the
  bundled bridge already relays MCP prompt, resource and completion requests
  unchanged, and a test now holds it to that.
