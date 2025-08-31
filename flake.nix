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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, sops-nix, ... }: {
    # P2.2: NixOS VM test infrastructure
    tests.x86_64-linux = {
      rave-vm = import ./tests/rave-vm.nix { pkgs = nixpkgs.legacyPackages.x86_64-linux; };
    };

    # VM image packages - Streamlined build targets
    packages.x86_64-linux = {
      # === PRIMARY BUILD TARGET ===
      # Complete production image - ALL services pre-configured and ready
      default = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/complete-production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # === STRIPPED-DOWN OPTIONS (when needed) ===
      
      # Minimal development - Just nginx, SSH, basic services
      minimal = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/demo.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # Monitoring-only - Just observability stack (Grafana, Prometheus)
      monitoring = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/monitoring-only.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # === LEGACY COMPATIBILITY (deprecated) ===
      complete = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./nixos/configs/complete-production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # RAVE CLI - Main management interface
      rave-cli = nixpkgs.legacyPackages.x86_64-linux.writeShellScriptBin "rave" ''
        export PATH="${nixpkgs.legacyPackages.x86_64-linux.python3.withPackages (ps: [ ps.click ])}/bin:$PATH"
        cd ${./.}
        exec python3 cli/rave "$@"
      '';
    };
    
    # Development shell with CLI
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
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