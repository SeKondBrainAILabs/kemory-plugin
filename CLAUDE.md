# CLAUDE.md

Contributor notes for the Kemory plugin: Claude Code and Grok hooks, an MCP entry and
two slash commands, written in bash and Python. Only `plugin/` ships (the marketplace
source is `./plugin`). This file, `scripts/`, `test/` and `changes/` do not.
Server, CLI and MCP tool definitions live in kemory-community, not here.

## Architecture

Layers, from the host inward:

1. **Host wiring** (data, no logic): `plugin/hooks/hooks.json`, `plugin/.mcp.json`,
   `plugin/commands/*.md`, `plugin/skills/*`. The host reads these and runs the scripts.
2. **Hook scripts**: `session-start.sh`, `prompt-recall.sh`, `rate-reminder.sh`,
   `capture.sh`, `store-nudge.sh` in `plugin/scripts/`. `capture.sh` serves Stop, PreCompact and SessionEnd.
3. **Shared code**: `plugin/scripts/lib.sh` (bash, sourced; credential resolution via
   `kemory_resolve_auth`) and `plugin/scripts/redact.py` (imported by `capture.sh` and
   `prompt-recall.sh`) and `plugin/scripts/muse_log.py` (imported by `capture.sh` and
   `store-nudge.sh`). Each is one copy on purpose, so both paths redact alike and share
   one session-id guard.
4. **Entry scripts**: `mcp.sh` runs `kemory mcp serve` or `mcp_bridge.py`
   (the `exec` lines in `mcp.sh`); `login.sh` runs `login.py`; `status.sh` is behind `/kemory:status`.
5. **Dev tooling (not shipped)**: `scripts/check.sh`, `scripts/check_mcp_entry.py`,
   `scripts/release.py`.
6. **Tests**: `test/test_hooks.py` and `test/fixtures/`.

Dependency rules:

- A plugin script may depend only on `lib.sh`, `redact.py`, `muse_log.py` and its own sibling entry
  file (`login.py`, `mcp_bridge.py`).
- Nothing under `plugin/` depends on `scripts/` or `test/`.
- Nothing imports from `test/`. Tests run the shipped scripts as subprocesses and do not
  import them.

The status line, panel and read-only auto-approval live in the separate kemory-panel
plugin, not here (`plugin/hooks/hooks.json` description). Do not add them here.

## Traps

Versions and releases:

- `plugin/.claude-plugin/plugin.json` and `plugin/.grok-plugin/plugin.json` must be
  byte-identical, with one `X.Y.Z` version. `.claude-plugin/marketplace.json`
  `plugins[0].version` must match it (`scripts/check.sh`, "manifests agree" steps).
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
- A `python3 <<'PY'` heredoc becomes the program's stdin. Read the hook payload into a
  variable first and pass it in an environment variable, as `store-nudge.sh:22-23` does
  with `HOOK_INPUT`. Never read `sys.stdin` inside the heredoc.

Repo hygiene:

- Every `*.sh` must be executable and every `*.json` must parse (`scripts/check.sh`).
- The repo is public. `scripts/check.sh` fails on tracker ids and Notion links in any
  tracked file, and `release.yml` copies `CHANGELOG.md` into a public release.

## Checks and tests

```bash
./scripts/check.sh
python3 test/test_hooks.py
shellcheck plugin/scripts/*.sh scripts/*.sh
```

CI (`.github/workflows/check.yml`) runs these three. `check.sh` runs the test suite
itself, so it takes a few minutes. Its "official manifest validation" step runs only
when a `claude` CLI is on PATH, so CI skips it. In an agent sandbox the `claude` on
PATH is a wrapper that rejects `claude plugin validate` (`unknown option '--model'`),
so that step shows FAIL for both manifests even on a clean `main`. Compare against
`main` before treating it as a regression.

`python3 test/test_hooks.py` alone takes over 2 minutes. While iterating, run one class:
`python3 test/test_hooks.py ClassName`.

The tests start local HTTP servers on 127.0.0.1 and point `KEMORY_URL` at them. Some
classes (`DuplicateServerTest`, `SkippedServerTest`) set `KEMORY_URL` to the hosted API
host (`https://api.kemory.s9n.ai`) to test host matching. Do not add a test that needs
a real network reply.

A test that runs `status.sh` or `session-start.sh` must point `KEMORY_URL` at a local
`Recorder` or a closed 127.0.0.1 port. Unset, it falls back to `KEMORY_DEFAULT_URL`
(`lib.sh:16`) and curls the production API with a 6 s timeout. `kemory_retarget_url`
(`lib.sh:68`) also rewrites the retired host `https://kemory.prod.apps.s9n.ai` to that
production URL, so the retired host is no safe placeholder either.
