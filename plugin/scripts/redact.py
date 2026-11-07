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
# Anthropic and OpenAI project/service keys have dashes and underscores after sk-;
# the \b keeps words like task-... and disk-... from matching. The old sk- branch
# stays after the new one so plain keys glued to a word (key%3Dsk-...) are still caught.
SECRET = re.compile(
    r'(?i)(bearer\s+[\w\-\.]{8,}'
    r'|(?:api[_-]?key|api[_-]?token|access[_-]?token|auth[_-]?token|token'
    r'|secret|password|passwd|pwd)\s*[:=]\s*["\']?[^\s"\',;}]{6,}'
    r'|\bsk-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}'
    r'|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
    r'|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    r'|-----BEGIN[^-]+PRIVATE KEY-----)'
)

PLACEHOLDER = "[REDACTED]"


def redact(text: str) -> str:
    """Replace credential-shaped substrings with a placeholder."""
    return SECRET.sub(PLACEHOLDER, text)
