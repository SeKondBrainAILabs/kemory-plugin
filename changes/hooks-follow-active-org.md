### Fixed
- **Recall and capture follow the organisation you selected with
  `kemory use`.** The CLI, and so the Kemory tools, sent the selected
  organisation on every request, but the hooks sent only the token. With more
  than one organisation, prompt recall read from, and session capture wrote
  to, the token's own organisation while the tools used the selected one. The
  hooks and the MCP bridge now send `X-Organization-ID` from the credential
  file's `active_org_id`, as the CLI does. An API key is unaffected.
