{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem = { system, lib, pkgs, inputs', config, ... }:
    let
      authOverlay = final: prev:
        let
          mkAuthManager = pkgs: pkgs.buildGoModule {
            pname = "auth-manager";
            version = "0.1.0";
            src = ../src/apps/auth-manager;
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

      libcapOverlay = final: prev: {
        libcap = prev.libcap.override { withGo = false; };
      };

      redisOverlay = final: prev: {
        redis = prev.redis.overrideAttrs (_: { doCheck = false; });
        valkey = prev.valkey.overrideAttrs (_: { doCheck = false; });
      };

      compatOverlay = final: prev: {
        lib = prev.lib // {
          types = prev.lib.types // {
            pathWith = prev.lib.types.pathWith or prev.lib.types.path;
          };
        };
        nodejs_24 = prev.nodejs_24 or prev.nodejs_23 or prev.nodejs_22;
      };

      authentikOverlay = final: prev: (inputs.authentik-nix.overlays.default or (_: _: {})) final prev;

      overlaysList = [ authOverlay goOverlay compatOverlay authentikOverlay libcapOverlay redisOverlay ];

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
              inputs.sops-nix.nixosModules.sops
              inputs.authentik-nix.nixosModules.default
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
            then { customFormats.qcow.imports = [ ../infra/nixos/modules/formats/qcow-large.nix ]; }
            else {};
        in inputs.nixos-generators.nixosGenerate (({
          inherit system format modules;
        }) // formatArgs);

      mkVmVariant = { configModule, extraModules ? [] }:
        let
          systemConfig = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules =
              [
                configModule
                inputs.sops-nix.nixosModules.sops
                inputs.authentik-nix.nixosModules.default
                "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
                ({ ... }: { nixpkgs.overlays = overlaysList; })
              ] ++ extraModules;
          };
        in systemConfig.config.system.build.vm;

      nixosTestsLocal = {
        minimal-vm = import ../tests/minimal-vm.nix {
          inherit pkgs;
          sopsModule = inputs.sops-nix.nixosModules.sops;
          overlays = overlaysList;
        };
        full-stack = import ../tests/full-stack.nix {
          inherit pkgs;
          sopsModule = inputs.sops-nix.nixosModules.sops;
          overlays = overlaysList;
        };
        login-flow = import ../tests/login-flow.nix {
          inherit pkgs;
          sopsModule = inputs.sops-nix.nixosModules.sops;
          overlays = overlaysList;
        };
      };
    in {
      _module.args = {
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = overlaysList;
        };
        overlaysList = overlaysList;
        mkImage = mkImage;
        mkVmVariant = mkVmVariant;
        nixosTestsLocal = nixosTestsLocal;
      };

      checks = {
        minimal-test = nixosTestsLocal.minimal-vm;
        full-stack = nixosTestsLocal.full-stack;
        login-flow = nixosTestsLocal.login-flow;
      };
    };
}
