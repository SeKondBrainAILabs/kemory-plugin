#!/usr/bin/env bash
# Stop + PreCompact + SessionEnd hook — capture the session into Kemory as episodic memories
# tagged with session_id, so the server-side Reflector can consolidate them into
# a semantic summary later.
#
# Runs on Stop (after each assistant response) so a session that is killed,
# crashes, or is never cleanly ended still leaves its work behind. PreCompact
# flushes whatever is pending before /compact (manual or auto) summarises the
# context away, and SessionEnd flushes whatever is left at the end.
#
# PreCompact can block compaction (exit 2, or "decision": "block" on stdout),
# so this script must print nothing and exit 0 on every path, which it already
# does for Stop and SessionEnd.
#
# Only NEW turns are posted. Kemory's community edition has no idempotency
# support, so a client-side high-water mark is the only thing preventing the
# same turns being stored over and over as overlapping memories.
#
# ON BY DEFAULT, OPT-OUT. Capture uploads conversation content to your Kemory
# instance. A memory plugin that remembers nothing unless you first find a flag
# is not doing its job, so this runs unless you set KEMORY_AUTO_CAPTURE=0.
#
# Best-effort by design: any failure exits 0 so a session is never blocked.
set -uo pipefail

[ "${KEMORY_AUTO_CAPTURE:-1}" = "1" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"
# Resolves hosted (bearer) or community (X-API-Key) auth, from the CLI's
# credential file or from environment variables.
kemory_resolve_auth || exit 0

HOOK_INPUT="$(cat)"
export HOOK_INPUT
export KEMORY_SCRIPT_DIR="$DIR"
# Importing redact.py must not litter the user's plugin directory.
export PYTHONDONTWRITEBYTECODE=1
# Session digests are the most incidentally-revealing thing this plugin
# handles — half-formed debugging, client names, things typed before thinking.
# Now that capture is on by default they land somewhere private by default too,
# not in `shared`, whose name reads as team-visible to every engineer who sees
# it. Set KEMORY_CAPTURE_NAMESPACE to put them somewhere else deliberately.
export KEMORY_NAMESPACE="${KEMORY_CAPTURE_NAMESPACE:-$KEMORY_DEFAULT_CAPTURE_NAMESPACE}"
export KEMORY_MAX_TURNS="${KEMORY_CAPTURE_MAX_TURNS:-12}"
export KEMORY_MIN_NEW_TURNS="${KEMORY_CAPTURE_MIN_NEW_TURNS:-3}"
export KEMORY_CAPTURE_SOURCE="${KEMORY_CAPTURE_SOURCE:-claude-code}"

python3 "$DIR/capture.py" 2>/dev/null
exit 0
