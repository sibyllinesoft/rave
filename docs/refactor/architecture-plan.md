# Architecture Simplification Plan — 2025-11-07

## 1. Objectives
- Reduce cognitive load for contributors and AI agents by separating source, infrastructure definitions, and generated artifacts.
- Establish a modular, testable Nix foundation that can produce dev, staging, and production VM targets without editing the same monolithic file.
- Create a single documentation system that reflects the current CLI-first workflow and consolidates security guidance.
- Enforce secrets-as-code practices so builds never fall back to embedded sample passwords.
- Add automated verification (formatting + NixOS VM tests) before publishing new QCOW images.

## Status — 2025-11-08

### Completed
- **Service modularization:** GitLab, Mattermost, Penpot, n8n, monitoring, nginx, Redis, PostgreSQL, etc. all live in dedicated modules with shared password-setter scaffolding; `services.rave.*` options are now consumed by the production/development/demo profiles.
- **Secrets as code:** Every Postgres role (Grafana, Mattermost, Penpot, n8n, Prometheus exporter) reads from `/run/secrets/**`, and the CLI’s `rave secrets install` refreshes the roles via SSH helpers. Grafana/Mattermost docs describe the new flows.
- **Docs migration:** README + how-to content points to Divio sections; legacy Markdown files are stubs; repo hygiene/how-to now reflects the artifact staging workflow.
- **Flake outputs:** Production/development/demo images, `profileMetadata`, and the new `checks.x86_64-linux.minimal-test` smoke test run via `nix flake check`.
- **CLI alignment:** `rave vm build/create/launch/list-profiles` read flake metadata, `rave secrets install` warns on missing secrets, and `artifacts/README.md` explains where QCOW/logs belong.
- **Automated NixOS tests:** `tests/minimal-vm.nix` (GitLab + PostgreSQL smoke) and `tests/full-stack.nix` (Mattermost + CI bridge) now ship via `nixosTests` and `checks.x86_64-linux.{minimal-test,full-stack}` so `nix build .#checks.x86_64-linux.full-stack` exercises the full stack locally.
- **CLI/unit coverage:** Python unit suites (`tests/python/test_vm_manager.py`, `tests/python/test_platform_utils.py`, `tests/python/test_secrets_flow.py`, `tests/python/test_cli_secrets.py`) cover VM helpers, PlatformManager, `_sync_vm_secrets`, and the `rave secrets install` command; run `python3 -m unittest tests.python.*` after touching CLI helpers.
- **Repo hygiene:** All legacy QCOW snapshots moved under `artifacts/legacy-qcow/`, CLI fallback updated, and docs now point at the artifacts directory so the repo root stays source-only.

### Ready for Handoff
- **Command services:** `generate`, `spec-import`, and `sync` already use the service-backed architecture; `integrate` is mid-migration (shared context helper landed, but GitHub template helpers still inline).
- **Remaining to do:**
  1. Finish the integrate service extraction (including the GitHub template helpers) and ensure every command invokes the shared context helper.
  2. Split `services/generate` into submodules (compose parser, template runner, hook executor) with focused unit tests.
  3. Add service-level tests for spec import, sync, and integrate, then update contributor docs once the new architecture is locked in.

## 2. Guiding Principles
1. **Source vs. artifact separation** – Keep the Git history lean by storing large QCOW images, logs, and volume snapshots in release storage or Git LFS, referencing Atlassian’s “CI-friendly Git” guidance.
2. **Modular Nix everywhere** – Follow the NixOS module system pattern (imports/options/config) so each service, agent, and environment tier is its own module that can be composed per target.
3. **Secrets as code** – Treat every secret as encrypted configuration via sops + age, with keys sourced from `~/.config/sops/age/keys.txt` or `SOPS_AGE_KEY_FILE`, never from plain-text fallbacks.
4. **Documentation taxonomy** – Adopt the Divio classification (Tutorials, How-to, Reference, Explanation) to align documentation intent with reader expectations.
5. **Automated tests** – Use `pkgs.testers.runNixOSTest` (or flake `nixosTests`) for integration coverage so each change to the VM definition proves the critical services still boot together.

## 3. Workstreams

### A. Repository Hygiene & Layout
| Goal | Deliverables | Definition of Done |
| --- | --- | --- |
| Separate source from artifacts | - Move QCOWs, `.qcow2.backup`, `gitlab-complete/`, `run/*.log`, and cache directories under `artifacts/` (gitignored) or publish them to release storage. <br>- Add Git LFS pointer rules only for the few binary assets we must keep. | `git status` in root shows only source + config. README documents how to fetch images via CLI or release URL. |
| Clarify top-level purpose | - Introduce `apps/cli/`, `infra/nixos/`, `services/chat-control/`, `docs/`, `legacy/`. <br>- Migrate active code into these namespaces; move experiments to `legacy/` with README. | New directory map is documented, and CLI scripts/tests are discoverable under `apps/cli`. |
| Instrument metadata | - Add `.gitmodules` or `manifest.json` describing large external dependencies so automation can fetch them intentionally. | Automated tooling (e.g., `rave doctor`) reports missing artifacts instead of scanning filesystem heuristically. |

### B. Layered Nix Architecture
| Goal | Deliverables | Definition of Done |
| --- | --- | --- |
| Split monolithic config | - Create `infra/nixos/profiles/base.nix`, `services.nix`, `observability.nix`, `chat.nix`, etc. <br>- Compose new profiles: `development`, `demo`, `production`. | `nix build .#vm-dev` and `.#vm-prod` both succeed without editing shared modules. |
| Parameterize secrets & ports | - Replace inline passwords in `complete-production.nix` with option defaults that assert `config.services.rave.secretsRequired = true`. <br>- Provide environment overlays for port blocks per tenant. | Builds fail fast when secrets are missing; CLI prompts to sync via `rave secrets install`. |
| Align CLI with Nix outputs | - Update `cli/vm_manager.py` to read flake outputs instead of hardcoded filenames, enabling `rave vm build --profile development`. | CLI help lists available profiles derived from flake metadata. |

### C. Secrets & Compliance
| Goal | Deliverables | Definition of Done |
| --- | --- | --- |
| Enforce sops workflow | - Document key creation + storage (Age key location, `SOPS_AGE_KEY_FILE`). <br>- Ship `scripts/secrets/lint.py` to validate `.sops.yaml` entries. | CI fails if required secrets are missing or decrypted values are committed. |
| Runtime secret sync | - Convert systemd units to read from `/run/secrets/*` only. <br>- Extend `rave secrets install` to diff + reload affected services. | No service references bake-in fallback credentials; Git history never contains sample passwords. |
| Rotation playbooks | - Single doc describing rotation for GitLab OAuth, Mattermost bridge, chat-control clients. <br>- CLI helper to print which secrets changed. | Operators can rotate secrets without editing Nix files manually. |

### D. Documentation System
| Goal | Deliverables | Definition of Done |
| --- | --- | --- |
| Build Divio-aligned docs | - Create `docs/index.md` referencing Tutorials, How-to, Reference, Explanation subtrees. <br>- Convert `WORKING-SETUP.md`, `COMPLETE-BUILD.md`, etc. into the right buckets, eliminating duplicates. | Doc site (MkDocs or mdBook) categorizes content; README links to it as the source of truth. |
| Auto-generate CLI reference | - Use Click’s `rave --help` output to render command reference under the Reference section. | CLI docs regenerate via `poetry run docs:cli`. |
| Operational runbooks | - Produce a unified How-to for “Provision new tenant” covering CLI + secrets + testing. | Agents can follow a single link to stand up environments without bouncing among multiple markdown files. |

### E. Testing & Automation
| Goal | Deliverables | Definition of Done |
| --- | --- | --- |
| Add NixOS VM tests | ✅ `tests/minimal-vm.nix` (GitLab, PostgreSQL) and `tests/full-stack.nix` (Mattermost + CI bridge) now live; run them locally via `nix build .#checks.x86_64-linux.{minimal-test,full-stack}`. | Next: hook these checks into CI so pull requests block on failures once runner capacity is confirmed. |
| CLI/unit coverage | - `tests/python/test_vm_manager.py`, `tests/python/test_platform_utils.py`, `tests/python/test_secrets_flow.py`, and `tests/python/test_cli_secrets.py` cover VM manager flows, PlatformManager, secrets syncing, and Click wiring; next step is to add pytest coverage for the remaining command services. <br>- Add formatting (`ruff`, `black`) and type checking (`pyright`). | `make test` (or `nix develop --command pytest`) passes locally and in CI. |
| Observability sanity checks | - Optional integration test verifying Grafana/Prometheus endpoints respond after boot. | Known dashboards load in automated smoke test. |

### F. Migration & Cleanup
1. **Inventory legacy files** – Create `legacy/README.md` listing what stays for historical reference vs. scheduled deletion dates.
2. **Deprecate unused scripts** – Flag each script in `build-scripts/` and `scripts/` as “supported” or “sunset” inside a SCRIPT_CATALOG.md.
3. **Archive QCOW snapshots** – Publish current golden image to OCI bucket or release asset, remove it from Git history, and replace with download instructions.

## 4. Execution Phasing
| Phase | Weeks | Focus |
| --- | --- | --- |
| 0 – Preparation | 1 | Freeze new QCOW additions; capture baseline metrics; communicate plan. |
| 1 – Repo Hygiene | 2 | Move artifacts, new directory map, update README + CLI references. |
| 2 – Modular Nix Core | 3 | Break out modules, add profiles, adjust CLI, ensure dev builds run. |
| 3 – Secrets & Docs | 2 | Enforce sops flow, publish Divio-style docs, remove duplicated guides. |
| 4 – Testing Rollout | 2 | Author NixOS VM tests + CLI tests, add CI jobs, document workflow. |
| 5 – Legacy Cleanup | ongoing | Track remaining legacy scripts/assets, solicit deletion approvals. |

## 5. Risks & Mitigations
- **Hidden consumers of legacy scripts** → survey commit history + open issues; provide shims that emit “deprecated” warnings before removal.
- **Long build times for new profiles** → cut the “development” (formerly dev-minimal) profile early so contributors can iterate while production build matures.
- **Secrets migration churn** → stage environment-specific secret bundles and run tabletop exercise before flipping `useSecrets = true` permanently.
- **Documentation drift recurring** → tie doc build into CI so every change in CLI or Nix modules requires doc link updates (fail the pipeline otherwise).

## 6. Success Metrics
- Repository clone size < 1 GB, with zero QCOW files tracked.
- `rave vm build --profile development` completes in < 20 minutes on 12 GB host; production profile < 45 minutes.
- Divio doc site has ≥1 tutorial, ≥3 how-to guides, ≥1 reference per subsystem, ≥2 explanation articles.
- Secrets lint + NixOS tests run on every pull request with < 30 minute wall-clock.
- Legacy directory shrinks by 50 % within two iterations, with remaining files referenced in documentation as historical artifacts.
