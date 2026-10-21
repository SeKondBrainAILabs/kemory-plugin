### Added
- **A Kemory plugin for Cursor, in `plugins/cursor`.** It brings the hosted Kemory MCP server, the `kemory` skill, and hooks that load context at session start and capture the session through the Kemory CLI. The hooks do nothing when the CLI is not installed. Do not combine it with `kemory connect --host cursor`, or Cursor gets every tool twice.
