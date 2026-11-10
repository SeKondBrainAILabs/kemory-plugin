"""Secret redaction for anything a Kemory hook sends off this machine.

One copy, imported by both hooks that egress text: capture.sh (session
digests) and prompt-recall.sh (the search query, which is the user's raw
prompt). Two copies of a security regex drift, and the drift is silent.

Import from a heredoc with the script directory on sys.path:

    sys.path.insert(0, os.environ["KEMORY_SCRIPT_DIR"])
    from redact import redact
"""

import re

# Redaction must not eat ordinary prose: developer conversations say "token"
# and "secret" constantly, so a keyword only redacts when it is followed by an
# actual assignment and a value long enough to be a credential.
SECRET = re.compile(
    r'(?i)(bearer\s+[\w\-\.]{8,}'
    r'|(?:api[_-]?key|api[_-]?token|access[_-]?token|auth[_-]?token|token'
    r'|secret|password|passwd|pwd)\s*[:=]\s*["\']?[^\s"\',;}]{6,}'
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

PLACEHOLDER = "[REDACTED]"


def redact(text: str) -> str:
    """Replace credential-shaped substrings with a placeholder."""
    return SECRET.sub(PLACEHOLDER, KEY.sub(PLACEHOLDER, text))
