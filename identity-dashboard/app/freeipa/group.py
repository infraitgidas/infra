"""FreeIPA group operations — wrappers around the ``ipa`` CLI."""

from __future__ import annotations

from typing import Any


def group_add_member(group: str, username: str) -> str:
    """Build ``ipa group-add-member`` subcommand (without ``ipa`` prefix)."""
    return f"group-add-member {group} --users={username}"


def group_remove_member(group: str, username: str) -> str:
    """Build ``ipa group-remove-member`` subcommand (without ``ipa`` prefix)."""
    return f"group-remove-member {group} --users={username}"


def group_find(group: str) -> str:
    """Build ``ipa group-find`` subcommand (without ``ipa`` prefix)."""
    return f"group-find {group}"


# ── Command registry ──────────────────────────────────────────────────

COMMANDS: dict[str, dict[str, Any]] = {
    "add_member": {
        "fn": group_add_member,
        "params": ["group", "username"],
        "description": "Add user to FreeIPA group",
    },
    "remove_member": {
        "fn": group_remove_member,
        "params": ["group", "username"],
        "description": "Remove user from FreeIPA group",
    },
    "find": {
        "fn": group_find,
        "params": ["group"],
        "description": "Find FreeIPA group",
    },
}
