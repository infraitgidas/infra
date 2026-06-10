"""Click commands for user operations (AD + FreeIPA)."""

from __future__ import annotations

import logging
import secrets

import click

from app.ad.client import ADClient
from app.ad.group import add_member as ad_group_add_member
from app.ad.group import get_members as ad_group_get_members
from app.ad.user import create_user as ad_create_user
from app.ad.user import disable_user as ad_disable_user
from app.ad.user import enable_user as ad_enable_user
from app.ad.user import get_user as ad_get_user
from app.ad.user import remove_user as ad_remove_user
from app.ad.user import set_user as ad_set_user
from app.config import AppConfig, resolve_default_group, resolve_ou_path
from app.freeipa.client import FreeIPAClient
from app.freeipa.group import group_add_member as ipa_group_add_member
from app.freeipa.user import user_add as ipa_user_add
from app.freeipa.user import user_del as ipa_user_del
from app.freeipa.user import user_disable as ipa_user_disable
from app.freeipa.user import user_enable as ipa_user_enable
from app.freeipa.user import user_find as ipa_user_find
from app.notify.sender import EmailSender
from app.notify.templates import user_created as email_user_created
from app.notify.templates import user_modified as email_user_modified
from app.notify.templates import user_welcome as email_user_welcome

logger = logging.getLogger(__name__)


def _get_config(ctx: click.Context) -> AppConfig:
    """Retrieve ``AppConfig`` from the Click context or raise."""
    config: AppConfig | None = ctx.obj.get("config")
    if config is None:
        raise click.UsageError(
            "Secrets not loaded. Use --secrets or set GIDAS_SECRETS_PATH."
        )
    return config


def _parse_name(full_name: str) -> tuple[str, str]:
    """Split ``'First Last'`` into ``(first, last)``."""
    parts = full_name.strip().split(maxsplit=1)
    if len(parts) != 2:
        raise click.UsageError("--name must be 'First Last' (two words)")
    return parts[0], parts[1]


# ── User group ─────────────────────────────────────────────────────────

@click.group(name="user")
def user_group() -> None:
    """Manage user accounts (AD + FreeIPA)."""


# ── Create ─────────────────────────────────────────────────────────────

@user_group.command()
@click.option("--name", required=True, help="Full name (First Last)")
@click.option("--username", required=True, help="sAMAccountName / login")
@click.option("--role", required=True, help="Role: director|vicedirector|coordinador|becario")
@click.option("--proyecto", required=True, help="Project name (e.g. Telepark)")
@click.option("--email", default=None, help="Email address")
@click.option("--phone", default=None, help="Phone number")
@click.option("--notify", is_flag=True, default=False, help="Send email notification")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def create(
    ctx: click.Context,
    name: str,
    username: str,
    role: str,
    proyecto: str,
    email: str | None,
    phone: str | None,
    notify: bool,
    dry_run: bool,
) -> None:
    """Create a user account in AD and FreeIPA."""
    first, last = _parse_name(name)
    try:
        ou_path = resolve_ou_path(role)
        default_group = resolve_default_group(role)
    except ValueError as exc:
        raise click.UsageError(str(exc)) from exc
    password = secrets.token_urlsafe(16)

    if dry_run:
        click.echo(f"[DRY-RUN] Would create user: {username} ({name})")
        click.echo(f"           Role: {role}")
        click.echo(f"           OU: {ou_path}")
        click.echo(f"           Default group: {default_group}")
        click.echo(f"           Project: {proyecto}")
        click.echo(f"           Password: {password}")
        click.echo(f"           AD: New-ADUser + Set-ADUser + Add-ADGroupMember")
        click.echo(f"           FreeIPA: ipa user-add + ipa group-add-member")
        if notify:
            click.echo("           Email notification would be sent to admin")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    # ── Pre-check: verify user does NOT exist in AD ────────────────
    ad_check = ad.run_ps(ad_get_user(username), timeout=15)
    if ad_check["ok"]:
        click.echo(f"ERROR: User '{username}' already exists in AD.", err=True)
        raise click.Abort()

    # ── 1. AD: Create user + add to groups ─────────────────────────
    logger.info("Creating AD user %s ...", username)
    create_ps = ad_create_user(
        username, first, last, ou_path, password,
        role=role, proyecto=proyecto, email=email or "",
    )
    result = ad.run_ps(create_ps)
    if not result["ok"]:
        click.echo(f"ERROR: AD user creation failed: {result['error']}", err=True)
        raise click.Abort()

    for group_name in (default_group, proyecto):
        if not group_name:
            continue
        logger.info("Adding %s to AD group %s ...", username, group_name)
        result = ad.run_ps(ad_group_add_member(group_name, username))
        if not result["ok"]:
            click.echo(
                f"WARNING: Could not add to AD group {group_name}: {result['error']}",
                err=True,
            )

    # ── 2. FreeIPA: Create user + add to groups ────────────────────
    ad_created = True
    try:
        logger.info("Creating FreeIPA user %s ...", username)
        ipa_cmd = ipa_user_add(username, first, last, role=role, proyecto=proyecto, email=email or "")
        result = freeipa.run_ipa(ipa_cmd)
        if not result["ok"]:
            err_msg = result.get("error", "unknown")
            logger.error("FreeIPA user creation failed: %s", err_msg)
            # Rollback: remove from AD
            logger.warning("Rolling back AD user %s ...", username)
            ad.run_ps(
                "Remove-ADUser -Identity '{0}' -Confirm:$false".format(username)
            )
            ad_created = False
            click.echo(
                f"ERROR: FreeIPA user creation failed — AD user rolled back: {err_msg}",
                err=True,
            )
            raise click.Abort()

        for group_name in (default_group, proyecto):
            if not group_name:
                continue
            logger.info("Adding %s to FreeIPA group %s ...", username, group_name)
            freeipa.run_ipa(ipa_group_add_member(group_name, username))

    finally:
        freeipa.close()

    # ── 3. Email notification ──────────────────────────────────────
    if notify:
        try:
            sender = EmailSender(config.smtp)

            # Welcome email to the new user
            if email:
                welcome_subj, welcome_body = email_user_welcome(
                    username, name, password,
                )
                sender.send(welcome_subj, welcome_body, to_addr=email)

            # Notification to admin
            admin_subj, admin_body = email_user_created(
                username, name, role, proyecto, password,
            )
            if email:
                admin_body += f"\nEmail: {email}\n"
            sender.send(admin_subj, admin_body)
        except Exception as exc:
            logger.warning("Email notification failed: %s", exc)

    click.echo(f"User '{username}' created successfully.")
    click.echo(f"Temporary password: {password}")


# ── Modify ─────────────────────────────────────────────────────────────

@user_group.command()
@click.option("--username", required=True, help="Username to modify")
@click.option("--disable", is_flag=True, default=False, help="Disable account")
@click.option("--enable", is_flag=True, default=False, help="Enable account")
@click.option("--email", default=None, help="New email address")
@click.option("--phone", default=None, help="New phone number")
@click.option("--notify", is_flag=True, default=False, help="Send email notification")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def modify(
    ctx: click.Context,
    username: str,
    disable: bool,
    enable: bool,
    email: str | None,
    phone: str | None,
    notify: bool,
    dry_run: bool,
) -> None:
    """Modify a user account (disable/enable/update attributes)."""
    if disable and enable:
        raise click.UsageError("--disable and --enable are mutually exclusive")
    if not any([disable, enable, email, phone]):
        raise click.UsageError(
            "At least one of --disable, --enable, --email, --phone is required"
        )

    if dry_run:
        click.echo(f"[DRY-RUN] Would modify user: {username}")
        if disable:
            click.echo("           Disable in AD (Disable-ADAccount)")
            click.echo("           Disable in FreeIPA (ipa user-disable)")
        if enable:
            click.echo("           Enable in AD (Enable-ADAccount)")
            click.echo("           Enable in FreeIPA (ipa user-enable)")
        if email:
            click.echo(f"           Set email: {email}")
        if phone:
            click.echo(f"           Set phone: {phone}")
        if notify:
            click.echo("           Email notification would be sent")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    changes: list[str] = []

    # ── Disable ────────────────────────────────────────────────────
    if disable:
        logger.info("Disabling user %s in AD ...", username)
        result = ad.run_ps(ad_disable_user(username))
        if result["ok"]:
            changes.append("disabled in AD")
        else:
            click.echo(f"WARNING: AD disable failed: {result['error']}", err=True)

        try:
            logger.info("Disabling user %s in FreeIPA ...", username)
            result = freeipa.run_ipa(ipa_user_disable(username))
            if result["ok"]:
                changes.append("disabled in FreeIPA")
            else:
                click.echo(
                    "WARNING: FreeIPA disable failed: {0}".format(
                        result.get("error", "unknown")
                    ),
                    err=True,
                )
        finally:
            freeipa.close()

    # ── Enable ─────────────────────────────────────────────────────
    if enable:
        logger.info("Enabling user %s in AD ...", username)
        result = ad.run_ps(ad_enable_user(username))
        if result["ok"]:
            changes.append("enabled in AD")
        else:
            click.echo(f"WARNING: AD enable failed: {result['error']}", err=True)

        try:
            logger.info("Enabling user %s in FreeIPA ...", username)
            result = freeipa.run_ipa(ipa_user_enable(username))
            if result["ok"]:
                changes.append("enabled in FreeIPA")
            else:
                click.echo(
                    "WARNING: FreeIPA enable failed: {0}".format(
                        result.get("error", "unknown")
                    ),
                    err=True,
                )
        finally:
            freeipa.close()

    # ── Email notification ─────────────────────────────────────────
    if notify and changes:
        try:
            sender = EmailSender(config.smtp)
            subject, body = email_user_modified(username, ", ".join(changes))
            sender.send(subject, body)
        except Exception as exc:
            logger.warning("Email notification failed: %s", exc)

    if changes:
        click.echo(f"User '{username}' modified: {'; '.join(changes)}")
    else:
        click.echo(f"No changes made for user '{username}'.")


# ── List ───────────────────────────────────────────────────────────────

@user_group.command(name="list")
@click.option("--ou", default=None, help="Filter by OU (partial DN match)")
@click.option("--role", default=None, help="Filter by role (Title attribute)")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def list_users(ctx: click.Context, ou: str | None, role: str | None, dry_run: bool) -> None:
    """List user accounts from Active Directory."""
    if dry_run:
        click.echo("[DRY-RUN] Would list users from Active Directory")
        if ou:
            click.echo(f"           OU filter: {ou}")
        if role:
            click.echo(f"           Role filter: {role}")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)

    filters = []
    if role:
        filters.append(f"Title -like '{role}'")
    if ou:
        filters.append(f"DistinguishedName -like '*{ou}*'")

    where = " -Filter '({0})'".format(" -and ".join(filters)) if filters else " -Filter *"
    ps = (
        "Get-ADUser {0} -Properties Title,Department,Enabled "
        "| Select-Object Name,SamAccountName,Title,Department,Enabled "
        "| Format-Table -AutoSize"
    ).format(where)

    result = ad.run_ps(ps)
    if result["ok"]:
        click.echo(result["output"])
    else:
        click.echo(f"ERROR: {result['error']}", err=True)


# ── Show ───────────────────────────────────────────────────────────────

@user_group.command(name="show")
@click.argument("username")
@click.option("--dry-run", is_flag=True, default=False, help="Print actions without executing")
@click.pass_context
def show_user(ctx: click.Context, username: str, dry_run: bool) -> None:
    """Show details for a specific user in AD and FreeIPA."""
    if dry_run:
        click.echo(f"[DRY-RUN] Would show details for user: {username}")
        click.echo("           AD: Get-ADUser")
        click.echo("           FreeIPA: ipa user-find")
        return

    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    # AD
    click.echo("── AD ──")
    result = ad.run_ps(
        ad_get_user(username, "Title,Department,Enabled,EmailAddress,TelephoneNumber"),
    )
    if result["ok"]:
        click.echo(result["output"])
    else:
        click.echo(f"AD lookup: {result['error']}")

    # FreeIPA
    click.echo("── FreeIPA ──")
    try:
        result = freeipa.run_ipa(ipa_user_find(username))
        if result["ok"]:
            click.echo(result["output"])
        else:
            click.echo(f"FreeIPA lookup: {result.get('error', 'unknown')}")
    finally:
        freeipa.close()


# ── Delete ─────────────────────────────────────────────────────────────

@user_group.command(name="delete")
@click.argument("username")
@click.option("--notify", is_flag=True, help="Send email notification")
@click.option("--dry-run", is_flag=True, help="Preview changes without executing")
@click.pass_context
def delete_user(ctx: click.Context, username: str, notify: bool, dry_run: bool) -> None:
    """Delete a user account from AD and FreeIPA."""
    config = _get_config(ctx)
    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)
    changes: list[str] = []

    try:
        if dry_run:
            click.echo(f"[DRY-RUN] Would delete user: {username}")
            click.echo("           AD: Remove-ADUser")
            click.echo("           FreeIPA: ipa user-del")
            changes.append(f"Deleted user {username}")
        else:
            # AD
            click.echo(f"  AD: Removing user {username}...")
            result = ad.run_ps(ad_remove_user(username))
            if not result["ok"]:
                click.echo(f"  AD error: {result['error']}", err=True)
            else:
                click.echo("  AD: OK")

            # FreeIPA
            click.echo(f"  FreeIPA: Removing user {username}...")
            result = freeipa.run_ipa(ipa_user_del(username))
            if result["ok"]:
                click.echo("  FreeIPA: OK")
            else:
                click.echo(f"  FreeIPA error: {result.get('error', 'unknown')}", err=True)

            changes.append(f"Deleted user {username}")
            click.echo(f"User {username} deleted successfully.")

        # Notification
        if notify and changes:
            try:
                sender = EmailSender(config.smtp)
                subject = f"[GIDAS Identity] User deleted: {username}"
                body = "\n".join(changes)
                sender.send(subject, body)
                click.echo("  Notification sent.")
            except Exception as e:
                click.echo(f"  Warning: notification failed: {e}", err=True)

    finally:
        freeipa.close()
