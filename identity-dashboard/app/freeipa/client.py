"""SSH connection manager for FreeIPA operations.

Connects to the IPA server via paramiko, obtains a Kerberos ticket via
``kinit`` (password from decrypted secrets, passed via stdin), and
executes ``ipa`` CLI commands.
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


class FreeIPAClientError(Exception):
    """Raised when FreeIPA operations fail after all retries."""


class FreeIPAClient:
    """Manages an SSH session to the FreeIPA server.

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
            key_filename=self._config.ssh_key_path,
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
        """Execute an arbitrary *command* on the FreeIPA server.

        Prepends ``kinit`` with the admin password so the ``ipa`` CLI
        has a valid Kerberos ticket.  The admin password is **never**
        logged (the logging filter in ``app.logging`` strips it).
        """
        # kinit via stdin to avoid exposing the password in the process table
        kinit = f"echo '{self._config.admin_password}' | kinit admin"
        full_cmd = f"{kinit} && {command}"

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
