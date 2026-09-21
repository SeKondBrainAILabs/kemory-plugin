#!/usr/bin/env bash
# Report whether Kemory is actually working: credentials, API reachability,
# capture state, and local capture history. Read-only and safe to run anytime.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }

echo "Kemory status"
echo

# Kemory has two independent halves and they authenticate separately: the MCP
# tools, and the hooks. Reporting one number for both is how a user ends up
# believing the plugin works when half of it is inert.
echo "HOOKS — context injection, prompt recall, rating, capture"

# --- credentials -----------------------------------------------------------
if kemory_resolve_auth; then
  case "$KEMORY_AUTH_HEADER" in
    X-API-Key:*)      mode="API key" ;;
    Authorization:*)  mode="bearer token" ;;
    *)                mode="unknown" ;;
  esac
  ok "credentials resolved — $mode"
  info "endpoint: $KEMORY_BASE_URL"
  if [ -n "${KEMORY_URL_RETARGETED_FROM:-}" ]; then
    info "${KEMORY_URL_RETARGETED_FROM} no longer serves the API — using the"
    info "current host instead. Where that value comes from still needs fixing:"
    # Two different setups reach the same dead host, and the remedy differs. Do
    # not tell someone with no CLI to re-run a CLI command.
    if [ -n "${KEMORY_URL:-}" ]; then
      info "KEMORY_URL is set — point it at https://api.kemory.s9n.ai"
    else
      info "it is stored in your credentials file — re-run 'kemory login'"
    fi
  fi
  if [ "${KEMORY_TOKEN_EXPIRED:-0}" = "1" ]; then
    bad "the stored token is expired and could not be refreshed"
    info "run /kemory:login again — until then every hook will be rejected"
  fi
else
  bad "no credential the hooks can use — every hook is inert"
  mcp_key="$(kemory_find_mcp_config_key)"
  if [ -n "$mcp_key" ]; then
    info "found an API key in $mcp_key, which the hooks cannot read"
    info "export that same key as KEMORY_API_KEY to turn the hooks on"
  else
    if command -v kemory >/dev/null 2>&1; then
      info "run /kemory:login (browser sign-in), or set KEMORY_API_KEY"
    else
      # /kemory:login ships with the plugin, so there is no longer a machine
      # where the best route has to be installed first.
      info "run /kemory:login (browser sign-in), or set KEMORY_API_KEY"
    fi
  fi
fi

# --- API reachability ------------------------------------------------------
if [ -n "${KEMORY_BASE_URL:-}" ] && command -v curl >/dev/null 2>&1; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 \
          -H "$KEMORY_AUTH_HEADER" "$KEMORY_BASE_URL/api/v1/namespaces" 2>/dev/null || echo 000)"
  api_code="$code"
  case "$code" in
    200)      ok  "API reachable and credentials accepted (HTTP 200)" ;;
    401|403)  bad "API reachable but rejected the credentials (HTTP $code)" ;;
    000)      bad "API unreachable — wrong URL, or the server is down" ;;
    # A redirect means the endpoint is not an API host — typically a
    # browser/SSO host, which answers every path with a login redirect. Naming
    # that is the difference between a fix and a mystery status code.
    3??)      bad "API redirected (HTTP $code) — that endpoint is not the API"
              info "a browser or SSO host cannot serve the API; re-run 'kemory login',"
              info "or set KEMORY_URL to your instance's API host" ;;
    *)        bad "API returned HTTP $code" ;;
  esac
fi

# --- MCP tools -------------------------------------------------------------
# Report what actually decides whether the tools appear, not a proxy for it.
# Until 0.4.0 this printed "kemory CLI on PATH — the bundled MCP server can
# start", which was left over from a stdio entry; under the http entry that
# replaced it the CLI was irrelevant, so the line said the tools were fine
# while the entry was dead. The bundled entry now launches scripts/mcp.sh,
# which resolves a credential the same way the hooks do — so the honest check
# is to resolve it here too and name who would serve.
echo
echo "TOOLS — the kemory_* MCP tools"

# Resolved here rather than at its own section below, because the skip report
# needs it: a stand-down is a deliberate exit 1, and a host that caches that
# as a failed launch would otherwise make us report our own correct behaviour
# as the host wrongly skipping us.
duplicate="$(kemory_find_duplicate_server)"
standing_down=0
[ -n "$duplicate" ] && [ "${KEMORY_ALLOW_DUPLICATE:-0}" != "1" ] && standing_down=1

# Everything below answers "could this server start". The host decides whether
# it is ALLOWED to, and after a connect timeout the answer is no for 15 minutes
# across every session on the machine. Ask that first, and downgrade the verb
# of every line under it: a tick saying the server "will start" beside a host
# that is refusing to launch it is the same lie, one layer up.
verb="will start"
serves="ok"
skipped=""
[ "$standing_down" -eq 0 ] && skipped="$(kemory_mcp_skipped_at)"
if [ -n "$skipped" ]; then
  skipped_key="${skipped%%	*}"
  skipped_at="${skipped##*	}"
  now="$(date +%s)"
  retry_at=$(( skipped_at + 900 ))
  when="$(date -r "$skipped_at" '+%H:%M:%S' 2>/dev/null \
          || date -d "@$skipped_at" '+%H:%M:%S' 2>/dev/null || echo "$skipped_at")"
  until_when="$(date -r "$retry_at" '+%H:%M:%S' 2>/dev/null \
          || date -d "@$retry_at" '+%H:%M:%S' 2>/dev/null || echo "$retry_at")"
  if [ "$now" -lt "$retry_at" ]; then
    # No green tick under a red cross: the credential really is fine, but
    # saying so with a ✔ next to a host that is refusing to launch the server
    # is how someone reads past the line that matters.
    verb="would start"
    serves="info"
    bad "Claude Code is SKIPPING this server — it cached a connect failure"
    info "'$skipped_key' failed at $when; the host retries by itself at $until_when"
    info "that cache is global, so the tools are off for EVERY session started in"
    info "that window — including this one, whose own launch may be fine"
    info "restart the session to retry sooner, or wait for $until_when"
  else
    # The window has passed, so the host will try again on the next launch.
    # Worth naming anyway: it explains a session that had no tools earlier.
    info "a connect failure for '$skipped_key' was cached at $when; that window"
    info "has passed, so the host retries on the next launch"
  fi
  info "the real error is under ~/Library/Caches/claude-cli-nodejs/, in a folder"
  info "named for the cwd of the session that FAILED — often another project"
fi

if [ -n "${KEMORY_BASE_URL:-}" ]; then
  if [ -n "${KEMORY_API_KEY:-}" ] || [ -n "${KEMORY_TOKEN:-}" ]; then
    if command -v python3 >/dev/null 2>&1; then
      "$serves" "bundled server $verb — credential from the environment"
    else
      bad "credential found, but python3 is missing and the CLI cannot read it"
      info "install python3, or run 'kemory login' to use the CLI's own bridge"
    fi
  elif command -v kemory >/dev/null 2>&1; then
    "$serves" "bundled server $verb — CLI credential, served by 'kemory mcp serve'"
  elif command -v python3 >/dev/null 2>&1; then
    "$serves" "bundled server $verb — CLI credential, served by the bundled bridge"
  else
    bad "credential found, but neither the kemory CLI nor python3 is available"
  fi
else
  bad "bundled server will not start — no credential (same one the hooks need)"
  info "it exits with that reason rather than appearing connected with no tools"
  info "using the claude.ai connector for tools? that is fine — disable this"
  info "server under /mcp so you are not running two"
fi

# The launcher stands down when another server already covers this same Kemory,
# so the status has to say the same thing -- a tick here beside a server that
# quietly declines to start is exactly the lie this section was fixed for once
# already. ($duplicate is resolved above, where the skip report needs it.)
if [ "$standing_down" -eq 1 ]; then
  info "…but it will stand down: '${duplicate%%	*}' in ${duplicate##*	} already"
  info "serves this same Kemory. Your hooks are unaffected. Remove that entry to"
  info "use this one instead, or set KEMORY_ALLOW_DUPLICATE=1 to run both."
elif [ -n "$duplicate" ]; then
  info "another server ('${duplicate%%	*}') covers this same Kemory, and"
  info "KEMORY_ALLOW_DUPLICATE=1 is set — you are deliberately running two"
fi

# Everything above predicts whether the server CAN start. Only the server knows
# whether it DID: each MCP handshake registers (or refreshes) a claude-code
# agent row, and that row is what the dashboard shows. Hooks writing captures
# while that row is missing is how a user ends up "set up" with no memory tools
# and an empty dashboard card. Asked with the same credential the
# hooks use; skipped for an API key, which authenticates as its own agent.
if [ "${api_code:-}" = "200" ] && [ "${KEMORY_AUTH_HEADER#Authorization:}" != "$KEMORY_AUTH_HEADER" ] \
   && command -v python3 >/dev/null 2>&1; then
  agents="$(curl -s --max-time 6 -H "$KEMORY_AUTH_HEADER" \
            "$KEMORY_BASE_URL/api/v1/agents?status=active&scope=mine" 2>/dev/null)"
  seen="$(printf '%s' "$agents" | python3 -c '
import json, sys
from datetime import datetime, timezone
try:
    rows = json.load(sys.stdin)
except Exception:
    print("unknown"); raise SystemExit
if not isinstance(rows, list):
    print("unknown"); raise SystemExit
last = None
for a in rows:
    if not isinstance(a, dict):
        continue
    if a.get("client_slug") != "claude-code" and a.get("agent_name") != "claude-code-agent":
        continue
    try:
        t = datetime.fromisoformat(str(a.get("last_active_at") or "").replace("Z", "+00:00"))
    except ValueError:
        continue
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    last = t if last is None or t > last else last
if last is None:
    print("never")
else:
    print(int((datetime.now(timezone.utc) - last).total_seconds() // 86400))
' 2>/dev/null)"
  case "$seen" in
    never)
      bad "the Kemory server has never seen the memory tools connect from Claude Code"
      info "so the kemory_* tools are missing and the dashboard shows Claude Code as"
      info "not connected, even though the hooks work."
      # Before 0.6.8 the CLI's bridge answered `initialize` itself and never
      # sent it upstream, so its tools worked and nothing ever registered.
      cli_version="$(kemory --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p')"
      if [ -n "$cli_version" ] && [ "$(printf '%s\n0.6.8\n' "$cli_version" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" != "0.6.8" ]; then
        info "kemory CLI $cli_version serves the tools, and versions before 0.6.8"
        info "never register with the server: run 'kemory upgrade', then restart"
        info "Claude Code fully"
      else
        info "Run /mcp: if kemory is failed or missing, restart Claude Code fully;"
        info "if it names another entry, that entry is the one to fix"
      fi ;;
    ''|unknown)
      info "could not ask the Kemory server whether the memory tools have connected" ;;
    *)
      if [ "$seen" -le 7 ] 2>/dev/null; then
        ok "the Kemory server has seen the memory tools connect from Claude Code"
      else
        bad "the memory tools last connected from Claude Code $seen days ago"
        info "run /mcp: if kemory is failed or missing, restart Claude Code fully"
      fi ;;
  esac
fi

# Entries for a DIFFERENT Kemory are deliberate multi-env work, not a fault, so
# they are counted rather than warned about. A claude.ai connector lives inside
# Claude and is invisible from a shell, which is why it is named here instead.
others=$(kemory_count_mcp_entries)
if [ "${others:-0}" -gt 0 ] && [ -z "$duplicate" ]; then
  if [ "$others" -eq 1 ]; then noun="entry"; else noun="entries"; fi
  info "$others other kemory MCP $noun on this machine, pointing elsewhere"
  info "if one of them is meant to be this Kemory, keep a single server"
fi
info "using the claude.ai connector as well? that cannot be seen from here —"
info "disable the bundled server under /mcp so you are not running two"
info "run /mcp to confirm which kemory server Claude is actually talking to"

# --- plugin version --------------------------------------------------------
manifest="$DIR/../.claude-plugin/plugin.json"
if [ -r "$manifest" ] && command -v python3 >/dev/null 2>&1; then
  installed=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version",""))' "$manifest" 2>/dev/null)
  [ -n "$installed" ] && info "plugin version $installed — '/plugin update kemory@kemory' to move it"
fi

# --- capture ---------------------------------------------------------------
echo
echo "SETTINGS"
if [ "${KEMORY_AUTO_CAPTURE:-0}" = "1" ]; then
  ok "session capture ENABLED — digests of your prompts are uploaded at session end"
  info "namespace: ${KEMORY_CAPTURE_NAMESPACE:-shared}, last ${KEMORY_CAPTURE_MAX_TURNS:-12} turns"
else
  info "session capture disabled (default) — set KEMORY_AUTO_CAPTURE=1 to enable"
fi
n=$(find "$HOME/.kemory/.captured" -type f 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -gt 0 ] && info "$n session(s) captured so far"

# --- context injection -----------------------------------------------------
if [ "${KEMORY_CONTEXT:-1}" = "1" ]; then
  info "context injection on (budget ${KEMORY_CONTEXT_MAX_CHARS:-4000} chars, depth ${KEMORY_CONTEXT_DEPTH:-l3})"
else
  info "context injection disabled via KEMORY_CONTEXT=0"
fi
exit 0
