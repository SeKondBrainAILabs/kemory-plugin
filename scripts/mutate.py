#!/usr/bin/env python3
"""On-demand guard-deletion mutation check for the shipped scripts.

Each mutant removes one early exit (a shell `exit`/`return` statement, or a
Python `if` that guards an early return) and runs the hook tests that cover
the mutated file. A mutant no test notices ("survived") marks a guard whose
deletion would ship green. Stdlib only; see CONTRIBUTING.md "Mutation check".

  python3 scripts/mutate.py --list
  python3 scripts/mutate.py --files plugin/scripts/capture.sh
"""
import argparse
import ast
import concurrent.futures
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEST_FILE = "test/test_hooks.py"
DEFAULT_SKIP_FILE = ROOT / "scripts" / "mutation-skip.json"
DEFAULT_TARGETS = ("plugin/scripts/*.sh", "plugin/scripts/*.py",
                   "plugins/cursor/scripts/*.sh")
BASELINE_TIMEOUT = 1800
MIN_TIMEOUT = 60

HEREDOC_OPEN = re.compile(r"<<(-?)\s*(?:'([A-Za-z_][\w]*)'|\"([A-Za-z_][\w]*)\"|([A-Za-z_][\w]*))")
EXIT_WORD = re.compile(r"\b(exit|return)\b")
ARG = r"(?:[ \t]+\d+)?"
# (a) `cmd || exit N  # comment`; the operator and statement go, the comment stays.
SUFFIX = re.compile(r"^(?P<pre>.*\S)\s*(?:\|\||&&)\s*(?:exit|return)" + ARG
                    + r"(?P<comment>\s+#.*)?\s*$")
# (b) a statement inside a `{ ...; exit N; }` group.
GROUP = re.compile(r"(?<![$\w])\{\s[^{}]*\}")
GROUP_STMT = re.compile(r"(?<![\w$-])(?:exit|return)" + ARG + r"[ \t]*;[ \t]*")
# (c) a line holding only the statement.
BARE = re.compile(r"^(?P<indent>\s*)(?:exit|return)" + ARG + r"[ \t]*(?P<comment>#.*)?$")
# (d) a case arm `) return N ;;`.
CASE_ARM = re.compile(r"\)[ \t]*(?:exit|return)" + ARG + r"[ \t]*;;")
PY_MULTI = re.compile(r"^(?P<head>\s*(?:el)?if )(?P<cond>.+):\s*$")
PY_ONE = re.compile(r"^(?P<head>\s*(?:el)?if )(?P<cond>.+?):[ \t]*"
                    r"(?P<stmt>(?:return|continue|break|raise|sys\.exit\(|exit\()(?:\W.*)?)$")
PY_EXITS = ("return", "continue", "break", "raise", "sys.exit(", "exit(")


class Mutant:
    def __init__(self, path, line, op, original, mutated):
        self.path, self.line, self.op = path, line, op
        self.original, self.mutated = original, mutated  # whole lines, no newline

    @property
    def key(self):
        return f"{self.path}:{self.line}"

    def describe(self):
        return f"{self.key}  {self.op}  {self.original.strip()} -> {self.mutated.strip()}"


def heredoc_regions(lines):
    """Return {(index, python?)}: indices inside a heredoc body or its closing tag."""
    inside = {}
    i = 0
    while i < len(lines):
        m = HEREDOC_OPEN.search(lines[i])
        if not m or lines[i].lstrip().startswith("#") or lines[i].lstrip().startswith("<<<"):
            i += 1
            continue
        dash = m.group(1) == "-"
        tag = m.group(2) or m.group(3) or m.group(4)
        runs_python = "python3" in lines[i]
        j = i + 1
        while j < len(lines):
            body = lines[j].lstrip("\t") if dash else lines[j]
            inside[j] = runs_python
            if body == tag:
                break
            j += 1
        i = j + 1
    return inside


def shell_mutations(line):
    """Yield (operator, mutated_line) for one shell line outside a heredoc."""
    m = SUFFIX.match(line)
    if m:
        yield "drop-exit", m.group("pre") + (m.group("comment") or "")
    for g in GROUP.finditer(line):
        body = g.group(0)
        for s in GROUP_STMT.finditer(body):
            rest = body[:s.start()] + body[s.end():]
            if not rest[1:-1].strip():
                rest = "{ :; }"
            yield "drop-exit", line[:g.start()] + rest + line[g.end():]
    m = BARE.match(line)
    if m:
        yield "drop-exit", m.group("indent") + ":" + (" " + m.group("comment") if m.group("comment") else "")
    for a in CASE_ARM.finditer(line):
        yield "drop-exit", line[:a.start()] + ") : ;;" + line[a.end():]


def python_mutation(lines, i):
    line = lines[i]
    m = PY_ONE.match(line)
    if m:
        return m.group("head") + "False: " + m.group("stmt")
    m = PY_MULTI.match(line)
    if not m:
        return None
    indent = len(line) - len(line.lstrip())
    for nxt in lines[i + 1:]:
        if not nxt.strip():
            continue
        if len(nxt) - len(nxt.lstrip()) > indent and nxt.lstrip().startswith(PY_EXITS):
            return m.group("head") + "False:"
        return None
    return None


def scan_file(path, rel):
    """Return (mutants, unmutated) for one file. unmutated: [(line_no, text)]."""
    text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    last = max((i for i, l in enumerate(lines) if l.strip()), default=-1)
    is_shell = str(path).endswith(".sh")
    heredocs = heredoc_regions(lines) if is_shell else {}
    mutants, unmutated = [], []
    for i, line in enumerate(lines):
        if i == last:
            continue
        found = []
        if is_shell and i not in heredocs:
            if line.lstrip().startswith("#"):
                continue
            found = list(shell_mutations(line))
            if not found and EXIT_WORD.search(line):
                unmutated.append((i + 1, line))
        elif (not is_shell) or heredocs.get(i):
            new = python_mutation(lines, i)
            if new is not None:
                found = [("if-false", new)]
        seen = set()
        for op, new in found:
            if new != line and (op, new) not in seen:
                seen.add((op, new))
                mutants.append(Mutant(rel, i + 1, op, line, new))
    return mutants, unmutated


def repo_rel(path):
    p = pathlib.Path(path)
    p = p if p.is_absolute() else pathlib.Path.cwd() / p
    p = p.resolve()
    try:
        return p.relative_to(ROOT).as_posix(), p
    except ValueError:
        return str(p), p


def default_files():
    out = []
    for pattern in DEFAULT_TARGETS:
        out.extend(sorted(ROOT.glob(pattern)))
    return out


def test_classes():
    """Map class name -> source text of each class in the hook tests."""
    src = (ROOT / TEST_FILE).read_text()
    seg = {}
    for node in ast.parse(src).body:
        if isinstance(node, ast.ClassDef):
            seg[node.name] = ast.get_source_segment(src, node) or ""
    return seg


def script_texts():
    out = {}
    for pattern in ("plugin/scripts/*", "plugins/cursor/scripts/*"):
        for p in sorted(ROOT.glob(pattern)):
            if p.is_file():
                out[p.name] = p.read_text(errors="replace")
    return out


def names_of(basename):
    """Strings that mean this script: its basename, and for .py its module name."""
    pats = [re.escape(basename)]
    if basename.endswith(".py"):
        pats.append(r"(?<![\w.-])" + re.escape(basename[:-3]) + r"(?![\w-])")
    return re.compile("|".join(pats))


def select_tests(basename, classes, scripts):
    """Classes naming the file, or (transitively) any script that names it."""
    related, todo = {basename}, [basename]
    while todo:
        pat = names_of(todo.pop())
        for name, text in scripts.items():
            if name not in related and pat.search(text):
                related.add(name)
                todo.append(name)
    return sorted(c for c, s in classes.items() if any(r in s for r in related))


class Runner:
    """Runs test commands in their own process groups; kills them on exit."""

    def __init__(self):
        self.live = set()
        self.lock = threading.Lock()

    def run(self, cwd, names, timeout):
        """Return (status, seconds, output); status is 'pass', 'fail' or 'timeout'."""
        start = time.monotonic()
        proc = subprocess.Popen([sys.executable, TEST_FILE, *names], cwd=cwd,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace", start_new_session=True)
        with self.lock:
            self.live.add(proc.pid)
        try:
            out, _ = proc.communicate(timeout=timeout)
            status = "pass" if proc.returncode == 0 else "fail"
        except subprocess.TimeoutExpired:
            self.kill(proc.pid)
            out, _ = proc.communicate()
            status = "timeout"
        finally:
            with self.lock:
                self.live.discard(proc.pid)
        return status, time.monotonic() - start, out

    @staticmethod
    def kill(pid):
        try:
            os.killpg(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass

    def kill_all(self):
        with self.lock:
            pids = list(self.live)
        for pid in pids:
            self.kill(pid)


def make_copy(parent, mutant=None):
    """Copy every git-tracked file, as found in the working tree, then edit one line."""
    dest = pathlib.Path(tempfile.mkdtemp(dir=parent))
    raw = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, timeout=60,
                         stdout=subprocess.PIPE).stdout
    for name in filter(None, raw.decode().split("\0")):
        src = ROOT / name
        if not src.exists():
            continue  # tracked but deleted in the working tree
        (dest / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest / name)
    if mutant:
        target = dest / mutant.path
        lines = target.read_text(encoding="utf-8", errors="replace").split("\n")
        lines[mutant.line - 1] = mutant.mutated
        target.write_text("\n".join(lines), encoding="utf-8")
    return dest


def load_skips(path):
    if not path or not pathlib.Path(path).exists():
        return []
    data = json.loads(pathlib.Path(path).read_text())
    for e in data:
        if not (e.get("file") and e.get("line") and str(e.get("reason", "")).strip()):
            sys.exit(f"{path}: every entry needs file, line and a non-empty reason")
    return data


def collect(args):
    files = [repo_rel(f) for f in args.files] if args.files else \
        [repo_rel(p) for p in default_files()]
    if args.only:
        wanted = {o.rsplit(":", 1)[0] for o in args.only}
        if not args.files:
            files = [f for f in files if f[0] in wanted]
    mutants, unmutated = [], []
    for rel, path in files:
        m, u = scan_file(path, rel)
        mutants.extend(m)
        unmutated.extend((rel, n, t) for n, t in u)
    if args.only:
        mutants = [m for m in mutants if m.key in set(args.only)]
    return files, mutants, unmutated


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--list", action="store_true", help="print mutants, run no tests")
    ap.add_argument("--files", nargs="+", metavar="PATH")
    ap.add_argument("--only", nargs="+", metavar="PATH:LINE")
    ap.add_argument("--tests", nargs="+", metavar="UNITTEST_NAME")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--timeout", type=float, metavar="SECONDS")
    ap.add_argument("--skip-file", default=str(DEFAULT_SKIP_FILE), metavar="PATH")
    args = ap.parse_args()

    files, mutants, unmutated = collect(args)
    if args.list:
        for m in mutants:
            print(m.describe())
        for rel, n, text in unmutated:
            print(f"{rel}:{n}  unmutated  {text.strip()}")
        return 0
    outside = [m.path for m in mutants if os.path.isabs(m.path)]
    if outside:
        print(f"cannot run tests for files outside the repo: {outside[0]}", file=sys.stderr)
        return 2

    classes, scripts = test_classes(), script_texts()
    selection = {}
    for m in mutants:
        selection[m.key] = tuple(args.tests) if args.tests else tuple(
            select_tests(os.path.basename(m.path), classes, scripts))
    skips = load_skips(args.skip_file)

    runner = Runner()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="kemory-mutate-"))
    began = time.monotonic()
    results = {}  # mutant key+op+text -> status
    try:
        baselines = {}
        distinct = sorted({s for s in selection.values() if s})
        if distinct:
            base = make_copy(tmp)
            print(f"baseline: {len(distinct)} test selection(s) on an unmutated copy", flush=True)
            with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
                outs = list(pool.map(lambda s: (s, runner.run(base, s, BASELINE_TIMEOUT)), distinct))
            for sel, (status, secs, out) in outs:
                if status != "pass":
                    print(f"baseline {status} for tests: {' '.join(sel)}\n{out[-3000:]}")
                    return 2
                baselines[sel] = secs
            shutil.rmtree(base, ignore_errors=True)

        def one(m):
            sel = selection[m.key]
            if not sel:
                return m, "survived", 0
            limit = args.timeout or max(MIN_TIMEOUT, 3 * baselines[sel])
            work = make_copy(tmp, m)
            try:
                status, _, _ = runner.run(work, sel, limit)
            finally:
                shutil.rmtree(work, ignore_errors=True)
            return m, {"pass": "survived", "fail": "killed", "timeout": "timed out"}[status], limit

        done = []
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            for m, status, limit in pool.map(one, mutants):
                done.append((m, status, limit))
                print(f"{status:10} {m.key}  {m.op}", flush=True)
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130
    finally:
        runner.kill_all()
        shutil.rmtree(tmp, ignore_errors=True)

    def skipped(m):
        return any(e["file"] == m.path and e["line"] == m.original.strip() for e in skips)

    counts = {"killed": 0, "timed out": 0, "survived": 0, "skipped": 0}
    bad = {"survived": [], "timed out": []}
    for m, status, limit in done:
        if status != "killed" and skipped(m):
            counts["skipped"] += 1
        else:
            counts[status] += 1
            if status != "killed":
                bad[status].append((m, limit))
    print(f"\nkilled {counts['killed']}, timed out {counts['timed out']}, "
          f"survived {counts['survived']}, skipped {counts['skipped']}; "
          f"{time.monotonic() - began:.0f}s total")
    for heading, status in (("Survivors", "survived"), ("Timed out", "timed out")):
        if bad[status]:
            print(f"\n{heading}:")
        for m, limit in bad[status]:
            names = ", ".join(selection[m.key]) or "none"
            extra = f", timeout {limit:.0f}s" if status == "timed out" else ""
            print(f"{m.key}  {m.op}  {m.original.strip()}  (tests: {names}{extra})")
    scanned = {rel for rel, _ in files}
    for e in skips:
        if e["file"] in scanned and not any(
                m.path == e["file"] and m.original.strip() == e["line"] for m in mutants):
            print(f"warning: stale skip entry {e['file']}: {e['line']}", file=sys.stderr)
    return 1 if bad["survived"] or bad["timed out"] else 0


if __name__ == "__main__":
    sys.exit(main())
