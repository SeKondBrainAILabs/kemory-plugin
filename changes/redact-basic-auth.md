### Fixed
- **Basic credentials in `Authorization` headers are now redacted.** The credential after `Authorization: Basic` and `Proxy-Authorization: Basic` (plain, quoted, JSON, `curl -H`, client code, server config and `HTTP_AUTHORIZATION` env lines) was sent unredacted in the session digest and the prompt-recall query; change any password you pasted in such a header before this release.
