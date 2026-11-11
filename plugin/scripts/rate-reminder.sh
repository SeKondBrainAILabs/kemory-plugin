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
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input="$(cat)"

command -v python3 >/dev/null 2>&1 || exit 0

read -r recall_id count <<< "$(printf '%s' "$input" | python3 "$DIR/rate_reminder.py" 2>/dev/null || printf 'unknown 0')"

[ "${count:-0}" -gt 0 ] 2>/dev/null || exit 0

if [ "$count" -eq 1 ]; then noun="1 memory"; else noun="$count memories"; fi
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Reminder: you just recalled %s from Kemory. Before ending this turn, call kemory_rate_memory for each one you actually used in your response (up if it helped, down with a reason if not). Do not rate memories you merely skimmed. recall_id=%s"}}\n' \
  "$noun" "${recall_id:-unknown}"
exit 0
