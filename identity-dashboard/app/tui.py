"""gidas-identity TUI — interactive menu-driven interface.

Usage::

    python -m app.tui --secrets <path>

Requires: rich, questionary (pip install rich questionary)
"""

from __future__ import annotations

import argparse
import logging
import secrets as stdlib_secrets
import sys
from typing import Any

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
import questionary

from app.ad.client import ADClient
from app.ad.group import add_member as ad_add_member
from app.ad.group import remove_member as ad_remove_member
from app.ad.password import reset_password as ad_reset_password
from app.ad.user import create_user as ad_create_user
from app.ad.user import disable_user as ad_disable_user
from app.ad.user import enable_user as ad_enable_user
from app.ad.user import remove_user as ad_remove_user
from app.config import AppConfig, resolve_ou_path
from app.freeipa.client import FreeIPAClient
from app.freeipa.group import group_add_member as ipa_group_add_member
from app.freeipa.group import group_remove_member as ipa_group_remove_member
from app.freeipa.hbac import hbacrule_find as ipa_hbacrule_find
from app.freeipa.hbac import hbactest as ipa_hbactest
from app.freeipa.password import passwd as ipa_passwd
from app.freeipa.user import user_add as ipa_user_add
from app.freeipa.user import user_del as ipa_user_del
from app.freeipa.user import user_disable as ipa_user_disable
from app.freeipa.user import user_enable as ipa_user_enable
from app.freeipa.user import user_find as ipa_user_find
from app.logging import setup_logging
from app.notify.sender import EmailSender
from app.notify.templates import (
    user_created as email_new_user,
    password_reset as email_password_reset,
)

console = Console()
log = logging.getLogger("gidas-identity")


# ── Helpers ──────────────────────────────────────────────────────────


def _load_config(secrets_path: str | None) -> AppConfig:
    """Load configuration from SOPS-encrypted secrets."""
    try:
        config = AppConfig.from_secrets(secrets_path)
        console.print(
            Panel.fit(
                f"Configuración cargada desde: [bold]{secrets_path or 'GIDAS_SECRETS_PATH'}[/]",
                border_style="green",
            )
        )
        return config
    except Exception as e:
        console.print(f"[bold red]ERROR:[/] No se pudo cargar la configuración: {e}")
        sys.exit(1)


def _make_table(title: str, columns: list[str], rows: list[list[str]]) -> Table:
    """Build a rich Table."""
    table = Table(title=title, title_style="bold cyan", border_style="blue")
    for col in columns:
        table.add_column(col, style="white")
    for row in rows:
        table.add_row(*row)
    return table


# ── AD-only commands ────────────────────────────────────────────────


def _list_users(config: AppConfig) -> None:
    """List users from AD."""
    ad = ADClient(config.ad)
    try:
        with console.status("[cyan]Consultando AD...[/]"):
            ps = (
                "Get-ADUser -Filter * -Properties Title,Department,Enabled "
                "| Select-Object Name,SamAccountName,Title,Department,Enabled "
                "| Format-Table -AutoSize"
            )
            result = ad.run_ps(ps)
        if result["ok"]:
            console.print(Panel(result["output"], title="Usuarios AD", border_style="green"))
        else:
            console.print(f"[red]ERROR:[/] {result['error']}")
    finally:
        ad.close()


def _list_groups(config: AppConfig) -> None:
    """List groups from AD."""
    ad = ADClient(config.ad)
    try:
        choice = questionary.select(
            "Filtrar por prefijo:",
            choices=["Todos", "G- (Groups)", "PROY- (Proyectos)", "SRV- (Servicios)", "Otro"],
        ).ask()
        prefix = ""
        if choice == "G- (Groups)":
            prefix = "G-"
        elif choice == "PROY- (Proyectos)":
            prefix = "PROY-"
        elif choice == "SRV- (Servicios)":
            prefix = "SRV-"
        elif choice == "Otro":
            prefix = questionary.text("Prefijo:").ask() or ""

        filter_clause = ""
        if prefix:
            filter_clause = f' -Filter "Name -like \'{prefix}*\'"'
        ps = (
            f"Get-ADGroup{filter_clause} -Properties GroupCategory,Description "
            "| Select-Object Name,GroupCategory,Description "
            "| Format-Table -AutoSize"
        )
        with console.status("[cyan]Consultando AD...[/]"):
            result = ad.run_ps(ps)
        if result["ok"]:
            console.print(Panel(result["output"], title="Grupos AD", border_style="green"))
        else:
            console.print(f"[red]ERROR:[/] {result['error']}")
    finally:
        ad.close()


# ── User create ─────────────────────────────────────────────────────


def _create_user(config: AppConfig) -> None:
    """Interactive user creation (AD + FreeIPA)."""
    console.print(Panel.fit("[bold]Crear usuario[/]", border_style="cyan"))

    full_name = questionary.text("Nombre completo:").ask()
    if not full_name:
        return
    username = questionary.text("Username (login):").ask()
    if not username:
        return
    role = questionary.select(
        "Rol:",
        choices=sorted(config.ou_mapping.keys()),
    ).ask()
    if not role:
        return
    proyecto = questionary.text("Proyecto:").ask()
    if not proyecto:
        return

    notify = questionary.confirm("¿Enviar email al admin?", default=False).ask()

    # ── Resolve data
    password = stdlib_secrets.token_urlsafe(16)
    ou_path = resolve_ou_path(role)
    group_name = config.role_default_group.get(role, "")
    first, *rest = full_name.split(" ", 1)
    last = rest[0] if rest else ""

    # ── Summary
    console.print()
    console.print("[bold]Resumen:[/]")
    table = Table.grid(padding=(0, 2))
    table.add_column("Campo", style="cyan")
    table.add_column("Valor")
    table.add_row("Nombre", full_name)
    table.add_row("Username", username)
    table.add_row("Rol", role)
    table.add_row("OU", ou_path)
    table.add_row("Grupo default", group_name or "—")
    table.add_row("Proyecto", proyecto)
    table.add_row("Password", f"[bold yellow]{password}[/]")
    console.print(table)

    if not questionary.confirm("¿Confirmar creación?", default=False).ask():
        console.print("[yellow]Cancelado[/]")
        return

    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)

    try:
        # ── AD ──
        with console.status("[cyan]Creando en AD...[/]"):
            result = ad.run_ps(
                ad_create_user(username, first, last, ou_path, password,
                               role=role, proyecto=proyecto)
            )
        if not result["ok"]:
            console.print(f"[red]ERROR en AD:[/] {result['error']}")
            return

        # Add to default group in AD
        if group_name:
            with console.status(f"[cyan]Agregando a grupo {group_name} en AD...[/]"):
                result = ad.run_ps(ad_add_member(group_name, username))
            if not result["ok"]:
                console.print(f"[yellow]WARN en AD:[/] No se pudo agregar a grupo: {result['error']}")

        # ── FreeIPA ──
        with console.status("[cyan]Creando en FreeIPA...[/]"):
            result = freeipa.run_ipa(
                ipa_user_add(username, first, last, role=role, proyecto=proyecto)
            )
        if not result["ok"]:
            # Rollback AD
            console.print(f"[red]ERROR en FreeIPA:[/] {result['error']}")
            console.print("[yellow]Rollback: eliminando de AD...[/]")
            ad.run_ps(ad_remove_user(username))
            console.print("[red]Creación fallida — AD revertido[/]")
            return

        # Add to FreeIPA group
        if group_name:
            with console.status(f"[cyan]Agregando a grupo {group_name} en FreeIPA...[/]"):
                freeipa.run_ipa(ipa_group_add_member(group_name, username))

        # ── Notify ──
        if notify:
            try:
                sender = EmailSender(config.smtp)
                subject, body = email_new_user(username, full_name, password)
                sender.send(subject, body)
                console.print("[green]Email de notificación enviado[/]")
            except Exception as e:
                console.print(f"[yellow]WARN:[/] Notificación falló: {e}")

        console.print()
        console.print(Panel.fit(
            f"[bold green]Usuario '{username}' creado exitosamente[/]\n"
            f"Password: [bold yellow]{password}[/]",
            border_style="green",
        ))
    finally:
        freeipa.close()
        ad.close()


# ── User modify (enable / disable) ──────────────────────────────────


def _modify_user(config: AppConfig) -> None:
    """Enable or disable a user in both AD and FreeIPA."""
    username = questionary.text("Username:").ask()
    if not username:
        return

    action = questionary.select(
        "Acción:",
        choices=["Deshabilitar", "Habilitar"],
    ).ask()

    is_disable = action == "Deshabilitar"

    if not questionary.confirm(f"¿{action} usuario '{username}'?", default=False).ask():
        return

    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)
    try:
        with console.status(f"[cyan]{action} en AD...[/]"):
            ps = ad_disable_user(username) if is_disable else ad_enable_user(username)
            result = ad.run_ps(ps)
        if not result["ok"]:
            console.print(f"[red]ERROR en AD:[/] {result['error']}")
            return

        ipa_fn = ipa_user_disable if is_disable else ipa_user_enable
        with console.status(f"[cyan]{action} en FreeIPA...[/]"):
            result = freeipa.run_ipa(ipa_fn(username))
        if not result["ok"]:
            console.print(f"[yellow]WARN en FreeIPA:[/] {result['error']}")

        verb = "deshabilitado" if is_disable else "habilitado"
        console.print(f"[bold green]Usuario '{username}' {verb} correctamente[/]")
    finally:
        freeipa.close()
        ad.close()


# ── Delete user ─────────────────────────────────────────────────────


def _delete_user(config: AppConfig) -> None:
    """Delete a user from AD and FreeIPA."""
    username = questionary.text("Username a eliminar:").ask()
    if not username:
        return

    console.print(f"[bold red]ATENCIÓN:[/] Se eliminará a '{username}' de AD y FreeIPA")
    if not questionary.confirm("¿Estás seguro?", default=False).ask():
        return
    double = questionary.text("Escribí el username para confirmar:").ask()
    if double != username:
        console.print("[red]Cancelado — los nombres no coinciden[/]")
        return

    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)
    try:
        # AD first (source of truth)
        with console.status("[cyan]Eliminando de AD...[/]"):
            result = ad.run_ps(ad_remove_user(username))
        if not result["ok"]:
            console.print(f"[red]ERROR en AD:[/] {result['error']}")
            return

        with console.status("[cyan]Eliminando de FreeIPA...[/]"):
            result = freeipa.run_ipa(ipa_user_del(username))
        if not result["ok"]:
            console.print(f"[yellow]WARN en FreeIPA:[/] {result['error']}")

        console.print(f"[bold green]Usuario '{username}' eliminado[/]")
    finally:
        freeipa.close()
        ad.close()


# ── Password reset ──────────────────────────────────────────────────


def _reset_password(config: AppConfig) -> None:
    """Reset password for a user in both AD and FreeIPA."""
    username = questionary.text("Username:").ask()
    if not username:
        return

    method = questionary.select(
        "Método:",
        choices=["Generar aleatorio", "Especificar password"],
    ).ask()

    password = (
        stdlib_secrets.token_urlsafe(16)
        if method == "Generar aleatorio"
        else questionary.password("Nuevo password:").ask()
    )
    if not password:
        return

    force_change = questionary.confirm("¿Forzar cambio en próximo login?", default=True).ask()
    notify = questionary.confirm("¿Enviar email al admin?", default=False).ask()

    if not questionary.confirm(f"¿Resetear password de '{username}'?", default=False).ask():
        return

    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)
    try:
        with console.status("[cyan]Reseteando password en AD...[/]"):
            result = ad.run_ps(ad_reset_password(username, password, force_change=force_change))
        if not result["ok"]:
            console.print(f"[red]ERROR en AD:[/] {result['error']}")
            return

        with console.status("[cyan]Reseteando password en FreeIPA...[/]"):
            result = freeipa.run(ipa_passwd(username, password), timeout=30)
        if not result["ok"]:
            # Rollback AD to a random password so the old one is invalidated
            rollback = stdlib_secrets.token_urlsafe(16)
            ad.run_ps(ad_reset_password(username, rollback, force_change=True))
            console.print(f"[red]ERROR en FreeIPA — AD revertido:[/] {result['error']}")
            return

        if notify:
            try:
                sender = EmailSender(config.smtp)
                subject, body = email_password_reset(username, username, password)
                sender.send(subject, body)
                console.print("[green]Email de notificación enviado[/]")
            except Exception as e:
                console.print(f"[yellow]WARN:[/] Notificación falló: {e}")

        console.print(Panel.fit(
            f"[bold green]Password de '{username}' cambiado[/]\n"
            f"Nuevo password: [bold yellow]{password}[/]",
            border_style="green",
        ))
    finally:
        freeipa.close()
        ad.close()


# ── Group management ────────────────────────────────────────────────


def _group_menu(config: AppConfig) -> None:
    """Group operations sub-menu."""
    action = questionary.select(
        "Acción de grupo:",
        choices=["Agregar miembro", "Quitar miembro", "Listar grupos"],
    ).ask()
    if not action:
        return

    if action == "Listar grupos":
        _list_groups(config)
        return

    group = questionary.text("Nombre del grupo:").ask()
    if not group:
        return
    username = questionary.text("Username:").ask()
    if not username:
        return

    is_add = action == "Agregar miembro"
    action_verb = "agregar" if is_add else "quitar"
    if not questionary.confirm(
        f"¿{action_verb.capitalize()} '{username}' en '{group}'?", default=False
    ).ask():
        return

    ad = ADClient(config.ad)
    freeipa = FreeIPAClient(config.freeipa)
    try:
        ad_fn = ad_add_member if is_add else ad_remove_member
        ipa_fn = ipa_group_add_member if is_add else ipa_group_remove_member

        with console.status(f"[cyan]{action_verb} en AD...[/]"):
            result = ad.run_ps(ad_fn(group, username))
        if not result["ok"]:
            console.print(f"[red]ERROR en AD:[/] {result['error']}")
            return

        with console.status(f"[cyan]{action_verb} en FreeIPA...[/]"):
            result = freeipa.run_ipa(ipa_fn(group, username))
        if not result["ok"]:
            console.print(f"[yellow]WARN en FreeIPA:[/] {result['error']}")

        console.print(f"[bold green]'{username}' {action_verb}do en '{group}'[/]")
    finally:
        freeipa.close()
        ad.close()


# ── HBAC ────────────────────────────────────────────────────────────


def _hbac_menu(config: AppConfig) -> None:
    """HBAC operations sub-menu."""
    action = questionary.select(
        "Acción HBAC:",
        choices=["Testear acceso SSH", "Listar reglas"],
    ).ask()
    if not action:
        return

    freeipa = FreeIPAClient(config.freeipa)
    try:
        if action == "Listar reglas":
            with console.status("[cyan]Consultando reglas HBAC...[/]"):
                result = freeipa.run_ipa(ipa_hbacrule_find(""))
            if result["ok"]:
                console.print(Panel(
                    result["output"],
                    title="Reglas HBAC",
                    border_style="green",
                ))
            else:
                console.print(f"[red]ERROR:[/] {result['error']}")
        else:
            user = questionary.text("Username:").ask()
            if not user:
                return
            host = questionary.text("Host:").ask()
            if not host:
                return
            service = questionary.text("Servicio:", default="sshd").ask()
            if not service:
                return

            with console.status(f"[cyan]Testeando acceso: {user} → {host}:{service}...[/]"):
                result = freeipa.run_ipa(ipa_hbactest(user, host, service))
            if result["ok"]:
                console.print(Panel(
                    result["output"],
                    title=f"HBAC Test: {user} → {host}:{service}",
                    border_style="green",
                ))
            else:
                console.print(f"[red]ERROR:[/] {result['error']}")
    finally:
        freeipa.close()


# ── Main menu ───────────────────────────────────────────────────────


MENU_CHOICES = [
    "👤  Crear usuario",
    "📋  Listar usuarios",
    "🔧  Habilitar / Deshabilitar usuario",
    "❌  Eliminar usuario",
    "🔑  Resetear password",
    "👥  Grupos",
    "🛡️  HBAC",
    "🚪  Salir",
]


def _run_menu(config: AppConfig) -> None:
    """Main menu loop."""
    while True:
        console.print()
        choice = questionary.select(
            "[bold cyan]gidas-identity[/] — seleccioná una opción",
            choices=MENU_CHOICES,
            qmark="▸",
        ).ask()

        if not choice or choice == "🚪  Salir":
            break
        elif choice == "👤  Crear usuario":
            _create_user(config)
        elif choice == "📋  Listar usuarios":
            _list_users(config)
        elif choice == "🔧  Habilitar / Deshabilitar usuario":
            _modify_user(config)
        elif choice == "❌  Eliminar usuario":
            _delete_user(config)
        elif choice == "🔑  Resetear password":
            _reset_password(config)
        elif choice == "👥  Grupos":
            _group_menu(config)
        elif choice == "🛡️  HBAC":
            _hbac_menu(config)

        console.print("\n[dim]─────────────────────[/]")
        if not questionary.confirm("¿Volver al menú?", default=True).ask():
            break

    console.print("[bold green]¡Chau![/]")


# ── Entry point ─────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="gidas-identity TUI")
    parser.add_argument(
        "--secrets",
        default=None,
        help="Path to SOPS-encrypted secrets YAML",
    )
    args = parser.parse_args()

    setup_logging(level=logging.WARNING)  # quiet during TUI
    config = _load_config(args.secrets)

    console.print(
        Panel.fit(
            "[bold cyan]gidas-identity TUI[/]\n"
            "Gestión de identidad AD + FreeIPA interactiva",
            border_style="cyan",
        )
    )
    _run_menu(config)


if __name__ == "__main__":
    main()
