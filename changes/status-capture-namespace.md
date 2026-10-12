### Fixed
- **`/kemory:status` names the right capture namespace.** It reported `shared`; capture writes to `user:sessions` unless `KEMORY_CAPTURE_NAMESPACE` says otherwise, and the plugin docs now list `KEMORY_ALLOW_DUPLICATE`, `KEMORY_MCP_TIMEOUT` and `KEMORY_CLIENT_ID`.
