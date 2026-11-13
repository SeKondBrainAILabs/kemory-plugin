#!/usr/bin/env python3
"""Tests for scripts/mutate.py, the guard-deletion mutation check.

The tool runs as a subprocess, as it does for a person. Target lines are found
by searching the file text, so an edit that moves them does not break a test.
Run: python3 test/test_mutate.py
"""
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL = ROOT / "scripts" / "mutate.py"
CAPTURE = "plugin/scripts/capture.sh"
OPT_OUT = '[ "${KEMORY_AUTO_CAPTURE:-1}" = "1" ] || exit 0'
TIMEOUT = 120


def run_tool(*args):
    return subprocess.run([sys.executable, str(TOOL), *args], cwd=ROOT, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=TIMEOUT)


def git_status():
    return subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, text=True, timeout=60,
                          stdout=subprocess.PIPE, check=True).stdout


def line_number(rel, text):
    """1-based number of the first line of `rel` whose stripped text is `text`."""
    for n, line in enumerate((ROOT / rel).read_text().split("\n"), 1):
        if line.strip() == text:
            return n
    raise AssertionError(f"{rel} has no line {text!r}")


def listed(rel, text, operator):
    """The `--list` lines for the given file line with the given operator."""
    n = line_number(rel, text)
    out = run_tool("--list").stdout.splitlines()
    return [l for l in out if l.startswith(f"{rel}:{n}  {operator}  ")]


class ListTest(unittest.TestCase):
    def test_lists_capture_opt_out_guard(self):
        found = listed(CAPTURE, OPT_OUT, "drop-exit")
        self.assertEqual(len(found), 1, found)
        self.assertTrue(found[0].endswith(f"{OPT_OUT} -> " + OPT_OUT.replace(" || exit 0", "")))

    def test_lists_session_start_curl_group_guard(self):
        text = "command -v curl >/dev/null 2>&1 || { emit_instruction_only; exit 0; }"
        found = listed("plugin/scripts/session-start.sh", text, "drop-exit")
        self.assertEqual(len(found), 1, found)
        self.assertTrue(found[0].endswith("|| { emit_instruction_only; }"), found[0])

    def test_lists_grok_case_arm(self):
        text = 'case "${CLAUDE_PLUGIN_ROOT:-}" in */.grok/*) return 0 ;; esac'
        found = listed("plugin/scripts/lib.sh", text, "drop-exit")
        self.assertEqual(len(found), 1, found)
        self.assertTrue(found[0].endswith('in */.grok/*) : ;; esac'), found[0])

    def test_lists_unmutated_shell_exit(self):
        with tempfile.TemporaryDirectory() as d:
            script = pathlib.Path(d) / "probe.sh"
            script.write_text('#!/bin/bash\nrc=$?\nexit "$rc"\necho done\n')
            out = run_tool("--list", "--files", str(script))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn(f'{script}:3  unmutated  exit "$rc"', out.stdout.splitlines())

    def test_heredoc_body_is_not_mutated_as_shell(self):
        with tempfile.TemporaryDirectory() as d:
            script = pathlib.Path(d) / "probe.sh"
            script.write_text("#!/bin/bash\npython3 - <<'PY'\ndef f():\n    return 1\nPY\n"
                              "echo done\n")
            out = run_tool("--list", "--files", str(script))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout, "")

    def test_python_early_return_is_made_false(self):
        with tempfile.TemporaryDirectory() as d:
            script = pathlib.Path(d) / "probe.py"
            script.write_text("def f(x):\n    if x:\n        return 1\n    return 2\n"
                              "print(f(1))\n")
            out = run_tool("--list", "--files", str(script))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.splitlines(),
                         [f"{script}:2  if-false  if x: -> if False:"])


class RunTest(unittest.TestCase):
    def mutate(self, test_name):
        n = line_number(CAPTURE, OPT_OUT)
        before = git_status()
        out = run_tool("--only", f"{CAPTURE}:{n}", "--tests", test_name,
                       "--skip-file", "/dev/null/none")
        self.assertEqual(git_status(), before)
        return out

    def test_guard_mutant_killed_by_opt_out_test(self):
        out = self.mutate("HookTest.test_capture_opted_out_by_zero")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("killed", out.stdout)
        self.assertIn("killed 1, timed out 0, survived 0", out.stdout)

    def test_guard_mutant_survives_unrelated_test(self):
        out = self.mutate("HookTest.test_capture_uploads_when_enabled")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("survived 1", out.stdout)
        self.assertIn(f"{CAPTURE}:{line_number(CAPTURE, OPT_OUT)}  drop-exit  {OPT_OUT}",
                      out.stdout)

    def test_working_tree_untouched(self):
        before = git_status()
        text = (ROOT / CAPTURE).read_text()
        self.mutate("HookTest.test_capture_opted_out_by_zero")
        self.assertEqual(git_status(), before)
        self.assertEqual((ROOT / CAPTURE).read_text(), text)


class SkipFileTest(unittest.TestCase):
    def test_skipped_survivor_does_not_fail(self):
        n = line_number(CAPTURE, OPT_OUT)
        with tempfile.TemporaryDirectory() as d:
            skip = pathlib.Path(d) / "skip.json"
            skip.write_text(json.dumps([{"file": CAPTURE, "line": OPT_OUT,
                                         "reason": "test fixture"}]))
            before = git_status()
            out = run_tool("--only", f"{CAPTURE}:{n}", "--skip-file", str(skip), "--tests",
                           "HookTest.test_capture_uploads_when_enabled")
            self.assertEqual(git_status(), before)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("skipped 1", out.stdout)
        self.assertIn("survived 0", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
