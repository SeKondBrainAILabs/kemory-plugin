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

**Redaction is best-effort.** `scripts/capture.sh` strips common secret
shapes (bearer tokens, `api_key=`/`password=` assignments, `sk-`, `gh*_`,
AWS access key ids, PEM private-key headers) before upload. This is
pattern-matching, not a guarantee — a novel or unusual secret format can pass
through. If you work with sensitive material, leave capture disabled.

**Local state.** Capture writes a digest hash per session under
`~/.kemory/.captured/` for de-duplication, and the setup notice writes a
timestamp to `~/.kemory/.setup-hint`. Neither contains conversation content.

**Credentials** are read from the Kemory CLI's local credential file, or from
`KEMORY_URL` / `KEMORY_TOKEN`. The plugin never writes credentials anywhere
and never logs them, and refuses to send them to a URL that is not
`http://` or `https://`.
