"""Muse session-log lookup for the hooks that read a session transcript.

One copy, imported by capture.sh and store-nudge.sh. It holds the session-id
guard that keeps a hostile session_id from steering the glob out of Muse's
sessions directory, and two copies of a guard drift, and the drift is silent.

Import from a heredoc with the script directory on sys.path:

    sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
    from muse_log import muse_session_log
"""

import glob
import os
import re


def muse_session_log(sid):
    """Newest Muse session log for this id, or "" (Muse sends no transcript_path).

    Only under Muse, and only for a plain id, so a hostile session_id cannot
    steer the glob out of Muse's sessions directory.
    """
    if not os.environ.get("MUSE_PLUGIN_ROOT") or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", sid):
        return ""
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    found = glob.glob(os.path.join(
        glob.escape(base), "muse", "sessions", "*", "*", "*", sid, "session.jsonl"))
    return max(found, key=os.path.getmtime) if found else ""
