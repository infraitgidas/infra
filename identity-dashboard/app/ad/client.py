"""WinRM connection manager for Active Directory operations."""

from __future__ import annotations

import logging
import time
from typing import Any

import winrm

from app.config import ADConfig

logger = logging.getLogger(__name__)

# Retry strategy per design.md
_RETRY_DELAYS = [2, 5, 10]
_MAX_RETRIES = 3


class ADClientError(Exception):
    """Raised when AD operations fail after all retries."""


class ADClient:
    """Manages a WinRM session to a Windows Domain Controller.

    Usage::

        client = ADClient(config.ad)
        result = client.run_ps("Get-ADUser -Identity jperez")
    """

    def __init__(self, config: ADConfig) -> None:
        self._config = config
        self._session: winrm.Session | None = None

    # ── Session management ─────────────────────────────────────────

    @property
    def session(self) -> winrm.Session:
        if self._session is None:
            self._session = winrm.Session(
                self._config.endpoint,
                auth=(self._config.username, self._config.password),
                transport="ntlm",
                server_cert_validation="ignore",
            )
        return self._session

    def close(self) -> None:
        """Release the WinRM session (no-op for pywinrm)."""
        self._session = None

    # ── Command execution ──────────────────────────────────────────

    def run_ps(self, script: str, timeout: int = 30) -> dict[str, Any]:
        """Execute a PowerShell *script* and return the parsed result.

        Retries up to ``_MAX_RETRIES`` (3) with exponential-ish backoff
        on timeout and connection errors.

        Returns
            ``{"ok": True, "output": "..."}`` on success, or
            ``{"ok": False, "error": "..."}`` on PowerShell error.
        """
        last_error: Exception | None = None

        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                r = self.session.run_ps(script)
                if r.status_code == 0:
                    # PowerShell legacy output uses the OEM code page
                    # (CP850 for Spanish). Try UTF-8 first (PowerShell
                    # Core), then CP850, then fall back to latin-1.
                    for enc in ("utf-8", "cp850", "latin-1"):
                        try:
                            text = r.std_out.decode(enc)
                            break
                        except (UnicodeDecodeError, LookupError):
                            continue
                    else:
                        text = r.std_out.decode("latin-1", errors="replace")
                    return {"ok": True, "output": text}

                stderr = r.std_err.decode("cp850", errors="replace")
                logger.warning(
                    "PS non-zero exit [attempt %d/%d]: %s",
                    attempt,
                    _MAX_RETRIES,
                    stderr[:200],
                )
                return {"ok": False, "error": stderr}

            except Exception as exc:
                last_error = exc
                logger.warning(
                    "WinRM attempt %d/%d failed: %s",
                    attempt,
                    _MAX_RETRIES,
                    exc,
                )
                if attempt < _MAX_RETRIES:
                    time.sleep(_RETRY_DELAYS[attempt - 1])

        msg = f"WinRM failed after {_MAX_RETRIES} attempts: {last_error}"
        raise ADClientError(msg) from last_error
