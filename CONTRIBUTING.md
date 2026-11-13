# Contributing

Thanks for helping improve the Kemory plugin. By taking part you agree to the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Ground rules

- Open an issue before a large change so we can agree on the approach.
- Keep hooks **best-effort**: a hook must never block or fail a user's
  session. Exit `0` on every error path.
- Keep the plugin **no-op safe**: if no Kemory server is connected, or the
  user has no credentials, nothing should error. One deliberate exception:
  `scripts/mcp.sh` exits non-zero with a reason when it finds no credential.
  A silent no-op there produces an MCP server that looks connected and serves
  no tools, which hides a misconfiguration instead of reporting it. Under Grok
  Build it starts signed out instead: every tool is listed and each call names
  `/kemory:login`, so nothing is hidden and no restart is needed after signing
  in.
- Anything that sends data anywhere must be **opt-in and documented**. Two
  exceptions are on by default: session capture (`capture.sh`,
  `KEMORY_AUTO_CAPTURE=0` turns it off) and prompt recall (`prompt-recall.sh`,
  `KEMORY_PROMPT_RECALL=0` turns it off), because a memory plugin that
  remembers nothing unless you first find a flag is not doing its job. They
  must stay documented in the privacy section of `README.md` and in
  `plugin/README.md`.

## Before opening a PR

```bash
./scripts/check.sh
./scripts/py_check.sh
```

`check.sh` validates every JSON manifest and shell script, and lints the Python with
ruff (B, E4, E7, E9 and F rules). CI runs the same script.

`py_check.sh` lints `plugin/scripts`, `scripts` and `test` with ruff, then runs the
hook tests under coverage.py and prints coverage per file and for the credential
code (`kemory_creds.py`). It has no coverage threshold. It keeps ruff and coverage in
a venv under `${XDG_CACHE_HOME:-$HOME/.cache}/kemory-plugin-check`, outside the
repo, and needs PyPI the first time. Python lives in `.py` files next to the hook
scripts, never in `python3 -c` or a heredoc, which would import from the current
directory.

Describe a change for users in a changelog fragment, `changes/<topic>.md`,
not in `CHANGELOG.md`. [changes/README.md](changes/README.md) has the format
and the release steps.

## Testing hooks locally

Pipe a synthetic payload into the script the way the harness would:

```bash
echo '{"tool_response":{"retrieval":{"recall_id":"rc_test"}}}' \
  | plugin/scripts/rate-reminder.sh
```

## Mutation check

`scripts/mutate.py` removes one guard at a time from the shipped scripts and runs
the hook tests that cover that file. A guard is a shell `exit` or `return`
statement (`|| exit 0`, a `{ ...; exit 0; }` group, a bare line, a case arm) or a
Python `if` that guards an early return, continue, break or raise. A mutant that
no test fails ("survived") marks a guard whose deletion would ship green. Each
mutant runs in a temporary copy of the tracked files, so your working tree is
never written.

```bash
python3 scripts/mutate.py --list                      # list mutants, run no tests
python3 scripts/mutate.py --files plugin/scripts/capture.sh
```

A full run is estimated at 1-2 hours, so it is on demand, not part of
`check.sh`; split it with `--files`. `--only PATH:LINE` runs one mutant and
`--tests HookTest.test_x` replaces the selected tests. `--jobs` defaults to 2
and should stay there: the sandbox has 6 GiB of memory. Only the tool's own
test, `python3 test/test_mutate.py`, runs in `check.sh`.

Reading the output:

- **survived**: no selected test failed. Add a test that fails without the
  guard; do not edit the guard. Tests that only assert silence usually land here.
- **timed out**: the run exceeded max(60 s, 3x its unmutated baseline). It is
  never counted as killed. Run it again with `--only` and a larger `--timeout`.
- **unmutated** (in `--list`): a shell line with `exit` or `return` that no
  operator recognised. Extend the tool or check whether it is a real guard.

Exit status is 1 while any survivor or timed-out mutant is not in
`scripts/mutation-skip.json`. Add an entry (`file`, the exact original `line`
text, a non-empty `reason`) only when the guard cannot be reached in the test
environment, for example `command -v python3` when the tests always have
python3. A guard that is merely untested is a missing test, not a skip. An entry
that matches no mutant is printed as a stale-entry warning.

## Scope

This repo holds client-side integrations only. Server behaviour, MCP tool
definitions, and the CLI live in
[kemory-community](https://github.com/SeKondBrainAILabs/kemory-community).
