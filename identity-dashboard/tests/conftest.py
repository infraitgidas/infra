"""Shared fixtures and mocks for gidas-identity CLI tests."""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock

import pytest
from click.testing import CliRunner

from app.config import ADConfig, AppConfig, FreeIPAConfig, SMTPConfig


# ── Test configuration ──────────────────────────────────────────────

@pytest.fixture
def app_config() -> AppConfig:
    """Return a test AppConfig with dummy-but-valid values."""
    return AppConfig(
        ad=ADConfig(
            endpoint="http://dc01.gdc01.local:5985/wsman",
            username="GDC01\\Administrator",
            password="TestPass123!",
        ),
        freeipa=FreeIPAConfig(
            host="ipa.gdc01.local",
            ssh_user="root",
            ssh_key_path="/tmp/test-key",
            admin_password="TestPass456!",
        ),
        smtp=SMTPConfig(
            smtp_host="mail.test.local",
            smtp_port=587,
            smtp_tls=True,
            smtp_user="test@test.local",
            smtp_password="smtppass",
            from_addr="admin-identity@test.local",
            to_addr="admin-identity@test.local",
        ),
    )


# ── Runner ──────────────────────────────────────────────────────────

@pytest.fixture
def cli_runner() -> CliRunner:
    """Return a Click CliRunner (default mix_stderr=True for compat)."""
    return CliRunner()


# ── Mock AppConfig injection helper ─────────────────────────────────

@pytest.fixture
def invoke_config(cli_runner, app_config):
    """Return a helper that invokes a Click command with config in context.

    Usage::

        result = invoke_config(cli, ["user", "list"], app_config)
    """

    def _invoke(cli_group, args, config=None):
        obj = {"config": config or app_config}
        return cli_runner.invoke(cli_group, args, obj=obj)

    return _invoke


# ── Mock remote clients (patch once, affects all imports) ───────────

@pytest.fixture(autouse=True)
def mock_ad_client(monkeypatch):
    """Replace ADClient.run_ps with a mock returning success by default.

    Tests can access ``mock_ad_client.run_ps`` to assert calls or change
    return values.
    """
    mock = MagicMock()
    mock.run_ps.return_value = {"ok": True, "output": "Mocked AD output"}
    # The ADClient constructor just stores config — we can keep it real
    # but replace the instance method.  Since CLI code does:
    #   ad = ADClient(config.ad)
    #   result = ad.run_ps(...)
    # we monkeypatch the method on the class itself.
    import app.ad.client as ad_mod

    monkeypatch.setattr(ad_mod.ADClient, "run_ps", mock.run_ps)
    monkeypatch.setattr(ad_mod.ADClient, "close", lambda self: None)
    return mock


@pytest.fixture(autouse=True)
def mock_freeipa_client(monkeypatch):
    """Replace FreeIPAClient.run_ipa / .run with mocks.

    Also stubs ``close()`` since CLI code calls it in ``finally`` blocks.
    """
    mock = MagicMock()
    mock.run_ipa.return_value = {"ok": True, "output": "Mocked FreeIPA output"}
    mock.run.return_value = {"ok": True, "output": "Mocked FreeIPA output"}

    import app.freeipa.client as ipa_mod

    monkeypatch.setattr(ipa_mod.FreeIPAClient, "run_ipa", mock.run_ipa)
    monkeypatch.setattr(ipa_mod.FreeIPAClient, "run", mock.run)
    monkeypatch.setattr(ipa_mod.FreeIPAClient, "close", lambda self: None)
    return mock


@pytest.fixture(autouse=True)
def mock_email_sender(monkeypatch):
    """Replace EmailSender.send with a no-op mock."""
    mock = MagicMock()

    import app.notify.sender as notify_mod

    monkeypatch.setattr(notify_mod.EmailSender, "send", mock.send)
    return mock
