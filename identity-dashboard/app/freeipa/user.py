"""FreeIPA user operations — wrappers around the ``ipa`` CLI."""

from __future__ import annotations

from typing import Any


def user_add(
    username: str,
    first: str,
    last: str,
    *,
    role: str = "",
    proyecto: str = "",
    shell: str = "/bin/bash",
) -> str:
    """Build ``ipa user-add`` command."""
    return (
        f"ipa user-add {username} "
        f'--first="{first}" '
        f'--last="{last}" '
        f'--title="{role}" '
        f'--orgunit="{proyecto}" '
        f"--shell={shell} "
        f"--homedir=/home/{username}"
    )


def user_mod(
    username: str,
    *,
    role: str | None = None,
    proyecto: str | None = None,
) -> str:
    """Build ``ipa user-mod`` command."""
    parts = [f"ipa user-mod {username}"]
    if role is not None:
        parts.append(f'--title="{role}"')
    if proyecto is not None:
        parts.append(f'--orgunit="{proyecto}"')
    return " ".join(parts)


def user_find(username: str) -> str:
    """Build ``ipa user-find`` command."""
    return f"ipa user-find {username}"


def user_disable(username: str) -> str:
    """Build ``ipa user-disable`` command."""
    return f"ipa user-disable {username}"


def user_enable(username: str) -> str:
    """Build ``ipa user-enable`` command."""
    return f"ipa user-enable {username}"


def user_del(username: str) -> str:
    """Build ``ipa user-del`` command."""
    return f"ipa user-del {username}"


# ── Command registry ──────────────────────────────────────────────────

COMMANDS: dict[str, dict[str, Any]] = {
    "add": {
        "fn": user_add,
        "params": ["username", "first", "last"],
        "description": "Create FreeIPA user",
    },
    "mod": {
        "fn": user_mod,
        "params": ["username"],
        "description": "Modify FreeIPA user",
    },
    "find": {
        "fn": user_find,
        "params": ["username"],
        "description": "Find FreeIPA user",
    },
    "disable": {
        "fn": user_disable,
        "params": ["username"],
        "description": "Disable FreeIPA user",
    },
    "enable": {
        "fn": user_enable,
        "params": ["username"],
        "description": "Enable FreeIPA user",
    },
    "del": {
        "fn": user_del,
        "params": ["username"],
        "description": "Delete FreeIPA user",
    },
}
