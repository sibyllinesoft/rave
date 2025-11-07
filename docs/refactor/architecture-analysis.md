# RAVE Architecture Analysis — 2025-11-07

## 1. Purpose & Approach
- Capture the state of the repository as observed on 2025-11-07 to explain how the platform is assembled today.
- Highlight structural patterns that contribute to perceived cruft and AI-agent confusion, based on direct inspection plus existing documentation.
- Inputs: `README.md`, `docs/explanation/architecture.md`, ADRs under `docs/adr/`, CLI sources in `cli/`, Nix stack under `flake.nix` and `nixos/**`, runtime service code in `services/**`, and operational guides in the repo root + `docs/`.

## 2. Repository Topology
- Active code and infrastructure live beside large artifacts: a dozen `*.qcow2` images, log directories (`run/`, `logs/`), and complete data volumes under `gitlab-complete/` checked into the repo root. This makes directory discovery noisy and breaks expectations for source-only repos.
- There is no single `src/` or `packages/` boundary; instead, functionality is split across `cli/` (Python), `services/chat-control` (Python), `services/mattermost-bridge` (Python), `nixos/` (NixOS modules), `scripts/`, `build-scripts/`, `demo-scripts/`, and `legacy-configs/`.
- Historical assets are only partially segregated: `legacy-configs/` and `archive/` contain old Nix configs, shell scripts, and nginx fixes, yet they share naming with still-used assets (e.g., `run.sh` under `legacy-configs/` conflicts with documentation that still references `./run.sh`).
- Documentation is split between the root (e.g., `COMPLETE-BUILD.md`, `WORKING-SETUP.md`, `PRODUCTION-SECRETS-GUIDE.md`) and `docs/**` (architecture, services, deployment). No index ties them together, so onboarding requires guesswork.

## 3. Build & VM Lifecycle Flow
- The authoritative build path is Nix flakes: `flake.nix` defines inputs (`nixpkgs`, `nixos-generators`, `sops-nix`), outputs for QCOW images, and a `rave-cli` derivation that wraps the Python CLI. SAFE-mode resource throttling is embedded directly in `nixConfig`.
- Only one configuration file exists under `nixos/configs/` (`complete-production.nix`), meaning every VM build pulls in the entire service stack regardless of use case. Legacy P0–P6 configs exist under `legacy-configs/` but are disconnected from current flake outputs.
- Manual shell helpers in `build-scripts/` duplicate some flake responsibilities (`build-vm.sh`, `build-vms.sh`, etc.), which can drift from the CLI’s automation path (`cli/vm_manager.py`) and add to cognitive load.
- Tests are minimal: the flake exposes `tests/rave-vm.nix`, but there are no automated checks for the Python CLI or the chat-control services. Continuous integration hooks (.github workflows) were not observed, and `.gitlab-ci.yml` exists but its applicability is unclear without active pipelines.

## 4. CLI & Orchestration Layer
- `cli/rave` is a Click app that bootstraps environment variables from `.env` files and wires subcommands for VM lifecycle, user management, OAuth, secrets, and TLS helpers.
- `cli/vm_manager.py` shells out to `ssh`, `qemu-system-x86_64`, and `nix` via `PlatformManager`, stores VM metadata in JSON under `~/.local/share/rave/vms/`, and still offers `sshpass` fallbacks (indicating inconsistent keypair/secret policies).
- Several helper files (`vm_manager.cover`, `oauth_manager.cover`, etc.) at the root of `cli/` look like coverage artefacts, living beside source files. They are easy to confuse with actual modules.
- CLI docstrings describe `rave vm launch-local`, but README instructions emphasize `rave vm create/start`; other docs still instruct `./run.sh start` (`docs/SERVICES-OVERVIEW.md`), creating mismatched operator workflows.

## 5. Runtime Service Stack
- `nixos/configs/complete-production.nix` wires a monolithic VM image that includes GitLab CE, Mattermost, Penpot, Outline, n8n, Prometheus + exporters, Grafana, nginx, PostgreSQL, Redis, NATS JetStream, and a bespoke chat-control bridge. All services are enabled regardless of deployment scenario, which inflates closure size (40 GB disk, 12 GB RAM) and slows iteration.
- Agent orchestration is described in `nixos/agents.nix`, defining ~10 placeholder agents plus the Mattermost bridge, installing source trees from `services/chat-control/src` and `services/mattermost-bridge`. The repo does not carry actual agent implementations, so these systemd units deploy empty scaffolding.
- Secrets handling toggles between baked-in defaults and `/run/secrets/...` files populated via sops-nix. `config/services/rave/gitlab.useSecrets` gates multiple fallback passwords and API tokens that are still committed in plain text within Nix files.
- Multiple service-specific directories (`gitlab-complete/`, `postgres/`, `nixos/static/`, `matrix-setup/`) hold runtime data snapshots that overlap with what the QCOW images already package, hinting at ad-hoc recovery workflows rather than a clean infrastructure-as-code boundary.

## 6. Documentation & Knowledge Assets
- Core references include `README.md` (high-level pitch), `docs/explanation/architecture.md` (conceptual diagrams), `docs/reference/services-overview.md` (historical Docker Compose era), and ADRs in `docs/adr/` for P0–P2 milestones. Later capabilities—chat-control bridge, Outline/n8n inclusion, CLI mandates—lack ADR coverage.
- Operational guides such as `WORKING-SETUP.md`, `COMPLETE-BUILD.md`, and `PRODUCTION-SECRETS-GUIDE.md` repeat overlapping steps (install Nix, build QCOW, bootstrap secrets) with slight variations, but none establish a canonical “operator runbook.”
- Security guidance is fragmented: `docs/security/SECURITY_MODEL.md`, `PRODUCTION-SECRETS-GUIDE.md`, and inline README content each describe different portions of the secrets story (Age key generation, `rave secrets init`, manual SOPS editing).
- There is no single architecture index linking to the many Markdown files, so AI agents (and humans) have to brute-force search to find the right doc for a task.

## 7. Sources of Confusion & Risk
- **Artifact Sprawl**: Checking large QCOWs, log files, and data directories into the repo blurs the line between source and state, making it hard for automation (or agents) to know what is safe to touch.
- **Monolithic Nix Config**: Only one `complete-production` module exists, so any attempt to build a lighter dev/test environment requires editing production definitions directly or resurrecting `legacy-configs` by hand.
- **Inconsistent Tooling Paths**: Multiple orchestration interfaces (`cli/rave`, `build-scripts/*.sh`, `legacy-configs/run*.sh`, documentation for Docker Compose) coexist, with no authoritative matrix of which commands remain supported.
- **Documentation Drift**: References to `./run.sh`, outdated port maps, and missing ADRs mean contributors cannot trust instructions without cross-checking real code paths.
- **Secrets & Compliance**: Default passwords embedded in Nix (`gitlab-production-password`, `Password123!`, etc.) are still used whenever `useSecrets` is false. Because secrets live under `config/secrets.yaml` without templated validation, there is no automated guarantee they are present before builds.
- **Testing Gap**: Only `tests/rave-vm.nix` exists; CLI, chat-control, and multi-agent services have no automated verification, yet they interact with external systems (GitLab, Mattermost, OAuth) that are brittle to regressions.

## 8. Opportunities Highlighted for Refactor Planning
- Establish clear separation between **source** (code + configs) and **artifacts** (VM images, runtime logs, data snapshots) by moving large binaries to `artifacts/` or release storage, keeping the repo lean.
- Introduce layered Nix configurations (foundation, minimal dev, full production) so contributors can iterate on smaller builds while preserving production parity.
- Consolidate automation paths around the CLI by retiring unused shell scripts and updating docs to match the supported workflow; optionally generate CLI reference docs from Click commands.
- Create a documentation index (or a MkDocs/Sphinx site) that consolidates architecture, operations, and security content, reducing duplication and guiding agents to the right file quickly.
- Harden secrets management by making `useSecrets = true` the only supported mode, validating `config/secrets.yaml` entries, and documenting rotation flows in one place.
- Capture new architectural decisions—chat bridge, Outline/n8n adoption, agent scaffolding—via fresh ADRs so future contributors understand why they exist and how to evolve them.
