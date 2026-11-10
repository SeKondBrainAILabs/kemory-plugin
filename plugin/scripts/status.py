"""The Python programs behind status.sh, one function each.

status.sh runs `python3 status.py <subcommand> [args]`. Each function is the
program status.sh used to pass to `python3 -c`, moved unchanged. They live in a
file because `python3 -c` puts the current directory first on sys.path, so a
json.py in a project root would run inside /kemory:status. Running a file puts
this directory there instead.

Each function reads the same environment, stdin and arguments as before, and
main() removes the subcommand from sys.argv before calling it, so sys.argv[1:]
holds exactly what the inline program received (the manifest path, for
manifest-version).
"""
import sys


def agent_last_seen():
    import json, sys
    from datetime import datetime, timezone
    try:
        rows = json.load(sys.stdin)
    except Exception:
        print("unknown"); raise SystemExit  # noqa: B904
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


def manifest_version():
    import json,sys;print(json.load(open(sys.argv[1])).get("version",""))


COMMANDS = {
    "agent-last-seen": agent_last_seen,
    "manifest-version": manifest_version,
}


def main():
    cmd = sys.argv.pop(1) if len(sys.argv) > 1 else ""
    func = COMMANDS.get(cmd)
    if func is None:
        raise SystemExit(1)
    func()


if __name__ == "__main__":
    main()
