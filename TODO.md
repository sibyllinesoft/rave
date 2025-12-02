### 1. The Authentik Fix (Priority)
The current setup (inferred from docs/scripts) attempts to run Authentik via Docker containers inside the NixOS VM. This causes networking friction between the host, the Traefik proxy, and the internal Postgres/Redis services.

**The Issue:**
In `docs/how-to/authentik.md`, you define manual steps or `authentik-sync-oidc-applications.service` to configure providers. This is brittle because if the Docker container restarts, state or connectivity to the "host" (VM) database might be lost or race-conditioned.

**The Solution: Use Native NixOS Modules**
NixOS has a first-class `services.authentik` module. Switching to this removes the Docker layer, allowing systemd to manage dependencies (Postgres/Redis) and file permissions natively.

**Refactor Plan:**
1.  Remove the Docker container definition for Authentik.
2.  Enable the native module in your `infra/nixos/modules/services/authentik/default.nix`:

```nix
# infra/nixos/modules/services/authentik/default.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.rave.authentik;
in {
  config = lib.mkIf cfg.enable {
    services.authentik = {
      enable = true;
      # The environment file provided by sops-nix
      environmentFile = config.sops.secrets."authentik/env".path;
      settings = {
        email.host = "smtp.example.com";
        disable_startup_analytics = true;
        avatars = "gravatar";
      };
      # Automatically provision the ingress
      nginx = {
        enable = true;
        enableACME = false;
        host = "auth.localtest.me";
      };
    };

    # Declarative Configuration (Blueprints)
    # This replaces manual setup steps for Mattermost/Grafana integration
    systemd.services.authentik-apply-blueprints = {
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik-worker.service" "authentik-web.service" ];
      script = ''
        ${pkgs.authentik}/bin/ak apply_blueprint ${./blueprints}
      '';
    };
  };
}
```

### 2. Repository Structural Refactoring
The current structure mixes source code (`apps/`), infrastructure (`infra/`), and massive artifacts (`*.qcow2` files in root or artifacts folder).

**Action Items:**
1.  **Strict Separation:** Ensure `.gitignore` is extremely aggressive about `*.qcow2`. The hygiene script (`scripts/repo/hygiene-check.sh`) is good, but you should move *all* binary artifacts to a dedicated S3/R2 bucket or use `git-lfs` if you must track them.
2.  **Unified "Src" Directory:** Move `services/` and `apps/` into a single `src/` directory to simplify tooling paths.
3.  **Shell Script Consolidation:** You have `scripts/`, `scripts/build`, `scripts/demo`, `scripts/security`, etc.
    *   **Refactor:** Replace the many bash scripts with a **Justfile**. `Just` is a command runner perfect for Nix projects. It allows you to document commands and dependencies clearly.

**Example `Justfile`:**
```makefile
# Instead of scripts/build/build-vm.sh
build profile="development":
    nix build .#{{profile}} --show-trace

# Instead of apps/cli/rave vm launch-local
launch profile="development":
    ./apps/cli/rave vm launch-local --profile {{profile}}

# Replaces scripts/security/p1-security-verification.sh
verify-security:
    trivy fs --severity HIGH,CRITICAL .
```

### 3. Python CLI Refactoring (`apps/cli`)
`vm_manager.py` is becoming a "God Class" (13,000+ tokens). It handles SSH injection, QEMU management, disk creation, and config parsing.

**Refactor Plan:**
1.  **Split `vm_manager.py`:**
    *   `qemu_driver.py`: Pure functions to generate QEMU command lines.
    *   `ssh_client.py`: A dedicated wrapper for `subprocess.run(["ssh", ...])` that handles connection retries and `sshpass` fallback logic centrally.
    *   `provisioner.py`: Logic for `install_age_key` and `inject_ssh_key`.
2.  **Use `pydantic-settings`:** Currently, you parse `.env` files manually in `rave` (main file). Use Pydantic to load environment variables automatically, ensuring types are correct before the CLI starts.
3.  **Remove `PlatformManager` checks:** NixOS provides a uniform environment inside the VM. The CLI runs on the host, but using Python's `pathlib` and standard libraries usually negates the need for complex OS switching logic unless you are supporting Windows directly (which QEMU/Nix usually implies WSL2 anyway).

### 4. Nix Flake Simplification
The `flake.nix` (inferred from context) seems to export many packages and checks.

**Refactor Plan:**
Use **`flake-parts`**. This is the modern standard for maintaining complex Nix flakes. It allows you to split your flake logic into multiple files without the boilerplate of standard flakes.

**Proposed Structure:**
```
repo/
├── flake.nix (using flake-parts)
├── parts/
│   ├── devshells.nix (dev environments)
│   ├── vms.nix (nixosConfigurations and image generators)
│   └── packages.nix (CLI tools)
```

### 5. `auth-manager` Improvements
The `auth-manager` Go service (`apps/auth-manager`) attempts to create shadow users for Mattermost.

**Code Review of `internal/server/server.go`:**
*   **Circuit Breakers:** You are initializing new circuit breakers in `New()`, which is good. However, in `handleMattermostForwardAuth`, if the breaker is open, you return `503`. Traefik might interpret this as "Auth server down" and block the request entirely.
    *   *Improvement:* Ensure Traefik `forwardAuth` middleware is configured with `failResponseHeaders`.
*   **Cookie Handling:**
    ```go
    // In handleMattermostForwardAuth
    http.SetCookie(w, &http.Cookie{Name: "MMAUTHTOKEN", ...})
    ```
    Mattermost expects the token in the header `Authorization: Bearer <token>` for API calls, or the `MMAUTHTOKEN` cookie for browser access. Ensure your logic handles the `X-Requested-With: XMLHttpRequest` header correctly, as Mattermost's SPA behaves differently than standard browser navigation.

### 6. Secret Management UX
The current workflow requires `rave secrets init` and manual `sops` editing.

**Improvement:**
Implement a **Development Mode Secret Generator**.
In `infra/nixos/modules/foundation/secrets.nix` (create if missing), add logic:

```nix
config.sops.secrets = lib.mkIf config.services.rave.devMode {
  "mattermost/admin-password" = {
    format = "binary";
    sopsFile = pkgs.writeText "dummy" "password123"; # Insecure, dev only
  };
}
```
This allows a developer to run `nix build .#development` without needing to set up GPG/Age keys immediately, lowering the barrier to entry for new contributors.

### Summary of Next Steps

1.  **Immediate Fix:** Create a `infra/nixos/modules/services/authentik.nix` using the native NixOS module system to replace the Docker-based setup.
2.  **Cleanup:** Run the `hygiene-check.sh` and move all `*.qcow2` files to a `.gitignore`d `artifacts/` folder.
3.  **Refactor:** Break `apps/cli/vm_manager.py` into `qemu.py`, `ssh.py`, and `provision.py`.
4.  **Tooling:** Install `just` and create a `Justfile` to replace the `scripts/` directory chaos.
