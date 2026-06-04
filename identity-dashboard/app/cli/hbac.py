"""Click commands for FreeIPA HBAC (Host-Based Access Control) operations."""

from __future__ import annotations

import logging

import click

from app.config import AppConfig
from app.freeipa.client import FreeIPAClient
from app.freeipa.hbac import hbacrule_disable as ipa_hbacrule_disable
from app.freeipa.hbac import hbacrule_enable as ipa_hbacrule_enable
from app.freeipa.hbac import hbacrule_find as ipa_hbacrule_find
from app.freeipa.hbac import hbacrule_find_by_user as ipa_hbacrule_find_by_user
from app.freeipa.hbac import hbactest as ipa_hbactest

logger = logging.getLogger(__name__)


def _get_config(ctx: click.Context) -> AppConfig:
    config: AppConfig | None = ctx.obj.get("config")
    if config is None:
        raise click.UsageError(
            "Secrets not loaded. Use --secrets or set GIDAS_SECRETS_PATH."
        )
    return config


# ── HBAC group ─────────────────────────────────────────────────────────

@click.group(name="hbac")
def hbac_group() -> None:
    """Manage FreeIPA HBAC (Host-Based Access Control) rules."""


# ── List ───────────────────────────────────────────────────────────────

@hbac_group.command(name="list")
@click.option("--user", "username", default=None, help="Filter rules by username")
@click.option("--host", default=None, help="Filter rules by host")
@click.pass_context
def list_rules(
    ctx: click.Context,
    username: str | None,
    host: str | None,
) -> None:
    """List HBAC rules, optionally filtered by user or host."""
    config = _get_config(ctx)
    freeipa = FreeIPAClient(config.freeipa)

    try:
        if username:
            click.echo(f"HBAC rules for user '{username}':")
            result = freeipa.run_ipa(ipa_hbacrule_find_by_user(username))
        elif host:
            # The FreeIPA CLI doesn't filter HBAC rules directly by host
            # in hbacrule-find, so we list all and show context
            click.echo(f"HBAC rules (context for host '{host}'):")
            result = freeipa.run_ipa(ipa_hbacrule_find(""))
        else:
            click.echo("All HBAC rules:")
            result = freeipa.run_ipa(ipa_hbacrule_find(""))

        if result["ok"]:
            click.echo(result["output"])
        else:
            click.echo(
                "ERROR: HBAC query failed: {0}".format(result.get("error", "unknown")),
                err=True,
            )
    finally:
        freeipa.close()


# ── Toggle ─────────────────────────────────────────────────────────────

@hbac_group.command(name="toggle")
@click.option("--rule", required=True, help="HBAC rule name")
@click.option(
    "--enable/--disable",
    "enable_rule",
    default=True,
    help="Enable or disable the rule",
)
@click.pass_context
def toggle_rule(
    ctx: click.Context,
    rule: str,
    enable_rule: bool,
) -> None:
    """Enable or disable an HBAC rule in FreeIPA."""
    config = _get_config(ctx)
    freeipa = FreeIPAClient(config.freeipa)

    action = "enable" if enable_rule else "disable"
    logger.info("%s HBAC rule %s ...", action.capitalize(), rule)

    try:
        if enable_rule:
            result = freeipa.run_ipa(ipa_hbacrule_enable(rule))
        else:
            result = freeipa.run_ipa(ipa_hbacrule_disable(rule))

        if result["ok"]:
            click.echo(f"HBAC rule '{rule}' {action}d successfully.")
        else:
            click.echo(
                "ERROR: HBAC rule {0} failed: {1}".format(
                    action, result.get("error", "unknown")
                ),
                err=True,
            )
    finally:
        freeipa.close()


# ── Test ───────────────────────────────────────────────────────────────

@hbac_group.command(name="test")
@click.option("--user", "username", required=True, help="Username to test")
@click.option("--host", required=True, help="Host to test access against")
@click.option(
    "--service",
    default="sshd",
    show_default=True,
    help="Service to test (default: sshd)",
)
@click.pass_context
def test_access(
    ctx: click.Context,
    username: str,
    host: str,
    service: str,
) -> None:
    """Simulate an HBAC access check (ipa hbactest)."""
    config = _get_config(ctx)
    freeipa = FreeIPAClient(config.freeipa)

    try:
        result = freeipa.run_ipa(ipa_hbactest(username, host, service))
        if result["ok"]:
            click.echo(result["output"])
        else:
            click.echo(
                "HBAC test failed: {0}".format(result.get("error", "unknown")),
                err=True,
            )
    finally:
        freeipa.close()
