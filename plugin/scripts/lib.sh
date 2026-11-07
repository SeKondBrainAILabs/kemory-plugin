#!/usr/bin/env bash
# Shared credential resolution for Kemory hooks. Sourced, not executed.
#
# Sets, on success (return 0):
#   KEMORY_BASE_URL    — API base, no trailing slash
#   KEMORY_AUTH_HEADER — a complete header line to send
#   KEMORY_ORG_HEADER  — "X-Organization-ID: <id>" when `kemory use` selected an
#                        organisation for the credential file's token, else empty
#   KEMORY_URL_RETARGETED_FROM — set only when a superseded host was rewritten
#
# Hosted Kemory authenticates with a bearer token; the community edition
# authenticates with X-API-Key only (backend/core/auth.py), so both are
# supported and detected rather than assumed.
# Hosted Kemory. Only override KEMORY_URL when pointing at a self-hosted or
# community instance, so the common case needs a key and nothing else.
KEMORY_DEFAULT_URL="${KEMORY_DEFAULT_URL:-https://api.kemory.s9n.ai}"

# Where this plugin is installed. Hosts substitute ${CLAUDE_PLUGIN_ROOT} into the
# commands they run, but Grok Build does not export it to the shell (measured on
# Grok 1.0.52: unset inside a command's shell call), so a script that branches
# on the variable alone mistakes Grok for some other host. Its own location is
# the fact that does not depend on the host.
KEMORY_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"

# This file's own directory, where the Python programs the helpers below run live.
# Not the caller's $DIR: hooks, mcp.sh, status.sh and tests all source this file
# by absolute path from their own directories.
KEMORY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# True when this plugin is running under Grok Build: installed under ~/.grok, or
# told so by a host that does export CLAUDE_PLUGIN_ROOT.
kemory_is_grok() {
  case "${CLAUDE_PLUGIN_ROOT:-}" in */.grok/*) return 0 ;; esac
  case "${KEMORY_PLUGIN_DIR:-}" in */.grok/*) return 0 ;; esac
  return 1
}

# Where capture writes digests unless KEMORY_CAPTURE_NAMESPACE says otherwise;
# capture.sh and status.sh both read it.
# shellcheck disable=SC2034  # read by the scripts that source this file
KEMORY_DEFAULT_CAPTURE_NAMESPACE="user:sessions"

# A cached credential keeps the API host it was written with, so a host that has
# since stopped serving the API survives indefinitely on an existing install —
# the default above only ever reaches a fresh login. The kemory CLI rewrites
# these when it loads a credential; this path reads the file directly, so it
# needs the same rewrite or the hooks and /kemory:status stay pointed at a dead
# host while the CLI itself is fine.
#
# Exact match only. A self-hosted or community host that merely looks similar
# must be left alone.
#
# Answers in KEMORY_RETARGETED_URL rather than on stdout: a command
# substitution would run this in a subshell and lose the
# KEMORY_URL_RETARGETED_FROM breadcrumb, leaving a silent rewrite.
# How to update the plugin, said so the person can act on it where they are.
# `/plugin` is a terminal dialog; the desktop app (CLAUDE_CODE_ENTRYPOINT is
# claude-desktop there) has no such command, so it gets the CLI form.
# Grok Build has neither: it installs under ~/.grok and updates from its own
# CLI, so naming a Claude command there is advice the person cannot run.
kemory_update_command() {
  if kemory_is_grok; then
    printf '%s' "'grok plugin update kemory' in a terminal"
    return
  fi
  if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = "claude-desktop" ]; then
    printf '%s' "'claude plugin update kemory@kemory' in a terminal"
  else
    printf '%s' "/plugin update kemory@kemory"
  fi
}

kemory_retarget_url() {
  KEMORY_RETARGETED_URL="$1"
  case "$1" in
    # Retired: now redirects to the browser dashboard, which sends any API path
    # on to SSO login. A caller sees a redirect or an HTML login page.
    https://kemory.prod.apps.s9n.ai)
      KEMORY_RETARGETED_URL="https://api.kemory.s9n.ai"
      KEMORY_URL_RETARGETED_FROM="$1"
      ;;
  esac
}

kemory_resolve_auth() {
  local creds url token api_key org
  url="" ; token="" ; api_key="" ; org=""
  unset KEMORY_URL_RETARGETED_FROM KEMORY_CREDS_CORRUPT KEMORY_TOKEN_EXPIRED

  if [ -n "${KEMORY_API_KEY:-}" ]; then
    api_key="$KEMORY_API_KEY"
    url="${KEMORY_URL:-$KEMORY_DEFAULT_URL}"
  elif [ -n "${KEMORY_TOKEN:-}" ]; then
    token="$KEMORY_TOKEN"
    url="${KEMORY_URL:-$KEMORY_DEFAULT_URL}"
  else
    creds="$HOME/.kemory/credentials-${KEMORY_ENV:-prod}"
    [ -r "$creds" ] || creds="$HOME/.kemory/credentials"
    [ -r "$creds" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    eval "$(KEMORY_CREDS="$creds" python3 "$KEMORY_LIB_DIR/kemory_creds.py" 2>/dev/null)"
  fi

  [ -n "$url" ] || return 1
  if [ -n "$api_key" ]; then
    KEMORY_AUTH_HEADER="X-API-Key: $api_key"
  elif [ -n "$token" ]; then
    KEMORY_AUTH_HEADER="Authorization: Bearer $token"
  else
    return 1
  fi
  # The organisation `kemory use` selected. The CLI, and so the MCP tools it
  # serves, sends it on every request; without it the hooks would recall from
  # and capture into the token's own organisation instead.
  KEMORY_ORG_HEADER=""
  if [ -z "$api_key" ] && [ -n "$org" ]; then
    KEMORY_ORG_HEADER="X-Organization-ID: $org"
  fi
  kemory_retarget_url "${url%/}"
  KEMORY_BASE_URL="$KEMORY_RETARGETED_URL"
  export KEMORY_BASE_URL KEMORY_AUTH_HEADER KEMORY_ORG_HEADER KEMORY_URL_RETARGETED_FROM
  return 0
}

# Which organisation the credential acts in, BY NAME: echoes "<name>\t<id>".
#
# The id alone is a UUID nobody reads, and the name only exists server-side, so
# ask the server the way an MCP client would (kemory_whoami, which returns
# org_name in structuredContent). This is what makes a wrong active
# organisation visible: until it was shown, a fresh sign-in could put a user in
# their account's home organisation and every capture went there unnoticed.
#
# Needs kemory_resolve_auth to have run. Silent on any failure — no network, an
# older server, a reply without a name — because a missing name must never stop
# status or sign-in.
kemory_active_org() {
  [ -n "${KEMORY_BASE_URL:-}" ] && [ -n "${KEMORY_AUTH_HEADER:-}" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  # Options written inline rather than through an array, so the PRIVACY.md
  # call-site guard sees this call.
  curl -s --max-time "${KEMORY_ORG_TIMEOUT:-5}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "$KEMORY_AUTH_HEADER" ${KEMORY_ORG_HEADER:+-H "$KEMORY_ORG_HEADER"} \
    -X POST "$KEMORY_BASE_URL/mcp/v1" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kemory_whoami","arguments":{}}}' \
    2>/dev/null | python3 "$KEMORY_LIB_DIR/kemory_lib.py" active-org 2>/dev/null
}

# Locate a Kemory API key sitting in an MCP client config, where our own docs
# tell Claude Code users to put it.
#
# The hooks cannot use it: they read KEMORY_API_KEY / KEMORY_TOKEN from the
# environment, or the CLI credential file. A user who follows the documented
# local-client route therefore ends up with a valid key on disk, working
# tools, and no hooks. This detects that state so we can say so, and
# deliberately does NOT return the key itself -- harvesting a credential out
# of another tool's config is not a habit worth building in.
#
# Echoes the config path and returns 0 when found.
kemory_find_mcp_config_key() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 "$KEMORY_LIB_DIR/kemory_lib.py" find-mcp-config-key "$@" 2>/dev/null
}

# Count kemory MCP server entries sitting in MCP client configs on this machine.
#
# Two entries means every request carries two copies of the same tools. The
# most common way to get there is installing the plugin while a hand-written
# entry from the pre-plugin docs is still in place, and nothing surfaces it:
# /mcp lists them without saying they are the same server twice.
#
# Counts on-disk entries only. A claude.ai connector is not an entry in any of
# these files, so callers name that case separately (kemory_connector_ever_connected)
# rather than reporting a reassuring zero.
#
# Echoes the count. The plugin's own bundled entry is not in these files.
kemory_count_mcp_entries() {
  command -v python3 >/dev/null 2>&1 || { echo 0; return 0; }
  python3 "$KEMORY_LIB_DIR/kemory_lib.py" count-mcp-entries 2>/dev/null || echo 0
}

# Has a claude.ai Kemory connector ever connected to Claude Code on this machine?
#
# claudeAiMcpEverConnected in ~/.claude.json only ever grows, so it records that
# a connector connected once, not that it is on in this session. Report it as
# history; never stand a server down on it.
#
# Echoes "seen<TAB><entry>" for the first Kemory entry, or "never" when the file
# parses and holds none. Echoes nothing when it cannot tell: a missing, unreadable
# or non-JSON file, or a key that is not a list.
kemory_connector_ever_connected() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 "$KEMORY_LIB_DIR/kemory_lib.py" connector-ever-connected 2>/dev/null
}

# Find an MCP server already configured on this machine that points at the SAME
# Kemory this plugin would serve.
#
# Two servers for one endpoint means every request carries two copies of the
# same tools, and /mcp lists them without saying they are the same server twice.
# The plugin's bundled entry is the one that should stand down: an entry in a
# host config was put there deliberately, by `kemory mcp install`, by a pasted
# pair-claim prompt, or by hand, and yielding costs only the duplicate — the
# hooks read credentials directly and keep working either way.
#
# SAME ENDPOINT, not same name. `kemory mcp install` pins the env in the args
# precisely so prod and staging can coexist as separate servers, so two entries
# on different hosts are deliberate multi-env work and must be left alone.
#
# Resolves each entry the way the thing that runs it would:
#   * an http/sse entry          -> the host of its own url
#   * `kemory [--env X] mcp serve` -> the host in ~/.kemory/credentials-X,
#                                     if that command is on this process's PATH
# An entry whose endpoint cannot be worked out is SKIPPED, never guessed at:
# standing down wrongly costs the user their tools.
#
# ONLY configs Claude Code loads for THIS session count: the project's
# .mcp.json, the user-scope mcpServers in ~/.claude.json, and that file's entry
# for the current project. Claude Desktop's claude_desktop_config.json belongs
# to a different app, and another project's entry is not loaded here — standing
# down for either left Claude Code with no memory tools at all while the hooks
# kept capturing.
#
# Echoes "<server name>\t<config path>" on a match; silent otherwise.
kemory_find_duplicate_server() {
  [ -n "${KEMORY_BASE_URL:-}" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  KEMORY_MINE="$KEMORY_BASE_URL" python3 "$KEMORY_LIB_DIR/kemory_lib.py" find-duplicate-server 2>/dev/null
}

# Ask the HOST whether it has switched our MCP server off.
#
# Claude Code gives a server 30s to answer `initialize`, and on a timeout it
# records the failure in ~/.claude/mcp-needs-auth-cache.json and SKIPS the
# server for the next 15 minutes. That file is global and shared by every
# session on the machine, so one slow launch in one project takes the memory
# tools away from every session started afterwards -- including sessions whose
# own launch would have succeeded in under a second. The user sees
# "Skipping connection (recent failure cached...)" and nothing else.
#
# Without this, /kemory:status resolves a credential, reaches the API, finds no
# duplicate, and reports the tools as fine while the host is not running them.
# That is the same lie the TOOLS section was already fixed for once (see
# status.sh) arriving through a different door: we were reporting whether the
# server COULD start, never whether the host intends to start it.
#
# Read-only, and deliberately so. Deleting the entry from a hook is tempting
# and wrong twice over: the file is the host's own undocumented state, global
# and written by concurrent sessions with no lock we can take, so a
# read-modify-write can drop another server's entry; and the entry is there
# because a launch really did exceed 30s, so clearing it every session start
# just moves the cost from one skipped session to a 30s stall in all of them.
# Saying what happened is the fix. Making it not happen is a startup-time
# problem, not a status problem.
#
# Matches any kemory entry rather than the exact bundled key: the same cache
# holds host-config and connector entries, and a rigid key match that silently
# misses is precisely the failure mode being fixed here.
#
# Echoes "<cache key>\t<epoch seconds>" for the most recent hit; silent
# otherwise, including when the file is absent, unreadable or not JSON.
kemory_mcp_skipped_at() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 "$KEMORY_LIB_DIR/kemory_lib.py" mcp-skipped-at 2>/dev/null
}

# Ask Grok Build whether the user has switched our MCP server off.
#
# Grok keeps a top-level `disabled_mcp_servers` list in ~/.grok/config.toml,
# and a server named there is never launched. Its MCP Servers tab cannot
# delete a server a plugin provides ("only locally-configured servers can be
# deleted"), so disabling is the one action it offers, and nothing afterwards
# says so: the hooks keep running, recall keeps firing, and the kemory_* tools
# are simply absent. That is the Grok shape of the failure
# kemory_mcp_skipped_at() reports for Claude Code.
#
# Only under Grok. A Grok config on a machine where this session runs in
# another host says nothing about this session.
#
# Read-only, and deliberately so: the list is the user's own setting, and may
# be deliberate. Saying what it does is the fix; editing it is not ours to do.
#
# Matches the bundled server's name exactly, or as the last segment of a
# namespaced name ("plugin:kemory:kemory"). A substring match would report a
# user's own deliberately disabled "kemory-staging" entry as our server.
#
# Echoes the matching entry; silent otherwise, including when the config is
# absent, unreadable or not valid TOML.
kemory_grok_disabled_server() {
  kemory_is_grok || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 "$KEMORY_LIB_DIR/kemory_lib.py" grok-disabled-server 2>/dev/null
}

# Locate the host's per-cwd MCP log directory for a cache key, on THIS machine.
#
# Printing a literal path is how the first version of the skip report shipped a
# macOS-only instruction: the logs live under ~/Library/Caches on a Mac and
# under $XDG_CACHE_HOME (or ~/.cache) everywhere else, so half the users would
# have been sent to a directory that does not exist. Worse than saying nothing,
# because it looks authoritative.
#
# The directory is named for the cwd of the session that FAILED, which is
# routinely a different project, so we cannot compute it from here -- we look
# for what is actually on disk and take the most recently written match.
#
# Echoes an existing directory, or nothing when none is found (no python3, a
# host that stores logs elsewhere, or logs that have been cleaned up).
kemory_mcp_log_dir() {
  command -v python3 >/dev/null 2>&1 || return 0
  KEMORY_LOG_KEY="${1:-}" python3 "$KEMORY_LIB_DIR/kemory_lib.py" mcp-log-dir 2>/dev/null
}
