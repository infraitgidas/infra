"""Tests for user CLI commands (create / modify / list / show / delete)."""

from __future__ import annotations

import pytest

from app.cli.main import cli


# ═══════════════════════════════════════════════════════════════════
# create
# ═══════════════════════════════════════════════════════════════════

CREATE_ARGS = [
    "user",
    "create",
    "--name",
    "Juan Perez",
    "--username",
    "jperez",
    "--role",
    "coordinador",
    "--proyecto",
    "Telepark",
]


class TestCreate:
    def test_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview but NOT call AD/FreeIPA."""
        result = invoke_config(cli, CREATE_ARGS + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would create user" in result.stdout

    def test_create_success(self, invoke_config, app_config, mock_ad_client, mock_freeipa_client):
        """Happy path — user created in AD and FreeIPA."""
        # AD pre-check: user does NOT exist, then create succeeds
        mock_ad_client.run_ps.side_effect = [
            {"ok": False, "error": "Not found"},  # pre-check
            {"ok": True, "output": "User created"},  # AD create
            {"ok": True, "output": "Added to group"},  # AD group 1
            {"ok": True, "output": "Added to group"},  # AD group 2
        ]

        result = invoke_config(cli, CREATE_ARGS, app_config)
        assert result.exit_code == 0, f"stdout: {result.stdout}, stderr: {result.stderr}"
        assert "created successfully" in result.stdout

    def test_create_user_already_exists(
        self, invoke_config, app_config, mock_ad_client
    ):
        """Pre-check should abort if user already exists in AD."""
        result = invoke_config(cli, CREATE_ARGS, app_config)
        assert result.exit_code != 0
        # Default mock returns {"ok": True} → pre-check sees user exists
        assert "already exists" in result.stderr

    def test_create_ad_fails(self, invoke_config, app_config, mock_ad_client):
        """Should abort if AD creation fails."""
        mock_ad_client.run_ps.side_effect = [
            {"ok": False, "error": "Not found"},  # pre-check
            {"ok": False, "error": "AD create failed"},  # AD create
        ]

        result = invoke_config(cli, CREATE_ARGS, app_config)
        assert result.exit_code != 0
        assert "AD user creation failed" in result.stderr

    def test_create_freeipa_fails_rolls_back_ad(
        self, invoke_config, app_config, mock_ad_client, mock_freeipa_client
    ):
        """Should rollback AD user if FreeIPA creation fails."""
        mock_ad_client.run_ps.side_effect = [
            {"ok": False, "error": "Not found"},  # pre-check: not found ✅
            {"ok": True, "output": "User created"},  # AD create
            {"ok": True, "output": "Added"},  # AD default group
            {"ok": True, "output": "Added"},  # AD project group
            {"ok": True, "output": "Rolled back"},  # AD rollback
        ]

        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA error",
        }

        result = invoke_config(cli, CREATE_ARGS, app_config)
        assert result.exit_code != 0
        assert "rolled back" in result.stderr

        # Verify Remove-ADUser was called as the last call (rollback)
        assert mock_ad_client.run_ps.call_count == 5
        rollback_call = mock_ad_client.run_ps.call_args_list[4]
        assert "Remove-ADUser" in str(rollback_call), (
            "Expected AD rollback (Remove-ADUser)"
        )

    def test_create_with_notify(
        self, invoke_config, app_config, mock_ad_client, mock_email_sender
    ):
        """--notify should trigger EmailSender.send."""
        mock_ad_client.run_ps.side_effect = [
            {"ok": False, "error": "Not found"},  # pre-check
            {"ok": True, "output": "User created"},  # AD create
            {"ok": True, "output": "Added"},  # AD group 1
            {"ok": True, "output": "Added"},  # AD group 2
        ]

        result = invoke_config(cli, CREATE_ARGS + ["--notify"], app_config)
        assert result.exit_code == 0, f"stdout: {result.stdout}, stderr: {result.stderr}"
        assert mock_email_sender.send.call_count >= 1


# ═══════════════════════════════════════════════════════════════════
# modify
# ═══════════════════════════════════════════════════════════════════

MODIFY_ARGS = ["user", "modify", "--username", "jperez"]


class TestModify:
    def test_dry_run_disable(self, invoke_config, app_config):
        """--dry-run --disable should print preview."""
        result = invoke_config(cli, MODIFY_ARGS + ["--disable", "--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Disable" in result.stdout

    def test_dry_run_enable(self, invoke_config, app_config):
        """--dry-run --enable should print preview."""
        result = invoke_config(cli, MODIFY_ARGS + ["--enable", "--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Enable" in result.stdout

    def test_disable_both(self, invoke_config, app_config, mock_ad_client, mock_freeipa_client):
        """Disable should call AD disable + FreeIPA disable."""
        result = invoke_config(cli, MODIFY_ARGS + ["--disable"], app_config)
        assert result.exit_code == 0
        assert "disabled" in result.stdout

    def test_enable_both(self, invoke_config, app_config, mock_ad_client, mock_freeipa_client):
        """Enable should call AD enable + FreeIPA enable."""
        result = invoke_config(cli, MODIFY_ARGS + ["--enable"], app_config)
        assert result.exit_code == 0
        assert "enabled" in result.stdout

    def test_disable_and_enable_mutually_exclusive(self, invoke_config, app_config):
        """--disable and --enable together should be rejected."""
        result = invoke_config(
            cli, MODIFY_ARGS + ["--disable", "--enable"], app_config
        )
        assert result.exit_code != 0
        assert "mutually exclusive" in result.stderr

    def test_no_options(self, invoke_config, app_config):
        """Should error if no modify option is provided."""
        result = invoke_config(cli, MODIFY_ARGS, app_config)
        assert result.exit_code != 0
        assert "at least one" in result.stderr.lower()

    def test_dry_run_email_phone(self, invoke_config, app_config):
        """--dry-run with --email and --phone should print preview."""
        result = invoke_config(
            cli, MODIFY_ARGS + ["--email", "j@test.com", "--phone", "123", "--dry-run"], app_config
        )
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "j@test.com" in result.stdout


# ═══════════════════════════════════════════════════════════════════
# list
# ═══════════════════════════════════════════════════════════════════

class TestList:
    def test_list_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview without calling AD."""
        result = invoke_config(cli, ["user", "list", "--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout

    def test_list_success(self, invoke_config, app_config):
        """List should show AD output on success."""
        result = invoke_config(cli, ["user", "list"], app_config)
        assert result.exit_code == 0
        assert "Mocked AD output" in result.stdout

    def test_list_with_ou_filter(self, invoke_config, app_config, mock_ad_client):
        """--ou filter should be passed to AD query."""
        result = invoke_config(cli, ["user", "list", "--ou", "Direccion"], app_config)
        assert result.exit_code == 0
        # Verify filter was included in the PS script
        assert any("Direccion" in str(c) for c in mock_ad_client.run_ps.call_args_list)

    def test_list_with_role_filter(self, invoke_config, app_config):
        """--role filter should work."""
        result = invoke_config(cli, ["user", "list", "--role", "coordinador"], app_config)
        assert result.exit_code == 0

    def test_list_ad_failure(self, invoke_config, app_config, mock_ad_client):
        """Should print error message on AD failure."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}
        result = invoke_config(cli, ["user", "list"], app_config)
        assert result.exit_code == 0  # no exception, error echoed
        assert "ERROR" in result.stderr


# ═══════════════════════════════════════════════════════════════════
# show
# ═══════════════════════════════════════════════════════════════════

SHOW_ARGS = ["user", "show", "jperez"]


class TestShow:
    def test_show_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview."""
        result = invoke_config(cli, SHOW_ARGS + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would show details" in result.stdout

    def test_show_success(self, invoke_config, app_config):
        """Show should display AD + FreeIPA info."""
        result = invoke_config(cli, SHOW_ARGS, app_config)
        assert result.exit_code == 0
        assert "AD" in result.stdout
        assert "FreeIPA" in result.stdout

    def test_show_ad_failure(self, invoke_config, app_config, mock_ad_client):
        """AD failure should not crash — error printed."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD error"}
        result = invoke_config(cli, SHOW_ARGS, app_config)
        assert result.exit_code == 0
        assert "AD" in result.stdout  # section header still shown
        assert "AD error" in result.stdout  # but with error

    def test_show_freeipa_failure(self, invoke_config, app_config, mock_freeipa_client):
        """FreeIPA failure should not crash — error printed."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA error",
        }
        result = invoke_config(cli, SHOW_ARGS, app_config)
        assert result.exit_code == 0
        assert "FreeIPA" in result.stdout
        assert "FreeIPA error" in result.stdout


# ═══════════════════════════════════════════════════════════════════
# delete
# ═══════════════════════════════════════════════════════════════════

DELETE_ARGS = ["user", "delete", "jperez"]


class TestDelete:
    def test_delete_dry_run(self, invoke_config, app_config):
        """--dry-run should print preview without deleting."""
        result = invoke_config(cli, DELETE_ARGS + ["--dry-run"], app_config)
        assert result.exit_code == 0
        assert "[DRY-RUN]" in result.stdout
        assert "Would delete" in result.stdout

    def test_delete_success(self, invoke_config, app_config):
        """Happy path — user deleted from AD and FreeIPA."""
        result = invoke_config(cli, DELETE_ARGS, app_config)
        assert result.exit_code == 0
        assert "deleted successfully" in result.stdout

    def test_delete_with_notify(
        self, invoke_config, app_config, mock_email_sender
    ):
        """--notify should trigger email."""
        result = invoke_config(cli, DELETE_ARGS + ["--notify"], app_config)
        assert result.exit_code == 0
        assert mock_email_sender.send.call_count >= 1

    def test_delete_ad_failure(self, invoke_config, app_config, mock_ad_client):
        """AD failure should print error but not crash."""
        mock_ad_client.run_ps.return_value = {"ok": False, "error": "AD delete failed"}
        result = invoke_config(cli, DELETE_ARGS, app_config)
        assert result.exit_code == 0
        assert "AD error" in result.stderr

    def test_delete_freeipa_failure(self, invoke_config, app_config, mock_freeipa_client):
        """FreeIPA failure should print error but not crash."""
        mock_freeipa_client.run_ipa.return_value = {
            "ok": False,
            "error": "FreeIPA delete failed",
        }
        result = invoke_config(cli, DELETE_ARGS, app_config)
        assert result.exit_code == 0
        assert "FreeIPA error" in result.stderr
