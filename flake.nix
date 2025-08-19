{
  description = "AI Agent Sandbox VM Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }: {
    # VM image packages
    packages.x86_64-linux = {
      # QEMU qcow2 image
      qemu = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow";
        modules = [ ./ai-sandbox-config.nix ];
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

    # Default package
    defaultPackage.x86_64-linux = self.packages.x86_64-linux.qemu;
  };
}