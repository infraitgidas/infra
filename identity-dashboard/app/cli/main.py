"""Click root group for the gidas-identity CLI.

Defines the top-level ``cli`` group and registers subcommand groups
(``user``, ``group``, ``hbac``) from their respective modules.
"""

# NOTE: imports at bottom to avoid circular dependency issues.
# They are deferred (inside the module body) intentionally.

from __future__ import annotations

import logging

import click

from app.config import AppConfig
from app.logging import setup_logging

logger = logging.getLogger("gidas-identity")


# ── Global options ─────────────────────────────────────────────────────

@click.group()
@click.option(
    "--secrets",
    envvar="GIDAS_SECRETS_PATH",
    default=None,
    help="Path to SOPS-encrypted secrets YAML",
)
@click.option(
    "--verbose",
    is_flag=True,
    default=False,
    help="Enable debug-level logging",
)
@click.pass_context
def cli(ctx: click.Context, secrets: str | None, verbose: bool) -> None:
    """gidas-identity — Unified CLI for AD + FreeIPA identity management.

    Operates on Active Directory (via WinRM + PowerShell) and FreeIPA
    (via SSH + ipa CLI) simultaneously.
    """
    level = logging.DEBUG if verbose else logging.INFO
    setup_logging(level=level)

    ctx.ensure_object(dict)
    if secrets:
        ctx.obj["config"] = AppConfig.from_secrets(secrets)
        logger.info("Configuration loaded from %s", secrets)


# ── Register subcommand groups ─────────────────────────────────────────

from app.cli.user import user_group
from app.cli.group import group_group
from app.cli.hbac import hbac_group
from app.cli.password import password_cmd

cli.add_command(user_group)
cli.add_command(group_group)
cli.add_command(hbac_group)

# password is a subcommand of the user group, not a top-level group
user_group.add_command(password_cmd)
