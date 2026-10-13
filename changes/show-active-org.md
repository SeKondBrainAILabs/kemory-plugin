### Added
- **You are told which organisation Kemory is using, by name.** `/kemory:login`
  now ends with "Active organisation: <name>", and `/kemory:status` shows the
  same line. Signing in with no earlier credential file uses your account's home
  organisation, which may not be the one you work in; until now nothing said so,
  and recall and capture quietly used it. Both say how to switch:
  `kemory use <org-id>` with the Kemory CLI. When the server cannot name the
  organisation, nothing is shown and sign-in works as before.
