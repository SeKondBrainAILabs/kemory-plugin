### Fixed
- **Session capture and prompt recall now redact the private part of a pasted PuTTY `.ppk` key.** A `.ppk` file has no `BEGIN` line, so its `Private-Lines` body used to be uploaded whole; now the `Private-Lines` header, the body lines it counts and the `Private-MAC` line become one `[REDACTED]`, and the public key and comment stay.
