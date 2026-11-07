### Fixed
- **Session capture and prompt recall now redact a whole private-key block.** Only the `BEGIN` line of a pasted PEM, OpenSSH or PGP private key used to be replaced, so the key body was uploaded; now the block from `BEGIN` to `END` becomes one `[REDACTED]`.
