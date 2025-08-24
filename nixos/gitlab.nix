# GitLab Service Configuration for RAVE
# Minimal GitLab CE configuration for development
{ config, pkgs, lib, ... }:

{
  # P3.1: Minimal GitLab CE service configuration
  services.gitlab = {
    enable = true;
    host = "rave.local";
    
    # Create dummy secret files for demo
    initialRootPasswordFile = pkgs.writeText "gitlab-root-password" "changeme123!";
    secrets = {
      secretFile = pkgs.writeText "gitlab-secret" "dummy-secret-key-base";
      dbFile = pkgs.writeText "gitlab-db-secret" "dummy-db-secret-key";
      otpFile = pkgs.writeText "gitlab-otp-secret" "dummy-otp-secret-key";
      jwsFile = pkgs.writeText "gitlab-jws-secret" "dummy-jws-private-key";
    };
  };
  
  # P3.2: Enable PostgreSQL for GitLab database
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql;
    ensureDatabases = [ "gitlab" ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
      }
    ];
  };
  
  # P3.3: GitLab Runner service for CI/CD
  services.gitlab-runner = {
    enable = true;
    settings = {
      concurrent = 2;
      check_interval = 10;
    };
    
    # Basic Docker executor service - detailed config will be done post-deployment
    services.default-docker = {
      executor = "docker";
      dockerImage = "nixos/nix:latest";  # Use NixOS image for builds
      registrationConfigFile = pkgs.writeText "gitlab-runner-config" ''
        registration_token = "dummy-token"
        url = "http://rave.local"
      '';
    };
  };
  
  # P3.4: Additional system packages for GitLab and runner
  environment.systemPackages = with pkgs; [
    git
    git-lfs
    docker
    docker-compose
  ];
  
  # P3.5: Enable Docker service for GitLab Runner
  virtualisation.docker.enable = true;
  
  # P3.6: Enable KVM for nested virtualization in runners
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.package = pkgs.qemu_kvm;
  
  # Configure gitlab-runner user properly
  users.users.gitlab-runner = {
    isSystemUser = true;
    group = "gitlab-runner";
    extraGroups = [ "docker" "kvm" "libvirtd" ];
  };
  
  users.groups.gitlab-runner = {};
  
  # P3.7: Firewall configuration for GitLab
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  
  # P3.8: Basic nginx configuration for reverse proxy (if needed)
  services.nginx.enable = lib.mkDefault false;  # Can be enabled in higher-level configs
}