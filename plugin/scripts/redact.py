"""Secret redaction for anything a Kemory hook sends off this machine.

One copy, imported by both hooks that egress text: capture.py (session
digests) and prompt_recall.py (the search query, which is the user's raw
prompt). Two copies of a security regex drift, and the drift is silent.

Import with the script directory on sys.path:

    sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
    from redact import redact
"""

import re

# Redaction must not eat ordinary prose: developer conversations say "token"
# and "secret" constantly, so a keyword only redacts when it is followed by an
# actual assignment and a value long enough to be a credential. The key may be
# quoted (JSON, YAML, a Python dict), and JSON-escaped text puts a backslash
# before each quote. Names that end in "key" are matched too: SECRET...KEY (up to
# 24 characters between, so AWS_SECRET_ACCESS_KEY and JWT_SECRET_SIGNING_KEY),
# PRIVATE_KEY, ACCESS_KEY and ACCOUNT_KEY (an Azure AccountKey=). `secret` alone
# still needs the assignment, so "the secret key is stored in vault" is prose.
SECRET = re.compile(
    r'(?i)(bearer\s+[\w\-\.]{8,}'
    r'|(?:api[_-]?key|api[_-]?token|access[_-]?token|auth[_-]?token|token'
    r'|secret[a-z0-9_-]{0,24}?key|private[_-]?key|access[_-]?key|account[_-]?key'
    r'|secret|password|passwd|pwd)\\?["\']?\s*[:=]\s*\\?["\']?[^\s"\',;}]{6,}'
    r'|sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}'
    r'|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
    r'|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})'
)

# A private key is secret in its body, not its header, so this takes the whole
# block, BEGIN line to END line (PEM, OpenSSH and PGP). It runs as its own pass
# before SECRET: inside SECRET, a keyword such as `password=` starts earlier in
# the text than the BEGIN line, wins the leftmost match and eats only
# "-----BEGIN".
# The lazy scan is capped at 16 KB per BEGIN (a 4096-bit RSA key is about 3.3 KB)
# so a prompt full of unterminated headers cannot stall the synchronous
# prompt-recall hook. With no END line (a truncated paste) it takes the base64
# runs and PEM/PGP header lines that follow, separated by whitespace or a literal
# backslash-n from a JSON-escaped key, and stops at anything else. The header
# names are listed on purpose: a general `Name:` would eat ordinary lines.
KEY = re.compile(
    r'(?i)-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----'
    r'(?:[\s\S]{0,16384}?-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----'
    r'|(?:(?:\s|\\[rn])+(?:[A-Za-z0-9+/=]{16,}'
    r'|(?:Proc-Type|DEK-Info|Version|Comment|Hash|Charset):[^\n]*))*)'
)

# Anthropic and OpenAI project and service keys have dashes and underscores
# after sk-, where SECRET's sk- branch stops. This is its own pattern and
# redact() takes the union of both patterns' matches: as a branch inside
# SECRET it won the leftmost match and swallowed a following password=/token=,
# JWT or PEM header, leaking the value. The \b keeps words like task-... and
# disk-... from matching.
SK_DASHED = re.compile(r'(?i)\bsk-[A-Za-z0-9_-]{16,}')

# Vendor key shapes with a fixed prefix. Each is its own pattern, unioned in
# redact(), and not a branch of SECRET: SECRET is case-insensitive, and a branch
# there wins the leftmost match and swallows a following password=/token=
# value (see SK_DASHED). All four are case-sensitive: the vendors issue these
# prefixes in this case only, so matching any case catches no real key and would
# redact long glued uppercase constants such as RK_LIVE_ followed by 20+ letters.
#
# A GitHub fine-grained personal access token. The two length rules keep
# GITHUB_PAT_... names and github_pat_expiry_warning_threshold out.
GITHUB_PAT = re.compile(r'github_pat_[A-Za-z0-9]{16,}_[A-Za-z0-9]{32,}')

# A Stripe secret or restricted key, live or test. No lowercase letter may sit
# right before it, so risk_test_... and task_test_... identifiers stay. The key
# still matches after a JSON escape (\n, \r, \t, \uXXXX) or a percent-escape
# (%3D, %3d), whose last character can be a lowercase letter.
STRIPE_KEY = re.compile(
    r'(?:(?<![a-z])|(?<=\\[nrt])|(?<=\\u[0-9A-Fa-f]{4})|(?<=%[0-9A-Fa-f]{2}))'
    r'[sr]k_(?:live|test)_[A-Za-z0-9]{20,}'
)

# A Google API key: AIza and 35 more characters.
GOOGLE_API_KEY = re.compile(r'AIza[0-9A-Za-z_-]{35}')

# A GitLab personal access token. Other GitLab token prefixes are not covered.
GITLAB_PAT = re.compile(r'glpat-[A-Za-z0-9_.-]{20,}')

# The password in scheme://user:password@host. Only group 1 is redacted, so the
# user and host stay readable: Python's lookbehind must be fixed-width, and a
# .sub pass with this pattern would eat the whole URL, so redact() takes
# m.span(1) instead. The user runs to the first ':' and may contain '@'
# (user@server:pass@host). The greedy password class ends at the last @ before
# a '/', '?' or '#' (urllib's rule), so a password containing '@' is fully
# redacted. The scheme is capped at 32 characters: uncapped, the scan ran to
# the end of the text from every word start (10-16 s on 'a.' * 20000 in the
# synchronous prompt-recall hook).
URL_PASSWORD = re.compile(
    r'(?i)\b[a-z][a-z0-9+.-]{0,31}://[^\s:/]{0,256}:([^\s/?#]{1,256})@'
)

PLACEHOLDER = "[REDACTED]"


def redact(text: str) -> str:
    """Replace credential-shaped substrings with a placeholder."""
    # Private-key blocks go first, as their own pass (see KEY). Then the union
    # of the matches of SECRET, SK_DASHED and the four vendor key patterns, and
    # URL_PASSWORD's password group. When only SECRET matches, this equals
    # SECRET.sub(PLACEHOLDER, KEY.sub(PLACEHOLDER, text)).
    text = KEY.sub(PLACEHOLDER, text)
    spans = sorted(
        [
            m.span()
            for pattern in (
                SECRET, SK_DASHED, GITHUB_PAT, STRIPE_KEY, GOOGLE_API_KEY, GITLAB_PAT,
            )
            for m in pattern.finditer(text)
        ]
        + [m.span(1) for m in URL_PASSWORD.finditer(text)]
    )
    merged = []
    for start, end in spans:
        if merged and start < merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    out = []
    pos = 0
    for start, end in merged:
        out.append(text[pos:start])
        out.append(PLACEHOLDER)
        pos = end
    out.append(text[pos:])
    return "".join(out)
