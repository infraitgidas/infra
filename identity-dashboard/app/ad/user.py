"""PowerShell templates for Active Directory user operations.

Uses ``-PasswordNeverExpires $true`` and ``pwdLastSet=0`` for first-login
password change, per project conventions.  ``-ChangePasswordAtLogon`` is
NOT used because it conflicts with ``-PasswordNeverExpires $true`` in
New-ADUser; ``pwdLastSet=0`` (via Set-ADUser) is the reliable approach.

sAMAccountName convention (enforced by ``config.build_sam_account_name``):
first-letter + full surname, lowercase, no spaces.
UPN suffix: ``@GDC01.local``.
"""

from __future__ import annotations

from typing import Any

# ── User CRUD templates ───────────────────────────────────────────────


def create_user(
    username: str,
    first: str,
    last: str,
    ou_path: str,
    password: str,
    *,
    role: str = "",
    proyecto: str = "",
    force_change: bool = True,
) -> str:
    """PowerShell script to create an AD user and set password-change flags."""
    return f"""$sec = ConvertTo-SecureString "{password}" -AsPlainText -Force
New-ADUser -Name "{first} {last}" `
    -GivenName "{first}" `
    -Surname "{last}" `
    -SamAccountName "{username}" `
    -UserPrincipalName "{username}@GDC01.local" `
    -Path "{ou_path}" `
    -AccountPassword $sec `
    -Enabled $true `
    -PasswordNeverExpires $true `
    -Title "{role}" `
    -Department "{proyecto}" `
    -Description "Creado via gidas-identity CLI"

# Force password change at first login
Set-ADUser -Identity "{username}" -Replace @{{pwdLastSet=0}}
"""


def get_user(username: str, properties: str = "*") -> str:
    """PowerShell script to retrieve an AD user's attributes."""
    return f"Get-ADUser -Identity '{username}' -Properties {properties}"


def set_user(
    username: str,
    *,
    role: str | None = None,
    proyecto: str | None = None,
    description: str | None = None,
) -> str:
    """PowerShell script to update AD user attributes."""
    parts = [f"Set-ADUser -Identity '{username}'"]
    if role is not None:
        parts.append(f"    -Title '{role}'")
    if proyecto is not None:
        parts.append(f"    -Department '{proyecto}'")
    if description is not None:
        parts.append(f"    -Description '{description}'")
    parts[-1] = parts[-1].rstrip()
    return "\n".join(parts)


def disable_user(username: str) -> str:
    """PowerShell script to disable an AD account."""
    return f"Disable-ADAccount -Identity '{username}'"


def enable_user(username: str) -> str:
    """PowerShell script to enable an AD account."""
    return f"Enable-ADAccount -Identity '{username}'"


def remove_user(username: str) -> str:
    """PowerShell script to remove an AD user."""
    return f"Remove-ADUser -Identity '{username}' -Confirm:$false"


# ── Template registry (for introspection / testing) ───────────────────

TEMPLATES: dict[str, dict[str, Any]] = {
    "create": {
        "fn": create_user,
        "params": ["username", "first", "last", "ou_path", "password"],
        "description": "Create AD user with password and force-change flag",
    },
    "get": {
        "fn": get_user,
        "params": ["username"],
        "description": "Get AD user attributes",
    },
    "set": {
        "fn": set_user,
        "params": ["username"],
        "description": "Set AD user attributes",
    },
    "disable": {
        "fn": disable_user,
        "params": ["username"],
        "description": "Disable AD account",
    },
    "enable": {
        "fn": enable_user,
        "params": ["username"],
        "description": "Enable AD account",
    },
    "remove": {
        "fn": remove_user,
        "params": ["username"],
        "description": "Remove AD user",
    },
}
