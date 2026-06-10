"""Tests for HBAC CLI commands (list / toggle / test)."""

from __future__ import annotations

from app.cli.main import cli


# ═══════════════════════════════════════════════════════════════════
# list
# ═══════════════════════════════════════════════════════════════════

class TestHbacList:
    def test_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview without calling FreeIPA."""
        result = invoke_config(cli, ["hbac", "list", "--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout

    def test_list_all(self, invoke_config, app_config):
        """List all HBAC rules."""
        result = invoke_config(cli, ["hbac", "list"], app_config)
        assert result.exit_code == 0
        assert "Mocked FreeIPA output" in result.stdout

    def test_list_by_user(self, invoke_config, app_config):
        """Filter rules by username."""
        result = invoke_config(cli, ["hbac", "list", "--user", "jperez"], app_config)
        assert result.exit_code == 0

    def test_list_by_host(self, invoke_config, app_config):
        """Filter rules by host."""
        result = invoke_config(cli, ["hbac", "list", "--host", "server01"], app_config)
        assert result.exit_code == 0

    def test_freeipa_failure(self, invoke_config, app_config, mock_freeipa_client):
        """Should print error message on FreeIPA failure."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA HBAC error",
        }
        result = invoke_config(cli, ["hbac", "list"], app_config)
        assert result.exit_code == 0
        assert "ERROR" in result.stderr or "failed" in result.stderr


# ═══════════════════════════════════════════════════════════════════
# toggle
# ═══════════════════════════════════════════════════════════════════

TOGGLE_ENABLE = ["hbac", "toggle", "--rule", "allow-servers", "--enable"]
TOGGLE_DISABLE = ["hbac", "toggle", "--rule", "allow-servers", "--disable"]


class TestToggle:
    def test_dry_run_enable(self, invoke_config, app_config):
        """--dry-run --enable should print preview."""
        result = invoke_config(cli, TOGGLE_ENABLE + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "enable" in result.stdout.lower()

    def test_dry_run_disable(self, invoke_config, app_config):
        """--dry-run --disable should print preview."""
        result = invoke_config(cli, TOGGLE_DISABLE + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "disable" in result.stdout.lower()

    def test_enable_success(self, invoke_config, app_config):
        """Enable an HBAC rule."""
        result = invoke_config(cli, TOGGLE_ENABLE, app_config)
        assert result.exit_code == 0
        assert "enabled successfully" in result.stdout

    def test_disable_success(self, invoke_config, app_config):
        """Disable an HBAC rule."""
        result = invoke_config(cli, TOGGLE_DISABLE, app_config)
        assert result.exit_code == 0
        assert "disabled successfully" in result.stdout

    def test_freeipa_failure(self, invoke_config, app_config, mock_freeipa_client):
        """Should print error on FreeIPA failure."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA toggle error",
        }
        result = invoke_config(cli, TOGGLE_ENABLE, app_config)
        assert result.exit_code == 0
        assert "ERROR" in result.stderr or "failed" in result.stderr


# ═══════════════════════════════════════════════════════════════════
# test (hbac test command)
# ═══════════════════════════════════════════════════════════════════

TEST_ARGS = ["hbac", "test", "--user", "jperez", "--host", "server01"]


class TestHbacTest:
    def test_test_success(self, invoke_config, app_config):
        """Simulate HBAC access check."""
        result = invoke_config(cli, TEST_ARGS, app_config)
        assert result.exit_code == 0
        assert "Mocked FreeIPA output" in result.stdout

    def test_freeipa_failure(self, invoke_config, app_config, mock_freeipa_client):
        """Should print error on FreeIPA failure."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA test error",
        }
        result = invoke_config(cli, TEST_ARGS, app_config)
        assert result.exit_code == 0
        assert "failed" in result.stderr
