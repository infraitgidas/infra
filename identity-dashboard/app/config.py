"""Configuration model — loaded from SOPS-decrypted secrets in memory."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from app.secrets import load_secrets


# ── Role → OU path mapping ─────────────────────────────────────────────
# Must match the AD structure defined in design.md
OU_MAPPING: dict[str, str] = {
    "director": "OU=Direccion,DC=GDC01,DC=local",
    "vicedirector": "OU=Direccion,DC=GDC01,DC=local",
    "coordinador": "OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local",
    "becario": "OU=Becarios,DC=GDC01,DC=local",
}

# Default group per role (sAMAccountName)
ROLE_DEFAULT_GROUP: dict[str, str] = {
    "director": "G-Direccion",
    "vicedirector": "G-Direccion",
    "coordinador": "G-Coordinadores",
    "becario": "G-Becarios",
}


def resolve_ou_path(role: str) -> str:
    """Return the AD OU path for *role*, or raise ``ValueError``."""
    path = OU_MAPPING.get(role.lower())
    if path is None:
        valid = ", ".join(OU_MAPPING)
        msg = f"Unknown role '{role}'. Valid roles: {valid}"
        raise ValueError(msg)
    return path


def resolve_default_group(role: str) -> str:
    """Return the default AD/FreeIPA group for *role*."""
    group = ROLE_DEFAULT_GROUP.get(role.lower())
    if group is None:
        valid = ", ".join(ROLE_DEFAULT_GROUP)
        msg = f"Unknown role '{role}'. Valid roles: {valid}"
        raise ValueError(msg)
    return group


def build_sam_account_name(first: str, last: str) -> str:
    """Build sAMAccountName: first-letter + full surname, lowercase, no spaces."""
    return (first[0] + last).lower().replace(" ", "")


# ── Dataclasses ────────────────────────────────────────────────────────


@dataclass
class ADConfig:
    """Active Directory connection settings."""

    endpoint: str
    username: str
    password: str


@dataclass
class FreeIPAConfig:
    """FreeIPA connection settings (via SSH + kinit)."""

    host: str
    ssh_user: str
    ssh_key_path: str
    admin_password: str


@dataclass
class SMTPConfig:
    """Email notification settings."""

    smtp_host: str
    smtp_port: int = 587
    smtp_tls: bool = True
    smtp_user: str | None = None
    smtp_password: str | None = None
    from_addr: str = "admin-identity@gidas.local"
    to_addr: str = "admin-identity@gidas.local"


@dataclass
class AppConfig:
    """Top-level application configuration."""

    ad: ADConfig
    freeipa: FreeIPAConfig
    smtp: SMTPConfig
    ou_mapping: dict[str, str] = field(default_factory=lambda: dict(OU_MAPPING))
    role_default_group: dict[str, str] = field(
        default_factory=lambda: dict(ROLE_DEFAULT_GROUP)
    )

    @classmethod
    def from_secrets(cls, path: str | None = None) -> AppConfig:
        """Build config by decrypting the SOPS-encrypted secrets file."""
        data = load_secrets(path)

        ad_section: dict[str, Any] = data.get("ad", {})
        freeipa_section: dict[str, Any] = data.get("freeipa", {})
        email_section: dict[str, Any] = data.get("email", {})

        return cls(
            ad=ADConfig(
                endpoint=ad_section.get("endpoint", "http://192.168.1.117:5985/wsman"),
                username=ad_section.get("username", "GDC01\\Administrator"),
                password=ad_section["password"],
            ),
            freeipa=FreeIPAConfig(
                host=freeipa_section.get("host", "ipa-gidas.gidas.internal"),
                ssh_user=freeipa_section.get("ssh_user", "root"),
                ssh_key_path=freeipa_section.get(
                    "ssh_key_path", "/secrets/ipa-admin-key"
                ),
                admin_password=freeipa_section["admin_password"],
            ),
            smtp=SMTPConfig(
                smtp_host=email_section.get("smtp_host", "mail.gidas.local"),
                smtp_port=email_section.get("smtp_port", 587),
                smtp_tls=email_section.get("smtp_tls", True),
                smtp_user=email_section.get("smtp_user"),
                smtp_password=email_section.get("smtp_password"),
                from_addr=email_section.get(
                    "from_addr", "admin-identity@gidas.local"
                ),
                to_addr=email_section.get("to_addr", "admin-identity@gidas.local"),
            ),
        )
