#!/usr/bin/env bash
# Validate every manifest and script. Run before opening a PR; CI runs this too.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

echo "→ JSON manifests"
while IFS= read -r f; do
  if jq empty "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; fail=1
  fi
done < <(find . -name '*.json' -not -path './.git/*' -not -path '*/node_modules/*')

echo "→ shell scripts"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    if [ -x "$f" ]; then
      echo "  ok   $f"
    else
      echo "  FAIL $f (not executable)"; fail=1
    fi
  else
    echo "  FAIL $f (syntax)"; fail=1
  fi
done < <(find . -name '*.sh' -not -path './.git/*')

echo "→ python modules"
while IFS= read -r f; do
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null; then
    echo "  ok   $f"
  else
    echo "  FAIL $f (syntax)"; fail=1
  fi
done < <(find . -name '*.py' -not -path './.git/*' -not -path './test/*')

if command -v claude >/dev/null 2>&1; then
  echo "→ official manifest validation"
  if claude plugin validate . >/dev/null 2>&1; then
    echo "  ok   marketplace manifest"
  else
    echo "  FAIL marketplace manifest"; fail=1
  fi
  if claude plugin validate ./plugin >/dev/null 2>&1; then
    echo "  ok   plugin manifest"
  else
    echo "  FAIL plugin manifest"; fail=1
  fi
else
  echo "→ official manifest validation (skipped: claude CLI not on PATH)"
fi

echo "→ plugin source paths resolve"
while IFS= read -r m; do
  p=$(jq -r '.plugins[0].source | if type=="string" then . else .path end' "$m")
  if [ -d "${p#./}" ]; then echo "  ok   $m -> $p"; else echo "  FAIL $m -> $p"; fail=1; fi
done < <(find . -name 'marketplace.json' -not -path './.git/*')

# One tree, one plugin, one version — served to more than one agent host
# through a manifest each. Nothing at runtime reads both, so a bump applied to
# one and not the other ships a version that disagrees with itself, and the
# host that reads the stale one never sees an update at all: every marketplace
# that carries this plugin gates on the version STRING, not the commit.
echo "→ manifests agree on version"
pver=$(jq -r '.version' plugin/.claude-plugin/plugin.json)
gver=$(jq -r '.version' plugin/.grok-plugin/plugin.json)
mver=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
if [ "$pver" != "$gver" ]; then
  echo "  FAIL .claude-plugin $pver != .grok-plugin $gver"; fail=1
elif [ "$pver" != "$mver" ]; then
  echo "  FAIL plugin.json $pver != marketplace.json $mver"; fail=1
elif ! printf '%s' "$pver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  # release.yml turns this into the tag name, so a non-semver value would
  # either produce a junk tag or fail the release after main has already moved.
  echo "  FAIL version '$pver' is not X.Y.Z"; fail=1
else
  echo "  ok   $pver"
fi

echo "→ manifests agree on content"
if diff -q plugin/.claude-plugin/plugin.json plugin/.grok-plugin/plugin.json >/dev/null; then
  echo "  ok   .claude-plugin and .grok-plugin are identical"
else
  echo "  FAIL the two manifests have diverged:"
  diff plugin/.claude-plugin/plugin.json plugin/.grok-plugin/plugin.json | sed 's/^/    /'
  fail=1
fi

# This entry is the only thing standing between a user and no memory tools at
# all, and it is a static file no test exercises. Assert its shape here: a
# wrong host, a dropped credential header or a changed transport all ship
# silently otherwise, and the symptom reaches the user, not CI.
echo "→ bundled MCP entry"
if mcp_report=$(python3 scripts/check_mcp_entry.py 2>&1); then
  echo "  ok   $mcp_report"
else
  printf '  FAIL %s\n' "$mcp_report"; fail=1
fi

# This repo is public, and release.yml copies CHANGELOG.md straight into a
# published GitHub release. Internal tracker ids and Notion links have reached
# it more than once. Catch them here rather than after they are indexed.
echo "→ no internal references in tracked files"
if leaks=$(git grep -nIE 'S9N-[0-9]+|app\.notion\.com|notion\.so/' -- . ':!scripts/check.sh' 2>/dev/null); then
  echo "  FAIL internal references found:"; printf '    %s\n' "$leaks"; fail=1
else
  echo "  ok   no tracker ids or Notion links"
fi

echo "→ hooks reference existing scripts"
while IFS= read -r s; do
  s="${s/\$\{CLAUDE_PLUGIN_ROOT\}/plugin}"
  if [ -f "$s" ]; then echo "  ok   $s"; else echo "  FAIL missing $s"; fail=1; fi
done < <(jq -r '.hooks[][].hooks[].command | select(contains("CLAUDE_PLUGIN_ROOT"))' \
          plugin/hooks/hooks.json | awk '{print $1}')

echo "→ hook behaviour tests"
if python3 test/test_hooks.py >/tmp/kemory-tests.log 2>&1; then
  echo "  ok   $(grep -oE 'Ran [0-9]+ tests' /tmp/kemory-tests.log) passed"
else
  echo "  FAIL hook tests — see /tmp/kemory-tests.log"; tail -20 /tmp/kemory-tests.log; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAILURES ABOVE"; exit 1
fi
