# nixos/modules/foundation/nix-config.nix
# Nix configuration settings and optimizations
{ config, pkgs, lib, ... }:

{
  # Nix settings for better performance and functionality
  nix.settings = {
    # Enable flakes and new command-line interface
    experimental-features = [ "nix-command" "flakes" ];
    
    # Performance optimizations
    max-jobs = "auto";
    cores = 0; # Use all available cores
    
    # Disk space management
    auto-optimise-store = true;
    
    # Trusted users for remote builds
    trusted-users = [ "root" "agent" "@wheel" ];
  };

  # Garbage collection configuration
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # Enable distributed builds (useful for CI/CD)
  nix.distributedBuilds = true;
}
