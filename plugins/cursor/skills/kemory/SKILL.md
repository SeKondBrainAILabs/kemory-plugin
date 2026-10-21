---
name: kemory
description: How to use Kemory persistent memory well in Cursor - recall before re-deriving, rate what you use, store durable facts as they happen, and write memories so semantic search can find them again. Load when working with kemory_* tools, when the user asks about their memory vault, or when the Kemory tools are missing.
---

# Using Kemory well

You have persistent, cross-session memory via the `kemory_*` tools of the
`kemory` MCP server.

**If the tools are missing**, the server is not signed in. Tell the user to
open Cursor Settings → MCP, find `kemory`, and click its login button: a
browser window signs them in to Kemory. There is no API key to paste.

**Recall before re-deriving.** At the start of a task, call
`kemory_get_context` or `kemory_recall_memory` with the task topic to pull
prior decisions, runbooks, and solved problems. Re-query when the topic
shifts. An empty result is not evidence of absence — retrieval matches the
wording a memory was stored in, so retry with different phrasing
(identifiers, product names, error strings) before concluding it is missing.

If the conversation already opens with "Your Kemory memory" namespace
summaries, the session-start hook loaded them. That is a summary, not a
recall: still recall on the task topic before answering from it.

**Rate what you actually use.** When a recalled memory shapes your answer,
call `kemory_rate_memory` with `rating: "up"` and that response's
`retrieval.recall_id`, immediately — not batched at the end. When a returned
memory was irrelevant, wrong, or superseded, rate it `"down"` with a reason
(`irrelevant` / `outdated` / `duplicate` / `other`). Do not rate memories you
only skimmed; rating everything makes the signal meaningless.

**Store durable facts as they happen**, without waiting to be asked:
a stated preference, a project fact or technical decision, a solved problem
or gotcha-plus-fix; and a reusable procedure via `kemory_store_skill`. Put
personal preferences in a user-scoped namespace and project knowledge in a
team-visible one — call `kemory_list_namespaces` and reuse an existing
namespace rather than inventing a near-duplicate. Check `kemory_find_similar`
first and supersede rather than duplicate. Never store secrets, tokens, or
credentials. Say briefly what you stored and why.

**Write so it can be found again.** Open with the question a future session
would ask, in plain words, then keep identifiers, error strings, and env
vars in the body.

- Good: "Why does extraction skip on staging? SERVICE_URL is set but the S2S
  token is missing — it skips instead of falling back."
- Bad: "SERVICE_URL + missing token -> skip" (jargon only).
- Bad: "fixed the extraction bug" (prose only).

**When work concludes**, call `kemory_consolidate_session` to fold what was
established into durable memory. Do this even when the session-capture hook
is installed: capture keeps a digest of the conversation, consolidation
decides what is worth remembering.
