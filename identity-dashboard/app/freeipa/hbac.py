"""FreeIPA HBAC (Host-Based Access Control) operations.

Wrappers around ``ipa hbacrule-*`` and ``ipa hbacsvc-*`` commands.

.. note::
    All commands include a ``--notify`` wiring placeholder for future
    integration with the notification system.
"""

from __future__ import annotations

from typing import Any


def hbacrule_find_by_user(username: str) -> str:
    """List HBAC rules applicable to *username*."""
    return f"hbacrule-find --users={username} --all"


def hbacrule_enable(rule: str) -> str:
    """Enable an HBAC rule by name."""
    return f"hbacrule-enable {rule}"


def hbacrule_disable(rule: str) -> str:
    """Disable an HBAC rule by name."""
    return f"hbacrule-disable {rule}"


def hbacrule_find(rule: str) -> str:
    """Find an HBAC rule by name or pattern."""
    return f"hbacrule-find {rule} --all"


def hbacsvc_find(svc: str) -> str:
    """Find an HBAC service by name or pattern."""
    return f"hbacsvc-find {svc}"


def hbactest(
    user: str,
    host: str,
    service: str,
) -> str:
    """Simulate an HBAC access check (``ipa hbactest``)."""
    return f"hbactest --user={user} --host={host} --service={service}"


# ── Command registry ──────────────────────────────────────────────────

COMMANDS: dict[str, dict[str, Any]] = {
    "find_by_user": {
        "fn": hbacrule_find_by_user,
        "params": ["username"],
        "description": "List HBAC rules for a user",
    },
    "enable": {
        "fn": hbacrule_enable,
        "params": ["rule"],
        "description": "Enable HBAC rule",
    },
    "disable": {
        "fn": hbacrule_disable,
        "params": ["rule"],
        "description": "Disable HBAC rule",
    },
    "find": {
        "fn": hbacrule_find,
        "params": ["rule"],
        "description": "Find HBAC rule",
    },
    "svc_find": {
        "fn": hbacsvc_find,
        "params": ["svc"],
        "description": "Find HBAC service",
    },
    "test": {
        "fn": hbactest,
        "params": ["user", "host", "service"],
        "description": "Simulate HBAC access check",
    },
}
