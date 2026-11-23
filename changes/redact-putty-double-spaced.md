### Fixed
- **A double-spaced PuTTY `.ppk` paste is redacted whole.** With a blank line between lines, the redaction counted the blank lines toward the key's length and left the last private-key lines and the MAC in clear.
