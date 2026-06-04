"""Structured logging to stdout with password sanitization."""

from __future__ import annotations

import logging
import re
import sys
from typing import TextIO

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
DATE_FORMAT = "%Y-%m-%dT%H:%M:%S%z"


class SanitizingFilter(logging.Filter):
    """Replace password values in log messages with ``***``."""

    # Patterns that may contain sensitive values after the label
    _SENSITIVE_PATTERNS = [
        (re.compile(r'(password["\s:=]+\w+["\s]*)', re.IGNORECASE), r"password=***"),
    ]

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        for pattern, replacement in self._SENSITIVE_PATTERNS:
            if pattern.search(msg):
                record.msg = pattern.sub(replacement, record.msg)
        return True


def setup_logging(
    name: str = "gidas-identity",
    level: int = logging.INFO,
    stream: TextIO | None = None,
) -> logging.Logger:
    """Configure and return a logger with structured output.

    Writes to *stream* (default: ``sys.stdout``) with a sanitizing filter
    that replaces password-like values before they reach the output.
    """
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Prevent duplicate handlers on repeated calls
    if logger.handlers:
        return logger

    handler = logging.StreamHandler(stream or sys.stdout)
    handler.setFormatter(logging.Formatter(LOG_FORMAT, datefmt=DATE_FORMAT))
    handler.addFilter(SanitizingFilter())
    logger.addHandler(handler)

    return logger
