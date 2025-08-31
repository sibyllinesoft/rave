# nixos/modules/foundation/base.nix
# This is the foundation for ALL RAVE VMs - contains common settings that every VM needs.
{ config, pkgs, lib, ... }:

{
  # Allow unfree packages like steam-run
  nixpkgs.config.allowUnfree = true;

  # Basic system settings
  system.stateVersion = "24.11";
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Bootloader configuration for QEMU VMs (can be overridden by specific formats)
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
  boot.loader.timeout = lib.mkForce 3;

  # User configuration: the 'agent' user
  users.users.agent = {
    isNormalUser = true;
    description = "RAVE AI Agent";
    extraGroups = [ "wheel" ]; # For sudo access
    password = "agent"; # A simple default for development
  };
  security.sudo.wheelNeedsPassword = lib.mkDefault false; # For convenience in development (can be overridden)

  # Core system packages available in every VM
  environment.systemPackages = with pkgs; [
    # Dev tools
    git
    vim
    htop
    curl
    wget
    jq
    
    # Runtimes
    nodejs_20
    python3
    
    # For binary compatibility
    steam-run
  ];
}