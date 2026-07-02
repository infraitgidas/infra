"""LDAP authentication service for AD GDC01."""

from __future__ import annotations

import re
from typing import List, Optional, Tuple

import ldap3


class LDAPError(Exception):
    """Base LDAP exception."""


class AuthenticationError(LDAPError):
    """Invalid credentials."""


class ConnectionError(LDAPError):
    """Cannot reach AD server."""


def _extract_group_cns(member_of_values: List[str]) -> List[str]:
    """Extract CN from DN strings like 'CN=G-Direccion,OU=Groups,DC=GDC01,DC=local'."""
    groups = []
    for dn in member_of_values:
        match = re.match(r"^CN=(?P<cn>[^,]+)", dn)
        if match:
            groups.append(match.group("cn"))
    return groups


def authenticate(
    host: str,
    port: int,
    bind_dn: str,
    bind_password: str,
    base_dn: str,
    search_filter: str,
    group_attribute: str,
    username: str,
    password: str,
    use_ssl: bool = False,
) -> Tuple[str, List[str]]:
    """
    Authenticate user against AD.

    Returns:
        Tuple of (username, list of group CNs)

    Raises:
        AuthenticationError: invalid credentials or user not found
        ConnectionError: AD server unreachable
    """
    server = ldap3.Server(host=host, port=port, use_ssl=use_ssl, get_info=ldap3.NONE)

    try:
        conn = ldap3.Connection(server, user=bind_dn, password=bind_password, auto_bind=True)
    except ldap3.core.exceptions.LDAPException as exc:
        raise ConnectionError(f"Cannot connect to AD: {exc}") from exc

    try:
        # Step 1: Search for user DN
        actual_filter = search_filter.replace("{username}", username)
        conn.search(
            search_base=base_dn,
            search_filter=actual_filter,
            search_scope=ldap3.SUBTREE,
            attributes=[group_attribute, "distinguishedName"],
            size_limit=1,
        )

        if not conn.entries:
            raise AuthenticationError("User not found")

        user_dn = conn.entries[0].entry_dn

        # Step 2: Verify password by binding as the user
        user_conn = ldap3.Connection(server, user=user_dn, password=password, auto_bind=True)
        user_conn.unbind()

        # Step 3: Get groups (re-bind as service account for group search)
        conn.search(
            search_base=base_dn,
            search_filter=f"(distinguishedName={user_dn})",
            search_scope=ldap3.SUBTREE,
            attributes=[group_attribute],
            size_limit=1,
        )

        member_of = []
        if conn.entries and group_attribute in conn.entries[0]:
            member_of = conn.entries[0][group_attribute].values or []

        groups = _extract_group_cns(member_of)
        return (username, groups)

    except ldap3.core.exceptions.LDAPBindError as exc:
        raise AuthenticationError("Invalid password") from exc
    except ldap3.core.exceptions.LDAPException as exc:
        raise ConnectionError(f"LDAP error: {exc}") from exc
    finally:
        conn.unbind()
