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

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export PYTHONDONTWRITEBYTECODE=1
export KEMORY_NUDGE_SIGNALS="${KEMORY_STORE_NUDGE_SIGNALS:-}"

python3 <<'PY' 2>/dev/null
import hashlib, json, os, re, sys

# Phrases that mark a turn as having settled something worth keeping. Kept
# deliberately narrow: every entry here is a phrase that states a conclusion,
# not one that merely discusses a topic. "we could use redis" is not a
# decision; "we'll use redis" is.
DEFAULT_SIGNALS = (
    r"\bwe(?:'ll| will| should)\b",
    r"\b(?:i|we) (?:prefer|decided|chose|settled on|went with)\b",
    r"\blet's (?:go with|use|keep|stick)\b",
    r"\bfrom now on\b",
    r"\bthe (?:decision|convention|rule) is\b",
    r"\b(?:turns out|root cause|the reason .* is)\b",
    r"\b(?:always|never) (?:use|do|run|commit|merge)\b",
    r"\bdon't (?:use|do|run|commit|merge)\b",
)

# Tools that constitute "it was already stored". A rating or a recall is not a
# store; classify by what the call DOES, never by whether the name reads like
# a write (kemory_memory is an alias of kemory_store_memory).
WRITE_TOOLS = (
    "kemory_store_memory", "kemory_memory", "kemory_store_skill",
    "kemory_capture_session", "kemory_consolidate_session",
)

NUDGE = (
    "This turn settled something durable and nothing was written to Kemory. "
    "If a preference, decision, or non-obvious fact came out of it, store it "
    "now with kemory_store_memory (or kemory_capture_session for several "
    "items the user has confirmed), say in one line what you stored and "
    "where, and then finish. If nothing here is worth keeping past this "
    "session, just finish."
)


def die():
    raise SystemExit(0)


try:
    hook = json.loads(os.environ["HOOK_INPUT"])
except Exception:
    die()

# A Stop hook that fires because of a Stop hook would nudge in a loop. Claude
# Code also caps consecutive continuations, but this is the cheap guard.
if hook.get("stop_hook_active"):
    die()

transcript = hook.get("transcript_path") or ""
if not transcript or not os.path.isfile(transcript):
    die()

try:
    events = []
    with open(transcript, errors="replace") as fh:
        for line in fh:
            try:
                events.append(json.loads(line))
            except Exception:
                continue
except Exception:
    die()

if not events:
    die()


def blocks(ev):
    content = (ev.get("message") or {}).get("content")
    return content if isinstance(content, list) else []


def text_of(ev):
    content = (ev.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    return " ".join(b.get("text", "") for b in blocks(ev)
                    if isinstance(b, dict) and b.get("type") == "text")


# Only this turn is in scope: everything after the last real user message.
start = 0
for i, ev in enumerate(events):
    if ev.get("type") != "user":
        continue
    t = text_of(ev).strip()
    # Harness-injected messages are not the user starting a turn.
    if t and not t.startswith(("<", "Caveat:")):
        start = i
turn = events[start:]
if not turn:
    die()

# Already stored? Then there is nothing to ask for.
for ev in turn:
    for b in blocks(ev):
        if not isinstance(b, dict) or b.get("type") != "tool_use":
            continue
        name = b.get("name") or ""
        if any(w in name for w in WRITE_TOOLS):
            die()

extra = [s for s in os.environ.get("KEMORY_NUDGE_SIGNALS", "").split("|") if s]
patterns = [re.compile(p, re.I) for p in DEFAULT_SIGNALS + tuple(extra)]

haystack = "\n".join(filter(None, (
    text_of(ev) for ev in turn if ev.get("type") in ("user", "assistant")
)))
# The Stop payload carries the last assistant message directly; a transcript
# whose final write has not landed yet would otherwise miss it.
last = hook.get("last_assistant_message")
if isinstance(last, str):
    haystack += "\n" + last
if not haystack.strip():
    die()
if not any(p.search(haystack) for p in patterns):
    die()

# One nudge per turn. Without this, declining to store re-fires the nudge on
# the next Stop for the same material, which is how a helpful hook becomes an
# uninstallable one.
session = (hook.get("session_id") or "nosession")[:64].replace("/", "_")
fingerprint = hashlib.sha256(haystack[-4000:].encode()).hexdigest()
state_dir = os.path.expanduser("~/.kemory/.nudged")
try:
    os.makedirs(state_dir, exist_ok=True)
    marker = os.path.join(state_dir, session)
    if os.path.isfile(marker) and open(marker).read().strip() == fingerprint:
        die()
    with open(marker, "w") as fh:
        fh.write(fingerprint)
except OSError:
    pass  # no state dir is not a reason to skip the nudge, only to repeat it

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": NUDGE,
}}))
PY
exit 0
