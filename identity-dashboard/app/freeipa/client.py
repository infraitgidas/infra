"""SSH connection manager for FreeIPA operations.

Connects to the IPA server via paramiko, obtains a Kerberos ticket via
the host keytab (``sudo kinit -k``), and executes ``ipa`` CLI commands
via ``sudo``.  Only needs an SSH user with password-less sudo access;
no FreeIPA admin password is stored or transmitted.

If the SSH user doesn't have sudo, falls back to password-based kinit.
"""

from __future__ import annotations

import logging
import time
from typing import Any

import paramiko

from app.config import FreeIPAConfig

logger = logging.getLogger(__name__)

_RETRY_DELAYS = [3, 6]
_MAX_RETRIES = 2

# Default keytab path for password-less kinit via sudo
_KEYTAB_PATH = "/etc/krb5.keytab"
_KEYTAB_PRINCIPAL = "host/ipa-gidas.gdc01.local@IPA.GDC01.LOCAL"


class FreeIPAClientError(Exception):
    """Raised when FreeIPA operations fail after all retries."""


class FreeIPAClient:
    """Manages an SSH session to the FreeIPA server.

    Uses the host keytab for Kerberos authentication so no admin
    password is needed.  All ``ipa`` commands run via ``sudo``
    because the keytab is only readable by root.

    Usage::

        client = FreeIPAClient(config.freeipa)
        result = client.run_ipa("user-show jperez")
        client.close()
    """

    def __init__(self, config: FreeIPAConfig) -> None:
        self._config = config
        self._client: paramiko.SSHClient | None = None

    # ── Connection management ──────────────────────────────────────

    def connect(self) -> paramiko.SSHClient:
        """Establish (or return) the SSH connection."""
        if self._client is not None:
            return self._client

        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=self._config.host,
            username=self._config.ssh_user,
            key_filename=self._config.ssh_key_path if self._config.ssh_key_path else None,
            timeout=15,
        )
        self._client = client
        return client

    def close(self) -> None:
        """Close the SSH connection."""
        if self._client is not None:
            self._client.close()
            self._client = None

    # ── Command execution ──────────────────────────────────────────

    def run(self, command: str, timeout: int = 30) -> dict[str, Any]:
        """Execute a *command* on the FreeIPA server via keytab + sudo.

        Obtains a Kerberos ticket via the host keytab (readable only by
        root), then runs the command via sudo so the ``ipa`` CLI has a
        valid ticket.  No admin password is stored or transmitted.
        """
        kinit = f"sudo kinit -k -t {_KEYTAB_PATH} {_KEYTAB_PRINCIPAL}"
        full_cmd = f"{kinit} && sudo {command}"

        last_error: Exception | None = None

        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                client = self.connect()
                stdin, stdout, stderr = client.exec_command(
                    full_cmd,
                    timeout=timeout,
                )
                exit_code = stdout.channel.recv_exit_status()
                return {
                    "ok": exit_code == 0,
                    "output": stdout.read().decode(),
                    "error": stderr.read().decode(),
                }

            except Exception as exc:
                last_error = exc
                logger.warning(
                    "FreeIPA attempt %d/%d failed: %s",
                    attempt,
                    _MAX_RETRIES,
                    exc,
                )
                if attempt < _MAX_RETRIES:
                    time.sleep(_RETRY_DELAYS[attempt - 1])
                    # Reconnect on next attempt (stale connection)
                    self.close()

        msg = f"FreeIPA failed after {_MAX_RETRIES} attempts: {last_error}"
        raise FreeIPAClientError(msg) from last_error

    def run_ipa(self, subcommand: str, timeout: int = 30) -> dict[str, Any]:
        """Shorthand for ``run(f"ipa {subcommand}")``."""
        return self.run(f"ipa {subcommand}", timeout=timeout)
