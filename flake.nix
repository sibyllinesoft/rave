{
  description = "RAVE - Reproducible AI Virtual Environment";

  # Memory-disciplined build configuration
  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    max-jobs = 2;
    cores = 4;
    experimental-features = [ "nix-command" "flakes" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }: {
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

    # Default package (P0 production-ready)
    defaultPackage.x86_64-linux = self.packages.x86_64-linux.p0-production;
  };
}