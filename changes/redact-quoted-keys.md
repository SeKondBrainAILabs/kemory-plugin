### Fixed
- **Values after a quoted key are now redacted.** A pasted JSON, YAML or Python dict line such as `"api_key": "..."` or `'password': '...'` was sent unredacted in the session digest and the prompt-recall query; rotate any such credential you pasted before this release.
