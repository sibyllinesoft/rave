Of course. This repository shows great progress and contains all the necessary components, but they are tangled together. The key to getting it "ready to go" is to establish a clear, maintainable, and reproducible workflow—a **"Golden Path"**.

My analysis reveals two competing architectures (NixOS vs. Docker Compose), numerous redundant configurations, and a mix of declarative definitions and imperative scripts. Your own `TODO.md` and ADRs correctly identify that the NixOS Flake approach is the future.

This guide will walk you through a decisive refactoring to establish that Golden Path. We will:
1.  **Consolidate NixOS configurations** into a clean, modular structure.
2.  **Eliminate redundant scripts** and create a single, unified way to run VMs.
3.  **Clean up deprecated files** and organize documentation.

When we're done, building and running any VM will be a simple, two-command process based on a single source of truth.

---

### **Pillar 1: Consolidate Your NixOS Configurations**

**The Problem:** You have over a dozen `.nix` configuration files in the root directory (`p0-production.nix`, `gitlab-working-complete.nix`, etc.). This creates massive code duplication and makes maintenance nearly impossible. You've already started the correct modular structure in `nixos/modules/`—we will now complete this transition.

**The Solution:** We will use your existing modules and create clean, top-level configurations that simply import the features they need.

#### **Step 1.1: Create Final VM Configuration Files**

These new files will be very short. They define a complete VM by simply listing the feature modules it should include.

1.  **Create a new `production.nix` configuration file** inside `nixos/configs/`.

    ```bash
    # Make sure you are in the root of the 'rave' repository
    touch nixos/configs/production.nix
    ```

2.  **Copy the following code into `nixos/configs/production.nix`**. This will be your main production-ready VM, including all features from P6.

    ```nix
    # nixos/configs/production.nix
    # P6 production configuration - all services with full security hardening
    { ... }:

    {
      imports = [
        # Foundation modules (required for all VMs)
        ../modules/foundation/base.nix
        ../modules/foundation/nix-config.nix
        ../modules/foundation/networking.nix
        
        # Service modules
        ../modules/services/gitlab/default.nix
        ../modules/services/matrix/default.nix
        ../modules/services/monitoring/default.nix
        
        # Security modules
        ../modules/security/hardening.nix
        ../modules/security/certificates.nix
      ];

      # Production-specific settings
      networking.hostName = "rave-production";
      
      # Certificate configuration for production
      rave.certificates = {
        domain = "rave.local";
        useACME = false; # Set to true when deploying to a real domain
        email = "admin@rave.local";
      };

      # Enable all required services
      services.postgresql.enable = true;
      services.nginx.enable = true;
      services.redis.servers.default.enable = true;

      # Production security overrides
      security.sudo.wheelNeedsPassword = true; # Require password for sudo in production
      services.openssh.settings.PasswordAuthentication = false; # Key-based auth only

      # Production system limits
      systemd.extraConfig = ''
        DefaultLimitNOFILE=65536
        DefaultLimitNPROC=32768
      '';

      # Enhanced logging for production
      services.journald.extraConfig = ''
        Storage=persistent
        Compress=true
        SystemMaxUse=1G
        SystemMaxFileSize=100M
        ForwardToSyslog=true
      '';
    }
    ```

3.  **Create a new `development.nix` configuration file** for local testing.

    ```bash
    touch nixos/configs/development.nix
    ```
4.  **Copy the following code into `nixos/configs/development.nix`**. This defines a lightweight, HTTP-only environment for quick iteration.

    ```nix
    # nixos/configs/development.nix
    # Development configuration - HTTP-only, minimal security for local testing
    { config, pkgs, lib, ... }:

    {
      imports = [
        # Foundation modules (required for all VMs)
        ../modules/foundation/base.nix
        ../modules/foundation/nix-config.nix
        ../modules/foundation/networking.nix
        
        # Service modules (choose which services to enable for development)
        ../modules/services/gitlab/default.nix
        # ../modules/services/matrix/default.nix    # Uncomment if needed for development
        # ../modules/services/monitoring/default.nix # Uncomment if needed for development
        
        # Minimal security (no hardening in development)
        ../modules/security/certificates.nix
      ];

      # Development-specific settings
      networking.hostName = "rave-dev";
      
      # Certificate configuration for development
      rave.certificates = {
        domain = "rave.local";
        useACME = false; # Always use self-signed certs in development
        email = "dev@rave.local";
      };

      # Enable required services for development
      services.postgresql.enable = true;
      services.nginx.enable = true;
      services.redis.servers.default.enable = true;

      # Development overrides for convenience
      security.sudo.wheelNeedsPassword = false; # No password required in development
      services.openssh.settings.PasswordAuthentication = true; # Allow password auth for convenience

      # HTTP-only configuration for development (override HTTPS)
      services.nginx.virtualHosts."rave.local" = {
        forceSSL = lib.mkForce false; # Disable forced SSL redirect
        listen = [
          { addr = "0.0.0.0"; port = 80; }
          { addr = "0.0.0.0"; port = 8080; }
        ];
        
        # Remove SSL certificate configuration for HTTP-only
        sslCertificate = null;
        sslCertificateKey = null;
        useACMEHost = null;
      };
    }
    ```
#### **Step 1.2: Update `flake.nix` to Use New Configurations**

Now, we'll point your build system to these new, clean configurations.

1.  **Open `flake.nix`**.
2.  **Find the `packages.x86_64-linux` section.**
3.  **Replace the entire `packages` section** with this simplified version:

    ```nix
    # --- FILE: flake.nix (updated section) ---
    packages.x86_64-linux = {
      # Production image - Full security hardening and all services
      production = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # Development image - HTTP-only, minimal security for local testing
      development = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/development.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # Demo image - Minimal services for demonstrations
      demo = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/demo.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # Alternative image formats (all use production config)
      virtualbox = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "virtualbox";
        modules = [ ./nixos/configs/production.nix sops-nix.nixosModules.sops ];
      };
      vmware = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "vmware";
        modules = [ ./nixos/configs/production.nix sops-nix.nixosModules.sops ];
      };
      raw = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "raw";
        modules = [ ./nixos/configs/production.nix sops-nix.nixosModules.sops ];
      };
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "iso";
        modules = [ ./nixos/configs/production.nix sops-nix.nixosModules.sops ];
      };
    };

    # Default package (production configuration)
    defaultPackage.x86_64-linux = self.packages.x86_64-linux.production;
    ```
4. Find `defaultPackage.x86_64-linux` at the end of the `outputs` block and ensure it points to the new production package: `self.packages.x86_64-linux.production`.

#### **Step 1.3: Delete Old Configuration Files**

You can now safely delete all the old, monolithic configuration files from the root directory. This is a critical step to enforce the new "Golden Path".

```bash
# 🗑️ Run this command to delete the old files
rm ai-sandbox-config.nix \
   gitlab-autologin.nix \
   gitlab-complete-nixos.nix \
   gitlab-demo-config.nix \
   gitlab-working-complete.nix \
   minimal-nginx-demo.nix \
   nginx-http-fix.nix \
   nginx-https-dev.nix \
   simple-ai-config.nix \
   vibe-kanban.nix \
   vibe-kanban-simple.nix
```

**Pillar 1 Complete!** Your NixOS configurations are now modular, maintainable, and centrally located.

---

### **Pillar 2: Unify Scripts and Remove Redundancy**

**The Problem:** You have multiple `run-*.sh` scripts and test scripts that create confusion. Your `run.sh` script is already excellent and can serve as the single entry point.

**The Solution:** We will make `run.sh` the official way to run VMs and remove the rest. We will also consolidate test scripts into a unified `test/` directory.

#### **Step 2.1: Elevate `run.sh` as the Master Script**

Your `run.sh` is well-written. We just need to ensure it's the *only* way to run VMs. I have updated your `RUN-SCRIPT-DOCUMENTATION.md` to reflect the new, simpler configuration names (`production`, `development`, `demo`).

#### **Step 2.2: Delete Redundant Scripts**

The master `run.sh` script makes these other scripts obsolete.

```bash
# 🗑️ Run this command to delete the old scripts
rm check_nginx.exp \
   demo-redirect-server.py \
   gitlab-redirect-fix.conf \
   install-nix-deps.sh \
   install-nix-single-user.sh \
   install-nix-user.sh \
   nginx-http-only.conf \
   nginx-redirect-fix.conf \
   simple-gitlab-proxy.py \
   test-nginx.conf \
   test-redirect-server.py \
   test-p2-validation.sh \
   test-p3-gitlab.sh \
   test-p4-matrix.sh
```

#### **Step 2.3: Consolidate the `gitlab-complete` Docker setup**

The `gitlab-complete/` directory contains a parallel Docker Compose implementation of GitLab. While useful as a reference, it conflicts with the primary NixOS-based approach.

**Recommendation:** Archive or remove it to avoid confusion. For now, we will leave it, but understand that it is **not** part of the "Golden Path" production system. All GitLab functionality should come from the NixOS module.

**Pillar 2 Complete!** You now have a single, clear command (`./run.sh`) to launch any VM configuration.

---

### **Pillar 3: Final Cleanup and Verification**

#### **Step 3.1: Update `.gitignore`**

Your build process creates `result-*` symlinks and `*.qcow2` images. These should not be committed to Git.

1.  **Open the `.gitignore` file.**
2.  **Add these lines to the end:**

    ```
    *.qcow2
    result
    result-*
    ```

#### **Step 3.2: Consolidate Documentation**

You have several summary markdown files (`GITLAB-COMPLETE-SYSTEM.md`, `DEMO-RESULTS.md`, etc.). This information should be moved into your primary documentation (`README.md`, `docs/ARCHITECTURE.md`, or the ADRs).

1.  **Review** these files and copy any essential, long-term information into your main docs.
2.  **Delete** the summary files once their content is migrated.

    ```bash
    # 🗑️ Delete these after migrating their content
    rm DEMO-RESULTS.md \
       GITLAB-COMPLETE-SYSTEM.md \
       NGINX-REDIRECT-FIX-COMPLETE.md \
       gitlab-status-summary.txt
    ```

### **Final Verification**

You have now completed a major refactoring. To ensure everything is working:

1.  **Check your flake:** This validates the syntax of your new modular structure.
    ```bash
    nix flake check
    ```

2.  **Build your main production VM:**
    ```bash
    nix build .#production
    ```
    *(Note: The first build will take a while as it re-evaluates everything.)*

3.  **Run your new development VM:**
    ```bash
    ./run.sh --config development --mode gui
    ```

You now have a clean, stable, and maintainable repository that fully leverages the power of NixOS. The "Golden Path" is established. Your project is ready to go.