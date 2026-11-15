### Fixed
- **Environment-style keys and URL passwords are now redacted.** The values of `SECRET…KEY=` (such as `AWS_SECRET_ACCESS_KEY=`), `PRIVATE_KEY=`, `ACCESS_KEY=` and `AccountKey=` assignments, and the password in `scheme://user:pass@host` URLs, were sent unredacted in the session digest and the prompt-recall query; rotate any such credential you pasted before this release.
