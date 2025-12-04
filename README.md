# RAVE - Reproducible AI Virtual Environment

🚀 **Complete company development environments in minutes**

RAVE provides isolated, production-ready development VMs with GitLab, NATS JetStream, PostgreSQL, Redis, and pre-configured OAuth integration. Perfect for managing multiple company development environments with a single CLI.

## ✨ Quick Start

### Use RAVE CLI (**MANDATORY METHOD**)
```bash
# The RAVE CLI is the ONLY supported method for VM management
# All direct QEMU commands are FORBIDDEN
curl -Ls https://astral.sh/uv/install.sh | sh   # one-time uv install
cd apps/cli && uv sync && source .venv/bin/activate
export PATH="$PATH:$(pwd)"  # so `rave` resolves without a python -m prefix
```

### Create Your First Company Environment
```bash
# Create company development environment (development profile is default)
rave vm create acme-corp --profile development --keypair ~/.ssh/id_ed25519

# Skip the nix build step and reuse the cached profile image
rave vm create acme-corp --profile development --keypair ~/.ssh/id_ed25519 --skip-build

# Start the VM
rave vm start acme-corp

# SSH into the environment
rave vm ssh acme-corp

# View service logs
rave vm logs acme-corp traefik --follow
```

### Prepare Secrets (**required before building new VMs**)
- Run `rave secrets init` to generate an Age key if needed, inject the public key into `.sops.yaml`, and open `config/secrets.yaml` in `sops` for editing.
- Keep the Age private key (`~/.config/sops/age/keys.txt`) backed up securely—without it the encrypted secrets cannot be recovered.
- `rave vm create` offers to bootstrap secrets when they are missing and embeds the Age key into the VM automatically when available.
- Use `rave secrets install <company>` if you rotate credentials or need to refresh the Age key/secrets on an existing VM.
- Run `rave secrets diff --secrets-file config/secrets.yaml` for a dry-run list of every secret file that would be written before touching a VM.
- Before invoking `nix build` (or any command that reads the encrypted secrets), export `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` in your shell.
- For GitHub Actions, store the CI private key in the `SOPS_AGE_KEY_CI` secret so workflows can decrypt `config/secrets.yaml` using the dedicated `ci_key` recipient defined in `.sops.yaml`.
- When enabling external OAuth for GitLab, add `gitlab/oauth-provider-client-secret` (and its client ID) to `config/secrets.yaml` so the CLI can sync them into the VM.
- End-to-end OIDC setup (Google/GitHub) is documented in `docs/oidc-setup.md`; the CLI now prints required redirect URIs and can apply provider credentials live.

### Add Users via GitLab OAuth
```bash
# Add developer with name + initial metadata
rave user add john@acme-corp.com \
  --oauth-id 12345 \
  --name "John Smith" \
  --metadata '{"role":"engineer","team":"app"}' \
  --access developer --company acme-corp --provider google

# List company users
rave user list --company acme-corp

# Bulk import or update from CSV (email,oauth_id,name,access,role columns)
rave user bulk-add ./users.csv --company acme-corp --metadata 'project=beta'

# Persist the default provider (avoids repeating --provider on every command)
rave set-oauth-provider github
```

The GitLab VM enables OAuth via `services.rave.gitlab.oauth` (see `infra/nixos/configs/complete-production.nix`). Set the client ID in Nix and keep the client secret in `config/secrets.yaml`; the CLI pushes the secret into `/run/secrets/gitlab/oauth-provider-client-secret` when you start the VM.

## 🏗️ Repository Structure

```
rave/
├── apps/
│   ├── cli/                # RAVE CLI (main interface)
│   │   ├── rave            # Main CLI executable
│   │   ├── vm_manager.py   # VM lifecycle management
│   │   ├── user_manager.py # GitLab OAuth user management
│   │   └── oauth_manager.py
│   └── auth-manager/       # Go sidecar that bridges Pomerium to downstream apps
├── infra/
│   └── nixos/             # NixOS VM configurations
│       ├── configs/       # VM build configurations
│       │   ├── development.nix
│       │   ├── production.nix
│       │   └── demo.nix
│       └── modules/       # NixOS service modules
│           ├── services/  # GitLab, NATS, etc.
│           ├── security/  # SSL, certificates
│           └── foundation/# Base system config
├── services/              # Service-specific configurations
├── docs/                  # Documentation and reports
├── scripts/               # Utility and test scripts
├── scripts/build/         # VM build automation
-├── scripts/demo/          # Demo and example scripts
├── artifacts/             # Gitignored qcow images, logs, volume snapshots
│   └── qcow/              # Canonical qcow images per profile + dated builds
└── legacy/                # Archived assets kept for reference
    ├── configs/           # Historical Nix configs & scripts (formerly legacy-configs/)
    └── archive/           # Deprecated shell helpers & legacy nginx fixes
```

> ℹ️ The React-based provisioning dashboard now lives in the sibling repo
> [`../rave-infra/provisioning`](../rave-infra/provisioning). This keeps UI-specific
> dependencies out of the core VM builder while sharing the same artifacts bucket
> and CLI workflows.

## 🖥️ Architecture

Each company VM includes:
- **GitLab** - Source control with CI/CD pipelines
- **NATS JetStream** - Event streaming and messaging
- **PostgreSQL** - Primary database
- **Redis** - Caching (default + GitLab instances)
- **Traefik** - Reverse proxy with SSL termination
- **Penpot** - Design collaboration (OAuth via GitLab)
- **Mattermost** - Team chat and agent control (OAuth via GitLab)
- **Authentik** - Built-in IdP/front door; Pomerium becomes an optional value add

### Isolation
- **Port ranges**: Each company gets unique ports (8100+, 8110+, etc.)
- **SSH keys**: Baked-in keypair access per company
- **Data separation**: Isolated file systems and databases

### Chat Control Bridge
- **Mattermost** provides the default operator chat surface (`https://chat.localtest.me:8443/`).
- A hardened chat bridge (`rave-chat-bridge`) consumes Mattermost slash commands and maps them to agent actions.
- GitLab OIDC is pre-wired for Mattermost and the bridge; update the encrypted secrets (`mattermost/admin-username`, `mattermost/admin-email`, `mattermost/admin-password`, `oidc/chat-control-client-secret`, `gitlab/api-token`) before production use.
- Shared chat-control components live in `services/chat-control/` so alternate adapters (Slack, etc.) can be swapped in with minimal effort.
- Baseline setup automatically provisions the `rave` team, an `#agent-control` channel, a `/rave` slash command, and generates secure tokens that the bridge reads from `/etc/rave/mattermost-bridge/`.

## 📖 CLI Reference

### VM Management
```bash
rave vm create <company> [--profile name] --keypair <path>  # Create company VM
rave vm start <company>                      # Start VM
rave vm stop <company>                       # Stop VM
rave vm status [--all]                       # Show VM status
rave vm reset <company>                      # Reset to clean state
rave vm ssh <company>                        # SSH into VM
rave vm logs <company> [service] [options]   # View logs
```

### User Management
```bash
rave user add <email> --oauth-id <id> --access <level>  # Add user
rave user remove <email>                                # Remove user
rave user list [--company <name>]                       # List users
rave user config <email> --access <level>               # Change access
rave user show <email>                                   # Show details
```

### OAuth Status
```bash
rave oauth status [service]                  # Show OAuth integration status
rave oauth redirects [company]               # Print redirect URIs for Google/GitHub
rave oauth bootstrap google --company <name> # Generate gcloud command for OAuth client
rave oauth apply --company <name> --provider google --client-id ...
```

### GitOps override layers
```bash
rave overrides init                          # Scaffold config/overrides/global
rave overrides status                        # List known layers + file counts
rave overrides create-layer host-foo --priority 50 \
  --preset traefik                           # Add a dedicated layer with presets
rave overrides apply --dry-run --company <name> \
  --preflight-cmd "nixos-rebuild test --flake .#{company}"  # Preview + host preflight
rave overrides apply --company <name> --json-output  # Sync overrides and emit JSON summary
```

- The CLI treats `config/overrides/<layer>/files/` as a mirror of `/` on the VM, copying files verbatim with owner/mode hints from the layer’s `metadata.json`.
- Drop complete units under `config/overrides/<layer>/systemd/` to create/override services in `/etc/systemd/system/`; `daemon-reload` is handled automatically.
- Metadata presets (`--preset traefik`, `--preset gitlab`, etc.) append opinionated pattern blocks so new layers inherit the correct restart/reload semantics automatically (options: traefik, gitlab, mattermost, pomerium, authentik).
- `--dry-run` first runs `nix flake check` (override with `--nix-check-cmd` or skip via `--skip-nix-check`), optionally executes extra `--preflight-cmd` commands (placeholders: `{company}`, `{layers}`), then streams the layer into the VM in preview mode, printing the plan without touching the filesystem. Add `--json-output` to capture the resulting plan for automation.

## 🧹 Disk Cleanup

- `rave gc images --keep 2 --dry-run` scans `artifacts/qcow/` (or any path passed via `--directory`) and shows which QCOW files would be deleted while protecting images that are still referenced by VM configs or symlinks. Add `--min-age-hours 24` to avoid touching fresh builds, or `--force` if you intentionally want to remove files that are still referenced.
- `rave gc store --dry-run` prints the Nix commands that will run (`nix store gc`, `nix profile wipe-history --older-than 30d`, `nix store optimise`, and `nix-collect-garbage -d`). Drop `--dry-run` once you're comfortable, or adjust `--wipe-history`, `--no-optimize`, or `--no-legacy-collect` to fit your environment.
- Both subcommands are safe to place in cron/systemd timers to keep the repo’s artifacts and the Nix store from consuming hundreds of gigabytes.

### Secrets
```bash
rave secrets init                            # Bootstrap SOPS + Age locally
rave secrets install acme-corp               # Refresh Age key/secrets for a running VM
```
`rave vm create` embeds the Age key when it is available, and `rave vm start`
syncs secrets automatically on boot. Use `rave secrets install` to push new
credentials into a running VM after rotation.

### Trusted TLS for Local Browsers
```bash
rave tls bootstrap                           # Install mkcert & trust the local CA (run once per host)
rave tls issue acme-corp                     # Mint & install a cert for https://chat.localtest.me:8443
```
After issuing the certificate, hit the dashboard at `https://localhost:8443/` and Mattermost at
`https://chat.localtest.me:8443/` for green locks. Add `--domain` flags if you expose the VM on
additional hostnames (e.g. `--domain app.dev.vm`).

Need to front the stack with Google OAuth instead of GitLab? Follow `docs/how-to/oauth-google.md`
for the Google Console steps, SOPS secret layout, and the new `--idp-*` flags available on
`rave vm build-image` and `rave vm create`.
Prefer running Authentik (now baked into every image) as your IdP while keeping Pomerium optional?
See `docs/how-to/authentik.md` for the required secrets, default routes, and how to use
`RAVE_DISABLE_POMERIUM` when you want Traefik/Authentik to front the stack directly.
Want GitLab to skip the first-boot migrations? Capture a schema dump once and reuse it via
`services.rave.gitlab.databaseSeedFile` (see `docs/how-to/gitlab-schema-seed.md`).

### End-to-End Smoke Test
```bash
scripts/test-e2e.sh --profile development    # runs unit + integration suite
python3 test_vm_integration.py --profile development
python3 test_vm_integration.py --mode split --apps-profile appsPlane \
  --data-host 10.0.2.2 --data-pg-port 25432 --data-redis-port 26379
```
Use `--profile production` for the full stack or `--keep-vm` to leave the VM running for debugging.
Split mode spins up both the `dataPlane` (Postgres/Redis) and `appsPlane` VMs simultaneously, wiring the
apps tier to `10.0.2.2:<ports>` so you can run end-to-end OAuth/pomerium tests without rebuilding images.

## 🧱 VM Profiles

| Profile | Build Command | Notes |
| --- | --- | --- |
| `production` | `nix build .#production` | Full production stack with Outline + n8n and higher resource defaults (≈12 GB RAM, 40 GB disk). |
| `dataPlane` | `nix build .#dataPlane` | PostgreSQL + Redis only; run once per company to host durable data and keep app images stateless. |
| `appsPlane` | `nix build .#appsPlane` | Application tier (GitLab/Mattermost/etc.) configured to talk to an external data plane via `RAVE_DATA_HOST`. |
| `development` | `nix build .#development` | Lightweight dev image with Penpot/Outline/n8n disabled and smaller VM footprint (≈8 GB RAM, 30 GB disk). |
| `demo` | `nix build .#demo` | Demo-friendly build with observability/optional apps disabled for faster boots (≈6 GB RAM). |

Run `rave vm list-profiles` to print this matrix (and any future custom profiles) from the CLI.

When using the split deployment, set `RAVE_DATA_HOST=<ip-or-hostname>` before running `nix build` (or pass `--env RAVE_DATA_HOST=...` to the CLI) so the apps-plane image bakes the correct Postgres/Redis endpoints. You can also override `RAVE_DATA_PG_PORT` and `RAVE_DATA_REDIS_PORT` when the remote services are exposed on non-standard host ports (useful for CI or port-forwarded e2e runs). The data-plane profile listens on `0.0.0.0` for ports 5432/6379 by default; lock that down with firewalls or WireGuard in production.

From the CLI, run `rave vm build-image --profile development` for the lightweight variant (default `production`), or pass `--attr` if you need a custom flake output. `rave vm launch-local --profile development` picks the matching qcow2 and hides Penpot/Outline/n8n because that profile disables them.

Use `nix build .#development` when you need a faster local iteration loop, and swap back to the full profile before publishing artifacts.
Generated QCOWs, logs, and snapshots should live under `artifacts/` (ignored by Git); the CLI now writes qcow images into `artifacts/qcow/` automatically. See `artifacts/README.md` for the recommended layout.
The landing dashboard and welcome script automatically hide Outline/n8n (or any future optional services) when those modules are disabled.

## 🔧 Development

### Dev Shell
```bash
nix develop
```
The shell exposes the CLI, Go toolchain, and nix tooling, and automatically points
`GOPATH` at a repo-local `.gopath/` so `apps/auth-manager` builds without the
`runExitHooks redeclared` runtime error that appears with mismatched host Go installs.

### Building VMs
```bash
nix build .#development    # Development VM
nix build .#production     # Production VM  
nix build .#demo          # Demo VM
```

### Testing
```bash
# Run VM tests
nix build .#checks.x86_64-linux.minimal-test

# Health checks
./scripts/rave health   # runs status + any scripts/health_checks/*.sh

# Auth Manager unit tests (inside the dev shell)
cd apps/auth-manager
go test ./...
```

## 🚀 Use Cases

- **Agency/Consultancy**: Separate environments per client
- **Multi-tenant SaaS**: Isolated dev environments per customer
- **Team Management**: Department-specific development stacks
- **Training/Education**: Standardized learning environments
- **Demo/Sales**: Quickly spin up client demonstrations

## 🔐 Security

- Self-signed SSL certificates for development
- GitLab OAuth integration pre-configured
- SSH key-based authentication
- Isolated network namespaces
- Encrypted secrets management (production)

## 📚 Documentation

- [CLI Documentation](apps/cli/README.md)
- [VM Architecture](docs/SERVICES-OVERVIEW.md)
- [Security Reports](docs/)
- [Legacy Documentation](docs/DEPLOYMENT-STATUS.md)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push branch: `git push origin feature/amazing-feature`
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Experience the org dev sysadmin superpower: Multi-tenant development environments in 30 seconds.** 🚀

## 📚 Documentation Hub
The repository’s living documentation is now organized via the Divio model. Start with `docs/README.md` for links to tutorials, how-to guides, reference material, and explanation/architecture deep dives. Each entry lists which legacy documents still need to migrate so contributors can help retire duplicates safely.
