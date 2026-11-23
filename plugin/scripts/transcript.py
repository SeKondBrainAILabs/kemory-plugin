"""Session-transcript reading for the hooks that parse a transcript.

One copy, imported by capture.py and store_nudge.py. A fix to the transcript
shape (a line that is not an object, a part without text) made in two copies
drifts, and the drift is silent because hooks fail open.

Import under an alias, with the script directory on sys.path:

    sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
    import transcript as tlog

The hooks name their path variable `transcript`, which would rebind a bare
`import transcript` and make every call fail open into doing nothing.
"""

import json


def records(path):
    """Yield each JSON object of a JSONL file; skip lines that are not objects.

    An OSError from open() propagates when iteration starts.
    """
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                ev = json.loads(line)
            except Exception:
                continue
            # Valid JSON is not always an object; only objects are records.
            if isinstance(ev, dict):
                yield ev


def content(ev):
    """ev["message"]["content"] when message is an object, else None."""
    message = ev.get("message")
    return message.get("content") if isinstance(message, dict) else None


def blocks(ev):
    """The content parts of a message, or [] when its content is not a list."""
    c = content(ev)
    return c if isinstance(c, list) else []


def text(ev):
    """The message's text: a string content as is, else its text parts joined."""
    c = content(ev)
    if isinstance(c, str):
        return c
    return " ".join(b.get("text", "") for b in blocks(ev)
                    if isinstance(b, dict) and b.get("type") == "text"
                    and isinstance(b.get("text", ""), str))


def intent(t):
    """The stripped text of a real user turn, or "" for empty or harness noise."""
    t = t.strip()
    return "" if not t or t.startswith(("<", "Caveat:")) else t


def muse_event(ev):
    """(payload.kind, payload.event) of a Muse session record, else None."""
    if ev.get("type") in ("user", "assistant") or not isinstance(ev.get("payload"), dict):
        return None
    inner = ev["payload"].get("event")
    return (ev["payload"].get("kind"), inner if isinstance(inner, dict) else {})
