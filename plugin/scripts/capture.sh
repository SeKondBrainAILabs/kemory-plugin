#!/usr/bin/env bash
# Stop + SessionEnd hook — capture the session into Kemory as episodic memories
# tagged with session_id, so the server-side Reflector can consolidate them into
# a semantic summary later.
#
# Runs on Stop (after each assistant response) so a session that is killed,
# crashes, or is never cleanly ended still leaves its work behind. SessionEnd
# then flushes whatever is left.
#
# Only NEW turns are posted. Kemory's community edition has no idempotency
# support, so a client-side high-water mark is the only thing preventing the
# same turns being stored over and over as overlapping memories.
#
# ON BY DEFAULT, OPT-OUT. Capture uploads conversation content to your Kemory
# instance. A memory plugin that remembers nothing unless you first find a flag
# is not doing its job, so this runs unless you set KEMORY_AUTO_CAPTURE=0.
#
# Best-effort by design: any failure exits 0 so a session is never blocked.
set -uo pipefail

[ "${KEMORY_AUTO_CAPTURE:-1}" = "1" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"
# Resolves hosted (bearer) or community (X-API-Key) auth, from the CLI's
# credential file or from environment variables.
kemory_resolve_auth || exit 0

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export KEMORY_SCRIPT_DIR="$DIR"
# Importing redact.py must not litter the user's plugin directory.
export PYTHONDONTWRITEBYTECODE=1
# Session digests are the most incidentally-revealing thing this plugin
# handles — half-formed debugging, client names, things typed before thinking.
# Now that capture is on by default they land somewhere private by default too,
# not in `shared`, whose name reads as team-visible to every engineer who sees
# it. Set KEMORY_CAPTURE_NAMESPACE to put them somewhere else deliberately.
export KEMORY_NAMESPACE="${KEMORY_CAPTURE_NAMESPACE:-user:sessions}"
export KEMORY_MAX_TURNS="${KEMORY_CAPTURE_MAX_TURNS:-12}"
export KEMORY_MIN_NEW_TURNS="${KEMORY_CAPTURE_MIN_NEW_TURNS:-3}"
export KEMORY_CAPTURE_SOURCE="${KEMORY_CAPTURE_SOURCE:-claude-code}"

python3 <<'PY' 2>/dev/null
import hashlib, json, os, sys, urllib.request

sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
from redact import redact  # noqa: E402

MAX_CHARS = 8000


def die():
    raise SystemExit(0)


def env_int(name, default):
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return default


try:
    url = os.environ["KEMORY_BASE_URL"]
    auth_name, _, auth_value = os.environ["KEMORY_AUTH_HEADER"].partition(": ")
    hook = json.loads(os.environ["HOOK_INPUT"])
except Exception:
    die()
if not url or not auth_value:
    die()
if not url.startswith(("http://", "https://")):
    die()  # never send a credential to a non-HTTP scheme

# A Stop hook that runs because of a Stop hook would capture in a loop.
if hook.get("stop_hook_active"):
    die()

session_id = hook.get("session_id") or ""
reason = hook.get("reason") or "unknown"
event = hook.get("hook_event_name") or ""
transcript = hook.get("transcript_path") or ""
if not transcript or not os.path.isfile(transcript):
    die()

# SessionEnd is the last chance to store anything, so it flushes whatever is
# pending. Stop fires after every assistant response and waits for enough new
# material to be worth a memory.
flushing = event != "Stop"

# Only the user's own turns: they carry intent and goals, and skipping
# assistant output keeps the digest small and avoids re-storing tool dumps.
turns = []
try:
    with open(transcript, errors="replace") as fh:
        for line in fh:
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if ev.get("type") != "user":
                continue
            content = (ev.get("message") or {}).get("content")
            if isinstance(content, list):
                content = " ".join(
                    p.get("text", "") for p in content if isinstance(p, dict)
                )
            if isinstance(content, str):
                t = content.strip()
                # Skip harness-injected noise, not real user intent.
                if t and not t.startswith(("<", "Caveat:")):
                    turns.append(t)
except Exception:
    die()

if not turns:
    die()

# High-water mark of turns already stored for this session. Without it, the
# sliding window below produces a different digest every turn and every Stop
# would store a near-duplicate of the last one.
marker, state = None, {"digest": "", "captured_turns": 0}
state_dir = os.path.expanduser("~/.kemory/.captured")
try:
    os.makedirs(state_dir, exist_ok=True)
    marker = os.path.join(state_dir, (session_id or "nosession")[:64].replace("/", "_"))
    if os.path.isfile(marker):
        raw = open(marker).read().strip()
        try:
            loaded = json.loads(raw)
            if isinstance(loaded, dict):
                state = {
                    "digest": str(loaded.get("digest") or ""),
                    "captured_turns": max(0, int(loaded.get("captured_turns") or 0)),
                }
        except Exception:
            # Pre-0.2.0 markers were a bare sha256 of the whole digest.
            state = {"digest": raw, "captured_turns": 0}
except OSError:
    marker = None

already = state["captured_turns"]
new_turns = turns[already:]
if not new_turns:
    die()
if not flushing and len(new_turns) < env_int("KEMORY_MIN_NEW_TURNS", 3):
    die()

# Bound the payload. If a burst exceeded the cap we deliberately drop the
# oldest of the new turns and still advance the mark past them, rather than
# storing the same window twice.
posted = new_turns[-env_int("KEMORY_MAX_TURNS", 12):]

body = redact("\n".join(f"- {t}" for t in posted))[:MAX_CHARS]
window = (
    f"turns {already + len(new_turns) - len(posted) + 1}"
    f"-{already + len(new_turns)}"
)
content = (
    "What was this coding session about? Session digest captured automatically "
    f"({'at session end' if flushing else 'mid-session'}, user turns only, "
    f"secrets redacted, {window}).\n\ncwd: "
    f"{hook.get('cwd', 'unknown')}\n\n{body}"
)

digest = hashlib.sha256(content.encode()).hexdigest()
if digest == state["digest"]:
    die()  # identical digest already stored for this session

req = urllib.request.Request(
    url + "/api/v1/memories",
    data=json.dumps({
        "namespace": os.environ["KEMORY_NAMESPACE"],
        "namespace_tag": "session-capture",
        # Stated, not inherited. The server has its own default and it is not
        # this plugin's to assume — least of all for a hook that now runs for
        # everyone. Override deliberately with KEMORY_CAPTURE_VISIBILITY.
        "visibility": os.environ.get("KEMORY_CAPTURE_VISIBILITY", "user-private"),
        "content": content,
        "content_type": "text",
        "session_id": session_id,
        "metadata": {
            "source": os.environ.get("KEMORY_CAPTURE_SOURCE", "claude-code"),
            "capture": "auto",
            "capture_kind": "flush" if flushing else "incremental",
            "turns": len(posted),
            "end_reason": reason,
        },
    }).encode(),
    headers={
        auth_name: auth_value,
        "Content-Type": "application/json",
    },
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=8).read()
except Exception:
    raise SystemExit(0)  # never advance the mark past turns we did not store
if marker:
    try:
        with open(marker, "w") as fh:
            json.dump({"digest": digest, "captured_turns": len(turns)}, fh)
    except OSError:
        pass
PY
exit 0
