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
# before each quote.
SECRET = re.compile(
    r'(?i)(bearer\s+[\w\-\.]{8,}'
    r'|(?:api[_-]?key|api[_-]?token|access[_-]?token|auth[_-]?token|token'
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

PLACEHOLDER = "[REDACTED]"


def redact(text: str) -> str:
    """Replace credential-shaped substrings with a placeholder."""
    # Private-key blocks go first, as their own pass (see KEY). Then the union of
    # SECRET's and SK_DASHED's matches: with no SK_DASHED match this equals
    # SECRET.sub(PLACEHOLDER, KEY.sub(PLACEHOLDER, text)).
    text = KEY.sub(PLACEHOLDER, text)
    spans = sorted(
        m.span()
        for pattern in (SECRET, SK_DASHED)
        for m in pattern.finditer(text)
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
