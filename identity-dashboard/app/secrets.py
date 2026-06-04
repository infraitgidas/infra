"""SOPS integration — decrypt secrets.yaml in memory only."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import yaml

SECRETS_PATH = os.environ.get("GIDAS_SECRETS_PATH", "/secrets/identity.yaml")


def load_secrets(path: str | None = None) -> dict:
    """Decrypt SOPS-encrypted YAML, return the ``identity`` key as a dict.

    Credentials are decrypted in memory and never written to disk or env.
    The process lifetime is the CLI invocation — memory is freed on exit.
    """
    secrets_file = Path(path or SECRETS_PATH)

    if not secrets_file.exists():
        msg = f"Secrets file not found: {secrets_file}"
        raise FileNotFoundError(msg)

    result = subprocess.run(
        ["sops", "-d", str(secrets_file)],
        capture_output=True,
        text=True,
        check=True,
    )

    data: dict = yaml.safe_load(result.stdout)
    identity = data.get("identity", data)
    return identity
