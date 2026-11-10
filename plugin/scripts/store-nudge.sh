#!/usr/bin/env bash
# Stop hook — when a turn established something durable and nothing was stored,
# say so before the turn ends.
#
# This is the only mechanism in the plugin that makes a WRITE happen. Every
# other hook feeds the model and hopes; a standing instruction asks and hopes.
# Per the hooks reference, `hookSpecificOutput.additionalContext` on Stop
# "keeps the conversation going through the same loop protections as
# decision: block" but is shown as hook feedback rather than a hook error —
# which is what this is: guidance, not a failure.
#
# OPT-IN for its first release. A hook that continues a turn on a false
# positive is worse than one that stays quiet, so it ships off until the block
# rate has been measured on real sessions.
#
# Best-effort by design: any failure emits nothing and exits 0.
set -uo pipefail

[ "${KEMORY_STORE_NUDGE:-0}" = "1" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export KEMORY_SCRIPT_DIR="$DIR"
# Importing muse_log.py must not litter the user's plugin directory.
export PYTHONDONTWRITEBYTECODE=1
export KEMORY_NUDGE_SIGNALS="${KEMORY_STORE_NUDGE_SIGNALS:-}"

python3 "$DIR/store_nudge.py" 2>/dev/null
exit 0
