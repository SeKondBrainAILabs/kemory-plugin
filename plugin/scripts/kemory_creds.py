import json, os, shlex, tempfile, time

CREDS = os.environ["KEMORY_CREDS"]


def write_back(d):
    """Replace the credential file atomically, 0600.

    The temp name is unique per writer. It used to be CREDS + ".tmp" in every
    writer (this hook, login.py, the CLI), so two concurrent refreshes wrote
    into one inode and left the tail of the longer write behind the shorter
    one -- a file ending in "}}" that every reader rejected.
    mkstemp creates the file 0600 and beside the original, so the rename
    cannot cross a filesystem boundary.
    """
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(CREDS) or ".",
                               prefix="." + os.path.basename(CREDS) + ".",
                               suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(d, fh)
        os.replace(tmp, CREDS)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        return False
    return True


try:
    text = open(CREDS).read()
except Exception:
    raise SystemExit(0)  # noqa: B904
try:
    d = json.loads(text)
except ValueError:
    # A file damaged by the race above is one complete object followed by
    # leftover bytes. Take the object, and repair the file on disk: an older
    # kemory CLI -- which is what serves the MCP tools when it is installed --
    # still rejects the damaged file and would report the user signed out.
    try:
        d, _ = json.JSONDecoder().raw_decode(text.lstrip())
    except ValueError:
        d = None
    if isinstance(d, dict):
        write_back(d)
if not isinstance(d, dict):
    # Present but unreadable is not the same as absent: say which, so nobody
    # is sent to sign in when the fix is replacing a broken file.
    print("KEMORY_CREDS_CORRUPT=" + shlex.quote(CREDS))
    raise SystemExit(0)

expired = False


def refresh(d):
    """Trade the refresh token for a fresh access token, in place.

    The CLI refreshes on every use; the hooks used to read access_token and
    nothing else, so once it expired every hook 401d and no-opd with no
    notice at all -- the setup hint only fires when no credential file
    exists, and a stale one does. Best-effort: any failure leaves the old
    token in place and the caller reports it as expired.
    """
    import urllib.parse
    import urllib.request

    issuer = (d.get("issuer") or "").rstrip("/")
    token = d.get("refresh_token")
    client = d.get("client_id")
    if not (issuer and token and client):
        return False
    body = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": token,
        "client_id": client,
    }).encode()
    req = urllib.request.Request(
        issuer + "/protocol/openid-connect/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            fresh = json.load(r)
    except Exception:
        return False
    if not fresh.get("access_token"):
        return False
    d["access_token"] = fresh["access_token"]
    if fresh.get("refresh_token"):
        d["refresh_token"] = fresh["refresh_token"]
    if fresh.get("expires_in"):
        d["expires_at"] = time.time() + float(fresh["expires_in"])
    # The refreshed token is still good for this process even if the write
    # fails, so do not report failure.
    write_back(d)
    return True


exp = d.get("expires_at")
if d.get("access_token") and isinstance(exp, (int, float)):
    if time.time() > float(exp) - 60 and not refresh(d):
        expired = True

for var, key in (("url", "kemory_url"), ("token", "access_token"), ("api_key", "api_key"),
                 ("org", "active_org_id")):
    v = d.get(key) or ""
    if v:
        print(f"{var}={shlex.quote(str(v))}")
if expired:
    print("KEMORY_TOKEN_EXPIRED=1")
