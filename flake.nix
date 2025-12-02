{
  description = "RAVE - Reproducible AI Virtual Environment (flake-parts edition)";

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
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, nixos-generators, sops-nix, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      perSystem = { system, pkgs, lib, config, self', inputs', ... }:
        let
          authOverlay = final: prev:
            let
              mkAuthManager = pkgs: pkgs.buildGoModule {
                pname = "auth-manager";
                version = "0.1.0";
                src = ./apps/auth-manager;
                subPackages = [ "cmd/auth-manager" ];
                vendorHash = "sha256-cRXx1JHc+04bltuMtKhfZy+/Su+oY3UcxhTaapaIJgM=";
              };
            in {
              auth-manager = mkAuthManager prev;
            };

          goOverlay = final: prev:
            let
              unstable = import (builtins.fetchTarball {
                url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
                sha256 = "0z423v1f4pyllhqz68jichams2vrgnmply12lzkvj6k4hijkvnaa";
              }) {
                inherit system;
                config = prev.config;
              };
            in {
              go_1_24 = unstable.go_1_24;
              buildGo124Module = unstable.buildGo124Module;
            };

          overlaysList = [ authOverlay goOverlay ];

          mkImage = { configModule, format ? "qcow", httpsPort ? 8443, extraModules ? [] }:
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
                  "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
                  pomeriumOverrideModule
                  pomeriumDisableModule
                  ({ lib, ... }: {
                    services.rave.ports.https = httpsPort;
                    nixpkgs.overlays = overlaysList;
                    virtualisation.diskSize = lib.mkDefault (40 * 1024);
                    virtualisation.memorySize = lib.mkDefault 16384;
                    virtualisation.useNixStoreImage = false;
                    virtualisation.sharedDirectories = lib.mkForce {};
                    virtualisation.mountHostNixStore = lib.mkForce false;
                    virtualisation.writableStore = lib.mkForce false;
                  })
                ] ++ extraModules;
              formatArgs =
                if format == "qcow"
                then { customFormats.qcow.imports = [ ./infra/nixos/modules/formats/qcow-large.nix ]; }
                else {};
            in nixos-generators.nixosGenerate (({
              inherit system format modules;
            }) // formatArgs);

          mkVmVariant = { configModule, extraModules ? [] }:
            let
              systemConfig = inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules =
                  [
                    configModule
                    sops-nix.nixosModules.sops
                    "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
                    ({ ... }: { nixpkgs.overlays = overlaysList; })
                  ] ++ extraModules;
              };
            in systemConfig.config.system.build.vm;
        in
        let
          nixosTestsLocal = {
            minimal-vm = import ./tests/minimal-vm.nix {
              inherit pkgs;
              sopsModule = sops-nix.nixosModules.sops;
              overlays = overlaysList;
            };
            full-stack = import ./tests/full-stack.nix {
              inherit pkgs;
              sopsModule = sops-nix.nixosModules.sops;
              overlays = overlaysList;
            };
            login-flow = import ./tests/login-flow.nix {
              inherit pkgs;
              sopsModule = sops-nix.nixosModules.sops;
              overlays = overlaysList;
            };
          };
        in {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = overlaysList;
          };

          packages = let
            mkProfileImage = module: mkImage { configModule = module; };
          in {
            production = mkProfileImage ./infra/nixos/configs/production.nix;
            dataPlane = mkProfileImage ./infra/nixos/configs/data-plane.nix;
            appsPlane = mkProfileImage ./infra/nixos/configs/apps-plane.nix;
            development = mkProfileImage ./infra/nixos/configs/development.nix;
            demo = mkProfileImage ./infra/nixos/configs/demo.nix;
            productionWithPort = mkImage { configModule = ./infra/nixos/configs/production.nix; };
            virtualbox = mkImage { configModule = ./infra/nixos/configs/production.nix; format = "virtualbox"; };
            vmware = mkImage { configModule = ./infra/nixos/configs/production.nix; format = "vmware"; };
            raw = mkImage { configModule = ./infra/nixos/configs/production.nix; format = "raw"; };
            iso = mkImage { configModule = ./infra/nixos/configs/production.nix; format = "iso"; };
            default = self'.packages.production;
            vm-production = mkVmVariant { configModule = ./infra/nixos/configs/production.nix; };
            vm-development = mkVmVariant { configModule = ./infra/nixos/configs/development.nix; };
            vm-dataPlane = mkVmVariant { configModule = ./infra/nixos/configs/data-plane.nix; };
            vm-appsPlane = mkVmVariant { configModule = ./infra/nixos/configs/apps-plane.nix; };
            vm-demo = mkVmVariant { configModule = ./infra/nixos/configs/demo.nix; };
            rave-cli = pkgs.writeShellScriptBin "rave" ''
              export PATH="${pkgs.python3.withPackages (ps: [ ps.click ])}/bin:$PATH"
              cd ${./.}
              exec python3 apps/cli/rave "$@"
            '';
            auth-manager = pkgs.auth-manager;
          };

          devShells = {
            default = pkgs.mkShell {
              buildInputs = with pkgs; [
                python3
                python3Packages.click
                qemu
                nix
                go_1_24
              ];
              shellHook = ''
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

          checks = {
            minimal-test = nixosTestsLocal.minimal-vm;
            full-stack = nixosTestsLocal.full-stack;
            login-flow = nixosTestsLocal.login-flow;
          };
        };

      flake = {
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

      };
    };
}
