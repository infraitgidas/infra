"""FreeIPA password operations — wrapper around ``ipa passwd``.

The password is passed via stdin to avoid exposure in the process table.
All log messages are sanitized by the ``SanitizingFilter`` in
``app.logging``.
"""

from __future__ import annotations

from typing import Any


def passwd(username: str, password: str) -> str:
    """Build a command to change *username*'s password via stdin.

    Returns the full command including pipe (use with :meth:`run`,
    **not** :meth:`run_ipa`, since ``run_ipa`` prepends ``ipa ``).

    The raw *password* value is embedded in a shell echo — however the
    logging layer (``SanitizingFilter``) strips password-like values
    before they reach the output.
    """
    return f"echo '{password}' | ipa passwd {username}"


# ── Command registry ──────────────────────────────────────────────────

COMMANDS: dict[str, dict[str, Any]] = {
    "passwd": {
        "fn": passwd,
        "params": ["username", "password"],
        "description": "Reset FreeIPA password via stdin",
    },
}
