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
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

if ! kemory_resolve_auth; then
  if [ -n "${KEMORY_NO_PYTHON:-}" ]; then
    echo "kemory: python3 is missing or does not run (on macOS: xcode-select --install), so the credential file cannot be read. Install Python 3, then restart." >&2
    exit 1
  fi
  if [ -n "${KEMORY_CREDS_CORRUPT:-}" ]; then
    echo "kemory: $KEMORY_CREDS_CORRUPT is not valid JSON and could not be recovered — run /kemory:login to write a fresh one." >&2
    exit 1
  fi
  echo "kemory: no credential — run /kemory:login in Claude Code to sign in with your browser (or set KEMORY_API_KEY for a headless machine). Using the claude.ai connector instead? Disable this server under /mcp." >&2
  exit 1
fi

if [ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ]; then
  echo "kemory: stored token expired and could not be refreshed — run /kemory:login to sign in again." >&2
  exit 1
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

if ! kemory_python_ok; then
  echo "kemory: python3 is missing or does not run, and the kemory CLI is not installed — one of them is needed to serve the memory tools." >&2
  exit 1
fi

exec python3 "$DIR/mcp_bridge.py"
