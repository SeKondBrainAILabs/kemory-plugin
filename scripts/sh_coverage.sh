#!/usr/bin/env bash
# Opt-in line coverage for plugin/scripts/*.sh. Runs test/test_hooks.py with bash
# xtrace switched on through BASH_ENV, then prints a per-file report. Arguments go
# to test_hooks.py (a class name runs only that class). Exits with the test
# suite's status; it gates on no coverage figure and CI does not run it.
#
# Traces hold expanded values, such as the fake tokens the tests use. They go to
# a temp dir that is deleted on exit. Never run this against real credentials.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

traces="$(mktemp -d)"
trap 'rm -rf "$traces"' EXIT

export SHCOV_DIR="$traces"
export BASH_ENV="$root/scripts/sh_coverage_env.sh"
export PYTHONDONTWRITEBYTECODE=1

status=0
python3 test/test_hooks.py "$@" || status=$?

# The reporter must not trace itself or its own children.
unset BASH_ENV SHCOV_DIR
python3 -I scripts/sh_coverage.py "$traces" "$root"
exit "$status"
