# kemory-plus

Kemory inside Claude Code. Install it beside the `kemory` plugin, whose MCP
server and credential it uses:

```
/plugin install kemory-plus@kemory
```

| Piece | What it does |
|-------|--------------|
| `hooks/register.tsx` | A function-hooks module (Claude Code 2.1.267+; older builds and Grok ignore it). Draws the status line (`kemory ✓ · N recalled · N saved`, or what is broken), the memories in context above the prompt, a card on each save and recall in the transcript, and the `/kemory-plus:memories` panel with Helpful, Outdated, Delete and Open in Kemory. Suggests memories when a session goes quiet (`/kemory-plus:learned`), saves on request (`/kemory-plus:remember`), and keeps one set of Kemory tools in front when the claude.ai connector is live. |
| `scripts/recall-approve.sh` | `PreToolUse` on Kemory tools: auto-approves **read-only** tools so recall costs no permission prompt. Writes still ask, every time. |
| `scripts/lib.sh` | A copy of the kemory plugin's credential resolution, which the status check sources. `scripts/check.sh` fails if the two drift. |

It is a separate plugin because the plugin directory holds back versions whose
hooks approve tool calls or that ship a mod. Keeping both here lets `kemory`
itself reach users while this one is reviewed.
