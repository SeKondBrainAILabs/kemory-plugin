#!/usr/bin/env python3
"""Stdio MCP bridge: line-delimited JSON-RPC on stdin/stdout, HTTP to Kemory.

The fallback for a machine with a credential but no `kemory` binary. The CLI
ships a bridge of its own and `mcp.sh` prefers it; this exists so that dropping
the CLI dependency does not mean pinning the credential into a static header,
which is what made the bundled entry dead for CLI and connector users.

Reads KEMORY_BASE_URL and KEMORY_AUTH_HEADER from the environment — resolved by
lib.sh, the same function the hooks use, so both halves authenticate identically
and cannot drift apart.

Today's endpoint is stateless JSON — verified against the live API: `initialize`
answers 200 application/json and issues no `Mcp-Session-Id`. The transport
allows a server to start issuing one at any time, though, and a relay that
dropped it would break the moment that happened, in a way no test here would
catch. So the header is echoed back when the server sends one, and a 404 on a
session the server has since forgotten clears it rather than wedging every
later call. Same reason a text/event-stream reply is parsed: degrade to
working rather than to silence.

Every failure answers in-band as a JSON-RPC error. A bridge that dies on a bad
response leaves the host waiting on a request that can never complete.

SIGNED OUT. Under Grok, mcp.sh starts this bridge with no credential rather
than exiting (see mcp.sh for why). The API answers `initialize` and
`tools/list` without one, so the host still gets every tool. When a reply says
a credential is needed — HTTP 401/403, or the API's own 200 carrying
`isError` and `_meta["mcp/www_authenticate"]` — the bridge asks lib.sh for the
credential again and retries once. That is how a /kemory:login in the middle
of a session takes effect with no restart, and how an expired token gets
lib.sh's refresh. With still no credential, a tool call answers with the one
action that fixes it.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

TIMEOUT = float(os.environ.get("KEMORY_MCP_TIMEOUT", "120"))
# -32603 is JSON-RPC "internal error": the request was well-formed and we could
# not answer it. Transport faults are ours, not the caller's.
INTERNAL_ERROR = -32603

# Set from the server's Mcp-Session-Id when it issues one, and sent on every
# later request. Module state because a bridge process serves exactly one
# client connection, which is what a session is scoped to.
_session_id: str | None = None


# The credential in use, starting from what mcp.sh resolved. Empty when mcp.sh
# started us signed out. Replaced by _resolve() when a reply says it is needed.
_base_url: str = (os.environ.get("KEMORY_BASE_URL") or "").rstrip("/")
_auth_header: str = os.environ.get("KEMORY_AUTH_HEADER") or ""
# The organisation `kemory use` selected (lib.sh), sent beside the credential
# as the CLI sends it. Empty when none is selected.
_org_header: str = os.environ.get("KEMORY_ORG_HEADER") or ""

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib.sh")

SIGNED_OUT = ("Kemory: not signed in. Run /kemory:login, approve in the browser, "
              "then call this tool again. No restart is needed.")


def _endpoint() -> str:
    if not _base_url:
        raise SystemExit("kemory: KEMORY_BASE_URL is empty — mcp.sh must set it")
    return _base_url + "/mcp/v1"


def _headers() -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        # Both, so a server that prefers SSE still has a shape to choose.
        "Accept": "application/json, text/event-stream",
    }
    for line in (_auth_header, _org_header):
        name, _, value = line.partition(":")
        if name and value.strip():
            headers[name.strip()] = value.strip()
    return headers


def _resolve() -> tuple[str, str, str] | None:
    """Ask lib.sh for the credential now: the same resolution, refresh included,
    that mcp.sh and the hooks use. None when there is no usable one."""
    script = ('. "$1" >/dev/null 2>&1 || exit 1; '
              'kemory_resolve_auth >/dev/null 2>&1 || exit 1; '
              '[ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ] && exit 1; '
              'printf "%s\n%s\n%s\n" "$KEMORY_BASE_URL" "$KEMORY_AUTH_HEADER" "$KEMORY_ORG_HEADER"')
    try:
        r = subprocess.run(["bash", "-c", script, "_", LIB],
                           capture_output=True, text=True, timeout=30)
    except Exception:  # noqa: BLE001 — no credential is an answer, not a crash
        return None
    lines = r.stdout.splitlines()
    if r.returncode != 0 or len(lines) < 2 or not lines[0] or not lines[1]:
        return None
    return lines[0].rstrip("/"), lines[1], lines[2] if len(lines) > 2 else ""


def _needs_auth(reply: dict | None, status: int) -> bool:
    if status in (401, 403):
        return True
    result = reply.get("result") if isinstance(reply, dict) else None
    return (isinstance(result, dict) and bool(result.get("isError"))
            and "mcp/www_authenticate" in (result.get("_meta") or {}))


def _parse(raw: bytes, content_type: str) -> dict | None:
    """Decode one response body, JSON or SSE."""
    text = raw.decode("utf-8", "replace").strip()
    if not text:
        return None
    if "text/event-stream" in content_type:
        # Take the last complete `data:` payload; earlier frames are progress.
        payload = None
        for line in text.splitlines():
            if line.startswith("data:"):
                chunk = line[5:].strip()
                if chunk and chunk != "[DONE]":
                    payload = chunk
        if payload is None:
            return None
        text = payload
    return json.loads(text)


def _error(request_id, message: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": INTERNAL_ERROR, "message": message},
    }


def _relay(endpoint: str, headers: dict[str, str], request: dict) -> tuple[dict | None, int]:
    """POST one message. Returns (reply or None when none is due, HTTP status)."""
    global _session_id

    # A JSON-RPC notification has no `id` and takes no response. Answering one
    # is a protocol violation the host may drop the connection over.
    request_id = request.get("id")
    is_notification = "id" not in request

    sent = dict(headers)
    if _session_id:
        sent["Mcp-Session-Id"] = _session_id

    body = json.dumps(request).encode()
    req = urllib.request.Request(endpoint, data=body, headers=sent, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            issued = response.headers.get("Mcp-Session-Id")
            if issued:
                _session_id = issued
            status = response.status
            raw = response.read()
            content_type = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as exc:
        # 404 against a session id means the server has forgotten it. Dropping
        # it lets the next call start clean instead of failing forever.
        if exc.code == 404 and _session_id:
            _session_id = None
        if is_notification:
            return None, exc.code
        detail = exc.read().decode("utf-8", "replace")[:200].strip()
        hint = ""
        if exc.code in (401, 403):
            hint = " — credential rejected; re-run 'kemory login' or check KEMORY_API_KEY"
        return _error(request_id, f"kemory API HTTP {exc.code}{hint}: {detail}"), exc.code
    except Exception as exc:  # noqa: BLE001 — every transport fault answers in-band
        if is_notification:
            return None, 0
        return _error(request_id, f"kemory API unreachable: {exc.__class__.__name__}: {exc}"), 0

    if is_notification:
        return None, status
    # 202 Accepted is the transport's "received, nothing to return".
    if status == 202:
        return None, status
    try:
        parsed = _parse(raw, content_type)
    except ValueError as exc:
        return _error(request_id, f"kemory API sent a non-JSON reply: {exc}"), status
    if parsed is None:
        return _error(request_id, "kemory API sent an empty reply"), status
    return parsed, status


def _answer(request: dict) -> dict | None:
    """Relay one message; when it needs a credential, look again and retry once."""
    global _base_url, _auth_header, _org_header
    reply, status = _relay(_endpoint(), _headers(), request)
    if not _needs_auth(reply, status):
        return reply
    fresh = _resolve()
    if fresh and fresh[1] != _auth_header:
        _base_url, _auth_header, _org_header = fresh
        reply, status = _relay(_endpoint(), _headers(), request)
        if not _needs_auth(reply, status):
            return reply
    if fresh:
        # There is a credential and the API still refused it: the reply already
        # says so, in the server's words or the 401 hint above.
        return reply
    # No credential at all. A tool call answers as a tool error, which the
    # model reads; anything else as a JSON-RPC error.
    request_id = request.get("id")
    if request.get("method") == "tools/call":
        return {"jsonrpc": "2.0", "id": request_id,
                "result": {"content": [{"type": "text", "text": SIGNED_OUT}],
                           "isError": True}}
    return _error(request_id, SIGNED_OUT)


def main() -> None:
    _endpoint()  # fail at start, not on the first request, if mcp.sh set no URL

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except ValueError:
            # No id is recoverable from an unparseable line, so answer with the
            # null id the spec reserves for exactly this case.
            sys.stdout.write(json.dumps(_error(None, "invalid JSON from host")) + "\n")
            sys.stdout.flush()
            continue
        # A batch is a list; relay each member and answer with the replies due.
        if isinstance(request, list):
            replies = [r for r in (_answer(m) for m in request) if r]
            if replies:
                sys.stdout.write(json.dumps(replies) + "\n")
                sys.stdout.flush()
            continue
        reply = _answer(request)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        # The host closed the connection. Not an error worth a traceback.
        pass
