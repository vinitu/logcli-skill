.PHONY: compile test test-unit test-live check help

help: ## Show available targets
	@echo "make compile    — shellcheck all .sh files"
	@echo "make test       — run unit tests (no Docker needed)"
	@echo "make test-live  — run live tests (requires Docker + network)"
	@echo "make check      — verify prerequisites (docker, jq, bash 4.0+)"

compile: ## Shellcheck all scripts
	@shellcheck -x scripts/logcli.sh scripts/_lib/common.sh tests/*.sh
	@echo "All scripts pass shellcheck"

test: test-unit ## Run unit tests

test-unit: ## Run unit tests (no Docker needed)
	@bash tests/test_cli_help.sh
	@bash tests/test_env_resolution.sh
	@bash tests/test_chunking.sh
	@bash tests/test_json_output.sh
	@echo ""
	@echo "All unit tests passed ✓"

test-live: ## Run live tests (requires Docker + network)
	@echo "Requires Docker and network access to Loki"
	@echo "Not implemented yet"

check: ## Verify prerequisites
	@command -v docker >/dev/null 2>&1 && echo "✓ docker" || echo "✗ docker not found"
	@command -v jq >/dev/null 2>&1 && echo "✓ jq" || echo "✗ jq not found"
	@command -v shellcheck >/dev/null 2>&1 && echo "✓ shellcheck" || echo "✗ shellcheck not found"
	@bash -c 'if ((BASH_VERSINFO[0] >= 4)); then echo "✓ bash $${BASH_VERSION}"; else echo "✗ bash 4.0+ required, found $${BASH_VERSION}"; fi'
