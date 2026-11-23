# CLAUDE.md

Contributor notes for the Kemory plugin: Claude Code, Grok and Muse hooks, an MCP entry
and two slash commands, written in bash and Python, plus a Cursor plugin. Two trees
ship: `plugin/` (the Claude marketplace source is `./plugin`) and `plugins/cursor/`
(the Cursor marketplace source is `./plugins/cursor`). This file, `scripts/`, `test/`
and `changes/` do not.
Server, CLI and MCP tool definitions live in kemory-community, not here.

## Architecture

Layers, from the host inward:

1. **Host wiring** (data, no logic): `plugin/hooks/hooks.json`, `plugin/.mcp.json`,
   `plugin/commands/*.md`, `plugin/skills/*`. The host reads these and runs the scripts.
2. **Hook scripts**: `session-start.sh`, `prompt-recall.sh`, `rate-reminder.sh`,
   `capture.sh`, `store-nudge.sh` in `plugin/scripts/`. `capture.sh` serves Stop, PreCompact and SessionEnd.
   Each is a thin wrapper that runs its Python from a sibling file: `session_start.py`,
   `prompt_recall.py`, `rate_reminder.py`, `capture.py`, `store_nudge.py`. No shell
   script embeds a Python program, so ruff and coverage see all of it.
3. **Shared code**: `plugin/scripts/lib.sh` (bash, sourced; credential resolution via
   `kemory_resolve_auth`, which runs `kemory_creds.py`; its other helpers run
   `kemory_lib.py`) and `plugin/scripts/redact.py` (imported by `capture.py` and
   `prompt_recall.py`) and `plugin/scripts/muse_log.py` and `plugin/scripts/transcript.py`
   (each imported by `capture.py` and `store_nudge.py`; the latter as `tlog`, because
   both hooks name their transcript path variable `transcript`) and
   `plugin/scripts/hook_request.py` (imported by `capture.py` and `prompt_recall.py`).
   Each is one copy on purpose, so both paths redact alike, read a transcript the same
   way, share one session-id guard and share the check that decides where the
   credential goes.
4. **Entry scripts**: `mcp.sh` runs `kemory mcp serve` or `mcp_bridge.py`
   (the `exec` lines in `mcp.sh`); `login.sh` runs `login.py`; `status.sh` is behind
   `/kemory:status` and runs `status.py`.
5. **Dev tooling (not shipped)**: `scripts/check.sh`, `scripts/py_check.sh`,
   `scripts/check_mcp_entry.py`, `scripts/release.py`.
6. **Tests**: `test/test_hooks.py` and `test/fixtures/`.

Dependency rules:

- A plugin script may depend only on `lib.sh`, `kemory_creds.py`, `kemory_lib.py`,
  `redact.py`, `muse_log.py`, `transcript.py`, `hook_request.py` and its own sibling program file (`capture.py`,
  `prompt_recall.py`, `rate_reminder.py`, `session_start.py`, `status.py`,
  `store_nudge.py`, `login.py`, `mcp_bridge.py`). `lib.sh` runs `kemory_creds.py` and
  `kemory_lib.py`.
- Nothing under `plugin/` depends on `scripts/` or `test/`.
- Nothing imports from `test/`. Tests run the shipped scripts as subprocesses and do not
  import them.

The status line, panel and read-only auto-approval live in the separate kemory-panel
plugin, not here (`plugin/hooks/hooks.json` description). Do not add them here.

## Traps

Versions and releases:

- `plugin/.claude-plugin/plugin.json` and `plugin/.grok-plugin/plugin.json` must be
  byte-identical, with one `X.Y.Z` version. Four more must carry the same version:
  `plugin/.muse-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  `plugins[0].version`, `plugins/cursor/.cursor-plugin/plugin.json` and
  `.cursor-plugin/marketplace.json` `plugins[0].version`
  (`scripts/check.sh`, "manifests agree" steps).
- `.github/workflows/release.yml` tags `v<version>` on push to `main` and fails if
  `CHANGELOG.md` has no `## [X.Y.Z]` section. It does nothing if that tag exists.
- Put a user-facing change in `changes/<topic>.md`, with only the headings Upgrading,
  Added, Changed, Fixed, Removed, Notes. Never hand-edit `CHANGELOG.md`. Release with
  `python3 scripts/release.py X.Y.Z` (`changes/README.md`).
- This file is not user-facing, so a change to it needs no fragment.

Hooks:

- SessionStart and UserPromptSubmit hooks must stay synchronous: an async hook's stdout
  is discarded, so context injection would die silently. Only `capture.sh` runs async
  (`plugin/hooks/hooks.json` description).
- Hooks fail open and exit 0 on every error path. `mcp.sh` is the one deliberate
  exception: it exits non-zero when there is no credential (`CONTRIBUTING.md`),
  except under Grok Build, where it starts the bridge signed out.
- Detect Grok with `kemory_is_grok` (`lib.sh`), never `CLAUDE_PLUGIN_ROOT` alone.
  Grok substitutes `${CLAUDE_PLUGIN_ROOT}` into command text but does not export
  it to the shell, so the variable is unset inside `/kemory:status`.
- Never use `python3 -c`, `python3 -` or a `python3 <<` heredoc: all three put the
  current directory first on `sys.path`, so a `json.py` in a user's project would run
  inside the hook that holds the refresh token. Put the program in a `.py` file next
  to the script and run `python3 "$DIR/x.py"`, which puts `plugin/scripts` there
  instead. A test fails on any embedded program. A new module's name must not be a
  standard-library name (`plugin/scripts` is first on `sys.path` for all of them) and
  must not contain a hyphen.
- Hook programs read the payload from `HOOK_INPUT`, not `sys.stdin`: the script has
  already consumed stdin, as `store-nudge.sh:24-25` does.

Redaction (`plugin/scripts/redact.py`):

- It has copies in other repos: kemory-cli `internal/hook/redact.go` (the Cursor plugin
  runs it via `kemory hook`), hermes-kemory `hermes_kemory/redact.py` and
  openclaw-kemory `src/capture/redact.ts`. A pattern change here needs the same change
  there.
- `SECRET` is one alternation, so the leftmost match wins and branch order only decides
  between matches at the same position. A branch that can start earlier and run longer
  (one that allows `-` and `_`) swallows the start of a later keyword, JWT or PEM match
  and leaks its value. Give such a shape its own pattern unioned in `redact()`, as
  `SK_DASHED` is; a pattern that must take a whole block (private keys, `KEY`) runs as
  its own pass before `SECRET`. Compare main's and the new `redact()` on inputs like
  `sk-prod-db-password: <value>` before widening a pattern.
- `redact()` runs on the whole raw prompt inside the synchronous prompt-recall hook
  (10 s timeout), before truncation, so every quantifier must be bounded: an uncapped
  `\b[a-z][a-z0-9+.-]*://...` took about 12 s on `'a.' * 20000`.
- GitHub push protection scans pushes to this public repo. Build vendor-key test
  fixtures (Stripe, GitHub, Google) by string concatenation, never as one complete
  literal (`PREFIXED_SK_KEYS` in `test/test_hooks.py`).

Repo hygiene:

- Every `*.sh` must be executable and every `*.json` must parse (`scripts/check.sh`).
  Its json, sh and py `find` loops exclude only `./.git` (and `node_modules` for JSON),
  so a venv or tool cache inside the repo is checked as if it were plugin code. Keep
  them outside the tree.
- The repo is public. `scripts/check.sh` fails on tracker ids and Notion links in any
  tracked file, and `release.yml` copies `CHANGELOG.md` into a public release.

## Checks and tests

```bash
./scripts/check.sh
python3 test/test_hooks.py
shellcheck plugin/scripts/*.sh scripts/*.sh
./scripts/py_check.sh
```

`scripts/mutate.py` is an on-demand guard-deletion check (1-2 hours in full, never in CI);
`check.sh` runs only its self-test, `test/test_mutate.py`. See CONTRIBUTING.md "Mutation check".

CI (`.github/workflows/check.yml`) runs the first three; `py_check.sh` is run by hand
until a CI step is added for it. `check.sh` runs the test suite
itself (except under GitHub Actions, where the workflow's own step runs it), so it takes a few minutes locally. Its "official manifest validation" step runs only
when a `claude` CLI is on PATH, so CI skips it. In an agent sandbox the `claude` on
PATH is a wrapper that rejects `claude plugin validate` (`unknown option '--model'`),
so that step shows FAIL for both manifests even on a clean `main`. Compare against
`main` before treating it as a regression.

`./scripts/py_check.sh` lints `plugin/scripts`, `scripts` and `test` with ruff, then
runs `test/test_hooks.py` under coverage.py and prints a per-file report, then one for
`kemory_creds.py` (token refresh and write-back). It gates on lint and on the tests, not
on a coverage figure. ruff and coverage are pinned in `requirements-dev.txt` and live in
a venv at `${XDG_CACHE_HOME:-$HOME/.cache}/kemory-plugin-check/venv`, never in the
repo: `check.sh`'s `find` loops would walk it. `.coveragerc` reads `PY_CHECK_ROOT` (set
by the script) for absolute paths, because hooks run from other working directories.
A test that builds its child environment without `PATH` or `COVERAGE_*` is not
measured; that is expected.

`./scripts/sh_coverage.sh [ClassName]` prints line coverage for `plugin/scripts/*.sh`,
which coverage.py cannot see. It is opt-in: CI and `check.sh` do not run it. It runs
`test/test_hooks.py` (or just the named class) with bash xtrace switched on through
`BASH_ENV` (`scripts/sh_coverage_env.sh`), so a test whose child environment drops
`BASH_ENV` or `SHCOV_DIR` is not measured. `scripts/sh_coverage.py` turns the traces
into a per-file table with missing line ranges. The executable-line count is a
heuristic, so the percentages are approximate. It exits with the test suite's status
and gates on no figure. Traces hold expanded values, such as the tests' fake tokens, in
a temp dir deleted on exit: never point it at real credentials.

The "python lint (ruff)" step runs `ruff check .` (B, E4, E7, E9 and F rules, `ruff.toml`). It uses
a `ruff` on PATH only if it is 0.17.5, else `pipx run --spec ruff==0.17.5 ruff`, which is
how CI gets it; with neither it fails. Bump the pin in `check.sh` deliberately.

If shellcheck is not on PATH (apt unreachable, `pip install` blocked by PEP 668),
`python3 -m venv /tmp/tools && /tmp/tools/bin/pip install shellcheck-py ruff==0.17.5`
provides both tools in `/tmp/tools/bin`. To clone the repo into `/tmp`, use
`git clone --no-local`: `--local` fails with "Invalid cross-device link" when the
workspace and `/tmp` are on different filesystems.

ruff's B and F rules apply to Python moved out of a heredoc into a `.py` file: it trips
B904 on `raise SystemExit(0)` inside `except` and F401 on unused imports. If the move
must stay verbatim, add a trailing `# noqa: B904` or `# noqa: F401` rather than
changing the line.

`python3 test/test_hooks.py` alone takes over 2 minutes. While iterating, run one class:
`python3 test/test_hooks.py ClassName`.

CI and `check.sh` run only `test/test_hooks.py`, so a new test file under `test/` never
runs in CI. Add hook tests to `test_hooks.py`.

Start scripts with `run_with_timeout`, not `subprocess.run`, and give every Popen
`.wait()` or `.communicate()` a `timeout=`; `SubprocessTimeoutTest` fails otherwise.

Tests build child environments with `clean_env()`, which drops every `KEMORY_*`
variable, so a variable that `.coveragerc` expands must not start with `KEMORY_`.

`plugin/scripts` must hold no `__pycache__` when tests run: `PrivacyDocTest` reads every
file under it, and a `.pyc` holding a path string such as
`/protocol/openid-connect/token` fails its endpoint scan. Compile with
`PYTHONDONTWRITEBYTECODE=1` or delete the directory.

The tests start local HTTP servers on 127.0.0.1 and point `KEMORY_URL` at them. Some
classes (`DuplicateServerTest`, `SkippedServerTest`) set `KEMORY_URL` to the hosted API
host (`https://api.kemory.s9n.ai`) to test host matching. Do not add a test that needs
a real network reply.

A test that runs `status.sh` or `session-start.sh` must point `KEMORY_URL` at a local
`Recorder` or a closed 127.0.0.1 port. Unset, it falls back to `KEMORY_DEFAULT_URL`
(`lib.sh:16`) and curls the production API with a 6 s timeout. `kemory_retarget_url`
(`lib.sh:73`) also rewrites the retired host `https://kemory.prod.apps.s9n.ai` to that
production URL, so the retired host is no safe placeholder either.
