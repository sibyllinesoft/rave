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

    # VM image packages
    packages.x86_64-linux = {
      # QEMU qcow2 image (development)
      qemu = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./simple-ai-config.nix ];
      };
      
      # P0 Production-ready image with TLS/OIDC
      p0-production = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./p0-production-config.nix ];
      };
      
      # P1 Security Hardened Production image
      p1-production = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./p1-production-config.nix ];
      };
      
      # P2 Observability-Enhanced Production image
      p2-production = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./p2-production-config.nix ];
      };
      
      # P6 Sandbox-on-PR Production image
      p6-production = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./p6-production-config.nix 
          sops-nix.nixosModules.sops
        ];
      };
      
      # P6 Demo image (HTTP-only for quick demo)
      p6-demo = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./p6-demo-config.nix 
          sops-nix.nixosModules.sops
        ];
      };
      
      # RAVE Demo Ready (HTTP-only GitLab with fixed nginx)
      rave-demo-ready = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./p6-http-demo.nix 
          sops-nix.nixosModules.sops
        ];
      };
      
      # RAVE Development HTTPS (Self-signed certificates for local dev)
      rave-dev-https = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ 
          ./p0-dev-https-config.nix 
          sops-nix.nixosModules.sops
        ];
      };
      
      # RAVE HTTPS Demo (Simplified for demonstration)
      rave-https-demo = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./demo-https-config.nix ];
      };
      
      # VirtualBox OVA image  
      virtualbox = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "virtualbox";
        modules = [ ./ai-sandbox-config.nix ];
      };
      
      # VMware image
      vmware = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "vmware";
        modules = [ ./ai-sandbox-config.nix ];
      };
      
      # Raw disk image
      raw = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "raw";
        modules = [ ./ai-sandbox-config.nix ];
      };
      
      # ISO image for installation
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "iso";
        modules = [ ./ai-sandbox-config.nix ];
      };
    };

    # Default package (P6 sandbox-on-PR production)
    defaultPackage.x86_64-linux = self.packages.x86_64-linux.p6-production;
  };
}