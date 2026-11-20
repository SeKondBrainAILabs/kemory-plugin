### Fixed
- **Values after names like `SECRET_KEY_BASE=`, `GITHUB_TOKEN_RO=` and `DB_PASSWORD_PROD=` are now redacted.** They were uploaded unredacted in session digests and recall queries; rotate any such value you pasted before this release.
