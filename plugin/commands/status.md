---
description: Check whether Kemory is actually working — credentials, API reachability, capture and context-injection settings
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" *)
---

Run the Kemory status check and report the result to the user.

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh"`

Summarise what is working and what is not. If anything failed, give the single
most useful next step — do not list every possible fix. Common cases:

- **No credentials** — run `kemory login`, or set `KEMORY_URL` together with
  `KEMORY_TOKEN` (hosted) or `KEMORY_API_KEY` (community edition).
- **HTTP 401/403** — the endpoint is right but the key is wrong or expired;
  re-run `kemory login` or reissue the key.
- **API unreachable** — check `KEMORY_URL`, and for a local stack confirm the
  containers are up (`docker compose ps`).

If everything passed, say so in one line and mention that `/mcp` shows which
Kemory server Claude is actually connected to.
