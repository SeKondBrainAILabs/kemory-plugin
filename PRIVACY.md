# Privacy

The service is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/) and
its [sub-processor list](https://docs.sekondbrain.ai/subprocessors/). This
document covers the part that policy cannot: what *this plugin* transmits from
your machine, and when.

The plugin is a client. It sends data to the Kemory instance you point it at,
hosted or your own via `KEMORY_URL`, and, for sign-in and token refresh only,
to the identity provider that instance names. It sends no telemetry and no
analytics. Its update notice reads the marketplace copy already on your disk
and does not contact the network. These are all of its calls:

- **Hooks.** The `SessionStart`, `UserPromptSubmit` and `Stop`/`SessionEnd`
  hooks call your Kemory instance, as the table below shows.
- **Memory tools.** The bundled MCP server sends the arguments of every Kemory
  memory tool Claude calls to the same instance, for example the text of a
  memory being stored or a recall query.
- **`/kemory:status`.** Sends a health check and an authenticated request to
  the same instance.
- **`/kemory:login`.** Asks the instance's
  `/.well-known/oauth-authorization-server` which identity provider it uses,
  then runs the device sign-in and token requests against that provider.
- **Token refresh.** When a stored OAuth token has expired, the hooks send the
  refresh token to the identity provider named in the credential file.

## What each hook sends

| Hook | Event | What leaves your machine | Default |
|------|-------|--------------------------|---------|
| context injection | `SessionStart` | Your credential only; reads your namespace summaries back | on |
| prompt recall | `UserPromptSubmit` | **The text of your prompt**, as a search query | on |
| rate reminder | `PostToolUse` | Nothing — runs entirely locally | on |
| store nudge | `Stop` | Nothing — reads the transcript on your machine and prints guidance | **off** |
| session capture | `Stop`, `SessionEnd` | Your own prompts: last 12 turns, 8000 characters max, redacted, stored `user-private` in `user:sessions` | on |

The optional `kemory-panel` plugin is separate and is not covered by this
table. It calls Kemory through this plugin's server when you save, rate or
delete a memory, checks that your credential works against the Kemory API,
reads the latest version numbers from GitHub to tell you about updates, and
runs "Suggest memories" as a model call in your own Claude Code session.

Prompt recall skips prompts under 12 characters and any prompt starting with
`/`, `!` or `#`, so slash commands are never sent.

## kemory-panel

`kemory-panel` is a separate, optional plugin from its own repository,
<https://github.com/SeKondBrainAILabs/kemory-panel>. This document does not
cover it, and it makes calls of its own. Among them, at session start and
every 10 minutes it sends a GET, with no credential and no conversation
content, to
`https://raw.githubusercontent.com/SeKondBrainAILabs/kemory-plugin/main/plugin/.claude-plugin/plugin.json`
to read the latest version number, so GitHub sees your IP address. The kemory
plugin alone makes no such call.

## Turning transmission off

```bash
export KEMORY_PROMPT_RECALL=0   # stop sending prompt text
export KEMORY_AUTO_CAPTURE=0    # stop sending session digests
```

With no credential configured at all, every hook no-ops and nothing is sent.

## Storage, retention and deletion

What you send is stored as memories in your own vault, scoped to your
organisation and user. Encryption at rest is **opt-in per account** and off
until you enable it. Memories persist until you remove them — there is no
automatic expiry unless you set a TTL when storing.

Removal comes at two levels, and the difference matters:

- `kemory_delete_memory` and `kemory_forget` are **soft deletes**. The memory
  stops being active and stops coming back in recall, but the row remains.
- `DELETE /api/v1/user/memory-data` is **irreversible erasure**: every memory
  for your user in that organisation, everything derived from them (session
  summaries, session digests, the consolidated namespace summary), and your
  memory encryption key along with it. If your vault was encrypted, destroying
  that key makes any ciphertext surviving in a backup permanently
  unrecoverable; if it was never encrypted, this is an ordinary hard delete.
  The response tells you which of the two you got.

## Who else can see it

Memories default to `user-private` and are isolated per organisation; nothing
crosses to another organisation. You can widen a memory to `team` or
`org-public` yourself.

The hosted service builds the namespace summaries that context injection reads
by sending memory content to an LLM sub-processor — Groq, on the paths this
plugin uses. Embeddings are computed with a local model and do not leave the
service. On a self-hosted instance both are whatever you configured, and the
plugin itself adds no sub-processor. The
[sub-processor list](https://docs.sekondbrain.ai/subprocessors/) is the
authoritative record and covers the whole platform, not just this plugin.

One thing to be aware of: injected context becomes part of your Claude Code
conversation, so it reaches Anthropic on the same terms as anything else you
type there.

## Local files

None of these holds conversation content, except that the credential files
hold your sign-in tokens.

- `~/.kemory/.captured/` and `~/.kemory/.nudged/` hold per-session hashes, used
  to avoid storing or asking twice.
- `~/.kemory/.recalled/` holds, per session, 16-character fingerprints of the
  memories already injected, so the same memory is not injected twice.
- `~/.kemory/.setup-hint`, `~/.kemory/.paste-hint` and `~/.kemory/.version-hint`
  are empty files. Their modification time throttles a one-off notice.
- `~/.kemory/.capture-default` is an empty marker, so the capture notice is
  shown once.
- `~/.kemory/credentials-<env>` and `~/.kemory/credentials` are the credential
  files. `/kemory:login` writes `~/.kemory/credentials-<env>`. The hooks read
  one of the two, and rewrite the file they read when they refresh an expired
  OAuth token. The file holds an access token and a refresh token. It is
  replaced atomically with mode 0600. It is never logged, and never sent
  anywhere except in the refresh request to the identity provider named in the
  file.

At session start the plugin also **reads** `~/.claude/CLAUDE.md` and a
`CLAUDE.md` in the current directory, looking only for a hand-pasted copy of
the Kemory instruction so it can tell you the plugin now ships one. The file
contents are never sent anywhere, never stored, and never edited.

## Contact

Privacy and data questions: **privacy@sekondbrain.ai**, the contact named in
the [published policy](https://docs.sekondbrain.ai/legal/privacy/).
Vulnerabilities go to **security@sekondbrain.ai** — see
[SECURITY.md](SECURITY.md).

