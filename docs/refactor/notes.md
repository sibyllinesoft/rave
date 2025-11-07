# Refactor Notes – 2025-11-07

## Pass 1: Repo Layout Recon
- Top-level mixes active components (CLI, nixos, services, docs) with legacy assets (`archive/`, `legacy-configs/`, numerous `*.qcow2` snapshots) which makes discovery noisy.
- CLI lives under `cli/` as a Python Click app (`cli/rave`, `vm_manager.py`, etc.); appears to be the only supported interface per `README.md`.
- NixOS build entry points sit in `flake.nix` + `nixos/` (single `configs/complete-production.nix` plus modular tree under `nixos/modules/**`).
- `services/` contains Python-based chat-control code paths separate from the Nix modules, implying additional runtime services outside the VM image.
- Documentation is extensive but fragmented across root `.md` files and `docs/**`; some guides (e.g., `docs/SERVICES-OVERVIEW.md`) still describe deprecated Docker/Compose workflows.
- Large vm images and QCOW checkpoints (`*-dev.qcow2`) live at repo root; need confirmation whether they are artifacts or required inputs.

## Outstanding Questions
- Which directories are actively referenced by the CLI vs. historical experiments (`archive/`, `legacy-configs/`, `gitlab-complete/`)?
- Are the `*.qcow2` assets meant to stay under version control, or can they be generated on-demand via flakes?
- How is secrets management evolving (SOPS/age) and where is the source of truth recorded (only `config/secrets.yaml` template?)?

## Leads for Deeper Dives
- Read `docs/ARCHITECTURE.md` + ADRs to map intended architecture vs. repo reality.
- Trace CLI commands (especially `vm_manager.py`) to see how it orchestrates Nix builds, asset staging, and secret sync.
- Inventory automation scripts in `scripts/` and `build-scripts/` to see which ones are obsolete vs. still wired into CI/CD.

## Pass 2: CLI + VM Tooling
- `cli/rave` eagerly loads env files from `.env`, repo root, or `~/.config/rave/.env`, then wires subcommands backed by `VMManager`, `UserManager`, and `OAuthManager`.
- `cli/vm_manager.py` shells out to `nix` and QEMU via helper scripts, stores VM metadata under `~/.local/share/rave/vms/*.json`, and still offers sshpass fallback (implies inconsistent keypair story).
- CLI requirements are minimal (`click`), yet the repo roots also expose shell scripts in `build-scripts/`/`scripts/` that partially overlap capabilities; need to map which are still invoked.

## Pass 3: Nix + Service Footprint
- Single `nixos/configs/complete-production.nix` wires every service (GitLab, Mattermost, Outline, n8n, Grafana, Prometheus, chat bridge bootstrappers) into one monolithic VM image; earlier README references dev/demo variants that no longer exist.
- Secrets toggled via `config.services.rave.gitlab.useSecrets`, defaulting to baked-in passwords when false, which raises risk of secret drift; only `config/secrets.yaml` exists in repo for SOPS input.
- `flake.nix` builds multiple qcow variants but repo also tracks dozens of `*-dev.qcow2` images under version control, suggesting manual debugging artifacts lingering beside source.

## Pass 4: Docs + Knowledge Base
- Existing documentation spans root Markdown files plus `docs/**`, but messaging conflicts (e.g., `docs/SERVICES-OVERVIEW.md` still recommends `./run.sh start` even though only CLI is supported).
- ADRs (`docs/adr/*.md`) document P0–P2 milestones but there is no ADR for later additions like chat-control or Outline/n8n inclusion.
- Observed specialized guides (`COMPLETE-BUILD.md`, `WORKING-SETUP.md`, `PRODUCTION-SECRETS-GUIDE.md`) repeating environment bootstrap steps with slight variations—prime candidates for consolidation into a single operator guide.

## Pass 5: Agent & Chat Bridge Stack
- `nixos/agents.nix` defines ~10 agent systemd services plus installers for chat-control libraries, but there is no corresponding source tree for each agent under version control—likely placeholders.
- Chat bridge installation copies Python from `services/chat-control/src` + `services/mattermost-bridge` into `/opt/rave`, then wires secrets from SOPS paths such as `oidc/chat-control-client-secret`; this tight coupling to Mattermost makes swapping channels harder than README suggests.
- There is no automated test coverage for the agent/bridge pipeline beyond `tests/rave-vm.nix`, so regressions can creep in when reorganizing services.

## Pass 6: External Research Highlights
- Repo hygiene: both Atlassian’s CI-friendly Git guidance and Oracle’s binary storage recommendations stress pushing large/immutable artifacts to Git LFS or external storage to keep clones fast and histories clean.
- Documentation organization: Divio documentation system (tutorials, how-to, reference, explanation) fits the current sprawl and gives us a ready-made taxonomy for regrouping Markdown assets plus automation opportunities (e.g., `divio-docs-gen`).
- Secrets management: SOPS guidance reinforces age-based key management via `~/.config/sops/age/keys.txt` and environment overrides, backing a push to eliminate baked-in fallback credentials.
- Infrastructure testing: NixOS manual/wiki highlight modularizing configs and using NixOS VM tests; nix.dev’s integration-testing tutorial can anchor a new CI lane for `nixosTests`.

## Pass 7: Divio Migration Sprint
- Relocated `WORKING-SETUP.md` under `docs/tutorials/` and left a stub in the root so existing links keep working.
- Authored `docs/how-to/provision-complete-vm.md`, merging the actionable parts of `COMPLETE-BUILD.md` and `PRODUCTION-SECRETS-GUIDE.md` into one operator playbook.
- Tagged the legacy guides with pointers to the new pages and updated `docs/README.md` plus the tutorials/how-to indexes to reflect what is published vs. pending.

## Pass 8: Begin Service Modularization
- Extracted the Outline stack into `nixos/modules/services/outline/default.nix` with typed options (`services.rave.outline.*`) so it can be toggled per profile.
- Trimmed `nixos/configs/complete-production.nix` to consume those options, removing inline Docker/nginx/sql snippets and letting the module append Postgres initialization fragments via `mkAfter`.
- This creates the first reusable profile hook for eventually building a minimal image without Outline or other heavy services.
