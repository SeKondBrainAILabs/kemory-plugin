#!/usr/bin/env python3
"""Sign in to Kemory from the plugin — RFC 8628 device flow, no CLI required.

The plugin was the one link in the chain that could only READ a credential:
`lib.sh` takes KEMORY_API_KEY, KEMORY_TOKEN, or the CLI's stored login, and with
none of them the launcher exits telling the user to install a CLI or export a
long-lived secret — the two things a non-technical user does not have and should
not need. This closes that: one URL, approve in the browser, done.

WHY DEVICE FLOW AND NOT THE PAIR-CLAIM PROMPT. Pair-claim exists for AIs with no
browser of their own (ChatGPT web, Perplexity): it needs a dashboard session to
generate a code, it mints a long-lived API key, and the brief it hands the agent
persists an MCP entry — a SECOND one, beside the plugin's own. Claude Code runs
on the user's machine with a browser next to it, so none of that is necessary
here. Device flow needs no dashboard, yields refreshable revocable tokens, and
registers no MCP server.

WHAT IT WRITES. `~/.kemory/credentials-<env>`, the same file the Kemory CLI
writes and `lib.sh` already reads and refreshes, in the same v2 shape — so a CLI
installed later finds the user already signed in, and nothing downstream changes.

Measured against prod 2026-09-14: the realm advertises the device grant, the
public client REQUIRES PKCE (a request without `code_challenge_method` is
refused), and the response carries `verification_uri_complete`, so the user gets
one clickable URL and types no code.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_URL = os.environ.get("KEMORY_DEFAULT_URL", "https://api.kemory.s9n.ai")
ENV = os.environ.get("KEMORY_ENV", "prod")
CLIENT_ID = os.environ.get("KEMORY_CLIENT_ID", "kemory-cli")
SCOPE = "openid profile email offline_access"
TIMEOUT = 15
# The file records this; the CLI reads it to know how to interpret the rest.
CREDENTIAL_VERSION = 2


def fail(message: str) -> None:
    print(f"kemory: {message}", file=sys.stderr)
    raise SystemExit(1)


def _post(url: str, form: dict[str, str]) -> tuple[int, dict]:
    """POST a form, return (status, parsed body). Never raises on an HTTP error.

    The device grant signals "keep waiting" with a 400 carrying
    `authorization_pending`, so an error body is a normal part of the protocol
    and has to come back as data rather than an exception.
    """
    req = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(form).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.loads(exc.read() or b"{}")
        except ValueError:
            return exc.code, {}
    except Exception as exc:  # noqa: BLE001 — reported, not raised
        return 0, {"error": exc.__class__.__name__, "error_description": str(exc)}


def discover(base_url: str) -> str:
    """The realm's issuer, asked of the API rather than assumed.

    The API is host-aware, so KEMORY_URL alone is enough to reach the right
    Keycloak — hardcoding an issuer here would send a self-hosted or staging
    user to the wrong identity provider.
    """
    url = base_url.rstrip("/") + "/.well-known/oauth-authorization-server"
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
            meta = json.loads(response.read())
    except Exception:
        meta = {}
    issuer = (meta.get("issuer") or "").rstrip("/")
    if not issuer:
        fail(
            f"could not discover an identity provider from {base_url}. "
            "Check KEMORY_URL, or sign in with the Kemory CLI instead."
        )
    return issuer


def claims_of(access_token: str) -> dict:
    """The access token's own claims. `email` and `org_id` live here, so the
    credential file can be filled with no extra API call."""
    try:
        payload = access_token.split(".")[1]
        padded = payload + "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception:
        return {}


def credentials_path() -> str:
    return os.path.join(os.path.expanduser("~"), ".kemory", f"credentials-{ENV}")


def existing() -> dict:
    try:
        with open(credentials_path()) as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def write_credentials(tokens: dict, issuer: str, base_url: str) -> str:
    access = tokens.get("access_token") or ""
    claims = claims_of(access)
    prior = existing()

    org_id = claims.get("org_id") or prior.get("org_id") or ""
    # `active_org_id` is NOT a token claim and is NOT always org_id: `kemory use`
    # switches it, and on a machine where it had been switched, overwriting it
    # here would silently move the user back to their default organisation —
    # which is how memories have landed in the wrong org before. Keep what is
    # already there; only a first sign-in defaults it.
    active_org_id = prior.get("active_org_id") or org_id

    data = {
        "access_token": access,
        "refresh_token": tokens.get("refresh_token") or prior.get("refresh_token") or "",
        "expires_at": time.time() + float(tokens.get("expires_in") or 0),
        "client_id": CLIENT_ID,
        "issuer": issuer,
        "kemory_url": base_url.rstrip("/"),
        "env": ENV,
        "email": claims.get("email") or prior.get("email") or "",
        "org_id": org_id,
        "active_org_id": active_org_id,
        "version": CREDENTIAL_VERSION,
    }

    path = credentials_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    # Atomic and 0600, matching lib.sh's refresh: this file holds a refresh
    # token. The temp name is unique per writer -- a shared `.tmp` let two
    # concurrent writers corrupt the file. mkstemp creates it 0600.
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path),
                               prefix="." + os.path.basename(path) + ".",
                               suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return path


def main() -> None:
    base_url = (os.environ.get("KEMORY_URL") or DEFAULT_URL).rstrip("/")
    issuer = discover(base_url)

    verifier = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip("=")
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
        .decode()
        .rstrip("=")
    )

    status, start = _post(
        f"{issuer}/protocol/openid-connect/auth/device",
        {
            "client_id": CLIENT_ID,
            "scope": SCOPE,
            # Mandatory on this client, not optional: without it the endpoint
            # answers `invalid_request: Missing parameter: code_challenge_method`.
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        },
    )
    device_code = start.get("device_code")
    if not device_code:
        detail = start.get("error_description") or start.get("error") or f"HTTP {status}"
        fail(f"could not start sign-in against {issuer}: {detail}")

    # `verification_uri_complete` embeds the user code, so there is one link and
    # nothing to type. Fall back to the plain URI plus the code when a provider
    # does not offer it.
    complete = start.get("verification_uri_complete")
    user_code = start.get("user_code") or ""
    print("Sign in to Kemory — open this and approve:\n")
    if complete:
        print(f"  {complete}\n")
    else:
        print(f"  {start.get('verification_uri')}")
        print(f"  code: {user_code}\n")
    print("Waiting…", flush=True)

    interval = max(1, int(start.get("interval") or 5))
    deadline = time.time() + int(start.get("expires_in") or 600)
    token_url = f"{issuer}/protocol/openid-connect/token"

    while time.time() < deadline:
        time.sleep(interval)
        status, body = _post(
            token_url,
            {
                "client_id": CLIENT_ID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": device_code,
                "code_verifier": verifier,
            },
        )
        if body.get("access_token"):
            path = write_credentials(body, issuer, base_url)
            claims = claims_of(body["access_token"])
            who = claims.get("email") or claims.get("preferred_username") or "signed in"
            print(f"\nSigned in as {who}. Credential written to {path}.")
            print("Restart Claude Code to pick it up — the hooks and the memory tools both read this file.")
            return
        error = body.get("error")
        if error == "authorization_pending":
            continue
        if error == "slow_down":
            # The spec's own backpressure signal; ignoring it risks being cut off.
            interval += 5
            continue
        if error == "expired_token":
            fail("the sign-in link expired. Run the command again.")
        if error == "access_denied":
            fail("sign-in was declined in the browser.")
        detail = body.get("error_description") or error or f"HTTP {status}"
        fail(f"sign-in failed: {detail}")

    fail("timed out waiting for sign-in. Run the command again.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nkemory: sign-in cancelled.", file=sys.stderr)
        raise SystemExit(1)
