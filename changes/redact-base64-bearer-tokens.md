### Fixed
- **Bearer tokens in standard base64 are now redacted whole.** A token after `Bearer ` containing `+`, `/`, `~` or `=` padding was sent unredacted, or with its tail unredacted, in the session digest and the prompt-recall query; rotate any such token you pasted into a prompt before this release.
