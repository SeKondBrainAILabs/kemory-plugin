"""The Python programs behind lib.sh's helpers, one function each.

lib.sh runs `python3 kemory_lib.py <subcommand> [args]`. Each function is the
program lib.sh used to pass to `python3 -c` or a heredoc, moved unchanged. They
live in a file because `python3 -c` and `python3 -` put the current directory
first on sys.path, so a json.py in a project root would run inside every hook.
Running a file puts this directory there instead.

Each function reads the same environment, stdin and arguments as before, and
main() removes the subcommand from sys.argv before calling it, so sys.argv[1:]
holds exactly what the inline program received.
"""
import sys


def active_org():
    import json
    import sys
    raw = sys.stdin.read().strip()
    try:
        data = json.loads(raw)
    except ValueError:
        # An SSE reply: the last data line carries the result.
        lines = [ln[5:].strip() for ln in raw.splitlines() if ln.startswith("data:")]
        try:
            data = json.loads(lines[-1])
        except Exception:
            raise SystemExit(0)  # noqa: B904
    sc = ((data.get("result") or {}).get("structuredContent") or {}) if isinstance(data, dict) else {}
    name, org = sc.get("org_name"), sc.get("org_id")
    if isinstance(name, str) and name.strip():
        print(name.strip() + "\t" + str(org or ""))


def find_mcp_config_key():
    import json
    import os
    import sys  # noqa: F401

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


def count_mcp_entries():
    import json
    import os

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


def connector_ever_connected():
    import json
    import os

    try:
        with open(os.path.expanduser("~/.claude.json")) as fh:
            data = json.load(fh)
    except Exception:
        raise SystemExit(0)  # noqa: B904
    if not isinstance(data, dict):
        raise SystemExit(0)
    entries = data.get("claudeAiMcpEverConnected")
    if "claudeAiMcpEverConnected" not in data:
        print("never")
    elif isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, str) and "kemory" in entry.lower():
                print("seen\t" + entry)
                raise SystemExit(0)
        print("never")


def find_duplicate_server():
    import json
    import os
    import shutil
    import urllib.parse

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


def mcp_skipped_at():
    import json
    import os

    path = os.path.expanduser("~/.claude/mcp-needs-auth-cache.json")
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        raise SystemExit(0)  # noqa: B904
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


def grok_disabled_server():
    import os
    import re

    path = os.path.expanduser("~/.grok/config.toml")
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except Exception:
        raise SystemExit(0)  # noqa: B904

    names = None
    try:
        import tomllib  # Python 3.11+
    except ImportError:
        tomllib = None

    if tomllib is not None:
        try:
            names = tomllib.loads(raw.decode("utf-8")).get("disabled_mcp_servers")
        except Exception:
            raise SystemExit(0)  # noqa: B904
    else:
        # Older Python: read just the top-level key. In TOML that means before the
        # first table header, so search only that prefix: the same key under a
        # table, such as [cli], is a different key and Grok would not act on it.
        # Anything stranger than a flat list of strings is left unreported rather
        # than guessed at.
        top = re.split(rb'(?m)^\s*\[', raw, maxsplit=1)[0]
        m = re.search(rb'(?m)^disabled_mcp_servers\s*=\s*\[([^\]]*)\]', top)
        if m:
            pairs = re.findall(r'"([^"]*)"|\'([^\']*)\'', m.group(1).decode("utf-8", "replace"))
            names = [a or b for a, b in pairs]

    if not isinstance(names, list):
        raise SystemExit(0)
    for name in names:
        if isinstance(name, str) and (name == "kemory" or name.endswith(":kemory")):
            print(name)
            break


def mcp_log_dir():
    import glob
    import os

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


COMMANDS = {
    "active-org": active_org,
    "find-mcp-config-key": find_mcp_config_key,
    "count-mcp-entries": count_mcp_entries,
    "connector-ever-connected": connector_ever_connected,
    "find-duplicate-server": find_duplicate_server,
    "mcp-skipped-at": mcp_skipped_at,
    "grok-disabled-server": grok_disabled_server,
    "mcp-log-dir": mcp_log_dir,
}


def main():
    cmd = sys.argv.pop(1) if len(sys.argv) > 1 else ""
    func = COMMANDS.get(cmd)
    if func is None:
        raise SystemExit(1)
    func()


if __name__ == "__main__":
    main()
