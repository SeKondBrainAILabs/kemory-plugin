#!/usr/bin/env bash
# Cursor hook entry: hands the event payload on stdin to
# `kemory --env prod hook <session-start|capture> --agent cursor`, the one hook
# implementation every host shares (kemory-cli). It writes Cursor's
# sessionStart output itself, so this script adds nothing to stdout.
# `--env prod` matches the plugin's MCP server, which is the hosted API, and
# is what `kemory connect --host cursor` writes too.
#
# Without the kemory CLI on PATH there is nothing to run: exit 0 silently,
# so the plugin's MCP server and skill still work on their own. Always exit
# 0, because exit 2 from a Cursor hook blocks the action it is attached to.
command -v kemory >/dev/null 2>&1 || exit 0
case "${1:-}" in
  session-start | capture) kemory --env prod hook "$1" --agent cursor ;;
esac
exit 0
