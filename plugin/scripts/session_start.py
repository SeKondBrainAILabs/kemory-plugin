"""The Python programs behind session-start.sh, one function each.

session-start.sh runs `python3 session_start.py <subcommand>`. Each function is
the program session-start.sh used to pass to `python3 -c` or a heredoc, moved
unchanged. They live in a file because `python3 -c` and `python3 -` put the
current directory first on sys.path, so a json.py in a project root would run
inside every SessionStart hook. Running a file puts this directory there instead.

Each function reads the same environment and stdin as before, and main() removes
the subcommand from sys.argv before calling it, so sys.argv[1:] holds exactly
what the inline program received.
"""
import sys


def instruction_only():
    import json, os
    out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": os.environ["KEMORY_INSTRUCTION"]}}
    if os.environ.get("KEMORY_NOTICE"):
        out["systemMessage"] = os.environ["KEMORY_NOTICE"]
    print(json.dumps(out))


def payload_cwd():
    import json,sys; print((json.load(sys.stdin).get("cwd") or ""))


def stale_version():
    import glob, json, os, re


    def parts(v):
        """Compare numerically, so 0.10.0 sorts above 0.9.0."""
        m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", str(v or ""))
        return tuple(int(g) for g in m.groups()) if m else None


    try:
        installed = json.load(open(os.environ["KEMORY_MANIFEST"]))["version"]
    except Exception:
        raise SystemExit(0)  # noqa: B904

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


def setup_hint():
    import json, os; print(json.dumps({"systemMessage": " ".join(p for p in (os.environ["KEMORY_MSG"].encode().decode("unicode_escape") + " Silence this with KEMORY_QUIET_SETUP=1.", os.environ.get("KEMORY_VERSION_NOTICE", "")) if p), "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": os.environ["KEMORY_INSTRUCTION"]}}))


def auth_fault():
    import json, os
    msg = os.environ["KEMORY_MSG"]
    if os.environ.get("KEMORY_NOTICE"):
        msg += "\n\n" + os.environ["KEMORY_NOTICE"]
    print(json.dumps({"systemMessage": msg, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": os.environ["KEMORY_INSTRUCTION"]}}))


def context():
    import json, os, sys  # noqa: F401

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


COMMANDS = {
    "instruction-only": instruction_only,
    "payload-cwd": payload_cwd,
    "stale-version": stale_version,
    "setup-hint": setup_hint,
    "auth-fault": auth_fault,
    "context": context,
}


def main():
    cmd = sys.argv.pop(1) if len(sys.argv) > 1 else ""
    func = COMMANDS.get(cmd)
    if func is None:
        raise SystemExit(1)
    func()


if __name__ == "__main__":
    main()
