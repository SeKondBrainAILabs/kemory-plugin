import hashlib
import json
import os
import sys
import time
import urllib.request

try:
    import fcntl
except ImportError:  # native Windows Python: capture runs unlocked
    fcntl = None

sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
from redact import redact  # noqa: E402
from muse_log import muse_session_log  # noqa: E402
import transcript as tlog  # noqa: E402
from hook_request import env_int, request_setup  # noqa: E402

MAX_CHARS = 8000
# The host kills capture at 15 s and this program was allowed 8 s for its POST
# before locking existed. Lock wait plus POST must not pass that 8 s, so a run
# that waited shortens its POST timeout by the time it waited.
POST_TIMEOUT_SECONDS = 8
LOCK_WAIT_SECONDS = 5
LOCK_POLL_SECONDS = 0.1


def die():
    raise SystemExit(0)


url, headers, hook = request_setup()

# A Stop hook that runs because of a Stop hook would capture in a loop.
if hook.get("stop_hook_active"):
    die()

session_id = hook.get("session_id") or ""
event = hook.get("hook_event_name") or ""
# SessionEnd carries `reason`; PreCompact carries `trigger` (manual | auto).
reason = hook.get("reason") or (
    f"compact-{hook['trigger']}" if event == "PreCompact" and hook.get("trigger")
    else "unknown"
)
transcript = hook.get("transcript_path") or ""


if not transcript or not os.path.isfile(transcript):
    transcript = muse_session_log(session_id)
if not transcript or not os.path.isfile(transcript):
    die()

# SessionEnd is the last chance to store anything, and PreCompact the last
# chance before the context is summarised, so both flush whatever is pending.
# Stop fires after every assistant response and waits for enough new material
# to be worth a memory.
flushing = event != "Stop"
when = (
    "mid-session" if not flushing
    else "before compaction" if event == "PreCompact"
    else "at session end"
)

# Only the user's own turns: they carry intent and goals, and skipping
# assistant output keeps the digest small and avoids re-storing tool dumps.
turns = []
try:
    for ev in tlog.records(transcript):
        # A Muse session log: a user turn is a run-started record.
        muse = tlog.muse_event(ev)
        if muse:
            kind, run = muse
            if kind == "run" and run.get("kind") == "started" \
                    and isinstance(run.get("prompt"), str):
                t = tlog.intent(run["prompt"])
                if t:
                    turns.append(t)
            continue
        if ev.get("type") != "user":
            continue
        # Skip harness-injected noise, not real user intent.
        t = tlog.intent(tlog.text(ev))
        if t:
            turns.append(t)
except Exception:
    die()

if not turns:
    die()

# High-water mark of turns already stored for this session. Without it, the
# sliding window below produces a different digest every turn and every Stop
# would store a near-duplicate of the last one.
marker, state = None, {"digest": "", "captured_turns": 0}
marker_fd = None
waited = 0.0
state_dir = os.path.expanduser("~/.kemory/.captured")
try:
    os.makedirs(state_dir, exist_ok=True)
    marker = os.path.join(state_dir, (session_id or "nosession")[:64].replace("/", "_"))
    # Capture runs async on Stop, PreCompact and SessionEnd, so two runs for one
    # session can overlap. Lock the marker itself, before reading it, and hold
    # the lock until the mark is written; the kernel drops it when the run exits.
    # An empty marker is left behind by runs that exit early, and is never
    # unlinked: a run waiting on the lock would then lock a dead inode.
    if fcntl is not None:
        try:
            marker_fd = os.open(marker, os.O_RDWR | os.O_CREAT, 0o600)
            started = time.monotonic()
            while True:
                try:
                    fcntl.flock(marker_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() - started >= LOCK_WAIT_SECONDS:
                        die()
                    time.sleep(LOCK_POLL_SECONDS)
                    waited = time.monotonic() - started
            raw = b"".join(iter(lambda: os.read(marker_fd, 65536), b"")).decode(errors="replace").strip()
        except OSError:
            # No lock available: behave as without locking.
            if marker_fd is not None:
                os.close(marker_fd)
            marker_fd = None
            raw = open(marker, errors="replace").read().strip() if os.path.isfile(marker) else ""
    else:
        raw = open(marker, errors="replace").read().strip() if os.path.isfile(marker) else ""
    if raw:
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
    f"({when}, user turns only, "
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
    headers=headers,
    method="POST",
)
try:
    urllib.request.urlopen(
        req, timeout=max(3, POST_TIMEOUT_SECONDS - waited) if waited else POST_TIMEOUT_SECONDS
    ).read()
except Exception:
    raise SystemExit(0)  # never advance the mark past turns we did not store  # noqa: B904
if marker:
    try:
        if marker_fd is not None:
            with os.fdopen(marker_fd, "w") as fh:
                fh.seek(0)
                fh.truncate()
                json.dump({"digest": digest, "captured_turns": len(turns)}, fh)
                fh.flush()
        else:
            with open(marker, "w") as fh:
                json.dump({"digest": digest, "captured_turns": len(turns)}, fh)
    except OSError:
        pass
