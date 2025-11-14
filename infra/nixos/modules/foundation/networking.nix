# nixos/modules/foundation/networking.nix
# Basic network setup and firewall configuration
{ config, pkgs, lib, ... }:

{
  # Network configuration
  networking.hostName = lib.mkDefault "rave-vm"; # Default hostname (can be overridden)
  networking.networkmanager.enable = true;

  # Firewall configuration - secure by default but allow common services
  networking.firewall = {
    enable = true;
    
    # Allow SSH and common HTTP/HTTPS ports
    allowedTCPPorts = [ 22 80 443 ];
    
    # Allow STUN/TURN server for WebRTC calls
    allowedUDPPorts = [ 3478 ]; # STUN/TURN port
    allowedUDPPortRanges = [
      { from = 49152; to = 65535; } # RTC media ports for coturn
    ];
    
    # Allow specific services (these will be opened by service modules as needed)
    # GitLab: 8080, Matrix: 8008, Monitoring: 3000, 9090
    # Coturn: 3478 (UDP), 49152-65535 (UDP RTC)
  };

  # SSH configuration for secure remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = lib.mkDefault true; # Set to false in production
      X11Forwarding = false;
    };
  };

  # Enable mDNS for .local domain resolution
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };
}