# Contributing

Thanks for helping improve the Kemory plugin. By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Ground rules

- Open an issue before a large change so we can agree on the approach.
- Keep hooks **best-effort**: a hook must never block or fail a user's
  session. Exit `0` on every error path.
- Keep the plugin **no-op safe**: if no Kemory server is connected, or the
  user has no credentials, nothing should error. One deliberate exception:
  `scripts/mcp.sh` exits non-zero with a reason when it finds no credential.
  A silent no-op there produces an MCP server that looks connected and serves
  no tools, which hides a misconfiguration instead of reporting it. Under Grok
  Build it starts signed out instead: every tool is listed and each call names
  `/kemory:login`, so nothing is hidden and no restart is needed after signing
  in.
- Anything that sends data anywhere must be **opt-in and documented**. Two
  exceptions are on by default: session capture (`capture.sh`,
  `KEMORY_AUTO_CAPTURE=0` turns it off) and prompt recall (`prompt-recall.sh`,
  `KEMORY_PROMPT_RECALL=0` turns it off), because a memory plugin that
  remembers nothing unless you first find a flag is not doing its job. They
  must stay documented in the privacy section of `README.md` and in
  `plugin/README.md`.

## Before opening a PR

```bash
./scripts/check.sh
```

This validates every JSON manifest and shell script. CI runs the same script.

Describe a change for users in a changelog fragment, `changes/<topic>.md`,
not in `CHANGELOG.md`. [changes/README.md](changes/README.md) has the format
and the release steps.

## Testing hooks locally

Pipe a synthetic payload into the script the way the harness would:

```bash
echo '{"tool_response":{"retrieval":{"recall_id":"rc_test"}}}' \
  | plugin/scripts/rate-reminder.sh
```

## Scope

This repo holds client-side integrations only. Server behaviour, MCP tool
definitions, and the CLI live in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
