#!/usr/bin/env bash
# PreToolUse hook — auto-approve READ-ONLY Kemory tools so recall does not cost
# the user a permission prompt. Writes still ask, every time.
#
# The gate is an explicit allowlist of tool names, NOT a regex over the family.
# A regex would be wrong here: kemory_memory reads like a read and is in fact
# "Save one memory. Friendly alias of kemory_store_memory" (memory:write). The
# PostToolUse rate-reminder matcher already matches it by accident; reusing that
# pattern here would silently auto-approve memory writes.
#
# MUST stay synchronous: an async hook's stdout is discarded, so the permission
# decision would never be read and every recall would prompt again.
#
# Best-effort by design: anything not on the allowlist, and any failure, falls
# through to normal permission handling. This hook never denies.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || exit 0

# Read the payload here, not from sys.stdin: the heredoc below IS python3's
# stdin, so a script reading sys.stdin would parse itself.
HOOK_INPUT="$(cat)"
export HOOK_INPUT

python3 <<'PY' 2>/dev/null
import json, os, re

# Hosted Kemory exposes kemory_*; the community edition exposes the same tools
# as s9nmem_*. Server prefixes vary too (direct config, plugin-scoped, or the
# claude.ai connector), hence the permissive middle segment. Grok Build names
# an MCP tool <server>__<tool> with no mcp__ prefix (kemory__kemory_recall_memory).
TOOL_NAME = re.compile(r"^(?:mcp__.*__|[A-Za-z0-9-]+__)(?:kemory|s9nmem)_(.+)$")

# Read-only. Verified against the live tool descriptions rather than inferred
# from the names — see the kemory_memory note in the header.
READ_ONLY = {
    "recall",
    "recall_memory",
    "get_context",
    "ask",
    "find_similar",
    "get_compressed",
    "get_raw",
    "get_session_context",
    "get_namespace_summary",
    "get_profile",
    "get_user_context",
    "get_history",
    "list_namespaces",
    "list_projects",
    "list_skills",
    "whoami",
    "check_access",
    "rehydrate_session_sources",
}

# Not an allowlist gap — a decision, recorded so nobody "completes" the set:
#   memory, store_memory, store_skill, capture_session, consolidate_session,
#   delete_memory, forget, promote_memory, resolve_conflict — all writes.
#   rate_memory — a write whose rows feed scorecard_service._recall_usefulness,
#   an org-level indicator. An unattended agent
#   writer moving that number is a known failure mode, so a human stays in the
#   loop even though the write itself is harmless.

PASS = json.dumps({"continue": True, "suppressOutput": True})


def passthrough():
    print(PASS)
    raise SystemExit(0)


try:
    hook = json.loads(os.environ["HOOK_INPUT"])
    if not isinstance(hook, dict):
        raise ValueError
except Exception:
    passthrough()

match = TOOL_NAME.match(hook.get("tool_name") or "")
tool = match.group(1) if match else None
if not tool or tool not in READ_ONLY:
    passthrough()

query = (hook.get("tool_input") or {}).get("query")
message = (
    f"Kemory · recalling: {query}"
    if isinstance(query, str) and query.strip()
    else "Kemory · reading memory"
)

print(json.dumps({
    "systemMessage": message,
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": (
            f"kemory_{tool} is read-only; Kemory reads run without a prompt. "
            "Writes still ask."
        ),
    },
}))
PY
exit 0
