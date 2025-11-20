set positional-arguments

help:
	@just --list

build-vm *args:
	./scripts/build/build-vm.sh {{args}}

build-external-vm *args:
	./scripts/build/build-vm-external.sh {{args}}

run-demo *args:
	./scripts/demo/start-rave-demo.sh {{args}}
