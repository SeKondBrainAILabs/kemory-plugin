# shellcheck shell=bash
# BASH_ENV file for scripts/sh_coverage.sh: when SHCOV_DIR is set, every bash
# process that reads this file appends an xtrace of each command it runs to
# "$SHCOV_DIR/<pid>.trace", tagged @SHCOV@ so sh_coverage.py can pick the lines
# out. With SHCOV_DIR unset or empty it does nothing.
if [ -n "${SHCOV_DIR:-}" ]; then
  exec {SHCOV_FD}>>"$SHCOV_DIR/$$.trace"
  BASH_XTRACEFD=$SHCOV_FD
  PS4='+@SHCOV@${BASH_SOURCE[0]:-?}:${LINENO}: '
  set -x
fi
