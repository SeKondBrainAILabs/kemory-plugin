#!/usr/bin/env bash
# PostToolUse hook — after a Kemory recall, remind the agent to rate the
# memories it actually used, so retrieval quality improves instead of decaying.
#
# Fires only when the response is genuinely rateable: it carries a recall_id,
# or a non-empty result list. A recall that returned nothing, or a tool that
# is not a recall at all, produces no reminder — a reminder to rate zero
# memories is noise, and repeated noise trains the agent to ignore it.
#
# Best-effort by design: never blocks, never errors.
set -uo pipefail
input="$(cat)"

command -v python3 >/dev/null 2>&1 || exit 0

read -r recall_id count <<< "$(printf '%s' "$input" | python3 -c '
import json, os, re, sys

def out(rid, n):
    print(rid or "unknown", n)
    raise SystemExit(0)

def unwrap(r):
    """Normalise a tool_response into the recall payload dict.

    An MCP tool result arrives as a LIST of content blocks --
    [{"type":"text","text":"<json>"}] -- not as the payload itself. Older
    shapes (a bare dict, or a JSON string) are still accepted.
    """
    if isinstance(r, list):
        for block in r:
            if not isinstance(block, dict):
                continue
            txt = block.get("text")
            if isinstance(txt, str):
                try:
                    parsed = json.loads(txt)
                except Exception:
                    continue
                if isinstance(parsed, dict):
                    return parsed
        return None
    if isinstance(r, str):
        try:
            r = json.loads(r)
        except Exception:
            return None
    return r if isinstance(r, dict) else None

try:
    d = json.load(sys.stdin)
except Exception:
    out(None, 0)

# Muse has no hook matcher, so every PostToolUse reaches this script. Apply
# the PostToolUse matcher of hooks/hooks.json here, copied verbatim; a payload
# without a string tool_name cannot be shown to be a recall.
if os.environ.get("MUSE_PLUGIN_ROOT"):
    name = d.get("tool_name") if isinstance(d, dict) else None
    if not isinstance(name, str) or not re.match(
            r"(mcp__.*__|[A-Za-z0-9-]+__)kemory_(recall.*|ask|find_similar|get_.*)", name):
        out(None, 0)

r = unwrap(d.get("tool_response"))
if r is None:
    out(None, 0)

rid = (r.get("retrieval") or {}).get("recall_id")

count = None
for key in ("memories", "results", "items"):
    v = r.get(key)
    if isinstance(v, list):
        count = len(v)
        break
if count is None:
    for key in ("showing", "total", "count"):
        v = r.get(key)
        if isinstance(v, int):
            count = v
            break

if count == 0:
    out(rid, 0)
if count is None:
    out(rid, 1 if rid else 0)
out(rid, count)
' 2>/dev/null || printf 'unknown 0')"

[ "${count:-0}" -gt 0 ] 2>/dev/null || exit 0

if [ "$count" -eq 1 ]; then noun="1 memory"; else noun="$count memories"; fi
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Reminder: you just recalled %s from Kemory. Before ending this turn, call kemory_rate_memory for each one you actually used in your response (up if it helped, down with a reason if not). Do not rate memories you merely skimmed. recall_id=%s"}}\n' \
  "$noun" "${recall_id:-unknown}"
exit 0
