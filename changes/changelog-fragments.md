### Changed
- **Changelog entries are fragments.** A PR adds `changes/<topic>.md` instead
  of editing `CHANGELOG.md`, so two open PRs no longer conflict over the same
  lines. `scripts/release.py X.Y.Z` folds the fragments into the changelog,
  bumps every manifest and deletes them. `scripts/check.sh` validates the
  fragments.
