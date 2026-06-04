"""Click commands for group membership operations (AD + FreeIPA)."""

from __future__ import annotations

import logging

import click

from app.ad.client import ADClient
from app.ad.group import add_member as ad_add_member
from app.ad.group import get_members as ad_get_members
from app.ad.group import remove_member as ad_remove_member
from app.config import AppConfig
from app.freeipa.client import FreeIPAClient
from app.freeipa.group import group_add_member as ipa_group_add_member
from app.freeipa.group import group_find as ipa_group_find
from app.freeipa.group import group_remove_member as ipa_group_remove_member
from app.notify.sender import EmailSender
from app.notify.templates import (
    group_membership_changed as email_group_membership_changed,
)

logger = logging.getLogger(__name__)


def _get_config(ctx: click.Context) -> AppConfig:
    config: AppConfig | None = ctx.obj.get("config")
    if config is None:
        raise click.UsageError(
            "Secrets not loaded. Use --secrets or set GIDAS_SECRETS_PATH."
        )
    return config


# ── Group group ────────────────────────────────────────────────────────

@click.group(name="group")
def group_group() -> None:
    """Manage group memberships (AD + FreeIPA)."""


# ── Add member ─────────────────────────────────────────────────────────

@group_group.command(name="add-member")
@click.option("--group", "group_name", required=True, help="Group name (e.g. PROY-Telepark)")
@click.option("--user", "username", required=True, help="Username to add")
@click.option("--notify", is_flag=True, default=False, help="Send email notification")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def add_member(
    ctx: click.Context,
    group_name: str,
    username: str,
    notify: bool,
    dry_run: bool,
) -> None:
    """Add a user to a group in AD and FreeIPA."""
    if dry_run:
        click.echo(f"[DRY-RUN] Would add user '{username}' to group '{group_name}'")
        click.echo("           AD: Add-ADGroupMember")
        click.echo("           FreeIPA: ipa group-add-member")
        if notify:
            click.echo("           Email notification would be sent")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    # ── 1. AD: Add member ──────────────────────────────────────────
    logger.info("Adding %s to AD group %s ...", username, group_name)
    ps = ad_add_member(group_name, username)
    result = ad.run_ps(ps)
    if not result["ok"]:
        click.echo(
            "ERROR: AD add-member failed: {0}".format(result["error"]),
            err=True,
        )
        raise click.Abort()

    # ── 2. FreeIPA: Add member ─────────────────────────────────────
    try:
        logger.info("Adding %s to FreeIPA group %s ...", username, group_name)
        ipa_cmd = ipa_group_add_member(group_name, username)
        result = freeipa.run_ipa(ipa_cmd)
        if not result["ok"]:
            err_msg = result.get("error", "unknown")
            logger.error("FreeIPA add-member failed: %s", err_msg)
            # Rollback AD
            logger.warning("Rolling back AD group membership for %s ...", username)
            ad.run_ps(ad_remove_member(group_name, username))
            click.echo(
                "ERROR: FreeIPA add-member failed — AD membership rolled back: {0}".format(
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
            subject, body = email_group_membership_changed(
                username, group_name, "added",
            )
            sender.send(subject, body)
        except Exception as exc:
            logger.warning("Email notification failed: %s", exc)

    click.echo(f"User '{username}' added to group '{group_name}'.")


# ── Remove member ──────────────────────────────────────────────────────

@group_group.command(name="remove-member")
@click.option("--group", "group_name", required=True, help="Group name")
@click.option("--user", "username", required=True, help="Username to remove")
@click.option("--notify", is_flag=True, default=False, help="Send email notification")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def remove_member(
    ctx: click.Context,
    group_name: str,
    username: str,
    notify: bool,
    dry_run: bool,
) -> None:
    """Remove a user from a group in AD and FreeIPA."""
    if dry_run:
        click.echo(f"[DRY-RUN] Would remove user '{username}' from group '{group_name}'")
        click.echo("           AD: Remove-ADGroupMember")
        click.echo("           FreeIPA: ipa group-remove-member")
        if notify:
            click.echo("           Email notification would be sent")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    # ── 1. AD: Remove member ───────────────────────────────────────
    logger.info("Removing %s from AD group %s ...", username, group_name)
    ps = ad_remove_member(group_name, username)
    result = ad.run_ps(ps)
    if not result["ok"]:
        click.echo(
            "ERROR: AD remove-member failed: {0}".format(result["error"]),
            err=True,
        )
        raise click.Abort()

    # ── 2. FreeIPA: Remove member ──────────────────────────────────
    try:
        logger.info("Removing %s from FreeIPA group %s ...", username, group_name)
        ipa_cmd = ipa_group_remove_member(group_name, username)
        result = freeipa.run_ipa(ipa_cmd)
        if not result["ok"]:
            logger.warning(
                "FreeIPA remove-member failed (non-fatal): %s",
                result.get("error", "unknown"),
            )
            # Not rolled back since user IS already removed from AD
            click.echo(
                "WARNING: FreeIPA remove-member failed: {0}".format(
                    result.get("error", "unknown")
                ),
                err=True,
            )
    finally:
        freeipa.close()

    # ── 3. Email notification ──────────────────────────────────────
    if notify:
        try:
            sender = EmailSender(config.smtp)
            subject, body = email_group_membership_changed(
                username, group_name, "removed",
            )
            sender.send(subject, body)
        except Exception as exc:
            logger.warning("Email notification failed: %s", exc)

    click.echo(f"User '{username}' removed from group '{group_name}'.")


# ── List ───────────────────────────────────────────────────────────────

@group_group.command(name="list")
@click.option(
    "--prefix",
    default=None,
    help="Filter by group prefix (e.g. G-, PROY-, SRV-)",
)
@click.pass_context
def list_groups(ctx: click.Context, prefix: str | None) -> None:
    """List groups from Active Directory."""
    config = _get_config(ctx)
    ad = ADClient(config.ad)

    filter_clause = ""
    if prefix:
        filter_clause = " -Filter \"Name -like '{0}*'\"".format(prefix)

    ps = (
        "Get-ADGroup{0} -Properties GroupCategory,Description "
        "| Select-Object Name,GroupCategory,Description "
        "| Format-Table -AutoSize"
    ).format(filter_clause)

    result = ad.run_ps(ps)
    if result["ok"]:
        click.echo(result["output"])
    else:
        click.echo(f"ERROR: {result['error']}", err=True)
