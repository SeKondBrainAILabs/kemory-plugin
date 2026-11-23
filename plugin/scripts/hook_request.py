"""Request setup for the hooks that send a session or prompt to the Kemory API.

One copy, imported by capture.py and prompt_recall.py. It reads the API URL,
the credential header, the organisation header and the hook payload, and
refuses to go on unless the credential has somewhere safe to go. Two copies of
a check like this drift, and the drift is silent. The HTTP request itself stays
in each script.

Import with the script directory on sys.path:

    sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
    from hook_request import env_int, request_setup
"""

import json
import os


def die():
    raise SystemExit(0)


def env_int(name, default):
    try:
        return int(os.environ[name])
    except (KeyError, ValueError):
        return default


def request_setup():
    """Return (url, headers, hook), or exit 0 when the hook should not send."""
    try:
        url = os.environ["KEMORY_BASE_URL"]
        auth_name, _, auth_value = os.environ["KEMORY_AUTH_HEADER"].partition(": ")
        # The organisation `kemory use` selected, as the CLI sends it (lib.sh).
        org_name, _, org_value = os.environ.get("KEMORY_ORG_HEADER", "").partition(": ")
        hook = json.loads(os.environ["HOOK_INPUT"])
    except Exception:
        die()
    if not url or not auth_value:
        die()
    if not url.startswith(("http://", "https://")):
        die()  # never send a credential to a non-HTTP scheme
    headers = {
        auth_name: auth_value,
        **({org_name: org_value} if org_value else {}),
        "Content-Type": "application/json",
    }
    return url, headers, hook
