# Changelog fragments

Each PR that changes behaviour adds one file here, `changes/<topic>.md`,
instead of editing `CHANGELOG.md`. Two open PRs then never touch the same
lines.

A fragment is one or more of these headings, each followed by its bullets,
written exactly as they should read in the changelog:

```markdown
### Fixed
- **What changed, in one line.** Why it matters to someone using the plugin.
```

Headings: `Upgrading`, `Added`, `Changed`, `Fixed`, `Removed`, `Notes`.
`./scripts/check.sh` rejects anything else.

To release, on a branch from `main`:

```bash
python3 scripts/release.py X.Y.Z
```

It adds `## [X.Y.Z] — <today>` to `CHANGELOG.md` with every fragment under its
heading, bumps the version in both plugin manifests and the marketplace entry,
and deletes the fragments. Merging that PR tags and publishes the release.
