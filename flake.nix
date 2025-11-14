{
  description = "RAVE - Reproducible AI Virtual Environment";

  # P0.3: SAFE mode memory-disciplined build configuration (SAFE=1 defaults)
  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    # SAFE mode defaults: max-jobs=1, cores=2 for memory discipline
    max-jobs = 1;
    cores = 2;
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = true;
    extra-substituters = "https://nix-community.cachix.org";
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators/1.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ authOverlay goOverlay ];
      };
      lib = nixpkgs.lib;
      
      goOverlay =
        final: prev:
          let
            unstable = import (builtins.fetchTarball {
              url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
              sha256 = "04h7cq8rp8815xb4zglkah4w6p2r5lqp7xanv89yxzbmnv29np2a";
            }) {
              inherit system;
              config = prev.config;
            };
          in {
            go_1_24 = unstable.go_1_24;
            buildGo124Module = unstable.buildGo124Module;
          };

      mkAuthManager = pkgs: pkgs.buildGoModule {
        pname = "auth-manager";
        version = "0.1.0";
        src = ./apps/auth-manager;
        subPackages = [ "cmd/auth-manager" ];
        vendorHash = "sha256-xj6jSxUiSAYNbIITOY50KoCyGcABvWSCFhXA9ytrX3M=";
      };

      authOverlay = final: prev: {
        auth-manager = mkAuthManager prev;
      };

      mkImage =
        { configModule
        , format ? "qcow"
        , httpsPort ? 8443
        , extraModules ? []
        }:
        let
          pomeriumConfigEnv = builtins.getEnv "RAVE_POMERIUM_CONFIG_JSON";
          pomeriumOverrideModule =
            if pomeriumConfigEnv == "" then ({ ... }: {})
            else
              let
                parsed = builtins.fromJSON pomeriumConfigEnv;
                get = name: if builtins.hasAttr name parsed then parsed.${name} else null;
                idpAttrs = lib.filterAttrs (_: v: v != null) {
                  provider = get "provider";
                  providerUrl = get "providerUrl";
                  clientId = get "clientId";
                  clientSecret = get "clientSecret";
                  clientSecretFile = get "clientSecretFile";
                  scopes = get "scopes";
                };
              in
              ({ config, ... }: {
                services.rave.pomerium.idp =
                  (config.services.rave.pomerium.idp or {}) // idpAttrs;
              });
          pomeriumDisableEnv = builtins.getEnv "RAVE_DISABLE_POMERIUM";
          pomeriumDisableModule =
            if pomeriumDisableEnv == "" then ({ ... }: {})
            else ({ lib, ... }: {
              services.rave.pomerium.enable = lib.mkForce false;
            });
          modules =
            [
              configModule
              sops-nix.nixosModules.sops
              "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
              pomeriumOverrideModule
              pomeriumDisableModule
              ({ lib, ... }: {
                services.rave.ports.https = httpsPort;
                nixpkgs.overlays = [ authOverlay goOverlay ];
                virtualisation.diskSize = lib.mkDefault (40 * 1024);
                virtualisation.memorySize = lib.mkDefault 16384;
                virtualisation.useNixStoreImage = false;
                virtualisation.sharedDirectories = lib.mkForce {};
                virtualisation.mountHostNixStore = lib.mkForce false;
                virtualisation.writableStore = lib.mkForce false;
              })
            ]
            ++ extraModules;

          formatArgs =
            if format == "qcow"
            then { customFormats.qcow.imports = [ ./infra/nixos/modules/formats/qcow-large.nix ]; }
            else {};
        in
          nixos-generators.nixosGenerate ({
            inherit system format modules;
          } // formatArgs);
    in {
      nixosTests = {
        minimal-vm = import ./tests/minimal-vm.nix {
          inherit pkgs;
          sopsModule = sops-nix.nixosModules.sops;
          overlays = [ authOverlay goOverlay ];
        };
        full-stack = import ./tests/full-stack.nix {
          inherit pkgs;
          sopsModule = sops-nix.nixosModules.sops;
          overlays = [ authOverlay goOverlay ];
        };
      };

      checks.${system} = {
        minimal-test = self.nixosTests.minimal-vm;
        full-stack = self.nixosTests.full-stack;
      };

    # VM image packages exposed via meaningful profile names
    packages.${system} = rec {
      production = mkImage { configModule = ./infra/nixos/configs/production.nix; };
      dataPlane = mkImage { configModule = ./infra/nixos/configs/data-plane.nix; };
      appsPlane = mkImage { configModule = ./infra/nixos/configs/apps-plane.nix; };
      development = mkImage { configModule = ./infra/nixos/configs/development.nix; };
      demo = mkImage { configModule = ./infra/nixos/configs/demo.nix; };

      productionWithPort =
        let
          makeOverridableImage = args:
            let
              result = mkImage ({ configModule = ./infra/nixos/configs/production.nix; } // args);
            in
              result // {
                override = moreArgs: makeOverridableImage (args // moreArgs);
              };
        in
          makeOverridableImage {};

      virtualbox = mkImage {
        configModule = ./infra/nixos/configs/production.nix;
        format = "virtualbox";
      };
      vmware = mkImage {
        configModule = ./infra/nixos/configs/production.nix;
        format = "vmware";
      };
      raw = mkImage {
        configModule = ./infra/nixos/configs/production.nix;
        format = "raw";
      };
      iso = mkImage {
        configModule = ./infra/nixos/configs/production.nix;
        format = "iso";
      };

      default = production;

      # Legacy aliases (to be removed once CLI migrates)
      rave-qcow2 = production;
      rave-qcow2-dev = development;
      rave-qcow2-custom-port = productionWithPort;

      # RAVE CLI - Main management interface
      rave-cli = pkgs.writeShellScriptBin "rave" ''
        export PATH="${pkgs.python3.withPackages (ps: [ ps.click ])}/bin:$PATH"
        cd ${./.}
        exec python3 apps/cli/rave "$@"
      '';

      auth-manager = mkAuthManager pkgs;
    };

    profileMetadata = {
      production = {
        attr = "production";
        description = "Full stack (GitLab, Mattermost, Penpot, Outline, n8n, observability)";
        defaultImage = "artifacts/qcow/production/rave-production-localhost.qcow2";
        features = {
          penpot = true;
          outline = true;
          n8n = true;
          monitoring = true;
        };
      };
      dataPlane = {
        attr = "dataPlane";
        description = "Data plane only (PostgreSQL + Redis, SSH, SOPS secrets)";
        defaultImage = "artifacts/qcow/data-plane/rave-data-plane.qcow2";
        features = {
          penpot = false;
          outline = false;
          n8n = false;
          monitoring = false;
        };
      };
      appsPlane = {
        attr = "appsPlane";
        description = "Application plane (GitLab/Mattermost/etc.) targeting external data services";
        defaultImage = "artifacts/qcow/apps-plane/rave-apps-plane.qcow2";
        features = {
          penpot = true;
          outline = true;
          n8n = true;
          monitoring = true;
        };
      };
      development = {
        attr = "development";
        description = "Slimmer build (Penpot/Outline/n8n disabled, lower RAM/disk)";
        defaultImage = "artifacts/qcow/development/rave-development-localhost.qcow2";
        features = {
          penpot = false;
          outline = false;
          n8n = false;
          monitoring = true;
        };
      };
      demo = {
        attr = "demo";
        description = "Demo-friendly stack (observability + optional apps disabled)";
        defaultImage = "artifacts/qcow/demo/rave-demo-localhost.qcow2";
        features = {
          penpot = false;
          outline = false;
          n8n = false;
          monitoring = false;
        };
      };
    };
    
    # Development shell with CLI
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        python3
        python3Packages.click
        qemu
        nix
        go_1_24
      ];

      shellHook = ''
        # Ensure local GOPATH/GOROOT don't point at stale system installs
        unset GOROOT
        if [ -z "''${GOPATH:-}" ] || [ "''${GOPATH}" = "$HOME/go" ]; then
          export GOPATH="$(pwd)/.gopath"
        fi
        mkdir -p "$GOPATH"

        export PATH="$PATH:$(pwd)/apps/cli"
        echo "🚀 RAVE Development Environment"
        echo "CLI available at: $(pwd)/apps/cli/rave"
        go version 2>/dev/null || true
      '';
    };
  };
}
