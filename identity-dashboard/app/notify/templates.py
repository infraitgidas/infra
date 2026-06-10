"""Plain-text email templates for identity operations."""

from __future__ import annotations


def user_created(
    username: str,
    full_name: str,
    role: str,
    proyecto: str,
    password: str,
    *,
    domain: str = "GDC01.local",
) -> tuple[str, str]:
    """Return ``(subject, body)`` for a new-user notification."""
    subject = f"[Gidas Identity] Alta de usuario — {username}"
    body = f"""Se ha creado el usuario {username} ({full_name}) en AD y FreeIPA.

Rol: {role}
Proyecto: {proyecto}
Usuario: {username}
Password: {password}
Dominio: {domain}

El usuario debe cambiar la contraseña en el primer login.

Acceso Linux: ssh {username}@<host-asignado>
Acceso Windows: RDP a VM del proyecto
"""
    return subject, body


def user_modified(
    username: str,
    changes: str,
    *,
    domain: str = "GDC01.local",
) -> tuple[str, str]:
    """Return ``(subject, body)`` for a user modification notification.

    *changes* is a human-readable string e.g. "disabled in AD and FreeIPA".
    """
    subject = f"[Gidas Identity] Usuario modificado — {username}"
    body = f"""Se ha modificado el usuario {username} en AD y FreeIPA.

Cambios aplicados: {changes}

Dominio: {domain}
"""
    return subject, body


def user_welcome(
    username: str,
    full_name: str,
    password: str,
    *,
    domain: str = "GDC01.local",
) -> tuple[str, str]:
    """Return ``(subject, body)`` for a welcome email to the new user."""
    subject = f"Bienvenido a GIDAS — tus credenciales de acceso"
    body = f"""Hola {full_name},

Tu cuenta fue creada en el dominio GIDAS.

Usuario: {username}@GDC01.local
Password: {password}

Acceso Linux: ssh {username}@ipa-gidas.gidas.internal
Acceso Windows: RDP a tu VM del proyecto

Tenés que cambiar la contraseña en el primer inicio de sesión.

Saludos,
Equipo de Infraestructura GIDAS
"""
    return subject, body


def password_reset(
    username: str,
    full_name: str,
    password: str,
    *,
    domain: str = "GDC01.local",
) -> tuple[str, str]:
    """Return ``(subject, body)`` for a password-reset notification."""
    subject = f"[Gidas Identity] Password reseteado — {username}"
    body = f"""Se ha reseteado la contraseña del usuario {username} ({full_name}).

Nuevo password: {password}
Debe cambiarla en el próximo inicio de sesión.

Acceso Linux: ssh {username}@<host-asignado>
Acceso Windows: RDP a VM del proyecto

Dominio: {domain}
"""
    return subject, body


def group_membership_changed(
    username: str,
    group_name: str,
    action: str,
    *,
    domain: str = "GDC01.local",
) -> tuple[str, str]:
    """Return ``(subject, body)`` for a group membership change.

    *action* is ``"added"`` or ``"removed"``.
    """
    action_es = "agregado a" if action == "added" else "eliminado de"
    subject = f"[Gidas Identity] Grupo modificado — {username} / {group_name}"
    body = f"""Se ha {action_es} el usuario {username} al grupo {group_name} en AD y FreeIPA.

Usuario: {username}
Grupo: {group_name}
Acción: {action}

Dominio: {domain}
"""
    return subject, body
