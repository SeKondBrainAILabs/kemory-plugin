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
    r'|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    r'|-----BEGIN[^-]+PRIVATE KEY-----)'
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
    # With no SK_DASHED match this equals SECRET.sub(PLACEHOLDER, text).
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
