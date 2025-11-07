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
      
      # Build-time port configuration (can be overridden)
      makeVmModules = { httpsPort ? 8443, configModule ? ./nixos/configs/complete-production.nix }: [
        configModule
        sops-nix.nixosModules.sops
        "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        ({ lib, ... }: {
          # Pass port configuration to the NixOS module
          services.rave.ports.https = httpsPort;
          nixpkgs.overlays = [
            (final: prev:
              let
                unstable = import (builtins.fetchTarball {
                  url = "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
                  sha256 = "1vlmhgh1zdr00afxzsd7kfaynkc9zif0kwmbjmzvb1nqrwj05x3z";
                }) {
                  system = prev.system;
                  config = prev.config;
                };
              in {
                go_1_24 = unstable.go_1_24;
                buildGo124Module = unstable.buildGo124Module;
              }
            )
          ];

          virtualisation.diskSize = lib.mkDefault (40 * 1024); # 40GB default
          virtualisation.memorySize = lib.mkDefault 12288; # 12GB default
          virtualisation.useNixStoreImage = false;
          virtualisation.sharedDirectories = lib.mkForce {};
          virtualisation.mountHostNixStore = lib.mkForce false;
          virtualisation.writableStore = lib.mkForce false;
        })
      ];
      
      vmModules = makeVmModules {}; # Default port 8443
      devVmModules = makeVmModules { configModule = ./nixos/configs/dev-minimal.nix; };
    in {
    # P2.2: NixOS VM test infrastructure
    tests.x86_64-linux = {
        rave-vm = import ./tests/rave-vm.nix { pkgs = nixpkgs.legacyPackages.x86_64-linux; };
    };

    # VM image packages - Production only
    packages.${system} = rec {
      # Complete production image - ALL services pre-configured and ready (default port 8443)
      rave-qcow2 = nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow";
        customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ];
        modules = vmModules;
      };

      # Custom port build function - usage: nix build --override-input httpsPort 9443
      rave-qcow2-custom-port = httpsPort: nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow";
        customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ];
        modules = makeVmModules { inherit httpsPort; };
      };

      # Common port variants
      rave-qcow2-port-7443 = nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow";
        customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ];
        modules = makeVmModules { httpsPort = 7443; };
      };

      rave-qcow2-port-9443 = nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow";
        customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ];
        modules = makeVmModules { httpsPort = 9443; };
      };

      # Lightweight dev image (Outline/n8n disabled, reduced resources)
      rave-qcow2-dev = nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow";
        customFormats.qcow.imports = [ ./nixos/modules/formats/qcow-large.nix ];
        modules = devVmModules;
      };

      default = rave-qcow2;

      # RAVE CLI - Main management interface
      rave-cli = nixpkgs.legacyPackages.${system}.writeShellScriptBin "rave" ''
        export PATH="${nixpkgs.legacyPackages.${system}.python3.withPackages (ps: [ ps.click ])}/bin:$PATH"
        cd ${./.}
        exec python3 cli/rave "$@"
      '';
    };
    
    # Development shell with CLI
    devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
      buildInputs = with nixpkgs.legacyPackages.${system}; [
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
