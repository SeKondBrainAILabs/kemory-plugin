#!/usr/bin/env bash
# UserPromptSubmit hook — search Kemory with the prompt itself and inject the
# top matches, so recall happens on every substantive prompt instead of only
# when the agent remembers to spend a tool call on it.
#
# This is the difference between an instruction and a mechanism. Telling an
# agent "re-query when the topic shifts" relies on it noticing the shift; this
# hook does not.
#
# Default ON (it reads memory, like session-start.sh). Set KEMORY_PROMPT_RECALL=0
# to disable. The query is redacted before it leaves the machine.
#
# MUST stay synchronous: an async hook's stdout is discarded, which would make
# this silently inject nothing. The network call is capped instead.
#
# Best-effort by design: any failure emits nothing and exits 0.
set -uo pipefail
[ "${KEMORY_PROMPT_RECALL:-1}" = "1" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"
kemory_resolve_auth || exit 0

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export KEMORY_SCRIPT_DIR="$DIR"
# Importing redact.py must not litter the user's plugin directory.
export PYTHONDONTWRITEBYTECODE=1
export KEMORY_RECALL_LIMIT="${KEMORY_PROMPT_RECALL_LIMIT:-5}"
export KEMORY_RECALL_MIN_RELEVANCE="${KEMORY_PROMPT_RECALL_MIN_RELEVANCE:-0.55}"
export KEMORY_RECALL_SHORT_MIN_RELEVANCE="${KEMORY_PROMPT_RECALL_SHORT_MIN_RELEVANCE:-0.65}"
export KEMORY_RECALL_ITEM_CHARS="${KEMORY_PROMPT_RECALL_ITEM_CHARS:-600}"
export KEMORY_RECALL_TIMEOUT="${KEMORY_PROMPT_RECALL_TIMEOUT:-3}"
export KEMORY_RECALL_NAMESPACE="${KEMORY_PROMPT_RECALL_NAMESPACE:-}"

python3 "$DIR/prompt_recall.py" 2>/dev/null
exit 0
