# RAVE NixOS Configuration Entry Point
# This is the main configuration file that imports all service modules
{ config, pkgs, lib, ... }:

{
  # Import production configuration phases
  imports = [
    # Use P4 configuration which inherits from P3, P2, and P1
    ../p4-production-config.nix
    
    # Phase P5: Matrix Bridge and Agent services
    ./agents.nix
    
    # Modular service configurations:
    # ./matrix.nix is imported by P4
    # ./gitlab.nix is inherited from P3
    # ./prometheus.nix and ./grafana.nix are inherited from P2
  ];
  
  # System configuration
  system.stateVersion = "24.11";
  
  # Boot configuration for VM
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  
  # File systems
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };
  
  # Network configuration
  networking = {
    hostName = "rave-nixos";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 3002 80 443 ];
    };
  };
}