#!/usr/bin/env bash
# Lint the Python with ruff, then run the hook tests under coverage.py.
# Reports coverage per file and, separately, for the credential code. It gates
# on lint and on the tests, not on a coverage figure.
#
# ruff and coverage are pinned in requirements-dev.txt and live in a venv outside
# the repo, so scripts/check.sh's find loops never walk it.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

venv="${XDG_CACHE_HOME:-$HOME/.cache}/kemory-plugin-check/venv"
stamp="$venv/.requirements-dev.sha256"
want="$(sha256sum requirements-dev.txt | cut -d' ' -f1)"
if [ ! -x "$venv/bin/python3" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
  echo "→ creating the check environment in $venv"
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/python3" -m pip install --quiet --disable-pip-version-check -r requirements-dev.txt
  printf '%s\n' "$want" >"$stamp"
fi
# The venv first, so the hooks' own `python3` is the one coverage patched.
export PATH="$venv/bin:$PATH"

# .coveragerc reads this: hooks run from other working directories.
export PY_CHECK_ROOT="$root"

echo "→ ruff"
ruff check plugin/scripts scripts test

echo "→ tests under coverage"
coverage erase
coverage run test/test_hooks.py
coverage combine --quiet

echo "→ coverage, every plugin script"
coverage report -m

echo "→ coverage, credential code (token refresh and write-back)"
coverage report -m --include="$root/plugin/scripts/kemory_creds.py"
