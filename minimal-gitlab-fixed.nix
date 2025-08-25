# Minimal GitLab Configuration with nginx Redirect Fix
{ config, pkgs, lib, ... }:

{
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  # Memory-disciplined build settings
  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 1;
    cores = 2;
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    sandbox = true;
    extra-substituters = [ "https://nix-community.cachix.org" ];
  };

  # Boot configuration for VM
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
  boot.kernelParams = lib.mkDefault [ "console=ttyS0,115200n8" "console=tty0" ];
  boot.loader.timeout = lib.mkDefault 3;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim wget curl git htop tree jq
  ];

  # nginx with proper redirect fix
  services.nginx = {
    enable = true;
    package = pkgs.nginx;
    
    appendConfig = ''
      worker_processes auto;
      worker_connections 1024;
      keepalive_timeout 65;
      gzip on;
    '';

    virtualHosts.localhost = {
      listen = [
        { addr = "0.0.0.0"; port = 8080; ssl = false; }
        { addr = "0.0.0.0"; port = 8081; ssl = false; }
      ];

      locations = {
        # Health check
        "/health" = {
          return = "200 'RAVE GitLab Ready - Redirect Fix Applied!'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
        
        # GitLab main application with REDIRECT FIX
        "/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
          extraConfig = ''
            # CRITICAL FIX: Include port in Host header for correct redirects
            proxy_set_header Host $host:$server_port;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Port $server_port;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_http_version 1.1;
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            client_max_body_size 1024m;
          '';
        };
      };
    };
  };

  # Ensure nginx user exists
  users.users.nginx = {
    isSystemUser = true;
    group = "nginx"; 
  };
  users.groups.nginx = {};

  # GitLab CE Configuration - Simplified 
  services.gitlab = {
    enable = true;
    host = "localhost";
    port = 80;  # Internal port, nginx handles external access
    https = false;
    
    initialRootPasswordFile = pkgs.writeText "gitlab-root-password" "rave-demo-password";
    
    secrets = {
      secretFile = pkgs.writeText "gitlab-secret" "rave-demo-secret-key";
      otpFile = pkgs.writeText "gitlab-otp" "rave-demo-otp-key";
      dbFile = pkgs.writeText "gitlab-db" "rave-demo-db-key";
      jwsFile = pkgs.writeText "gitlab-jws" "rave-demo-jws-key";
      activeRecordPrimaryKeyFile = pkgs.writeText "gitlab-ar-primary" "rave-demo-ar-primary-key";
      activeRecordDeterministicKeyFile = pkgs.writeText "gitlab-ar-deterministic" "rave-demo-ar-deterministic-key";
      activeRecordSaltFile = pkgs.writeText "gitlab-ar-salt" "rave-demo-ar-salt";
    };
    
    databasePasswordFile = pkgs.writeText "gitlab-db-password" "rave-demo-db-password";
    
    extraConfig = {
      gitlab = {
        email_enabled = false;
        default_projects_features = {
          issues = true;
          merge_requests = true;
          wiki = true;
          snippets = true;
        };
      };
      
      # CRITICAL: This must match what users see externally
      external_url = "http://localhost:8080";
      
      nginx = {
        enable = false;  # Use system nginx instead
      };
    };
  };

  # PostgreSQL for GitLab
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    ensureDatabases = [ "gitlab" ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
      }
    ];
  };

  # Redis for GitLab
  services.redis.servers.gitlab = {
    enable = true;
    user = "gitlab";
  };

  # SSH access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Networking
  networking.firewall.allowedTCPPorts = [ 8080 8081 2222 ];
  networking.hostName = "rave-gitlab-fixed";

  # MOTD showing the fix
  environment.etc."motd".text = lib.mkForce ''
    
    🚀 RAVE GitLab with nginx Redirect Fix
    =====================================
    
    🌐 GitLab: http://localhost:8080
    📍 Health: http://localhost:8080/health
    
    ✅ REDIRECT FIX APPLIED:
    • Password reset: http://localhost:8080/users/sign_in
    • Form submissions: http://localhost:8080/[correct-path]
    • All URLs include port :8080
    
    🎯 Login: root / rave-demo-password
    
    🔧 nginx headers fixed:
    • Host: $host:$server_port (includes port)
    • X-Forwarded-Port: $server_port
    
  '';
}