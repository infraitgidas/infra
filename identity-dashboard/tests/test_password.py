"""Tests for password CLI commands (nested under user group)."""

from __future__ import annotations

from app.cli.main import cli

PASS_RESET = ["user", "password", "jperez", "--reset"]
PASS_SET = ["user", "password", "jperez", "--set", "NewP@ss123"]


# ═══════════════════════════════════════════════════════════════════
# password
# ═══════════════════════════════════════════════════════════════════

class TestPassword:
    def test_reset_dry_run(self, invoke_config, app_config):
        """--reset --dry-run should print preview."""
        result = invoke_config(cli, PASS_RESET + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would change password" in result.stdout

    def test_set_dry_run(self, invoke_config, app_config):
        """--set --dry-run should print preview."""
        result = invoke_config(cli, PASS_SET + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout

    def test_reset_success(self, invoke_config, app_config):
        """Password reset should work."""
        result = invoke_config(cli, PASS_RESET, app_config)
        assert result.exit_code == 0
        assert "Password changed" in result.stdout

    def test_set_success(self, invoke_config, app_config):
        """Setting a specific password should work."""
        result = invoke_config(cli, PASS_SET, app_config)
        assert result.exit_code == 0
        assert "Password changed" in result.stdout

    def test_no_option_provided(self, invoke_config, app_config):
        """Should error if neither --reset nor --set is provided."""
        result = invoke_config(cli, ["user", "password", "jperez"], app_config)
        assert result.exit_code != 0
        assert "required" in result.stderr.lower()

    def test_reset_and_set_mutually_exclusive(self, invoke_config, app_config):
        """--reset and --set together should be rejected."""
        result = invoke_config(cli, PASS_RESET + ["--set", "other"], app_config)
        assert result.exit_code != 0
        assert "mutually exclusive" in result.stderr

    def test_ad_failure_aborts(self, invoke_config, app_config, mock_ad_client):
        """If AD password reset fails, command should abort."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}
        result = invoke_config(cli, PASS_RESET, app_config)
        assert result.exit_code != 0
        assert "ERROR" in result.stderr

    def test_freeipa_failure_rolls_back_ad(
        self, invoke_config, app_config, mock_freeipa_client
    ):
        """If FreeIPA password reset fails, AD should be rolled back."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA error",
        }

        result = invoke_config(cli, PASS_RESET, app_config)
        assert result.exit_code != 0
        assert "rolled back" in result.stderr

    def test_with_notify(
        self, invoke_config, app_config, mock_email_sender
    ):
        """--notify should trigger email."""
        result = invoke_config(cli, PASS_RESET + ["--notify"], app_config)
        assert result.exit_code == 0
        assert mock_email_sender.send.call_count >= 1

    def test_no_expire_flag(self, invoke_config, app_config):
        """--no-expire should be accepted."""
        result = invoke_config(cli, PASS_SET + ["--no-expire"], app_config)
        assert result.exit_code == 0
        assert "Password changed" in result.stdout
