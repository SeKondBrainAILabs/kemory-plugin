#!/usr/bin/env python3
"""Line-coverage report for plugin/scripts/*.sh from bash xtrace files.

Usage: python3 scripts/sh_coverage.py <trace_dir> [<repo_root>]

sh_coverage_env.sh writes lines like "+@SHCOV@path/to/x.sh:42: cmd" to
<trace_dir>/<pid>.trace. A hit counts when the path's basename is a file in
<repo_root>/plugin/scripts, so copies of the plugin in temp dirs are included.
Executable lines are estimated from the source, so the percentages are
approximate. Always exits 0.
"""
import pathlib
import re
import sys

MARKER = "@SHCOV@"
TRACE_LINE = re.compile(r"^\++" + re.escape(MARKER) + r"(.+):(\d+): ")
HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(?:'([^']+)'|\"([^\"]+)\"|\\?([A-Za-z_][A-Za-z0-9_]*))")
STRUCTURE_ONLY = re.compile(r"^(?:then|else|fi|do|done|esac|\{|\}|;;|\)|\s)+$")
FUNCTION_HEADER = re.compile(
    r"^(?:function\s+[\w:.-]+(?:\s*\(\))?|[\w:.-]+\s*\(\))\s*\{?$")
# "start)" or "a|b)": a case pattern with no command, never traced.
CASE_PATTERN = re.compile(r"^\(?[^\s()]+(?:\s*\|\s*[^\s()]+)*\)$")
CONTINUES = ("\\", "|", "&&", "||")


def executable_lines(text):
    """Line numbers that look like they run a command."""
    lines = set()
    heredoc_end = None
    continued = False
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if heredoc_end is not None:
            if line == heredoc_end:
                heredoc_end = None
            continue
        was_continued = continued
        continued = line.endswith(CONTINUES) and not line.startswith("#")
        if was_continued or not line or line.startswith("#"):
            continue
        if (STRUCTURE_ONLY.match(line) or FUNCTION_HEADER.match(line)
                or CASE_PATTERN.match(line)):
            continue
        lines.add(number)
        found = HEREDOC.search(line)
        if found:
            heredoc_end = next(g for g in found.groups() if g)
    return lines


def read_hits(trace_dir, names):
    """{script name: set of line numbers} for traced lines in known scripts."""
    hits = {name: set() for name in names}
    for path in sorted(pathlib.Path(trace_dir).glob("*.trace")):
        try:
            handle = path.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with handle:
            for raw in handle:
                if MARKER not in raw:
                    continue
                found = TRACE_LINE.match(raw)
                if not found:
                    continue
                name = found.group(1).rsplit("/", 1)[-1]
                if name in hits:
                    hits[name].add(int(found.group(2)))
    return hits


def ranges(numbers):
    """[12, 13, 14, 15, 40] -> "12-15, 40"."""
    out = []
    start = prev = None
    for n in sorted(numbers):
        if start is None:
            start = prev = n
        elif n == prev + 1:
            prev = n
        else:
            out.append((start, prev))
            start = prev = n
    if start is not None:
        out.append((start, prev))
    return ", ".join(str(a) if a == b else f"{a}-{b}" for a, b in out)


def percent(hit, total):
    return 100 if total == 0 else int(100 * hit / total + 0.5)


def report(trace_dir, repo_root):
    scripts = sorted(pathlib.Path(repo_root, "plugin", "scripts").glob("*.sh"))
    hits = read_hits(trace_dir, [p.name for p in scripts])
    rows = []
    for path in scripts:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        hit = hits[path.name]
        executable = executable_lines(text) | hit
        rows.append((path.name, len(executable), len(hit), ranges(executable - hit)))
    width = max([len(r[0]) for r in rows] + [len("TOTAL")])
    out = ["Bash line coverage for plugin/scripts/*.sh "
           "(executable-line count is a heuristic)",
           f"{'File':<{width}}  {'Lines':>5}  {'Hit':>5}  {'Cover':>5}  Missing"]
    for name, total, hit, missing in rows:
        out.append(f"{name:<{width}}  {total:>5}  {hit:>5}  "
                   f"{percent(hit, total):>4}%  {missing}".rstrip())
    total = sum(r[1] for r in rows)
    hit = sum(r[2] for r in rows)
    out.append(f"{'TOTAL':<{width}}  {total:>5}  {hit:>5}  {percent(hit, total):>4}%")
    return "\n".join(out)


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 0
    root = argv[1] if len(argv) > 1 else str(pathlib.Path(__file__).resolve().parent.parent)
    print(report(argv[0], root))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
