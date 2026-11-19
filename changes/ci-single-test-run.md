### Changed

- CI runs the hook test suite once per pull request instead of twice. `scripts/check.sh` skips its test step under GitHub Actions, where the workflow's own step runs it with full output.
