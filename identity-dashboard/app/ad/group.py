"""PowerShell templates for Active Directory group operations."""

from __future__ import annotations

from typing import Any


def add_member(group: str, username: str) -> str:
    """PowerShell script to add a user to a group."""
    return f"Add-ADGroupMember -Identity '{group}' -Members '{username}'"


def remove_member(group: str, username: str) -> str:
    """PowerShell script to remove a user from a group (no confirmation)."""
    return (
        f"Remove-ADGroupMember -Identity '{group}' "
        f"-Members '{username}' -Confirm:$false"
    )


def get_members(group: str) -> str:
    """PowerShell script to list all members of a group."""
    return (
        f"Get-ADGroupMember -Identity '{group}' "
        f"| Select-Object -ExpandProperty SamAccountName"
    )


def get_group(group: str) -> str:
    """PowerShell script to retrieve group metadata."""
    return f"Get-ADGroup -Identity '{group}'"


# ── Template registry ─────────────────────────────────────────────────

TEMPLATES: dict[str, dict[str, Any]] = {
    "add_member": {
        "fn": add_member,
        "params": ["group", "username"],
        "description": "Add user to AD group",
    },
    "remove_member": {
        "fn": remove_member,
        "params": ["group", "username"],
        "description": "Remove user from AD group",
    },
    "get_members": {
        "fn": get_members,
        "params": ["group"],
        "description": "List group members",
    },
    "get_group": {
        "fn": get_group,
        "params": ["group"],
        "description": "Get group metadata",
    },
}
