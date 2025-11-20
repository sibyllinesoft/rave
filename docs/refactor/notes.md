# Refactor Notes – 2025-11-07

## Pass 1: Repo Layout Recon
- Top-level mixes active components (CLI, nixos, services, docs) with legacy assets (`legacy/archive/`, `legacy/configs/`, numerous `*.qcow2` snapshots) which makes discovery noisy.
- CLI lives under `apps/cli/` as a Python Click app (`apps/cli/rave`, `vm_manager.py`, etc.); appears to be the only supported interface per `README.md`.
- NixOS build entry points sit in `flake.nix` + `infra/nixos/` (single `configs/complete-production.nix` plus modular tree under `infra/nixos/modules/**`).
- `services/` contains Python-based chat-control code paths separate from the Nix modules, implying additional runtime services outside the VM image.
- Documentation is extensive but fragmented across root `.md` files and `docs/**`; some guides (e.g., `docs/reference/services-overview.md`) still describe the older Docker/Compose era even though the CLI + Nix VM is canonical.
- Large vm images and QCOW checkpoints (`*-dev.qcow2`) live at repo root; need confirmation whether they are artifacts or required inputs.

## Outstanding Questions
- Which directories are actively referenced by the CLI vs. historical experiments (`legacy/archive/`, `legacy/configs/`, `gitlab-complete/`)?
- Are the `*.qcow2` assets meant to stay under version control, or can they be generated on-demand via flakes?
- How is secrets management evolving (SOPS/age) and where is the source of truth recorded (only `config/secrets.yaml` template?)?

## Leads for Deeper Dives
- Read `docs/explanation/architecture.md` + ADRs to map intended architecture vs. repo reality.
- Trace CLI commands (especially `vm_manager.py`) to see how it orchestrates Nix builds, asset staging, and secret sync.
- Inventory automation scripts in `scripts/` and `scripts/build/` to see which ones are obsolete vs. still wired into CI/CD.

## Pass 2: CLI + VM Tooling
- `apps/cli/rave` eagerly loads env files from `.env`, repo root, or `~/.config/rave/.env`, then wires subcommands backed by `VMManager`, `UserManager`, and `OAuthManager`.
- `apps/cli/vm_manager.py` shells out to `nix` and QEMU via helper scripts, stores VM metadata under `~/.local/share/rave/vms/*.json`, and still offers sshpass fallback (implies inconsistent keypair story).
- CLI requirements are minimal (`click`), yet the repo roots also expose shell scripts in `scripts/build/`/`scripts/` that partially overlap capabilities; need to map which are still invoked.

## Pass 3: Nix + Service Footprint
- Single `infra/nixos/configs/complete-production.nix` wires every service (GitLab, Mattermost, Outline, n8n, Grafana, Prometheus, chat bridge bootstrappers) into one monolithic VM image; earlier README references dev/demo variants that no longer exist.
- Secrets toggled via `config.services.rave.gitlab.useSecrets`, defaulting to baked-in passwords when false, which raises risk of secret drift; only `config/secrets.yaml` exists in repo for SOPS input.
- `flake.nix` builds multiple qcow variants but repo also tracks dozens of `*-dev.qcow2` images under version control, suggesting manual debugging artifacts lingering beside source.

## Pass 4: Docs + Knowledge Base
- Existing documentation spans root Markdown files plus `docs/**`, and messaging easily drifts (e.g., `docs/reference/services-overview.md` previously told readers to run `./run.sh start`; make sure future edits keep pointing at `./apps/cli/rave vm …`).
- ADRs (`docs/adr/*.md`) document P0–P2 milestones but there is no ADR for later additions like chat-control or Outline/n8n inclusion.
- Observed specialized guides (`docs/architecture/COMPLETE-BUILD.md`, `docs/architecture/WORKING-SETUP.md`, `docs/architecture/PRODUCTION-SECRETS-GUIDE.md`) repeating environment bootstrap steps with slight variations—prime candidates for consolidation into a single operator guide.

## Pass 5: Agent & Chat Bridge Stack
- `infra/nixos/agents.nix` defines ~10 agent systemd services plus installers for chat-control libraries, but there is no corresponding source tree for each agent under version control—likely placeholders.
- Chat bridge installation copies Python from `services/chat-control/src` + `services/mattermost-bridge` into `/opt/rave`, then wires secrets from SOPS paths such as `oidc/chat-control-client-secret`; this tight coupling to Mattermost makes swapping channels harder than README suggests.
- There is no automated test coverage for the agent/bridge pipeline beyond `tests/rave-vm.nix`, so regressions can creep in when reorganizing services.

## Pass 6: External Research Highlights
- Repo hygiene: both Atlassian’s CI-friendly Git guidance and Oracle’s binary storage recommendations stress pushing large/immutable artifacts to Git LFS or external storage to keep clones fast and histories clean.
- Documentation organization: Divio documentation system (tutorials, how-to, reference, explanation) fits the current sprawl and gives us a ready-made taxonomy for regrouping Markdown assets plus automation opportunities (e.g., `divio-docs-gen`).
- Secrets management: SOPS guidance reinforces age-based key management via `~/.config/sops/age/keys.txt` and environment overrides, backing a push to eliminate baked-in fallback credentials.
- Infrastructure testing: NixOS manual/wiki highlight modularizing configs and using NixOS VM tests; nix.dev’s integration-testing tutorial can anchor a new CI lane for `nixosTests`.

## Pass 7: Divio Migration Sprint
- Relocated `docs/architecture/WORKING-SETUP.md` under `docs/tutorials/` and left a stub in the root so existing links keep working.
- Authored `docs/how-to/provision-complete-vm.md`, merging the actionable parts of `docs/architecture/COMPLETE-BUILD.md` and `docs/architecture/PRODUCTION-SECRETS-GUIDE.md` into one operator playbook.
- Tagged the legacy guides with pointers to the new pages and updated `docs/README.md` plus the tutorials/how-to indexes to reflect what is published vs. pending.

## Pass 8: Begin Service Modularization
- Extracted the Outline stack into `infra/nixos/modules/services/outline/default.nix` with typed options (`services.rave.outline.*`) so it can be toggled per profile.
- Trimmed `infra/nixos/configs/complete-production.nix` to consume those options, removing inline Docker/nginx/sql snippets and letting the module append Postgres initialization fragments via `mkAfter`.
- This creates the first reusable profile hook for eventually building a minimal image without Outline or other heavy services.

## Pass 9: n8n Module
- Mirrored the modularization approach for n8n (`infra/nixos/modules/services/n8n/default.nix`), capturing its Docker unit, nginx routing, and Postgres bootstrap in one place.
- `infra/nixos/configs/complete-production.nix` now just sets `services.rave.n8n` options; removing n8n from the minimal profile is as simple as flipping `enable = false`.

## Pass 10: Development Profile (formerly dev-minimal)
- Added `infra/nixos/configs/development.nix` which imports the full configuration but forces Outline/n8n off and shrinks VM resources (8 GB RAM, 30 GB disk).
- Updated `flake.nix` so `nix build .#development` (alias `.#rave-qcow2-dev`) spits out the lightweight image, and documented both profiles in `README.md` plus the provisioning how-to.
- `rave vm build-image` now accepts `--profile {production,development}` (with `production` default) so humans/agents can select the right flake output without remembering raw attribute names; `--attr` remains for custom builds.
- Dashboard + welcome scripts now query `services.rave.*.enable` so Outline/n8n cards disappear automatically in the development profile.
- Added `rave vm list-profiles` so automation can discover available flake outputs without hardcoding names; README/how-to reference the command.
- `rave vm launch-local` accepts `--profile` and defaults image/service messaging to match the selected build (development profile hides Outline/n8n URLs by default).

## Pass 11: Penpot Module
- Reworked `infra/nixos/modules/services/penpot` to append Postgres/Redis/nginx settings instead of overwriting them, and added options for public URLs, images, and secret/password inputs.
- `infra/nixos/configs/complete-production.nix` now configures Penpot via `services.rave.penpot` and stops hardcoding its database/Redis wiring; the dashboard/welcome scripts use optional snippets just like Outline/n8n.
- The dev-minimal profile disables Penpot, and the CLI (launch/build commands) reflects that when printing service URLs.

## Pass 12: Profile Metadata Export + CLI Autodiscovery
- `flake.nix` now exposes `profileMetadata` so every profile’s flake attribute, description, feature flags, and default qcow name live alongside the actual build outputs (`production`, `development`, `demo`).
- `rave vm build-image/list-profiles/launch-local` dynamically query that metadata via `nix eval --json .#profileMetadata`, falling back to a baked-in table if `nix` is unavailable. The CLI therefore stays in sync as new profiles land without additional code edits.
- Updated the README + how-to docs to document the three supported profiles (including the new `demo` build) and the `productionWithPort` helper.

## Pass 13: SOPS Bootstrap Polish + GitLab/Mattermost Docs
- Fixed the new `security.rave.sopsBootstrap` helper script so it references shell variables correctly (`$selector` / `$dest`) and creates destination directories safely. This unblocks `nix flake check`, which previously failed while rendering the script.
- Collapsed the legacy `docs/architecture/GITLAB-MATTERMOST-INTEGRATION.md` file into a tiny pointer to the Divio how-to entry, reducing duplication.
- Refreshed `docs/how-to/gitlab-mattermost-integration.md` with module-aware instructions (pointing operators at `services.rave.mattermost` / `services.rave.gitlab`) and updated the development workflow to use flake profiles plus the CLI.

## Pass 14: Grafana & Friends Secret Hygiene
- Added `adminPasswordFile`, `secretKeyFile`, and `database.passwordFile` options to the monitoring module so Grafana can read credentials via the `$__file{}` provider instead of embedding them in the Nix store.
- Wired the production profile to `/run/secrets/grafana/{admin-password,secret-key,db-password}` and taught the SOPS bootstrapper to extract + chmod those secrets (plus create `/run/secrets/grafana` via tmpfiles).
- Introduced `postgres-set-grafana-password.service`, `postgres-set-mattermost-password.service`, `postgres-set-penpot-password.service`, `postgres-set-n8n-password.service`, and `postgres-set-prometheus-password.service`, which read `/run/secrets/{grafana,database}/...` after `sops-init` and update the PostgreSQL roles instead of baking passwords inside `initialSql`. Grafana/Mattermost/Penpot/n8n + the Prometheus exporter wait for their respective units before starting.
- `rave secrets install` now copies all of these DB secrets (including the Prometheus exporter) and triggers remote refreshes via the CLI helpers, keeping the VM in sync without manual `psql`.
- With the new file-backed settings `nix flake check` no longer prints the Grafana plaintext warning, and Mattermost finally follows the same pattern.

## Pass 15: Artifact Staging
- Added `artifacts/README.md` (tracked) so contributors have a canonical place to stash QCOW images, logs, and data snapshots; updated the main README to remind folks to keep those files out of Git.
- Updated the hygiene how-to and `scripts/repo/hygiene-check.sh` so the script now scans the working tree for `*.qcow2` outside `artifacts/` and warns with relocation instructions.
- `docs/how-to/repo-hygiene.md` reflects the new check order, keeping the documentation aligned with the script’s output.

## Pass 16: Minimal Flake Test
- Replaced the outdated `tests/rave-vm.nix` (which depended on the old P2 configs) with `tests/minimal.nix`, a lightweight NixOS test that boots the production profile with optional services disabled and verifies nginx/PostgreSQL/basic HTTPS are alive.
- `flake.nix` now exposes the test via `checks.x86_64-linux.minimal-test`, so `nix flake check` runs it automatically and `nix build .#checks.x86_64-linux.minimal-test` provides a reproducible smoke test before shipping new images.
