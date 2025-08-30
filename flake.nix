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

    # VM image packages - Clean modular structure
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
      # VirtualBox OVA image  
      virtualbox = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "virtualbox";
        modules = [ 
          ./nixos/configs/production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # VMware image
      vmware = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "vmware";
        modules = [ 
          ./nixos/configs/production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # Raw disk image
      raw = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "raw";
        modules = [ 
          ./nixos/configs/production.nix
          sops-nix.nixosModules.sops
        ];
      };
      
      # ISO image for installation
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "iso";
        modules = [ 
          ./nixos/configs/production.nix
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

    # Default package (production configuration)
    defaultPackage.x86_64-linux = self.packages.x86_64-linux.production;
    
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