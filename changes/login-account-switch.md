### Fixed
- **Signing in as a different account no longer keeps the previous account's organisation or refresh token.** Hooks and MCP calls now act in the new account's own organisation; signing in again as the same account still keeps the organisation chosen with `kemory use`.
