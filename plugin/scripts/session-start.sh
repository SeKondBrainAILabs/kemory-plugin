#!/usr/bin/env bash
# SessionStart hook — inject the standing instruction and the user's Kemory
# memory summaries, so a session begins already knowing their preferences and
# project context instead of starting blind and hoping the agent calls recall.
#
# The instruction ships WITH the plugin rather than being pasted into
# CLAUDE.md: a rules file is per-machine or per-repo, drifts from the docs the
# day either changes, and a new project silently starts without it. Injected
# here it is unconditional, versioned, and updated by `/plugin update`.
#
# Also acts as a preflight: if Kemory is not usable yet, say so once, with the
# exact command to fix it, rather than failing silently in /mcp.
#
# Best-effort by design: any failure emits nothing and exits 0.
set -uo pipefail
[ "${KEMORY_CONTEXT:-1}" = "1" ] || exit 0

# The hook payload carries `source`: startup | resume | clear | compact.
# "compact" is the only channel that can nudge consolidation -- PreCompact
# itself rejects hookSpecificOutput.additionalContext outright, and runs as
# compaction begins, so the model would get no turn to act on it anyway.
PAYLOAD="$(cat 2>/dev/null || true)"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

# Deliberately short. The long standing instruction in the docs is long
# because it is compensating for the absence of mechanisms: recall it cannot
# trigger, a write it cannot enforce. Those are hooks now (prompt-recall.sh,
# store-nudge.sh), so this says only what no hook can say — what Kemory is,
# and the standard for writing to it.
read -r -d '' KEMORY_INSTRUCTION <<'TXT'
Kemory is this user's persistent memory, shared across their AIs and sessions.
- Check it before answering anything about their work, their decisions, or
  past sessions, and again when the topic shifts.
- Write the moment they state a preference, a decision is reached, or you
  learn something non-obvious. Do not ask whether to save it — save it, then
  say in one line what you stored and where.
- Where: personal ways of working in a user-scoped namespace, project facts
  in a shared one. Call kemory_list_namespaces and reuse what is already
  there rather than inventing a near-duplicate.
- Write in the words the thing would be searched for later: identifiers,
  error strings and names you actually used, not a paraphrase.
TXT
export KEMORY_INSTRUCTION

# Emit the instruction on its own, for every path that returns before the
# summaries are built: no credential, no curl, an unreachable API, an empty
# vault. Those are exactly the sessions of a new user, who needs it most.
emit_instruction_only() {
  python3 -c 'import json, os
out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": os.environ["KEMORY_INSTRUCTION"]}}
if os.environ.get("KEMORY_NOTICE"):
    out["systemMessage"] = os.environ["KEMORY_NOTICE"]
print(json.dumps(out))' 2>/dev/null
}

# The docs told people to paste a standing instruction into CLAUDE.md long
# before the plugin shipped one. Both is not harmful, but the pasted copy
# tells the agent to open each session with list_namespaces + recall — work
# prompt-recall.sh has already done by then, so it costs two tool calls a
# session to repeat it. Say so once; never edit their file.
KEMORY_PASTE_MARKS='Kemory memory tools|kemory_list_namespaces|Kemory is my long-term memory'

find_pasted_instruction() {
  [ "${KEMORY_QUIET_SETUP:-0}" = "1" ] && return 0
  command -v grep >/dev/null 2>&1 || return 0

  local stamp="$HOME/.kemory/.paste-hint" found=""
  if [ -f "$stamp" ]; then
    local now age
    now=$(date +%s)
    age=$(( now - $(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo "$now") ))
    [ "$age" -lt 604800 ] && return 0   # a week; this is housekeeping, not a fault
  fi

  local cwd f
  cwd="$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("cwd") or ""))' 2>/dev/null)"
  for f in "$HOME/.claude/CLAUDE.md" "${cwd:+$cwd/CLAUDE.md}"; do
    if [ -z "$f" ] || [ ! -r "$f" ]; then continue; fi
    if grep -qE "$KEMORY_PASTE_MARKS" "$f" 2>/dev/null; then found="$f"; break; fi
  done
  [ -n "$found" ] || return 0

  mkdir -p "$(dirname "$stamp")" 2>/dev/null && touch "$stamp" 2>/dev/null
  printf '%s' "$found"
}

# Set once, read by every emitter below: the file holding a hand-pasted copy
# of the instruction, or empty.
KEMORY_PASTED_AT="$(find_pasted_instruction)"
export KEMORY_PASTED_AT
KEMORY_PASTE_NOTICE="Kemory plugin: $KEMORY_PASTED_AT still contains a pasted memory instruction. The plugin now ships one, and the pasted copy asks the agent to open every session with list_namespaces + recall — which the prompt-recall hook has already done by then. Removing it saves two tool calls a session. Silence this with KEMORY_QUIET_SETUP=1."
export KEMORY_PASTE_NOTICE

# Plugins do not update themselves, and nothing tells anyone their install is
# behind. A 0.1.3 install ran for two weeks and three releases without the
# prompt-recall hook, which is the plugin's main mechanism — it looked healthy
# the whole time, because /kemory:status reported on the version it was rather
# than the version there was.
#
# Compares against the marketplace clone Claude Code keeps on disk. NOT a
# network call: PRIVACY.md promises this plugin adds "no third-party endpoint
# of its own", and asking GitHub for a version number would break that for a
# convenience. The trade is that a marketplace clone which has not been
# refreshed reads as up to date and says nothing — a silence that resolves
# itself the next time anything refreshes it, which is the right direction for
# a check like this to fail.
#
# Echoes "<installed> <available>" when behind, nothing otherwise.
find_stale_version() {
  [ "${KEMORY_QUIET_SETUP:-0}" = "1" ] && return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local stamp="$HOME/.kemory/.version-hint"
  if [ -f "$stamp" ]; then
    local now age
    now=$(date +%s)
    age=$(( now - $(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo "$now") ))
    [ "$age" -lt 86400 ] && return 0
  fi

  local answer
  answer="$(KEMORY_MANIFEST="$DIR/../.claude-plugin/plugin.json" python3 -c '
import glob, json, os, re


def parts(v):
    """Compare numerically, so 0.10.0 sorts above 0.9.0."""
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", str(v or ""))
    return tuple(int(g) for g in m.groups()) if m else None


try:
    installed = json.load(open(os.environ["KEMORY_MANIFEST"]))["version"]
except Exception:
    raise SystemExit(0)

here = parts(installed)
if here is None:
    raise SystemExit(0)

# Whichever marketplace carries this plugin; a user may have added it under
# any name, so match on the plugin rather than the directory.
best = None
for path in glob.glob(os.path.expanduser(
        "~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json")):
    try:
        entries = json.load(open(path)).get("plugins") or []
    except Exception:
        continue
    for entry in entries:
        if entry.get("name") != "kemory":
            continue
        there = parts(entry.get("version"))
        if there and (best is None or there > best):
            best = there

if best is not None and best > here:
    print(installed, ".".join(str(n) for n in best))
' 2>/dev/null)"

  [ -n "$answer" ] || return 0
  mkdir -p "$(dirname "$stamp")" 2>/dev/null && touch "$stamp" 2>/dev/null
  printf '%s' "$answer"
}

KEMORY_VERSION_NOTICE=""
KEMORY_STALE="$(find_stale_version)"
if [ -n "$KEMORY_STALE" ]; then
  KEMORY_VERSION_NOTICE="Kemory plugin: version ${KEMORY_STALE%% *} installed, ${KEMORY_STALE##* } available. Hooks are where this plugin's behaviour lives, so an old install quietly runs old behaviour. Update with /plugin update kemory@kemory, then restart. Silence this with KEMORY_QUIET_SETUP=1."
fi

# Session capture became the default in 0.8.0. An install that predates it was
# not capturing and, after an update, silently would be — so say it once, to
# whoever never made the choice themselves. Someone who has set
# KEMORY_AUTO_CAPTURE either way already knows; they are told nothing.
#
# The stamp is permanent, not throttled: this is one piece of news, not a nag.
capture_default_notice() {
  [ "${KEMORY_QUIET_SETUP:-0}" = "1" ] && return 0
  # Explicitly set, either way? Then it is their decision, not our default.
  [ -n "${KEMORY_AUTO_CAPTURE:-}" ] && return 0

  local stamp="$HOME/.kemory/.capture-default"
  [ -f "$stamp" ] && return 0
  mkdir -p "$(dirname "$stamp")" 2>/dev/null && touch "$stamp" 2>/dev/null

  printf '%s' "Kemory plugin: session capture is on by default from 0.8.0. At the end of a session it stores a redacted digest of your own prompts — last 12 turns, 8000 characters — in your vault. Turn it off with KEMORY_AUTO_CAPTURE=0; see PRIVACY.md for exactly what is sent. This is said once."
}

KEMORY_CAPTURE_NOTICE="$(capture_default_notice)"

# One systemMessage slot, so anything with something to say shares it.
KEMORY_NOTICE=""
if [ -n "$KEMORY_PASTED_AT" ]; then
  KEMORY_NOTICE="$KEMORY_PASTE_NOTICE"
fi
if [ -n "$KEMORY_VERSION_NOTICE" ]; then
  if [ -n "$KEMORY_NOTICE" ]; then
    KEMORY_NOTICE="$KEMORY_NOTICE

$KEMORY_VERSION_NOTICE"
  else
    KEMORY_NOTICE="$KEMORY_VERSION_NOTICE"
  fi
fi
if [ -n "$KEMORY_CAPTURE_NOTICE" ]; then
  if [ -n "$KEMORY_NOTICE" ]; then
    KEMORY_NOTICE="$KEMORY_NOTICE

$KEMORY_CAPTURE_NOTICE"
  else
    KEMORY_NOTICE="$KEMORY_CAPTURE_NOTICE"
  fi
fi
export KEMORY_VERSION_NOTICE KEMORY_CAPTURE_NOTICE KEMORY_NOTICE


emit_setup_hint() {
  [ "${KEMORY_QUIET_SETUP:-0}" = "1" ] && exit 0
  local stamp="$HOME/.kemory/.setup-hint"
  # Nag at most once a day so a deliberate connector-only setup is not spammed.
  if [ -f "$stamp" ]; then
    local now age
    now=$(date +%s)
    age=$(( now - $(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo "$now") ))
    [ "$age" -lt 86400 ] && exit 0
  fi
  mkdir -p "$(dirname "$stamp")" 2>/dev/null && touch "$stamp" 2>/dev/null

  # Never claim "nothing is configured": the MCP tools authenticate
  # separately and are very often already working when this fires. Say what
  # is actually true -- the hooks have no credential of their own -- and if a
  # key is sitting in an MCP config, name that file, because following our
  # own docs is the most likely way to arrive here.
  local found msg
  found="$(kemory_find_mcp_config_key)"
  if [ -n "$found" ]; then
    msg="Kemory plugin: found an API key in $found, which the hooks cannot read \u2014 they take a credential from the environment or the CLI, not from MCP config. Your memory tools are unaffected. To turn the hooks on, export KEMORY_API_KEY with that same key."
  else
    # One answer, whatever the machine has. This used to branch on whether the
    # kemory CLI was installed, because naming a command the user cannot run is
    # worse than naming none -- and the branch without it could only offer a
    # long-lived key pasted into a shell profile. /kemory:login ships with the
    # plugin, so there is now a route that is always available and always the
    # best one.
    msg="Kemory plugin: the hooks have no credential, so context injection, prompt recall, rating and capture are off. Your MCP memory tools may already be working \u2014 they authenticate separately. Run /kemory:login to sign in with your browser; nothing to install, nothing to paste."
  fi
  # A stale install is worth saying even here. Someone who gets their tools
  # from the connector has no hook credential on purpose, reaches this branch
  # every day, and would otherwise be the one population that never hears its
  # plugin is behind — which is exactly who the old bundled entry stranded.
  KEMORY_MSG="$msg" KEMORY_VERSION_NOTICE="$KEMORY_VERSION_NOTICE" python3 -c 'import json, os; print(json.dumps({"systemMessage": " ".join(p for p in (os.environ["KEMORY_MSG"].encode().decode("unicode_escape") + " Silence this with KEMORY_QUIET_SETUP=1.", os.environ.get("KEMORY_VERSION_NOTICE", "")) if p), "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": os.environ["KEMORY_INSTRUCTION"]}}))' 2>/dev/null \
    || printf '%s\n' '{"systemMessage":"Kemory plugin: the hooks have no credential, so context injection, recall, rating and capture are off. Run kemory login, or export KEMORY_API_KEY. Silence this with KEMORY_QUIET_SETUP=1."}'
  exit 0
}

kemory_resolve_auth || emit_setup_hint

# Say so when the host has switched our tools off for this session.
#
# Claude Code caches a connect failure in ~/.claude/mcp-needs-auth-cache.json
# and skips the server for 15 minutes. That cache is GLOBAL: one slow launch in
# one project silently removes the kemory_* tools from every session started
# afterwards, and the only trace is a line in /mcp the user is not reading. The
# agent then works the whole session believing it has no memory tools, or worse,
# that the user has none.
#
# Deliberately NOT throttled by a sentinel the way the paste and version
# notices are. Those nag about durable config that will still be there
# tomorrow, so once a day is right. This reports a transient fault that is
# true RIGHT NOW and gone in fifteen minutes: every session inside the window
# genuinely has no tools, so every one of them needs telling, and a 24h
# sentinel would inform the first and leave the rest guessing — the exact
# confusion this exists to remove.
#
# Runs after resolve_auth on purpose. With no credential the bundled server
# would not start for that reason instead, and emit_setup_hint above already
# says so; adding this would answer the wrong question.
KEMORY_SKIPPED_NOTICE=""
skipped="$(kemory_mcp_skipped_at)"
if [ -n "$skipped" ]; then
  skipped_at="${skipped##*	}"
  retry_at=$(( skipped_at + 900 ))
  # Only while the window is open. Past it the host retries on the next launch,
  # so a notice would describe a fault that has already cleared.
  if [ "$(date +%s)" -lt "$retry_at" ]; then
    # A stand-down is a deliberate exit 1. If the host caches that as a failed
    # launch, reporting it would turn our own correct behaviour into an alarm.
    # Checked second because it costs a subprocess and most sessions skip it.
    duplicate="$(kemory_find_duplicate_server)"
    if [ -z "$duplicate" ] || [ "${KEMORY_ALLOW_DUPLICATE:-0}" = "1" ]; then
      until_when="$(date -r "$retry_at" '+%H:%M' 2>/dev/null \
                    || date -d "@$retry_at" '+%H:%M' 2>/dev/null || echo "$retry_at")"
      KEMORY_SKIPPED_NOTICE="Kemory plugin: Claude Code is SKIPPING the kemory MCP server in this session — it cached a connect failure and retries at $until_when. That cache is shared by every session on this machine, so the failure may have come from an unrelated project. The kemory_* tools are unavailable until then; your hooks are unaffected, so context injection, recall and capture still work. Restart the session after $until_when to get the tools back, or run /kemory:status for detail."
      if [ -n "$KEMORY_NOTICE" ]; then
        KEMORY_NOTICE="$KEMORY_SKIPPED_NOTICE

$KEMORY_NOTICE"
      else
        KEMORY_NOTICE="$KEMORY_SKIPPED_NOTICE"
      fi
      export KEMORY_NOTICE
    fi
  fi
fi

command -v curl >/dev/null 2>&1 || { emit_instruction_only; exit 0; }

DEPTH="${KEMORY_CONTEXT_DEPTH:-l3}"
RESP="$(curl -s --max-time "${KEMORY_CONTEXT_TIMEOUT:-6}" \
  -H "$KEMORY_AUTH_HEADER" \
  "$KEMORY_BASE_URL/api/v1/user/context?depth=$DEPTH" 2>/dev/null)" \
  || { emit_instruction_only; exit 0; }
[ -n "$RESP" ] || { emit_instruction_only; exit 0; }

command -v python3 >/dev/null 2>&1 || exit 0
KEMORY_RESP="$RESP" \
KEMORY_PAYLOAD="$PAYLOAD" \
KEMORY_INSTRUCTION="$KEMORY_INSTRUCTION" \
KEMORY_PASTED_AT="$KEMORY_PASTED_AT" \
KEMORY_NOTICE="$KEMORY_NOTICE" \
KEMORY_MAX_CHARS="${KEMORY_CONTEXT_MAX_CHARS:-4000}" \
KEMORY_NAMESPACES="${KEMORY_CONTEXT_NAMESPACES:-}" \
python3 <<'PY' 2>/dev/null
import json, os, sys

INSTRUCTION = os.environ.get("KEMORY_INSTRUCTION", "").strip()


def emit(context):
    """Print one SessionStart payload. The instruction always leads it.

    Every exit below used to be `sys.exit(0)`, which meant a user with an
    empty vault, a stale token or an unreachable API got no instruction at
    all — the sessions where it matters most.
    """
    body = "\n\n".join(p for p in (INSTRUCTION, context) if p)
    if body:
        out = {"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": body,
        }}
        # Housekeeping, not a fault: the user has a working setup and one
        # redundant file. Throttled to weekly by the caller.
        if os.environ.get("KEMORY_NOTICE"):
            out["systemMessage"] = os.environ["KEMORY_NOTICE"]
        print(json.dumps(out))
    raise SystemExit(0)


try:
    data = json.loads(os.environ["KEMORY_RESP"])
except Exception:
    emit("")

try:
    source = (json.loads(os.environ.get("KEMORY_PAYLOAD") or "{}")
              .get("source") or "")
except Exception:
    source = ""
compacted = source == "compact"

CONSOLIDATE = (
    "This session was just compacted. Anything established before the "
    "compaction now exists only as a summary. If this session produced "
    "durable facts, decisions or solved problems that are not in kemory "
    "yet, store them now with kemory_consolidate_session (or "
    "kemory_store_memory for individual facts) before continuing."
)

namespaces = data.get("namespaces")
if not isinstance(namespaces, list):
    # Not the expected shape — most likely an auth error body. No summaries to
    # show, but the instruction still stands, and so does the compaction nudge.
    emit(CONSOLIDATE if compacted else "")

wanted = {n.strip() for n in os.environ["KEMORY_NAMESPACES"].split(",") if n.strip()}
lines = []
for ns in namespaces:
    ns = ns or {}
    summary = (ns.get("summary") or "").strip()
    name = ns.get("namespace")
    if not summary:
        continue
    if wanted and name not in wanted:
        continue
    lines.append(f"- [{name}] {summary}")

if not lines:
    # An empty vault is a new user. They get the instruction, which is the
    # whole reason they would ever have something to summarise later.
    emit(CONSOLIDATE if compacted else "")

budget = max(500, int(os.environ["KEMORY_MAX_CHARS"]))
body, used, truncated = [], 0, False
for line in lines:
    if used + len(line) > budget:
        truncated = True
        break
    body.append(line)
    used += len(line)
if not body:
    emit(CONSOLIDATE if compacted else "")

context = (
    "Your Kemory memory (persistent across sessions) — namespace summaries:\n"
    + "\n".join(body)
)
if truncated:
    context += (
        f"\n\n({len(lines) - len(body)} more namespace summaries omitted to stay "
        "within the context budget; raise KEMORY_CONTEXT_MAX_CHARS to include them.)"
    )
if compacted:
    context += "\n\n" + CONSOLIDATE
context += (
    "\n\nRecall details with kemory_recall_memory / kemory_get_context before "
    "re-deriving anything, and rate what you use with kemory_rate_memory."
)

emit(context)
PY
exit 0
