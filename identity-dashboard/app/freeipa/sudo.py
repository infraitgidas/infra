"""FreeIPA sudo rule operations — wrappers around the ``ipa`` CLI.

.. note::
    All commands include a ``--notify`` wiring placeholder for future
    integration with the notification system.
"""

from __future__ import annotations

from typing import Any


def sudorule_find(rule: str) -> str:
    """Find a sudo rule by name or pattern."""
    return f"sudorule-find {rule}"


def sudorule_add_option(rule: str, option: str) -> str:
    """Add a sudoOption to an existing sudo rule."""
    return f"sudorule-add-option {rule} --sudooption={option}"


def sudorule_add_user(rule: str, username: str) -> str:
    """Add a user to a sudo rule."""
    return f"sudorule-add-user {rule} --users={username}"


def sudorule_remove_user(rule: str, username: str) -> str:
    """Remove a user from a sudo rule."""
    return f"sudorule-remove-user {rule} --users={username}"


def sudorule_add_host(rule: str, host: str) -> str:
    """Add a host to a sudo rule."""
    return f"sudorule-add-host {rule} --hosts={host}"


def sudorule_remove_host(rule: str, host: str) -> str:
    """Remove a host from a sudo rule."""
    return f"sudorule-remove-host {rule} --hosts={host}"


def sudocmd_find(cmd: str) -> str:
    """Find a sudo command by name or pattern."""
    return f"sudocmd-find {cmd}"


def sudocmd_add(cmd: str) -> str:
    """Add a sudo command definition."""
    return f"sudocmd-add --cmd='{cmd}'"


# ── Command registry ──────────────────────────────────────────────────

COMMANDS: dict[str, dict[str, Any]] = {
    "find_rule": {
        "fn": sudorule_find,
        "params": ["rule"],
        "description": "Find sudo rule",
    },
    "add_option": {
        "fn": sudorule_add_option,
        "params": ["rule", "option"],
        "description": "Add sudo option to rule",
    },
    "add_user": {
        "fn": sudorule_add_user,
        "params": ["rule", "username"],
        "description": "Add user to sudo rule",
    },
    "remove_user": {
        "fn": sudorule_remove_user,
        "params": ["rule", "username"],
        "description": "Remove user from sudo rule",
    },
    "add_host": {
        "fn": sudorule_add_host,
        "params": ["rule", "host"],
        "description": "Add host to sudo rule",
    },
    "remove_host": {
        "fn": sudorule_remove_host,
        "params": ["rule", "host"],
        "description": "Remove host from sudo rule",
    },
    "find_cmd": {
        "fn": sudocmd_find,
        "params": ["cmd"],
        "description": "Find sudo command",
    },
    "add_cmd": {
        "fn": sudocmd_add,
        "params": ["cmd"],
        "description": "Add sudo command definition",
    },
}
