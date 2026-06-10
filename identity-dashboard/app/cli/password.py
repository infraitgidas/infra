"""Click command for password operations (nested under the user group).

Usage:

    gidas-identity user password <username> --reset [--notify] [--dry-run]
    gidas-identity user password <username> --set <password> [--no-expire] [--notify] [--dry-run]
"""

from __future__ import annotations

import logging
import secrets

import click

from app.ad.client import ADClient
from app.ad.password import reset_password as ad_reset_password
from app.config import AppConfig
from app.freeipa.client import FreeIPAClient
from app.freeipa.password import passwd as ipa_passwd
from app.notify.sender import EmailSender
from app.notify.templates import password_reset as email_password_reset

logger = logging.getLogger(__name__)


def _get_config(ctx: click.Context) -> AppConfig:
    config: AppConfig | None = ctx.obj.get("config")
    if config is None:
        raise click.UsageError(
            "Secrets not loaded. Use --secrets or set GIDAS_SECRETS_PATH."
        )
    return config


# ── Password command (registered under user group) ─────────────────────

@click.command(name="password")
@click.argument("username")
@click.option(
    "--reset",
    is_flag=True,
    default=False,
    help="Generate and set a random password",
)
@click.option(
    "--set",
    "set_password",
    default=None,
    help="Set a specific password (use --set '...')",
)
@click.option(
    "--no-expire",
    is_flag=True,
    default=False,
    help="Do NOT force password change at next login",
)
@click.option(
    "--notify",
    is_flag=True,
    default=False,
    help="Send email with the new password",
)
@click.option(
    "--dry-run",
    is_flag=True,
    default=False,
    help="Print actions without executing",
)
@click.pass_context
def password_cmd(
    ctx: click.Context,
    username: str,
    reset: bool,
    set_password: str | None,
    no_expire: bool,
    notify: bool,
    dry_run: bool,
) -> None:
    """Reset or set a user's password in AD and FreeIPA."""
    if not reset and set_password is None:
        raise click.UsageError("Either --reset or --set <password> is required")
    if reset and set_password is not None:
        raise click.UsageError("--reset and --set are mutually exclusive")

    password = set_password if set_password else secrets.token_urlsafe(16)
    force_change = not no_expire

    if dry_run:
        click.echo(f"[DRY-RUN] Would change password for: {username}")
        click.echo(f"           New password: {password}")
        click.echo(
            "           Force change at next login: {}".format(
                "yes" if force_change else "no"
            )
        )
        click.echo("           AD: Set-ADAccountPassword + Set-ADUser -ChangePasswordAtLogon")
        click.echo("           FreeIPA: ipa passwd (via stdin)")
        if notify:
            click.echo("           Email with new password would be sent to admin")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    # ── 1. AD: Reset password ──────────────────────────────────────
    logger.info("Resetting AD password for %s ...", username)
    ps = ad_reset_password(username, password, force_change=force_change)
    result = ad.run_ps(ps)
    if not result["ok"]:
        click.echo(f"ERROR: AD password reset failed: {result['error']}", err=True)
        raise click.Abort()

    # ── 2. FreeIPA: Reset password ─────────────────────────────────
    try:
        logger.info("Resetting FreeIPA password for %s ...", username)
        ipa_cmd = ipa_passwd(username, password)
        result = freeipa.run(ipa_cmd, timeout=30)
        if not result["ok"]:
            err_msg = result.get("error", "unknown")
            logger.error("FreeIPA password reset failed: %s", err_msg)
            # Rollback AD — reset to another random password, mark for change
            rollback_pw = secrets.token_urlsafe(16)
            ad.run_ps(ad_reset_password(username, rollback_pw, force_change=True))
            click.echo(
                "ERROR: FreeIPA password reset failed — AD password rolled back: {0}".format(
                    err_msg
                ),
                err=True,
            )
            raise click.Abort()
    finally:
        freeipa.close()

    # ── 3. Email notification ──────────────────────────────────────
    if notify:
        try:
            sender = EmailSender(config.smtp)
            subject, body = email_password_reset(username, username, password)
            sender.send(subject, body)
        except Exception as exc:
            logger.warning("Email notification failed: %s", exc)

    click.echo(f"Password changed for '{username}'.")
    click.echo(f"New password: {password}")
    if force_change:
        click.echo("User MUST change password at next login.")
