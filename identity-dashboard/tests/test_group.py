"""Tests for group CLI commands (add-member / remove-member / list)."""

from __future__ import annotations

from app.cli.main import cli

ADD_ARGS = ["group", "add-member", "--group", "PROY-Telepark", "--user", "jperez"]
REMOVE_ARGS = ["group", "remove-member", "--group", "PROY-Telepark", "--user", "jperez"]


# ═══════════════════════════════════════════════════════════════════
# add-member
# ═══════════════════════════════════════════════════════════════════

class TestAddMember:
    def test_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview."""
        result = invoke_config(cli, ADD_ARGS + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would add user" in result.stdout

    def test_add_success(self, invoke_config, app_config):
        """Happy path — user added to AD and FreeIPA."""
        result = invoke_config(cli, ADD_ARGS, app_config)
        assert result.exit_code == 0
        assert "added to group" in result.stdout

    def test_ad_failure_aborts(self, invoke_config, app_config, mock_ad_client):
        """If AD add fails, command should abort without calling FreeIPA."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}

        result = invoke_config(cli, ADD_ARGS, app_config)
        assert result.exit_code != 0
        assert "AD add-member failed" in result.stderr

    def test_freeipa_failure_rolls_back_ad(
        self, invoke_config, app_config, mock_ad_client, mock_freeipa_client
    ):
        """If FreeIPA add fails, AD should be rolled back."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA error",
        }

        result = invoke_config(cli, ADD_ARGS, app_config)
        assert result.exit_code != 0
        assert "rolled back" in result.stderr

        # Verify AD remove was called (rollback)
        remove_calls = [
            c for c in mock_ad_client.run_ps.call_args_list
            if "Remove-ADGroupMember" in str(c)
        ]
        assert remove_calls, "Expected AD rollback (Remove-ADGroupMember)"

    def test_add_with_notify(
        self, invoke_config, app_config, mock_email_sender
    ):
        """--notify should trigger email."""
        result = invoke_config(cli, ADD_ARGS + ["--notify"], app_config)
        assert result.exit_code == 0
        assert mock_email_sender.send.call_count >= 1


# ═══════════════════════════════════════════════════════════════════
# remove-member
# ═══════════════════════════════════════════════════════════════════

class TestRemoveMember:
    def test_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview."""
        result = invoke_config(cli, REMOVE_ARGS + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would remove user" in result.stdout

    def test_remove_success(self, invoke_config, app_config):
        """Happy path — user removed from AD and FreeIPA."""
        result = invoke_config(cli, REMOVE_ARGS, app_config)
        assert result.exit_code == 0
        assert "removed from group" in result.stdout

    def test_ad_failure_aborts(self, invoke_config, app_config, mock_ad_client):
        """If AD remove fails, command should abort."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}

        result = invoke_config(cli, REMOVE_ARGS, app_config)
        assert result.exit_code != 0
        assert "AD remove-member failed" in result.stderr

    def test_freeipa_failure_non_fatal(
        self, invoke_config, app_config, mock_freeipa_client
    ):
        """FreeIPA remove failure should warn but NOT abort (user already removed from AD)."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA error",
        }

        result = invoke_config(cli, REMOVE_ARGS, app_config)
        assert result.exit_code == 0
        assert "WARNING" in result.stdout or "removed from group" in result.stdout

    def test_remove_with_notify(
        self, invoke_config, app_config, mock_email_sender
    ):
        """--notify should trigger email."""
        result = invoke_config(cli, REMOVE_ARGS + ["--notify"], app_config)
        assert result.exit_code == 0
        assert mock_email_sender.send.call_count >= 1


# ═══════════════════════════════════════════════════════════════════
# list
# ═══════════════════════════════════════════════════════════════════

class TestGroupList:
    def test_list_success(self, invoke_config, app_config):
        """List groups should show AD output."""
        result = invoke_config(cli, ["group", "list"], app_config)
        assert result.exit_code == 0
        assert "Mocked AD output" in result.stdout

    def test_list_with_prefix(self, invoke_config, app_config):
        """--prefix filter should work."""
        result = invoke_config(cli, ["group", "list", "--prefix", "PROY-"], app_config)
        assert result.exit_code == 0

    def test_list_ad_failure(self, invoke_config, app_config, mock_ad_client):
        """Should print error on AD failure."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}
        result = invoke_config(cli, ["group", "list"], app_config)
        assert result.exit_code == 0
        assert "ERROR" in result.stderr
