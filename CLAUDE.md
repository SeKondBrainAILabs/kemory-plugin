# CLAUDE.md

Notes for agents working in this repo. Run `./scripts/check.sh` before opening a PR; CI runs the same script.

## Layout

- The repo ships two plugins: `plugin/` (kemory: shell hooks) and `plus/` (kemory-plus: the `register.tsx` function-hooks module and `recall-approve.sh`). `register.tsx` has no TypeScript toolchain or tests in the repo; only its `hooks.json` and manifests are checked by `scripts/check.sh`. (Source: agent task "PRIVACY.md and SECURITY.md no longer match what the plugin sends and writes". Its Notion link is left out because `scripts/check.sh` rejects Notion links in tracked files.)
