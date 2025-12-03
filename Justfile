set positional-arguments

default: help

help:
	@echo "Available recipes:" 
	@just --list

# Build a VM image for a profile (development, production, demo, etc.)
build profile="development":
	nix build .#{{profile}} --show-trace

# Launch the local VM using the Python CLI
launch profile="development":
	./src/apps/cli/rave vm launch-local --profile {{profile}}

dev-vm:
	just launch profile="development"

# Run security scan of the workspace (requires trivy)
verify-security:
	trivy fs --severity HIGH,CRITICAL .

# Repository hygiene / lint helpers
hygiene:
	./scripts/repo/hygiene-check.sh

lint:
	./scripts/repo/hygiene-check.sh

secrets-lint:
	python ./scripts/secrets/lint.py

# Tests and smoke checks
test-e2e *args:
	./scripts/test-e2e.sh {{args}}

smoke *args:
	./scripts/spinup_smoke.sh {{args}}

# Health checks for common services
health-database:
	./scripts/health_checks/check_database.sh

health-gitlab:
	./scripts/health_checks/check_gitlab.sh

health-mattermost:
	./scripts/health_checks/check_mattermost.sh

health-network:
	./scripts/health_checks/check_networking.sh

# Legacy wrappers kept for compatibility during transition
build-vm *args:
	./scripts/build/build-vm.sh {{args}}

build-external-vm *args:
	./scripts/build/build-vm-external.sh {{args}}

run-demo *args:
	./scripts/demo/start-rave-demo.sh {{args}}
