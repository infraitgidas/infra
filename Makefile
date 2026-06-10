# ──────────────────────────────────────────────────────────────
#  gidas-identity — Makefile (repo root)
# ──────────────────────────────────────────────────────────────
#  Targets to run the identity-dashboard CLI and TUI, either
#  directly (Python) or via SSH on the target host.
#
#  Secrets path (default: host convention on identity-dashboard):
#    make tui SECRETS=/custom/path/secrets.yaml
#
#  Remote host (default: identity-dashboard IP):
#    make ssh-cli SSH_HOST=192.168.1.124 CMD="user list"
# ──────────────────────────────────────────────────────────────

APP_DIR    := identity-dashboard
PYTHON     := python3

# ── Locally on the host ──────────────────────────────────────
SECRETS    ?= /opt/identity-dashboard/secrets/identity.yaml

# ── Remote via SSH ───────────────────────────────────────────
SSH_HOST   ?= 192.168.1.124
SSH_DIR    ?= /opt/identity-dashboard

# ── Help ─────────────────────────────────────────────────────
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Local (direct Python on the host) ─────────────────────────

cli: ## Run CLI (usage: make cli CMD="user list")
	cd $(APP_DIR) && $(PYTHON) -m app --secrets "$(SECRETS)" $(CMD)

tui: ## Run interactive TUI
	cd $(APP_DIR) && $(PYTHON) -m app.tui --secrets "$(SECRETS)"

list-users: ## List AD users (quick shortcut)
	cd $(APP_DIR) && $(PYTHON) -m app --secrets "$(SECRETS)" user list

list-groups: ## List AD groups (usage: PREFIX="G-")
	cd $(APP_DIR) && $(PYTHON) -m app --secrets "$(SECRETS)" group list --prefix "$(PREFIX)"

# ── Remote (via SSH over WinRM) ──────────────────────────────

ssh-cli: ## Run CLI on remote host (usage: make ssh-cli CMD="user list")
	ssh root@$(SSH_HOST) "cd $(SSH_DIR)/$(APP_DIR) && $(PYTHON) -m app --secrets '$(SECRETS)' $(CMD)"

ssh-tui: ## Run TUI on remote host (requires TTY-forwarding)
	ssh -t root@$(SSH_HOST) "cd $(SSH_DIR)/$(APP_DIR) && $(PYTHON) -m app.tui --secrets '$(SECRETS)'"

# ── Maintenance ──────────────────────────────────────────────

deps: ## Install Python dependencies (rich + questionary for TUI)
	pip install --upgrade pip
	pip install -r $(APP_DIR)/requirements.txt
	pip install rich questionary

sync: ## Git pull on remote host
	ssh root@$(SSH_HOST) "cd $(SSH_DIR) && git pull"

.PHONY: help cli tui list-users list-groups ssh-cli ssh-tui deps sync
