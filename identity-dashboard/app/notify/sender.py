"""Email notification sender — smtplib wrapper.

Non-blocking: delivery failures are logged as warnings and do not
propagate exceptions to the caller.  This follows the design decision
that email is a soft dependency.

Supports optional SMTP authentication and HTML content.
"""

from __future__ import annotations

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any

from app.config import SMTPConfig

logger = logging.getLogger(__name__)


class EmailSender:
    """Sends plain-text (and optional HTML) email notifications via SMTP.

    Usage::

        sender = EmailSender(config.smtp)
        sender.send("Subject", "Body text")
        sender.send("Subject", "Body text", html="<p>HTML body</p>")
    """

    def __init__(self, config: SMTPConfig) -> None:
        self._host = config.smtp_host
        self._port = config.smtp_port
        self._use_tls = config.smtp_tls
        self._from = config.from_addr
        self._to = config.to_addr
        self._user = config.smtp_user
        self._password = config.smtp_password

    def send(
        self,
        subject: str,
        body: str,
        html: str | None = None,
    ) -> bool:
        """Send an email.

        Returns ``True`` on success, ``False`` on failure (logged).
        If *html* is provided, a multipart/alternative message is sent
        with both plain-text and HTML parts.
        """
        msg: Any
        if html:
            msg = MIMEMultipart("alternative")
            msg.attach(MIMEText(body, "plain", "utf-8"))
            msg.attach(MIMEText(html, "html", "utf-8"))
        else:
            msg = MIMEText(body, "plain", "utf-8")

        msg["Subject"] = subject
        msg["From"] = self._from
        msg["To"] = self._to

        try:
            with smtplib.SMTP(self._host, self._port, timeout=10) as server:
                if self._use_tls:
                    server.starttls()
                if self._user and self._password:
                    server.login(self._user, self._password)
                server.send_message(msg)
            logger.info("Email sent: %s -> %s (%s)", self._from, self._to, subject)
            return True
        except Exception:
            logger.warning("Email delivery failed: %s", subject, exc_info=True)
            return False
