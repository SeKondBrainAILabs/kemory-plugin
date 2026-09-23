# Kemory plugin

Hooks and a skill that make Claude Code use Kemory memory well.

## What it does

| Hook | Event | Behaviour |
|------|-------|-----------|
| `session-start.sh` | `SessionStart` | Injects your Kemory namespace summaries so the session starts informed, and warns once if Kemory isn't configured yet |
| `prompt-recall.sh` | `UserPromptSubmit` | Searches Kemory with your prompt and injects the top matches, so recall happens on every substantive prompt instead of only when the agent thinks to spend a tool call |
| `recall-approve.sh` | `PreToolUse` on Kemory tools | Auto-approves **read-only** tools so recall costs no permission prompt. Writes still ask, every time |
| `rate-reminder.sh` | `PostToolUse` on any Kemory recall tool | Reminds the agent to rate memories it actually used, so recall quality improves over time. Fires only when the response is rateable — it carries a `recall_id` or a non-empty result list |
| `session-start.sh` | `SessionStart` with `source=compact` | Reminds the agent to consolidate what the pre-compaction context held. Deliberately not `PreCompact`: that event rejects `additionalContext`, and fires as compaction begins so the model gets no turn to act |
| `capture.sh` | `Stop`, `SessionEnd` | **On by default** (`KEMORY_AUTO_CAPTURE=0` opts out). Stores new turns as redacted episodic memories as the session goes, so a killed session still leaves its work behind |

Plus:

- **`/kemory:status`** — reports whether credentials resolve, whether the API
  accepts them, whether the CLI is on PATH, and how capture and context
  injection are configured. Run this first when something looks wrong.
- a **`kemory` skill** covering how to recall, rate, store, and phrase
  memories so semantic search can find them again.

## Install

See the [root README](../README.md#install) for the install commands.

## Connecting Kemory

The bundled MCP entry launches `scripts/mcp.sh`, which resolves a credential
at startup through the same `lib.sh` function the hooks use, then serves:
`kemory mcp serve` when the credential came from `kemory login`, and a bundled
stdio-to-HTTP bridge when it came from the environment. So one entry covers
every way of reaching Kemory, and the tools cannot end up authenticated
differently from the hooks or pointed at a different host.

With no credential it exits with that reason on stderr rather than starting.
A server that starts and exposes nothing reads as connected in `/mcp` while
every memory tool is missing, which is worse than a visible failure.

`KEMORY_URL` still repoints the whole plugin — the bridge takes its host from
the same resolution.

If you get the tools another way — the claude.ai connector, `kemory connect`,
or your own entry — disable the bundled server so you do not run two. Two
servers means two copies of every tool in each request; `/kemory:status`
counts the entries it can see on disk.

If no Kemory server is connected, every hook no-ops rather than erroring.

### Two credentials, not one

The MCP tools and the hooks authenticate **separately**, which is the single
most common source of confusion:

| You have | Tools | Hooks |
|----------|-------|-------|
| `KEMORY_API_KEY` in your environment | yes | yes |
| `kemory login` (CLI), nothing exported | yes | yes |
| Connector or remote MCP, nothing else | yes | **no** |
| A key inside an MCP config file | yes | **no** — the hooks never read MCP config |

That last row is worth stating twice: a key in `.mcp.json` or `~/.claude.json`
authenticates the *tools* and is invisible to the *hooks*. `/kemory:status`
detects that case and tells you; export the same key as `KEMORY_API_KEY` to
turn the hooks on.

Stored OAuth tokens are refreshed automatically when they expire. If a refresh
fails, `/kemory:status` says so rather than leaving the hooks quietly rejected.

### Platform support

The CLI ships for macOS and Linux (arm64, x64) and Windows x64. The hooks are
narrower: `bash` scripts calling `curl` and `python3`, so on Windows they need
Git Bash or WSL. Untested there, so Windows is not claimed for the hooks even
though the CLI runs on it.

## Session context injection

On every session start the plugin fetches your namespace summaries and injects
them, so the agent begins knowing your preferences and project context instead
of starting blind.

| Variable | Default | Meaning |
|----------|---------|---------|
| `KEMORY_CONTEXT` | `1` | Set to `0` to disable injection |
| `KEMORY_CONTEXT_DEPTH` | `l3` | Summary depth requested (`l3`, `l4`) |
| `KEMORY_CONTEXT_MAX_CHARS` | `4000` | Context budget; summaries beyond it are dropped with a note (floor 500) |
| `KEMORY_CONTEXT_NAMESPACES` | all | Comma-separated allowlist, e.g. `user:preferences,shared` |
| `KEMORY_CONTEXT_TIMEOUT` | `6` | Seconds to wait for the API |
| `KEMORY_QUIET_SETUP` | `0` | Set to `1` to suppress the "not configured yet" notice |

If Kemory is not configured, the hook prints one short setup notice and then
stays quiet for 24 hours rather than nagging every session.

## Prompt recall

On every substantive prompt the plugin searches your memories with the prompt
itself and injects the top matches. This is the difference between an
instruction and a mechanism: telling an agent to "recall when the topic shifts"
relies on it noticing the shift.

The query is redacted before it leaves your machine, using the same rules as
capture. Prompts under 12 characters and those starting with `/`, `!` or `#`
are skipped. A memory injected once is not injected again in the same session.

| Variable | Default | Meaning |
|----------|---------|---------|
| `KEMORY_PROMPT_RECALL` | `1` | Set to `0` to disable prompt recall |
| `KEMORY_PROMPT_RECALL_LIMIT` | `5` | Maximum memories injected per prompt |
| `KEMORY_PROMPT_RECALL_MIN_RELEVANCE` | `0.55` | Raw-cosine relevance floor (not the blended `min_score`) |
| `KEMORY_PROMPT_RECALL_ITEM_CHARS` | `600` | Per-memory truncation in the injected block |
| `KEMORY_PROMPT_RECALL_NAMESPACE` | all | Restrict recall to one namespace |
| `KEMORY_PROMPT_RECALL_TIMEOUT` | `3` | Seconds to wait for the API |

Because this path uses `POST /api/v1/memories/search`, which returns memory ids
rather than an invocation id, hook-injected memories carry no `recall_id`. The
agent is told to rate them by `memory_id`; they will not appear in recall
*coverage* metrics, which join on recall ids.

## Automatic session capture (on by default)

Capture runs unless you turn it off. It uploads a bounded, redacted digest of
your own prompts to the kemory instance you configured — a memory plugin that
remembers nothing until you find a flag is not doing its job. Digests land in
`user:sessions` as `user-private`, so turning capture on does not put your
sessions in front of your team; `KEMORY_CAPTURE_NAMESPACE` and
`KEMORY_CAPTURE_VISIBILITY` move them if that is what you want. To opt out:

```bash
export KEMORY_AUTO_CAPTURE=0
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `KEMORY_STORE_NUDGE` | `0` | Set to `1` to ask for a write when a turn settled something and stored nothing |
| `KEMORY_STORE_NUDGE_SIGNALS` | — | Extra `\|`-separated regexes that mark a turn as worth storing, added to the built-in set |
| `KEMORY_AUTO_CAPTURE` | `1` | Set to `0` to disable capture |
| `KEMORY_CAPTURE_NAMESPACE` | `user:sessions` | Namespace to write digests to |
| `KEMORY_CAPTURE_VISIBILITY` | `user-private` | Visibility of stored digests: `user-private`, `agent-private`, `team`, `org-public` |
| `KEMORY_CAPTURE_MAX_TURNS` | `12` | Maximum user turns in a single stored memory |
| `KEMORY_CAPTURE_MIN_NEW_TURNS` | `3` | New turns required before a mid-session `Stop` stores anything; `SessionEnd` flushes any remainder |
| `KEMORY_CAPTURE_SOURCE` | `claude-code` | Value recorded in the memory's `metadata.source` |
| `KEMORY_ENV` | `prod` | Which credentials file to read |
| `KEMORY_URL` | `https://api.kemory.s9n.ai` | Override only for a self-hosted or community instance |
| `KEMORY_TOKEN` | — | Bearer token, sent as `Authorization: Bearer` |
| `KEMORY_API_KEY` | — | API key from kemory.sekondbrain.ai, sent as `X-API-Key` |

All hooks that reach the API share one credential resolver
(`scripts/lib.sh`): the CLI's `~/.kemory/credentials` if present, otherwise
`KEMORY_API_KEY` or `KEMORY_TOKEN`, against `KEMORY_URL` (defaulting to
hosted Kemory). `kemory login` is the recommended route — OAuth browser
sign-in, nothing to paste, and it writes the credentials the hooks read. The
API accepts either credential style. With none of those, every hook stays
silent.

What is captured: your own turns only (assistant replies and tool output are
skipped), capped at the last N turns and 8000 characters, with common secret
patterns redacted. Digests are written to `POST /api/v1/memories` tagged
`session-capture` and carry the `session_id` so the server-side Reflector can
consolidate them into semantic summaries.

`SessionEnd` fires on exit, `/clear`, and resume, so the same turns can be
offered more than once. The hook stores a hash of each digest under
`~/.kemory/.captured/<session_id>` and skips a write whose content it has
already stored, so repeats do not accumulate duplicate memories. The hash is
recorded only after the write succeeds.

Redaction is pattern-based, so treat it as a safety net rather than a
guarantee. If you work with sensitive material, leave capture off.

Every hook is best-effort: missing credentials, an unreachable server, or a
malformed transcript all exit cleanly and never block a session.

## Privacy Policy

Everything this plugin sends goes to the Kemory instance you configured and
nowhere else — no telemetry, no analytics, no third party. Two hooks transmit
anything at all: **prompt recall**, which sends the text of your prompt as a
search query, and **session capture**, which sends a redacted digest of your
own turns. Both are on by default, and both are switched off with
`KEMORY_PROMPT_RECALL=0` and `KEMORY_AUTO_CAPTURE=0`. Context injection sends
only your credential; the recall-approval and rate-reminder hooks make no
network calls at all.

Stored content lives in your own vault, scoped to your organisation and user,
and persists until you delete it — note that the `kemory_delete_memory` and
`kemory_forget` tools are soft deletes, and `DELETE /api/v1/user/memory-data`
is the irreversible one. Encryption at rest is opt-in per account.
The hosted service sends memory content to a third-party model provider to
build the summaries context injection reads; a self-hosted instance uses
whatever you configured. Full policy — retention, deletion, who can see what,
local files — in the
[repository README](https://github.com/SeKondBrainAILabs/kemory-plugin#privacy-policy).
The service itself is governed by the
[SeKondBrain Privacy Policy](https://docs.sekondbrain.ai/legal/privacy/).
Privacy questions: **privacy@sekondbrain.ai**.
