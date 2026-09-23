# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.8.0] — 2026-09-23

### Changed
- **Session capture is now on by default; set `KEMORY_AUTO_CAPTURE=0` to opt
  out.** It shipped opt-in, and opt-in was the wrong shape for it: a memory
  plugin whose memory is off until you go looking for a flag spends every
  session rebuilding context it could have had. The capture itself is unchanged
  — same bounded digest of your own prompts, last 12 turns and 8000 characters,
  same redaction pass, same namespace — only the default moved.

  Everything that describes the default moved with it: the feature list and hook
  table in both READMEs, `PRIVACY.md`, `SECURITY.md`, the setup skill, and what
  `/kemory:status` prints under SETTINGS. `PRIVACY.md` had also been telling
  readers that `KEMORY_AUTO_CAPTURE=0` was "already the default" while the code
  defaulted it off, which is now simply true rather than accidentally right.

### Added
- **Digests now land somewhere private, and say so.** Capture used to write to
  `shared` and set no `visibility` at all, leaving the destination to whatever
  the server defaulted to. That was tolerable while capture was opt-in; for a
  hook that now runs for everyone it is not. Digests default to the
  `user:sessions` namespace with `visibility: user-private`, both stated in the
  payload. `KEMORY_CAPTURE_NAMESPACE` and the new `KEMORY_CAPTURE_VISIBILITY`
  move them deliberately — turning capture on no longer implies putting your
  sessions in front of your team. Existing digests already in `shared` stay
  where they are.

- **A one-time notice, so the flip is not silent.** `SessionStart` says once,
  on any install that has never set `KEMORY_AUTO_CAPTURE` either way, that
  capture is on, what it sends, and that `KEMORY_AUTO_CAPTURE=0` turns it off.
  Someone who already set the variable is told nothing — that is their decision,
  not our default. Stamped at `~/.kemory/.capture-default` and never repeated:
  one piece of news, not a nag. `KEMORY_QUIET_SETUP=1` suppresses it like the
  others.

### Upgrading
- **This changes what leaves your machine.** An existing install that never set
  the variable was not capturing; after this update it will, and will say so
  once. If you want the old behaviour, set `KEMORY_AUTO_CAPTURE=0` before
  restarting Claude Code. Nothing already stored is affected, and
  `/kemory:status` always states which way the setting currently sits.

## [0.7.5] — 2026-09-23

### Fixed
- **The plugin never noticed when Claude Code had switched its own MCP server
  off.** After a connect timeout the host records the failure in
  `~/.claude/mcp-needs-auth-cache.json` and skips that server for 15 minutes.
  That cache is *global*: one slow launch in one project silently removes the
  `kemory_*` tools from every session started afterwards, including sessions
  whose own launch would have succeeded in under a second. Nothing here read
  that file, so `/kemory:status` resolved a credential, reached the API, found
  no duplicate, and ticked "bundled server will start" while the host was not
  running it — the same lie the TOOLS section was fixed for once before,
  arriving one layer up. It now reports the skip, names the retry time, says
  the cache is shared so the failure may have come from an unrelated project,
  and points at the per-cwd log directory where the real error is. SessionStart
  says the same thing once per affected session, so an agent stops working a
  whole session believing the user has no memory.

### Notes
- Read-only by design. Clearing the entry is the obvious-looking fix and is
  wrong twice over: the file is the host's own undocumented state, global and
  written by concurrent sessions with no lock available to us, so a
  read-modify-write can drop another server's entry; and the entry is there
  because a launch really did exceed 30s, so clearing it on every session start
  trades one skipped session for a 30s stall in all of them. Startup time is a
  separate problem from reporting it.
- The log directory is located on disk rather than printed as a literal path.
  Claude Code keeps it under `~/Library/Caches` on macOS and `$XDG_CACHE_HOME`
  (or `~/.cache`) elsewhere, so a hardcoded path would send everyone not on a
  Mac to a directory that does not exist, in a tone that reads as
  authoritative. When none is found the report says where to look without
  naming a path that might be wrong.
- Nothing is reported while the plugin is deliberately standing down for a
  duplicate server. That stand-down is an intentional exit 1, and treating a
  host that caches it as a fault would raise an alarm on a machine configured
  exactly as intended.
## [0.7.4] — 2026-09-23

### Fixed
- **The memory tools could go missing while every check said Kemory was set
  up.** The bundled server stood down for any kemory entry it found, including
  ones Claude Code never runs: an entry in Claude Desktop's
  `claude_desktop_config.json`, an entry under a different project in
  `~/.claude.json`, and a `kemory mcp serve` entry whose bare `kemory` command
  is not on the app's PATH (a Homebrew prefix such as `~/homebrew/bin` is not).
  With nothing serving, the hooks kept capturing and the dashboard showed Claude
  Code as not connected. It now stands down only for an entry Claude Code loads
  for this session and can start.
- **`/kemory:status` now asks the server whether the tools connected.** A valid
  sign-in proves only the hooks, so it checks for a Claude Code agent the server
  has seen in the last 7 days, and names a kemory CLI older than 0.6.8 (whose
  bridge never registered). `kemory-setup` no longer calls that state set up.

## [0.7.2] — 2026-09-14

### Fixed
- **Claude Code and Claude Desktop were never told apart.** The README said
  "terminal, Desktop app and IDE extensions" and left a reader to guess whether
  the Claude *chat* app was in that list. It is not: Claude Desktop is a
  different product with no plugin system and no hooks — MCP tools only, through
  its own config. A three-row table now says per surface what you get, whether
  `/plugin` exists there, and how to install; the skill carries the same split so
  an agent stops answering for the wrong product.

### Notes
- This shipped a release late. It was committed to the 0.7.1 branch, but that
  PR's head never advanced past its first commit, so the merge took the
  `/reload-plugins` fix and left this behind — on the branch, not in main. Worth
  knowing as a shape: a pushed commit that a PR does not list is invisible to
  the merge, and the release still goes green.

## [0.7.1] — 2026-09-14

### Fixed
- **The README's install block read as three commands to run in a row, and the
  middle one is missing.** `/plugin install` prints "Run /reload-plugins to
  apply", and until that runs the plugin's commands do not exist — so following
  the README literally produced `Unknown command: /kemory:login` on a perfectly
  good install. Observed on a fresh machine. `/reload-plugins` is now its own
  step, with the reason, and `/kemory:login` sits after it.
- **"Works in the terminal, the Desktop app and the IDE extensions" implied
  `/plugin` works in all three.** It does not: in the Desktop app `/plugin`
  answers "isn't available in this environment". The plugin itself runs there
  fine — the Desktop app and the IDE extensions read the same
  `~/.claude/plugins` — so the fix is to say install from a terminal and restart
  the app, rather than to imply a command that is not there.
- The setup skill now names `Unknown command: /kemory:login` as "installed but
  not loaded yet", so an agent helping a stuck user stops suggesting a command
  that cannot exist until `/reload-plugins` has run.


## [0.7.0] — 2026-09-14

### Changed
- **The bundled server now stands down when this machine already has one for
  the same Kemory.** Three routes each register an MCP server for Claude Code —
  a pasted pair-claim prompt, `kemory mcp install`, and this plugin — so any two
  of them leave 29 tools duplicated in every request, with `/mcp` listing both
  without saying they are the same server twice.

  The bundled entry is the one that gives way: an entry in a host config was put
  there deliberately, and this one arrives with the plugin. The cost is only the
  duplicate — the hooks read credentials directly, so recall, context injection,
  rating and capture all keep working while the server stands aside. It says so
  in the message, because "your tools moved" and "your memory stopped working"
  are very different sentences.

  Loudly, never silently: it exits with the reason, names the offending entry
  and the file it is in, and gives the way back. A server that started and
  exposed nothing would read as connected in `/mcp` with every tool missing,
  which is the failure this launcher exists to avoid.

  `KEMORY_ALLOW_DUPLICATE=1` runs both anyway.

### Notes
- **Same ENDPOINT, not same name.** `kemory mcp install` pins the env in its
  args precisely so prod and staging can coexist as separate servers, so two
  entries pointing at different hosts are deliberate multi-env work and are left
  alone. Each entry is resolved the way the thing that runs it would: an http
  entry by its own url, a `kemory [--env X] mcp serve` entry through the host in
  `~/.kemory/credentials-X`.
- **An entry whose endpoint cannot be worked out is skipped, never guessed at.**
  The asymmetry decides it: failing to stand down costs duplicated tools,
  standing down wrongly costs the user their tools entirely.
- A claude.ai connector still cannot be seen from a shell. `/kemory:status` names
  that as the case it cannot detect rather than reporting a reassuring zero.
- `/kemory:status` mirrors the launcher — a tick there beside a server that
  quietly declines to start is the exact lie that section was fixed for once
  already.

## [0.6.1] — 2026-09-14

### Changed
- **Renamed the repository to `kemory-plugin`, and it now carries a manifest
  per host.** The name said `claude-kemory` while the thing inside is the
  plugin format several agent hosts read — the same disagreement between name
  and content that the previous rename was meant to end, arriving from the
  other direction once a second host appeared. GitHub redirects the old path,
  so an existing `/plugin marketplace add` keeps working, but the new name is
  what the docs and any catalog entry should use.

  `plugin/.grok-plugin/plugin.json` joins `plugin/.claude-plugin/plugin.json`.
  Both are the same manifest; the hooks, skills, commands and MCP entry under
  `plugin/` are shared, and `${CLAUDE_PLUGIN_ROOT}` stays as it is — it is what
  the hosts resolve, not a Claude-only spelling.

### Added
- **`scripts/check.sh` fails if the two manifests drift.** Nothing at runtime
  reads both, so a bump applied to one and not the other would ship a version
  that disagrees with itself, and the host reading the stale manifest would
  never see the update: every marketplace carrying this plugin gates on the
  version string, not the commit. The check asserts the two files are
  identical and that all three manifests agree on the version.

## [0.6.0] — 2026-09-14

### Added
- **`/kemory:login` — the plugin can now sign a user in by itself.** Until this
  release the plugin could only *read* a credential: `lib.sh` takes
  `KEMORY_API_KEY`, `KEMORY_TOKEN`, or the Kemory CLI's stored login, and with
  none of them the launcher exited telling the user to install a CLI or export a
  long-lived secret into a shell profile — the two things a non-technical user
  does not have and should not need. So the one route that carries the hooks was
  the one such a user could not complete.

  It is an RFC 8628 device authorization grant against the same public client
  the CLI uses: one link, approve in the browser, nothing typed and nothing
  pasted. The response carries `verification_uri_complete`, so the user code is
  already in the URL.

  Chosen over the pair-claim prompt deliberately. Pair-claim exists for AIs with
  no browser of their own; it needs a dashboard session to mint a code, it hands
  back a long-lived API key, and the brief it gives the agent persists an MCP
  entry — a second one, beside the plugin's own. Claude Code runs on the user's
  machine with a browser next to it, so none of that applies here. Device flow
  needs no dashboard, yields refreshable revocable tokens, registers no MCP
  server, and required no server-side change at all.

  It writes `~/.kemory/credentials-<env>` in the CLI's own v2 shape, so a CLI
  installed later finds the user already signed in, and `lib.sh` reads and
  refreshes it exactly as before. `email` and `org_id` come from the access
  token's own claims, so no extra API call is needed to fill the file.

### Changed
- **Every credential prompt now names one route instead of branching.** The
  setup hint used to choose between naming `kemory login` — useless on a machine
  without the CLI — and leading with `KEMORY_API_KEY`, a long-lived secret in a
  shell profile. `/kemory:login` ships with the plugin, so there is no longer a
  machine where the best answer has to be installed first. `mcp.sh`'s refusal,
  `/kemory:status` and the setup skill all say the same thing.
- `KEMORY_API_KEY` returns to being what it was meant to be: the headless
  fallback, for CI and containers with no browser to approve a sign-in in.

### Notes
- `active_org_id` is **not** a token claim and is not always equal to `org_id` —
  `kemory use` switches it. A sign-in that overwrote it would silently move a
  user back to their default organisation, which is how memories have landed in
  the wrong org before. An existing value is preserved; only a first sign-in
  defaults it. There is a test for exactly this.
- The credential file now has two writers, so the login writes it atomically at
  `0600`, matching `lib.sh`'s refresh.

## [0.5.1] — 2026-09-14

### Fixed
- **The bundled MCP entry now sits under `mcpServers`.** `plugin/.mcp.json`
  held the servers map at the top level. Claude Code reads both shapes, so
  this worked for every user and nothing in CI objected — but it is not what
  the rest of the ecosystem reads. A catalogue generator that scans a plugin's
  `.mcp.json` for the standard wrapper finds no servers and lists the plugin
  as shipping hooks, skills and a command and no memory tools, which is the
  whole product. Measured against a third-party marketplace's index
  generator: 19 of 19 MCP-shipping plugins there use the wrapper, and kemory
  was the one that generated an empty `mcpServers`.

  No behaviour change for existing installs — same launcher, same credential
  resolution at launch. `scripts/check_mcp_entry.py` now requires the wrapper
  so the shape cannot drift back, and locates the server under either shape
  first so an entry that is wrong in two ways still reports the transport as
  the reason.

## [0.5.0] — 2026-09-14

### Added
- **A session-start notice when the installed plugin is behind.** Plugins do
  not update themselves and nothing said so: a 0.1.3 install ran for two weeks
  and three releases without `prompt-recall.sh` — the plugin's main mechanism —
  and looked healthy the whole time, because `/kemory:status` could only report
  on the version it was, never the version there was.

  It compares against the marketplace clone Claude Code already keeps on disk.
  Deliberately **not** a network call: `PRIVACY.md` promises this plugin adds
  "no third-party endpoint of its own", and asking GitHub for a version number
  would trade that promise for a convenience. The cost is that a marketplace
  clone nobody has refreshed reads as current and says nothing — a silence
  that resolves itself the next time anything refreshes it, which is the right
  direction for a check like this to fail.

  Once a day, `KEMORY_QUIET_SETUP=1` silences it, and it shares the one
  `systemMessage` slot with the pasted-instruction notice rather than
  displacing it. It also rides along with the no-credential setup hint: a user
  who gets their tools from the connector has no hook credential on purpose,
  reaches that branch every day, and would otherwise have been the one
  population that never hears the plugin moved — the same people the old
  bundled entry stranded.

### Fixed
- **The bundled bridge now carries `Mcp-Session-Id`.** The Kemory endpoint is
  stateless today — verified: `initialize` issues no session id — so 0.4.0's
  bridge held none. The transport allows a server to start issuing one at any
  time, and a relay that dropped it would break every call after the first,
  with nothing in a stateless test to catch it. The header is echoed back when
  the server sends one, a 404 against a forgotten session clears it rather
  than wedging every later call, and `202 Accepted` is treated as "received,
  nothing to return". Tests cover both the stateful and the stateless server.

## [0.4.0] — 2026-09-14

### Changed
- **The bundled MCP entry resolves a credential at launch instead of carrying
  a static one.** It now runs `scripts/mcp.sh`, which calls the same
  `kemory_resolve_auth` in `lib.sh` that every hook uses, then serves through
  `kemory mcp serve` for a CLI login or through a new bundled stdio-to-HTTP
  bridge for an environment credential.

  This entry had been rewritten three times — stdio, HTTP, stdio, HTTP — and
  each rewrite fixed one population by breaking another, because a static
  entry can only name one of the three ways people reach Kemory. The stdio
  versions needed the CLI on `PATH`, so a user with only a key got no tools.
  The HTTP versions sent `X-API-Key: ${KEMORY_API_KEY}`, so a user who signed
  in with `kemory login`, or who uses the claude.ai connector, sent an empty
  header, got a 401, and was pushed into an OAuth prompt for a server they
  never chose — a permanently red entry beside working hooks. Resolving at
  launch ends the cycle rather than swinging it back.

  The invariant is now stated in `.mcp.json`'s guard and enforced by
  `check.sh`: **one entry, credential resolved at launch, never a static
  credential in that file**. The guard rejects the exact HTTP entry this
  release replaces, so a fourth rewrite fails CI instead of shipping.

- **No credential is now a visible failure.** `mcp.sh` exits non-zero with one
  line naming the three remedies, including that the connector case is a
  choice rather than a misconfiguration. The alternative — starting and
  exposing nothing — reads as connected in `/mcp` while every memory tool is
  missing. `CONTRIBUTING.md` records this as the one deliberate exception to
  the plugin's no-op-safe rule.

### Fixed
- **`/kemory:status` claimed the tools were fine when the entry was dead.** It
  reported "kemory CLI on PATH — the bundled MCP server can start", which was
  left from a stdio entry and meaningless under the HTTP one that replaced it:
  the CLI had nothing to do with whether the tools appeared. It now resolves
  the credential the way the launcher does and names which bridge would serve,
  or why none would.
- **Duplicate MCP entries are counted and named.** Installing the plugin while
  a hand-written entry from the older docs is still in place means two copies
  of every tool in each request, and `/mcp` lists both without saying they are
  the same server twice. `/kemory:status` now counts kemory entries across the
  MCP configs on disk — by URL as well as by name, since a hand-written one is
  often called something else — and says to keep one. A claude.ai connector
  cannot be seen from a shell, so it is named as the case this cannot detect.
- **`/kemory:status` prints the installed plugin version.** Nothing surfaced
  it, so an install several releases behind looked identical to a current one.
## [0.3.1] — 2026-09-14

### Changed
- **The injected instruction now says where to write.** It told the agent to
  report "what you stored and where" without ever giving it a convention for
  where — guidance the long pasted version did carry. Anyone told to delete
  their pasted copy after 0.3.0 would have lost it.

### Added
- **A weekly notice when a hand-pasted instruction is still in place.** The
  docs told people to paste one into `CLAUDE.md` long before the plugin
  shipped one. Both together are not harmful, but the pasted copy asks the
  agent to open every session with `kemory_list_namespaces` plus a recall —
  work `prompt-recall.sh` has already done by then, so it costs two tool calls
  a session to repeat it. The plugin reads `~/.claude/CLAUDE.md` and the
  project's `CLAUDE.md` to spot it, says so once a week, and never edits
  either file. `KEMORY_QUIET_SETUP=1` silences it.

## [0.3.0] — 2026-09-14

### Added
- **The standing instruction ships with the plugin.** Until now the plugin
  made an agent *read* memory but left *writing* to a paragraph the user had
  to paste into `CLAUDE.md` themselves — per-machine, per-repo, silently
  absent in a new project, and drifting from the docs the day either changed.
  `session-start.sh` now injects it on every session, including a brand-new
  vault, an unreachable API and a user with no hook credential; those paths
  previously returned nothing at all. It is deliberately short: recall and the
  write prompt are mechanisms now, so it states only what no hook can.
- **Store nudge (`KEMORY_STORE_NUDGE=1`, off by default).** A `Stop` hook that
  fires when a turn settled something durable and no Kemory write happened,
  asking for the write before the turn ends. This is the only thing in the
  plugin that makes a write *happen* rather than hoping for one. It emits
  `hookSpecificOutput.additionalContext`, not `decision: "block"` — the hooks
  reference says both run the same continuation loop and the same loop
  protections, but the former is shown as hook feedback rather than a hook
  error, which is what guidance should look like. Gated on decision-shaped
  phrasing, silent when the turn already stored, and once per turn.

### Notes
- Off by default for one release. A hook that continues a turn is disruptive
  when it is wrong, so the false-positive rate gets measured on real sessions
  before it is considered for on-by-default.
## [0.2.10] — 2026-09-14

### Fixed
- **The privacy policy named a sub-processor that does not exist.** It said
  memory content reaches Groq and OpenRunner. OpenRunner is not a
  sub-processor and never was: it appears nowhere in the platform — no client,
  no base URL, no API key in any environment — and its entry on the public
  list came from an early drafting note. The claim was added in 0.2.8 by
  reading that list rather than the code, in the same pass that corrected
  three other privacy statements by checking them against the backend.

  Now names Groq, which is what the code shows on these paths, and defers to
  the [sub-processor list](https://docs.sekondbrain.ai/subprocessors/) as the
  authoritative record instead of restating a snapshot of it. A copied list
  goes stale, which is how this happened.

## [0.2.9] — 2026-09-13

The repo went public for the plugin directory, which does not accept
closed-source plugins. Most of this release is the consequence of being read
by strangers rather than by the people who wrote it.

### Added
- **`PRIVACY.md`.** The per-hook detail — what leaves your machine, how to
  switch each transmission off, retention, deletion, who can see what, the
  local files — now has its own document instead of being a section most
  readers scrolled past.
- **`check.sh` asserts the bundled MCP entry.** `plugin/.mcp.json` decides
  whether a user gets any memory tools, and nothing tested it: replacing it
  with a bogus endpoint and an empty headers block passed the whole suite. The
  check covers transport, path, the `${KEMORY_URL:-…}` fallback self-hosted
  users depend on, an `X-API-Key` that references the variable rather than
  carrying a literal key, and agreement with the hooks' own default host —
  the two halves authenticate separately and would otherwise drift onto
  different servers.
- **`check.sh` fails on internal tracker ids and Notion links** in tracked
  files. `release.yml` copies the changelog verbatim into a published release,
  so a pasted ticket reference reaches the public by itself.

### Changed
- **The README is a landing page.** It had grown into the whole manual. Install
  now branches on the four ways you can already be reaching Kemory, because the
  previous version presented `KEMORY_API_KEY` as universal — wrong for anyone
  signed in with `kemory login`, and wrong in the other direction for a
  connector user who has tools but no hook credential. CLI installation defers
  to the docs rather than being re-explained.
- **Says how to keep the plugin current**, which nothing did.

## [0.2.8] — 2026-09-11

Closes the gaps that would have failed a Claude plugin directory review.

### Added
- **A Privacy Policy, which the directory rejects submissions for lacking.**
  States per hook what leaves the machine, where it goes, how to switch each
  transmission off, how long content is kept and how to delete it, who can see
  it, what is written locally, and a contact address.
- **A `kemory-setup` skill.** Walks the agent through getting connected: the one
  environment variable that authenticates both halves, the browser-login route
  for anyone who would rather not hold a key, and what a silent session means.

### Changed
- **The bundled MCP entry is now an HTTP connection, not a stdio binary.** It
  was `kemory mcp serve`, which needs the CLI on `PATH` — so on a machine
  without it the server failed to start and the `kemory_*` tools never
  appeared. It is now
  `${KEMORY_URL:-https://api.kemory.s9n.ai}/mcp/v1` with `KEMORY_API_KEY` as
  `X-API-Key`, which is what the Kemory docs have always told people to paste
  by hand. Nothing to install, and because the hooks already read
  `KEMORY_API_KEY`, one export now turns on both halves instead of two
  credentials doing one job each. `kemory login` plus `kemory connect` remains
  the browser-login path; disable the bundled server if you use it.
- **`api.kemory.s9n.ai` is the canonical API host.** The default was
  `api.kemory.sekondbrain.ai` while the credential-retargeting path in
  `lib.sh` already rewrote retired hosts *to* `api.kemory.s9n.ai`. Aligned.

### Fixed
- **Prompt recall was undocumented in the capability table** despite being on by
  default and sending the text of every prompt to the search endpoint. It is now
  listed alongside the other hooks, in both the table and the privacy policy.
- **The bundled MCP server's dependency on the CLI is now stated** rather than
  implied by "covers CLI users".

## [0.2.7] — 2026-09-01

### Added
- **Which Claude surfaces this works on, stated for the first time.** The
  Quickstart applies to the terminal, the Desktop app and the IDE extensions.
  It does **not** work in **Claude Code on the web**: per the Claude Code docs,
  commands that only run in the terminal interface — `/plugin` among them —
  aren't available in cloud sessions, so `/plugin marketplace add` and
  `/plugin install` cannot be run there. Whether a repo-committed
  `.claude/settings.json` loads the plugin instead is untested and documented
  as such, along with the two conditions that would apply anyway: `kemory login`
  cannot work in a cloud VM, and the environment's egress would have to permit
  the Kemory API. **claude.ai chat** has no plugin or hook system at all and is
  connector-only.

## [0.2.6] — 2026-09-01

Two defects found by actually walking the install on a machine with no CLI and
an empty `$HOME`, rather than reasoning about it.

### Fixed
- **The README's non-Homebrew install command would have scattered a Python
  runtime across the user's `bin` directory.** The release archive is a bundle —
  a `kemory` launcher beside an `_internal/` runtime tree, 223 files — so
  `tar -xz -C ~/.local/bin` unpacks all of it into a `PATH` directory. Corrected
  to extract into `~/.kemory/lib` and symlink the launcher, which is what the
  s9n installer does and what actually works (verified: `kemory, version 0.6.7`
  from the symlink).
- **The setup notice and `/kemory:status` recommended `kemory login` on machines
  with no `kemory` binary,** and gave no way to obtain one. Both are now
  CLI-aware: without the CLI they lead with `KEMORY_API_KEY` — the remedy that
  needs no install — and mention the CLI as something to install first. With
  the CLI present the wording is unchanged.

## [0.2.5] — 2026-09-01

### Fixed
- **The 0.2.4 README claimed there is no Windows build. There is.**
  `kemory-windows-x64.zip` ships on the same release as the macOS and Linux
  tarballs. The claim came from reading the Homebrew formula, which has only
  `on_macos` and `on_linux` blocks — a source that structurally cannot express
  a Windows build was treated as evidence one does not exist. Same error class
  as the payload-shape defects in 0.1.3 and 0.2.1: inferring absence from a
  source that cannot represent presence.

  The real limit is narrower and still worth stating: the **hooks** are `bash`
  scripts calling `curl` and `python3`, so on Windows they need Git Bash or
  WSL, which is untested. The CLI runs on Windows; the hooks are unproven
  there.
- Removed a duplicated Quickstart in `README.md`, left by the 0.2.4 rebase
  against the two credential PRs.

## [0.2.4] — 2026-09-01

Four ways a user could believe the plugin was working while the hooks were
inert, and one install story that excluded people for no reason.

### Fixed
- **Expired tokens are now refreshed.** The credential file has carried
  `expires_at` and `refresh_token` all along, but `lib.sh` read `access_token`
  and nothing else — so once it expired, every hook 401'd and no-op'd with no
  notice at all, because the setup hint only fires when no credential file
  exists and a stale one does. Refresh is best-effort against the stored
  issuer, written back atomically at `0600`. A refresh that fails is reported
  as expired rather than silently retried forever.
- **The setup notice no longer claims nothing is configured.** It said "no
  memory backend configured yet" and pointed at `brew install` — wrong, and
  actively misleading, for anyone whose MCP tools were already working through
  a connector. It now says the *hooks* have no credential, notes the tools
  authenticate separately, and names both remedies.
- **A key in an MCP config is detected and explained.** Our own docs tell
  Claude Code users to put the API key in an `X-API-Key` header inside the MCP
  config file — where the hooks cannot see it, since they read the environment
  or the CLI credential file. The most likely path to working tools and inert
  hooks. `/kemory:status` and the setup notice now name the file and say to
  export the same key. Detection only: the key itself is never read out or
  echoed, because harvesting a credential from another tool's config is not a
  habit to build in.

### Changed
- **`/kemory:status` reports the two axes separately** — HOOKS and TOOLS — since
  one combined verdict is how a user concludes the plugin works when half of it
  is doing nothing.
- **Homebrew is no longer the headline.** The tap wraps four prebuilt tarballs
  on a GitHub release; the README now gives the direct `curl` for people
  without Homebrew, and the plugin install comes first, before any credential
  step. Supported platforms are stated for the first time: macOS and Linux on
  arm64/x64, no Windows build, hooks needing `bash`/`curl`/`python3`.
## [0.2.3] — 2026-09-01

### Fixed
- **A keyed setup got told to run a command it does not have.** Without the CLI
  there is no credentials file: the API host comes from `KEMORY_URL`, so it
  reaches a superseded host by a different route than a stale credential. The
  0.2.2 rewrite already covered that path, but `/kemory:status` offered
  `kemory login` as the remedy — not a command a connector or community-edition
  user has installed. It now picks the remedy from where the host actually came
  from, and both paths are pinned by tests.

### Changed
- The Quickstart names both credential routes at step 1. Installing the CLI was
  step 1 with the keyed route collapsed in a `<details>` below it, so a
  connector or community-edition user read a CLI-first onboarding for a setup
  that does not involve the CLI at all.

## [0.2.2] — 2026-09-01

### Fixed
- **A credential written before the API host moved kept the old host forever,
  and `/kemory:status` reported it as a bare `HTTP 301`.** The hooks read
  `~/.kemory/credentials-<env>` directly, and that file stores the API host
  captured at login time — so changing the default only ever helped a fresh
  login. `https://kemory.prod.apps.s9n.ai` has since stopped serving the API: it
  redirects to the browser dashboard, which answers any API path with an SSO
  login redirect. The result on an affected machine was every hook silently
  failing and a status check printing a redirect code with no explanation.

  `lib.sh` now rewrites that one host, exact-match, to the current API host, so
  the hooks recover without a re-login — mirroring what the `kemory` CLI already
  does when it loads a credential. The rewrite is announced rather than silent:
  `/kemory:status` says which host your credential names and that
  `kemory login` updates the file itself.

- **A redirect from the API is now named instead of numbered.** Any 3xx reports
  that the endpoint is not an API host — typically a browser or SSO host, which
  redirects every path to login — and points at `kemory login` or `KEMORY_URL`.
  This applies to self-hosted instances behind an SSO proxy too, not just the
  retired host above.

## [0.2.1] — 2026-09-01

### Fixed
- **The consolidate reminder had never fired, on any version.** `PreCompact`
  does not accept `hookSpecificOutput.additionalContext` — the harness rejects
  the output with `Hook JSON output validation failed` and prints that error to
  the user on every compaction — while both READMEs advertised the feature.
  Third instance of the same root cause as 0.1.3 and 0.2.0: a hook written
  against an assumed payload contract.

  The hook is removed rather than repaired. Even with valid output `PreCompact`
  fires as compaction begins, so the model gets no turn to act on it. The nudge
  moved to `SessionStart` with `source=compact`, which fires after compaction
  and does accept `additionalContext`. It is emitted even when there are no
  namespace summaries to inject, since a compaction is worth consolidating
  either way.

### Added
- Captured `SessionStart`, `PreCompact` and `SessionEnd` payloads as fixtures,
  completing the set: every registered hook event now has a real payload behind
  it, and a test fails when one does not. The exemption list is empty.
  `PreCompact`'s fixture is kept although the event is no longer registered —
  it is the evidence for why.
- `session_title` and `source` are now known `SessionStart` fields; `source`
  was observed as `resume`. `PreCompact` carries `trigger` and
  `custom_instructions`; `SessionEnd` carries `reason`, seen as `other` on a
  normal exit.

## [0.2.0] — 2026-08-31

### Added
- **Prompt recall.** A `UserPromptSubmit` hook now searches Kemory with your
  prompt and injects the top matches, so recall happens on every substantive
  prompt instead of only when the agent thinks to spend a tool call on it.
  Default on; `KEMORY_PROMPT_RECALL=0` disables it. The query is redacted
  before it leaves the machine, and a memory injected once is not injected
  again in the same session.

  Known limitation: `POST /api/v1/memories/search` returns memory ids, not an
  invocation id, so hook-injected memories carry no `recall_id`. The agent is
  told to rate them by `memory_id`. They will not appear in recall *coverage*
  metrics, which join on recall ids.
- **Read-only auto-approval.** A `PreToolUse` hook approves read-only Kemory
  tools so recall no longer costs a permission prompt. Writes still ask. The
  gate is an explicit allowlist, never a regex over the tool family — see the
  fix below for why that distinction matters.
- The hooks manifest now records why the injection hooks must stay
  synchronous: an async hook's stdout is discarded, so an async SessionStart,
  UserPromptSubmit or PreToolUse would silently inject nothing while still
  appearing to run.
- Real captured payloads for `UserPromptSubmit`, `PreToolUse` and `Stop` as
  test fixtures, alongside the existing PostToolUse one.

### Changed
- **Capture is incremental and now also runs on `Stop`,** so a session that is
  killed or crashes still leaves its work behind rather than losing everything.
  Only new turns are posted: the marker at `~/.kemory/.captured/<session_id>`
  became `{"digest", "captured_turns"}`, a high-water mark. Without it the
  12-turn window would slide on every response and store a near-duplicate each
  time — the same defect class as 57d6e53. `KEMORY_CAPTURE_MIN_NEW_TURNS`
  (default 3) gates mid-session stores; `SessionEnd` flushes the remainder.
  Pre-0.2.0 markers are read and upgraded. Capture remains opt-in.
- Secret redaction moved to a single shared `plugin/scripts/redact.py` now that
  two hooks send text off the machine. Behaviour is unchanged and still pinned
  by the existing redaction tests.

### Fixed
- **The rate-reminder matcher matched a write.** `kemory_memory` is an alias of
  `kemory_store_memory` and requires `memory:write`, but the 0.1.3 matcher
  `kemory_(recall.*|ask|memory|find_similar|get_.*)` included it, so the plugin
  would have prompted the agent to rate memories after a *store*. It was silent
  in practice only because the script fails closed without a `recall_id`. Had
  that regex been reused for the new auto-approval hook, it would have
  auto-approved memory writes. A test now asserts the matcher rejects every
  write in the family.

## [0.1.3] — 2026-08-31

### Fixed
- **The rate reminder never worked for MCP tools.** A PostToolUse
  `tool_response` from an MCP server is a *list* of content blocks
  (`[{"type":"text","text":"<json>"}]`), not the payload object. The script
  only handled a dict or a JSON string, so on 0.1.0–0.1.1 it reported
  `recall_id=unknown` (useless for rating) and on 0.1.2, after the fail-closed
  change, it went silent entirely. It now unwraps the MCP envelope.
- Captured a real hook payload as `test/fixtures/posttooluse-mcp-recall.json`
  and test against it. Every prior synthetic shape was invented, and all of
  them passed while the real one produced nothing.

## [0.1.2] — 2026-08-31

### Fixed
- The "not configured yet" notice told users to run `kemory login` without
  saying how to obtain the CLI, so a new user's first contact with the plugin
  was a `command not found`. It now names the install command.
- `plugin/README.md` linked to a `#install` anchor that no longer existed.
- Stale header comment in `capture.sh` referencing the removed
  `TaskCompleted` hook.

### Added
- `NOTICE`, and the copyright holder filled into the Apache appendix.

## [0.1.1] — 2026-08-31

### Fixed
- The rate reminder only matched `kemory_recall_memory` and
  `kemory_get_context`, so it never fired for `kemory_recall` (an alias of the
  former), `kemory_ask`, `kemory_memory`, `kemory_find_similar` or the
  `kemory_get_*` family. Verified live: a `kemory_recall` returning two
  memories produced no reminder. The matcher now covers the recall family and
  gates on a `recall_id` or non-empty result list, so write calls never
  trigger it. Fails closed on unparseable input.

### Changed
- Sign-in leads with `kemory login` (OAuth device flow) instead of exporting
  a long-lived `KEMORY_API_KEY`; the bundled MCP server uses the CLI's stdio
  bridge so one login covers tools and hook credentials. Documents installing
  the CLI, which the README previously never mentioned.

## [0.1.0] — 2026-08-31

Initial release. Claude Code only.

### Added
- Rate reminder now covers the whole recall family (`kemory_recall`,
  `kemory_ask`, `kemory_memory`, `kemory_find_similar`, `kemory_get_*`), not
  just `kemory_recall_memory` and `kemory_get_context`. It gates on a
  `recall_id` or a non-empty result list, so write calls never trigger it.
- Bundled MCP server runs the Kemory CLI's stdio bridge, so a single
  `kemory login` (OAuth browser sign-in) covers both the memory tools and the
  credentials the hooks need — no keys to copy or paste.
- 17 behavioural tests driving the real hook scripts, run by CI.
- `/kemory:status` slash command reporting credential, API, capture, and
  context-injection state, so users can tell whether the plugin is working.
- Client-side capture de-duplication: identical session digests are written
  once per session, since `SessionEnd` fires on exit, `/clear`, and resume.
- `SessionStart` hook that injects your Kemory namespace summaries into a new
  session, with a context budget, a namespace allowlist, and a once-a-day
  setup notice when Kemory is not configured yet.
- Shared credential resolver (`scripts/lib.sh`) supporting hosted bearer
  tokens and community-edition `X-API-Key`.
- `PostToolUse` hook reminding the agent to rate memories it actually used
  after a Kemory recall.
- `PreCompact` hook reminding the agent to consolidate before context is
  summarised away.
- `SessionEnd` hook that captures a bounded, redacted session digest
  (**opt-in**, off unless `KEMORY_AUTO_CAPTURE=1`).
- Hooks refuse to send credentials to a non-HTTP(S) URL.
- The rate reminder stays silent when a recall returned no memories.
- `kemory` skill covering recall, rating, storing, and phrasing memories so
  semantic search can find them again.
- Bundled stdio MCP server entry for the Kemory CLI.
