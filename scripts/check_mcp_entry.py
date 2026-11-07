#!/usr/bin/env python3
"""Assert the shape of the plugin's bundled MCP entry.

`plugin/.mcp.json` decides whether a user gets any memory tools. Nothing else
in this repo looks at it: on 2026-09-12 replacing it with a bogus endpoint and
an empty headers block passed all 85 tests, so a change that breaks every
install would go green through CI and fail only on the user's machine.

THE INVARIANT, and why it is worth a guard rather than a convention. The entry
has been rewritten three times — stdio, HTTP, stdio, HTTP — and each rewrite
fixed one population by breaking another, because a *static* entry can name
only one of the three ways a user reaches Kemory. stdio-to-the-CLI is dead
without the binary; an `X-API-Key: ${KEMORY_API_KEY}` header is dead for the
CLI and connector users who never set that variable, and it makes Claude Code
send an empty header, get a 401 and fall into an OAuth prompt for a server the
user never chose. So:

    one entry, launched through a script, credential resolved at launch,
    never a static credential in this file

What is checked:

  * valid JSON, one server named `kemory` — a typo here removes the tools
  * the servers map sits under a top-level `mcpServers` key. Claude Code reads
    both shapes, so the bare map worked and nothing here objected — but every
    other reader of an MCP config expects the wrapper, and one that does not
    find it reports the plugin as shipping no servers at all. That is how the
    plugin would list in a third-party marketplace catalogue: hooks, skills, a
    command, and no memory tools
  * launched via `${CLAUDE_PLUGIN_ROOT}/scripts/mcp.sh`, which exists and is
    executable — the plugin root variable is the only portable path
  * no `type`/`url` — an http entry cannot resolve a credential at launch
  * NO credential anywhere in the entry: no headers block, no `KEMORY_API_KEY`
    reference, no literal key. A reference reintroduces the 401/OAuth failure;
    a literal would be a committed secret
  * `mcp.sh` sources `lib.sh` and calls `kemory_resolve_auth` — the point of
    the launcher is that the tools authenticate exactly like the hooks, and a
    launcher that resolved its own way would drift
  * `mcp_bridge.py` hardcodes no host — it must take `KEMORY_BASE_URL` from
    that same resolution, or self-hosted users lose the one variable that
    repoints the whole plugin

Prints a one-line summary and exits 0, or the reason and exits 1.
"""

from __future__ import annotations

import json
import os
import pathlib

ENTRY = pathlib.Path("plugin/.mcp.json")
LAUNCHER = pathlib.Path("plugin/scripts/mcp.sh")
BRIDGE = pathlib.Path("plugin/scripts/mcp_bridge.py")
EXPECTED_COMMAND = "${CLAUDE_PLUGIN_ROOT}/scripts/mcp.sh"


def fail(message: str) -> None:
    print(message)
    raise SystemExit(1)


def main() -> None:
    try:
        entry = json.loads(ENTRY.read_text())
    except FileNotFoundError:
        fail(f"{ENTRY} is missing")
    except json.JSONDecodeError as exc:
        fail(f"{ENTRY} is not valid JSON: {exc}")

    # Locate the servers map before judging it, so an entry that is wrong in
    # two ways still reports the reason that matters most.
    wrapped = entry.get("mcpServers")
    servers = wrapped if isinstance(wrapped, dict) else entry

    server = servers.get("kemory")
    if not isinstance(server, dict):
        fail(f"{ENTRY} has no 'kemory' server (found: {', '.join(servers) or 'nothing'})")

    for field in ("type", "url"):
        if field in server:
            fail(
                f"entry carries {field!r}, so it is an http entry. An http entry "
                "sends a static header, which is dead for anyone who reaches "
                "Kemory by CLI login or connector. Launch scripts/mcp.sh instead."
            )

    command = server.get("command")
    if command != EXPECTED_COMMAND:
        fail(f"command is {command!r}, expected {EXPECTED_COMMAND!r}")

    if not LAUNCHER.is_file():
        fail(f"{LAUNCHER} does not exist, so the entry launches nothing")
    if not os.access(LAUNCHER, os.X_OK):
        fail(f"{LAUNCHER} is not executable, so the entry cannot start")

    if server.get("headers"):
        fail(
            "entry has a headers block. The credential is resolved at launch by "
            "mcp.sh — a header here is either a committed secret or an empty "
            "value that produces a 401 and an unwanted OAuth prompt."
        )

    blob = json.dumps(entry)
    if "KEMORY_API_KEY" in blob or "KEMORY_TOKEN" in blob:
        fail(
            "entry references a credential variable. mcp.sh reads those through "
            "lib.sh, the same path the hooks use; naming one here pins the entry "
            "to a single way of reaching Kemory, which is the bug this shape fixes."
        )

    launcher_source = LAUNCHER.read_text()
    if "lib.sh" not in launcher_source or "kemory_resolve_auth" not in launcher_source:
        fail(
            f"{LAUNCHER} does not source lib.sh and call kemory_resolve_auth — "
            "the tools would authenticate differently from the hooks"
        )

    bridge_source = BRIDGE.read_text() if BRIDGE.is_file() else ""
    if not bridge_source:
        fail(f"{BRIDGE} is missing — a machine with a key and no CLI gets no tools")
    for host in ("api.kemory.s9n.ai", "api.kemory.sekondbrain.ai"):
        if f"https://{host}" in bridge_source:
            fail(
                f"{BRIDGE} hardcodes {host}. It must use KEMORY_BASE_URL from "
                "lib.sh, so KEMORY_URL still repoints the whole plugin."
            )

    if not isinstance(wrapped, dict):
        fail(
            f"{ENTRY} puts the servers at the top level. Claude Code accepts "
            "that, which is why it shipped, but a reader that expects the "
            "standard `mcpServers` wrapper sees no servers and lists the "
            "plugin as having no memory tools. Wrap it."
        )

    print("stdio via scripts/mcp.sh under mcpServers, credential resolved at launch by lib.sh")


if __name__ == "__main__":
    main()
