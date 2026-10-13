### Fixed
- **Grok Build: no restart after `/kemory:login`.** Grok reads a server's tool
  list once, when a session starts. The bundled server used to exit without a
  credential, so the memory tools only appeared after a restart. Under Grok it
  now starts signed out: every tool is listed, each call answers
  "run `/kemory:login`" until you sign in, and the first call after signing in
  goes through. Claude Code is unchanged.
- **Grok Build: `/kemory:login` shows its link straight away.** Grok does not
  run a command's `` !`…` `` line, so the model used to read files to work out
  how to sign in. The command now says what to do when that line does not run.
- **Grok Build: the plugin recognises Grok from where it is installed.** Grok
  does not export `CLAUDE_PLUGIN_ROOT` to the shell, so inside
  `/kemory:status` the disabled-server report from 0.14.0 and the
  `grok plugin update` advice never appeared. Both work now.
