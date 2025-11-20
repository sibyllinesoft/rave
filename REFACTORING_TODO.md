# Refactoring TODO

Derived from latest architecture feedback. Work these sequentially (any order) and update status as we go.

## 1. Nix Improvements (Foundation)
- [x] Adopt `flake-parts` in `flake.nix` to simplify per-system definitions and inputs.
- [x] Expose fast `config.system.build.vm` targets (vmVariant) for local loops.
- [x] Add native NixOS tests (e.g., login-flow) that exercise the stack via `nixosTests`.

## 2. Python CLI Robustness (`apps/cli`)
- [x] Introduce Pydantic models for VM config/state validation.
- [x] Centralize subprocess execution in a wrapper with logging + timeouts.
- [x] Respect `XDG_CONFIG_HOME` for CLI config discovery.

## 3. Go Auth Manager Hardening (`apps/auth-manager`)
- [x] Switch to structured logging (Go `log/slog`).
- [x] Add circuit breaking / upstream health checks for Mattermost proxying.

## 4. Repository Hygiene
- [x] Remove `legacy/` tree (Git keeps history).
- [x] Collapse `scripts/build/`, `scripts/demo/`, etc. into a single `scripts/` dir with a `Justfile`/`Makefile` entry.
- [x] Move stray top-level docs (e.g., `CLAUDE.md`) under `docs/architecture/`.

## 5. Immediate Checklist
- [x] Delete obsolete artifacts (`gitlab-complete/`, stray QCOWs) and rely on `.gitignore`.
- [x] Update `.sops.yaml` so CI can decrypt needed secrets.
- [x] Replace `requirements.txt` with a managed `pyproject.toml` (uv) covering CLI deps (`click`, `requests`, `pyyaml`, etc.).

_Working plan:_ With the hygiene/CLI foundations complete, the next major tasks move to the Go auth hardening backlog and any outstanding workflow automation you’d like to prioritize.
