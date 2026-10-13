#!/usr/bin/env bash
# Launcher for the bundled MCP server: resolve a credential, then serve.
#
# The invariant this exists to hold: ONE bundled entry, credential resolved at
# launch, never a static header in .mcp.json. A static header can only name one
# of the three ways a user reaches Kemory, so every previous version was dead
# for the other two — stdio needed the CLI on PATH, HTTP needed KEMORY_API_KEY
# in the environment, and the transport was switched three times because each
# fix broke the population the other served. Resolving here ends that: the same
# lib.sh function the hooks use answers for the tools too, so the two halves
# cannot authenticate differently or point at different hosts.
#
# Serves via the CLI's own bridge when the credential came from the CLI (it
# refreshes its token natively), and via mcp_bridge.py when the credential came
# from the environment (which the CLI bridge does not read).
#
# Exits non-zero with one line on stderr when there is no credential. A server
# that starts and exposes nothing looks connected in /mcp while every memory
# tool is missing, which is the failure this whole change is about.
#
# Except under Grok Build, which starts the bundled bridge SIGNED OUT instead.
# Grok fixes a server's tool list when the session starts and never asks again
# (it ignores notifications/tools/list_changed — measured on Grok 1.0.52), so a
# server that exits for want of a credential costs the user a restart after
# /kemory:login. A signed-out bridge does not expose nothing: the Kemory API
# lists its tools without a credential, so every tool is there from the start,
# each call answers "run /kemory:login" until there is one, and the first call
# after signing in goes through. Claude Code keeps the exit: there a user who
# reaches Kemory through the claude.ai connector has no credential by design,
# and a signed-out bundled server would sit beside the connector's tools.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

signed_out=""
if ! kemory_resolve_auth; then
  if [ -n "${KEMORY_CREDS_CORRUPT:-}" ]; then
    echo "kemory: $KEMORY_CREDS_CORRUPT is not valid JSON and could not be recovered — run /kemory:login to write a fresh one." >&2
    kemory_is_grok || exit 1
  else
    if kemory_is_grok; then
      echo "kemory: no credential — starting signed out. The memory tools answer 'run /kemory:login' until you sign in, and work on the next call after; no restart needed. (Or set KEMORY_API_KEY for a headless machine.)" >&2
    else
      echo "kemory: no credential — run /kemory:login to sign in with your browser (or set KEMORY_API_KEY for a headless machine). Using the claude.ai connector instead? Disable this server under /mcp." >&2
      exit 1
    fi
  fi
  signed_out=1
elif [ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ]; then
  echo "kemory: stored token expired and could not be refreshed — run /kemory:login to sign in again." >&2
  kemory_is_grok || exit 1
  signed_out=1
fi

# Signed out (Grok only, by the branches above): point the bridge at the API
# with no credential. It resolves one through lib.sh when a call needs it.
if [ -n "$signed_out" ]; then
  kemory_retarget_url "${KEMORY_URL:-$KEMORY_DEFAULT_URL}"
  KEMORY_BASE_URL="${KEMORY_RETARGETED_URL%/}"
  KEMORY_AUTH_HEADER=""
  export KEMORY_BASE_URL KEMORY_AUTH_HEADER
fi

# Stand down when this machine already has a server for the same Kemory. Two
# means two copies of every tool in each request, and the bundled entry is the
# one that should give way: an entry in a host config was put there on purpose
# and this one arrives with the plugin. The cost is only the duplicate — the
# hooks read credentials directly, so recall, injection, rating and capture all
# keep working while this server stands aside.
#
# Loudly. A server that starts and exposes nothing reads as connected in /mcp
# with every tool missing, which is the failure this whole file exists to avoid.
if [ "${KEMORY_ALLOW_DUPLICATE:-0}" != "1" ]; then
  duplicate="$(kemory_find_duplicate_server)"
  if [ -n "$duplicate" ]; then
    name="${duplicate%%	*}"
    where="${duplicate##*	}"
    echo "kemory: standing down — '$name' in $where already serves this same Kemory, and two servers mean two copies of every tool. Your hooks are unaffected. Keep this one instead? Remove that entry (or run 'claude mcp remove $name'), then restart. Want both anyway? Set KEMORY_ALLOW_DUPLICATE=1." >&2
    exit 1
  fi
fi

# Signed out, the bundled bridge is the only server that can pick a credential
# up mid-session: the CLI's own bridge reads it once, at launch.
if [ -n "$signed_out" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "kemory: need python3 to serve the memory tools." >&2
    exit 1
  fi
  exec python3 "$DIR/mcp_bridge.py"
fi

# Which credential lib.sh used decides who serves. The CLI bridge reads
# ~/.kemory/credentials-<env> and ignores KEMORY_API_KEY, so preferring it for
# an environment credential would silently serve a different account than the
# hooks use.
from_env=0
[ -n "${KEMORY_API_KEY:-}" ] && from_env=1
[ -n "${KEMORY_TOKEN:-}" ] && from_env=1

if [ "$from_env" -eq 0 ] && command -v kemory >/dev/null 2>&1; then
  exec kemory mcp serve
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "kemory: need python3 (or the kemory CLI) to serve the memory tools." >&2
  exit 1
fi

exec python3 "$DIR/mcp_bridge.py"
