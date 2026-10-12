# Security Policy

## Reporting a vulnerability

Please report security issues privately to **security@sekondbrain.ai** rather
than opening a public issue. We aim to acknowledge within 3 business days.

## Scope notes for this plugin

**Session capture is on by default and opt-out.** Unless you set
`KEMORY_AUTO_CAPTURE=0`, the plugin sends a bounded digest of your own
prompts to the Kemory instance you have configured. Review
[plugin/README.md](plugin/README.md) and [PRIVACY.md](PRIVACY.md) for what
that covers, and set the variable to `0` if you do not want it.

**Redaction is best-effort.** `plugin/scripts/capture.sh` strips common secret
shapes (bearer tokens, `api_key=`/`password=` assignments, `sk-`, `gh*_`,
AWS access key ids, PEM private-key headers) before upload. This is
pattern-matching, not a guarantee — a novel or unusual secret format can pass
through. If you work with sensitive material, leave capture disabled.

**Local state.** The files the plugin writes under `~/.kemory/`, and what each
holds, are listed in the Local files section of [PRIVACY.md](PRIVACY.md).

**Credentials.** The hooks resolve them in this order: `KEMORY_API_KEY`, then
`KEMORY_TOKEN`, then `~/.kemory/credentials-${KEMORY_ENV:-prod}`, then
`~/.kemory/credentials`. `KEMORY_URL` picks the instance and defaults to hosted
Kemory. `/kemory:login` writes `~/.kemory/credentials-<env>`, and the hooks
rewrite the credential file they read when they refresh an expired OAuth token.
The file holds an access token and a refresh token, is replaced atomically with
mode 0600, and is never logged or sent anywhere except in the refresh request
to the identity provider named in the file. The plugin refuses to send
credentials to a URL that is not `http://` or `https://`.
