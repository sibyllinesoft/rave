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

# Run security scan of the workspace (requires trivy)
verify-security:
	trivy fs --severity HIGH,CRITICAL .

# Legacy wrappers kept for compatibility during transition
build-vm *args:
	./scripts/build/build-vm.sh {{args}}

build-external-vm *args:
	./scripts/build/build-vm-external.sh {{args}}

run-demo *args:
	./scripts/demo/start-rave-demo.sh {{args}}
