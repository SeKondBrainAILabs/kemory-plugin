### Fixed
- **A quoted password or token is redacted up to its closing quote.** A comma, semicolon or space inside the quotes (`"ab,cdefgh12345"`, `"correct horse battery staple"`) used to end the redaction early and send the rest of the secret on.
