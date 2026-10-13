### Added
- **Grok Build: the plugin now says when Grok has switched its MCP server off.**
  A server listed in `disabled_mcp_servers` in `~/.grok/config.toml` is never
  launched, and Grok's MCP Servers tab offers disabling as the only action on
  a plugin's server. Until now nothing said so: the hooks kept working and the
  `kemory_*` tools were simply missing. `/kemory:status` now reports it every
  time, without a "will start" tick, and a new Grok session tells the agent
  once a day. The setting is read, never changed.
