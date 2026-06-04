"""PowerShell templates for Active Directory password operations.

Uses ``pwdLastSet=0`` to force password change at next login, per
project conventions.
"""

from __future__ import annotations

from typing import Any


def reset_password(
    username: str,
    password: str,
    *,
    force_change: bool = True,
) -> str:
    """PowerShell script to reset a user's password.

    Sets ``-ChangePasswordAtLogon $true`` and ``pwdLastSet=0`` so the
    user MUST change their password on next login.
    """
    return f"""$sec = ConvertTo-SecureString "{password}" -AsPlainText -Force
Set-ADAccountPassword -Identity '{username}' -NewPassword $sec -Reset
Set-ADUser -Identity '{username}' -ChangePasswordAtLogon ${str(force_change).lower()}
Set-ADUser -Identity '{username}' -Replace @{{pwdLastSet=0}}
"""


# ── Template registry ─────────────────────────────────────────────────

TEMPLATES: dict[str, dict[str, Any]] = {
    "reset": {
        "fn": reset_password,
        "params": ["username", "password"],
        "description": "Reset AD password and force change at next logon",
    },
}
