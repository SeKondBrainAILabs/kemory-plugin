#!/usr/bin/env bash
# Shared credential resolution for Kemory hooks. Sourced, not executed.
#
# Sets, on success (return 0):
#   KEMORY_BASE_URL    — API base, no trailing slash
#   KEMORY_AUTH_HEADER — a complete header line to send
#   KEMORY_URL_RETARGETED_FROM — set only when a superseded host was rewritten
#
# Hosted Kemory authenticates with a bearer token; the community edition
# authenticates with X-API-Key only (backend/core/auth.py), so both are
# supported and detected rather than assumed.
# Hosted Kemory. Only override KEMORY_URL when pointing at a self-hosted or
# community instance, so the common case needs a key and nothing else.
KEMORY_DEFAULT_URL="${KEMORY_DEFAULT_URL:-https://api.kemory.s9n.ai}"

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
  local creds url token api_key
  url="" ; token="" ; api_key=""
  unset KEMORY_URL_RETARGETED_FROM

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
    # shellcheck disable=SC2016
    eval "$(KEMORY_CREDS="$creds" python3 -c '
import json, os, shlex, time

CREDS = os.environ["KEMORY_CREDS"]
try:
    d = json.load(open(CREDS))
except Exception:
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
    # Atomic, and 0600 -- this file holds a bearer token. Written beside the
    # original so the rename cannot cross a filesystem boundary.
    tmp = CREDS + ".tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(d, fh)
        os.replace(tmp, CREDS)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
        # The refreshed token is still good for this process even if the
        # write failed, so do not report failure.
    return True


exp = d.get("expires_at")
if d.get("access_token") and isinstance(exp, (int, float)):
    if time.time() > float(exp) - 60 and not refresh(d):
        expired = True

for var, key in (("url", "kemory_url"), ("token", "access_token"), ("api_key", "api_key")):
    v = d.get(key) or ""
    if v:
        print(f"{var}={shlex.quote(str(v))}")
if expired:
    print("KEMORY_TOKEN_EXPIRED=1")
' 2>/dev/null)"
  fi

  [ -n "$url" ] || return 1
  if [ -n "$api_key" ]; then
    KEMORY_AUTH_HEADER="X-API-Key: $api_key"
  elif [ -n "$token" ]; then
    KEMORY_AUTH_HEADER="Authorization: Bearer $token"
  else
    return 1
  fi
  kemory_retarget_url "${url%/}"
  KEMORY_BASE_URL="$KEMORY_RETARGETED_URL"
  export KEMORY_BASE_URL KEMORY_AUTH_HEADER KEMORY_URL_RETARGETED_FROM
  return 0
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
  python3 - "$@" <<'PY' 2>/dev/null
import json, os, sys

candidates = [
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".mcp.json"),
    os.path.expanduser("~/.claude.json"),
    os.path.expanduser("~/.mcp.json"),
    os.path.expanduser(
        "~/Library/Application Support/Claude/claude_desktop_config.json"),
]


def has_kemory_key(node):
    """True if any server entry looks like Kemory and carries a key."""
    if not isinstance(node, dict):
        return False
    for name, cfg in node.items():
        if not isinstance(cfg, dict):
            continue
        blob = json.dumps(cfg).lower()
        looks_kemory = "kemory" in str(name).lower() or "kemory" in blob
        has_key = any(
            k.lower() in ("x-api-key", "authorization")
            for k in (cfg.get("headers") or {})
        ) or "kemory_api_key" in blob
        if looks_kemory and has_key:
            return True
    return False


for path in candidates:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        continue
    servers = data.get("mcpServers") if isinstance(data, dict) else None
    if has_kemory_key(servers) or has_kemory_key(data):
        print(path)
        raise SystemExit(0)
    # Claude Code nests per-project config under "projects".
    for proj in (data.get("projects") or {}).values() if isinstance(data, dict) else []:
        if isinstance(proj, dict) and has_kemory_key(proj.get("mcpServers")):
            print(path)
            raise SystemExit(0)
raise SystemExit(1)
PY
}

# Count kemory MCP server entries sitting in MCP client configs on this machine.
#
# Two entries means every request carries two copies of the same tools. The
# most common way to get there is installing the plugin while a hand-written
# entry from the pre-plugin docs is still in place, and nothing surfaces it:
# /mcp lists them without saying they are the same server twice.
#
# Counts on-disk entries only. A claude.ai connector lives inside Claude and is
# invisible from a shell, so callers must name that case separately rather than
# reporting a reassuring zero.
#
# Echoes the count. The plugin's own bundled entry is not in these files.
kemory_count_mcp_entries() {
  command -v python3 >/dev/null 2>&1 || { echo 0; return 0; }
  python3 - <<'PY' 2>/dev/null || echo 0
import json, os

candidates = [
    os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()), ".mcp.json"),
    os.path.expanduser("~/.claude.json"),
    os.path.expanduser("~/.mcp.json"),
    os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json"),
]


def count(servers):
    if not isinstance(servers, dict):
        return 0
    n = 0
    for name, cfg in servers.items():
        blob = json.dumps(cfg).lower() if isinstance(cfg, dict) else ""
        if "kemory" in str(name).lower() or "kemory" in blob:
            n += 1
    return n


total = 0
for path in candidates:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    total += count(data.get("mcpServers"))
    for proj in (data.get("projects") or {}).values():
        if isinstance(proj, dict):
            total += count(proj.get("mcpServers"))
print(total)
PY
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
  KEMORY_MINE="$KEMORY_BASE_URL" python3 - <<'PY' 2>/dev/null
import json, os, shutil, urllib.parse

MINE = urllib.parse.urlparse(os.environ["KEMORY_MINE"]).netloc.lower()
if not MINE:
    raise SystemExit(0)

PROJECT = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
USER_CONFIG = os.path.expanduser("~/.claude.json")
candidates = [
    os.path.join(PROJECT, ".mcp.json"),
    USER_CONFIG,
]


def same_dir(a, b):
    try:
        return os.path.realpath(a) == os.path.realpath(b)
    except Exception:
        return False


def host_of(url):
    try:
        return urllib.parse.urlparse(url).netloc.lower()
    except Exception:
        return ""


def cli_host(args):
    """The endpoint `kemory [--env X] mcp serve` would forward to."""
    env = "prod"
    for i, a in enumerate(args):
        if a == "--env" and i + 1 < len(args):
            env = args[i + 1]
        elif a.startswith("--env="):
            env = a.split("=", 1)[1]
    for name in (f"credentials-{env}", "credentials"):
        try:
            with open(os.path.expanduser(f"~/.kemory/{name}")) as fh:
                return host_of(json.load(fh).get("kemory_url") or "")
        except Exception:
            continue
    return ""


def endpoint_of(cfg):
    if not isinstance(cfg, dict):
        return ""
    url = cfg.get("url")
    if isinstance(url, str) and url:
        return host_of(url)
    command = str(cfg.get("command") or "")
    args = [str(a) for a in (cfg.get("args") or [])]
    if os.path.basename(command) == "kemory" and "serve" in args:
        # The host launches this entry with the PATH it gave this process, so a
        # command we cannot find here cannot start there either. `kemory mcp
        # install` writes the bare name, and a desktop app's PATH lacks a
        # Homebrew prefix such as ~/homebrew/bin; yielding to that entry left
        # the session with no server at all.
        env = cfg.get("env") if isinstance(cfg.get("env"), dict) else {}
        if not shutil.which(command, path=env.get("PATH") or os.environ.get("PATH")):
            return ""
        return cli_host(args)
    return ""


def scan(servers, path):
    if not isinstance(servers, dict):
        return None
    for name, cfg in servers.items():
        blob = json.dumps(cfg).lower() if isinstance(cfg, dict) else ""
        if "kemory" not in str(name).lower() and "kemory" not in blob:
            continue
        if endpoint_of(cfg) == MINE:
            return name, path
    return None


for path in candidates:
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    hit = scan(data.get("mcpServers"), path)
    if not hit and path == USER_CONFIG:
        projects = data.get("projects")
        for key, proj in (projects.items() if isinstance(projects, dict) else ()):
            if isinstance(proj, dict) and same_dir(key, PROJECT):
                hit = scan(proj.get("mcpServers"), path)
                break
    if hit:
        print(f"{hit[0]}\t{hit[1]}")
        raise SystemExit(0)
PY
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
  python3 - <<'PY' 2>/dev/null
import json, os

path = os.path.expanduser("~/.claude/mcp-needs-auth-cache.json")
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(0)
if not isinstance(data, dict):
    raise SystemExit(0)

best = None
for key, entry in data.items():
    if "kemory" not in str(key).lower():
        continue
    if not isinstance(entry, dict):
        continue
    stamp = entry.get("timestamp")
    if not isinstance(stamp, (int, float)):
        continue
    # The host writes milliseconds. Guard the units rather than trusting them:
    # a seconds-valued entry read as milliseconds dates to 1970 and would be
    # reported as an ancient failure instead of a current one.
    secs = stamp / 1000.0 if stamp > 1e11 else float(stamp)
    if best is None or secs > best[1]:
        best = (str(key), secs)

if best is not None:
    print(f"{best[0]}\t{int(best[1])}")
PY
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
  KEMORY_LOG_KEY="${1:-}" python3 - <<'PY' 2>/dev/null
import glob, os

key = os.environ.get("KEMORY_LOG_KEY", "")
if not key:
    raise SystemExit(0)

# The host slugifies the cache key into the directory name.
slug = "".join(c if c.isalnum() else "-" for c in key)

roots = [
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    os.path.expanduser("~/Library/Caches"),
]

best = None
for root in roots:
    for path in glob.glob(os.path.join(root, "claude-cli-nodejs", "*", f"mcp-logs-{slug}")):
        if not os.path.isdir(path):
            continue
        try:
            when = os.path.getmtime(path)
        except OSError:
            continue
        if best is None or when > best[1]:
            best = (path, when)

if best is not None:
    print(best[0])
PY
}
