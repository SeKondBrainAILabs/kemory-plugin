# Privacy

The service is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/) and
its [sub-processor list](https://docs.sekondbrain.ai/subprocessors/). This
document covers the part that policy cannot: what *this plugin* transmits from
your machine, and when.

The plugin is a client. It sends data to one place — the Kemory instance you
point it at, hosted or your own via `KEMORY_URL`. It adds no telemetry, no
analytics and no third-party endpoint of its own.

## What each hook sends

| Hook | Event | What leaves your machine | Default |
|------|-------|--------------------------|---------|
| context injection | `SessionStart` | Your credential only; reads your namespace summaries back | on |
| prompt recall | `UserPromptSubmit` | **The text of your prompt**, as a search query | on |
| recall approval | `PreToolUse` | Nothing — runs entirely locally | on |
| rate reminder | `PostToolUse` | Nothing — runs entirely locally | on |
| store nudge | `Stop` | Nothing — reads the transcript on your machine and prints guidance | **off** |
| session capture | `Stop`, `SessionEnd` | Your own prompts: last 12 turns, 8000 characters max, redacted | on |

Prompt recall skips prompts under 12 characters and any prompt starting with
`/`, `!` or `#`, so slash commands are never sent. Separately, when a stored
OAuth token has expired the hooks refresh it against the identity provider
named in the CLI's own credential file.

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

`~/.kemory/.captured/` and `~/.kemory/.nudged/` hold per-session hashes used to
avoid storing or asking twice; `~/.kemory/.setup-hint` and
`~/.kemory/.paste-hint` hold timestamps that throttle one-off notices. None
contains conversation content. The plugin never writes credentials anywhere and
never logs them.

At session start the plugin also **reads** `~/.claude/CLAUDE.md` and a
`CLAUDE.md` in the current directory, looking only for a hand-pasted copy of
the Kemory instruction so it can tell you the plugin now ships one. The file
contents are never sent anywhere, never stored, and never edited.

## Contact

Privacy and data questions: **privacy@sekondbrain.ai**, the contact named in
the [published policy](https://docs.sekondbrain.ai/legal/privacy/).
Vulnerabilities go to **security@sekondbrain.ai** — see
[SECURITY.md](SECURITY.md).

