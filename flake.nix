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
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;
      
      goOverlay =
        final: prev:
          let
            unstable = import (builtins.fetchTarball {
              url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
              sha256 = "1vlmhgh1zdr00afxzsd7kfaynkc9zif0kwmbjmzvb1nqrwj05x3z";
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
        src = ./auth-manager;
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
          modules =
            [
              configModule
              sops-nix.nixosModules.sops
              "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
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
            then { customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ]; }
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
        };
        full-stack = import ./tests/full-stack.nix {
          inherit pkgs;
          sopsModule = sops-nix.nixosModules.sops;
        };
      };

      checks.${system} = {
        minimal-test = self.nixosTests.minimal-vm;
        full-stack = self.nixosTests.full-stack;
      };

    # VM image packages exposed via meaningful profile names
    packages.${system} = rec {
      production = mkImage { configModule = ./nixos/configs/production.nix; };
      development = mkImage { configModule = ./nixos/configs/development.nix; };
      demo = mkImage { configModule = ./nixos/configs/demo.nix; };

      productionWithPort =
        let
          makeOverridableImage = args:
            let
              result = mkImage ({ configModule = ./nixos/configs/production.nix; } // args);
            in
              result // {
                override = moreArgs: makeOverridableImage (args // moreArgs);
              };
        in
          makeOverridableImage {};

      virtualbox = mkImage {
        configModule = ./nixos/configs/production.nix;
        format = "virtualbox";
      };
      vmware = mkImage {
        configModule = ./nixos/configs/production.nix;
        format = "vmware";
      };
      raw = mkImage {
        configModule = ./nixos/configs/production.nix;
        format = "raw";
      };
      iso = mkImage {
        configModule = ./nixos/configs/production.nix;
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
        exec python3 cli/rave "$@"
      '';

      auth-manager = mkAuthManager pkgs;
    };

    profileMetadata = {
      production = {
        attr = "production";
        description = "Full stack (GitLab, Mattermost, Penpot, Outline, n8n, observability)";
        defaultImage = "rave-production-localhost.qcow2";
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
        defaultImage = "rave-development-localhost.qcow2";
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
        defaultImage = "rave-demo-localhost.qcow2";
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
      ];
      
      shellHook = ''
        export PATH="$PATH:$(pwd)/cli"
        echo "🚀 RAVE Development Environment"
        echo "CLI available at: $(pwd)/cli/rave"
      '';
    };
  };
}
