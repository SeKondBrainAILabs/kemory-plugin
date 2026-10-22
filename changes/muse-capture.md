### Added
- **Session capture works under Muse Code.** Muse sends no transcript path, so capture now finds its session log by session id and reads the user turns from it. Claude Code and Grok Build transcripts are read as before. The store reminder can read Muse logs too, but it stays off by default and Muse's cleared environment gives no way to turn it on yet.
