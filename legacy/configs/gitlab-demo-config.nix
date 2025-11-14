# Simple GitLab Demo Configuration for RAVE
{ config, pkgs, lib, ... }:

{
  # Basic system configuration
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;
  
  # Network configuration
  networking = {
    hostName = "rave-gitlab";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 3000 3001 3002 8080 ];
    };
  };

  # User configuration  
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    password = "agent"; # Simple password for demo
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  # PostgreSQL database for GitLab
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    authentication = lib.mkOverride 10 ''
      local all all              trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';
    initialScript = pkgs.writeText "postgresql-init.sql" ''
      CREATE USER gitlab WITH PASSWORD 'gitlab';
      CREATE DATABASE gitlab OWNER gitlab;
      ALTER USER gitlab CREATEDB;
    '';
  };

  # Redis for GitLab
  services.redis.servers.gitlab = {
    enable = true;
    port = 6379;
  };

  # GitLab CE
  services.gitlab = {
    enable = true;
    databasePasswordFile = pkgs.writeText "dbPassword" "gitlab";
    initialRootPasswordFile = pkgs.writeText "rootPassword" "rave-admin";
    host = "localhost";
    port = 3001;
    https = false;
    
    # GitLab configuration
    extraConfig = {
      gitlab = {
        email_from = "gitlab@rave.local";
        email_display_name = "RAVE GitLab";
        default_projects_limit = 100;
      };
    };

    # Runner configuration
    runner = {
      enable = true;
      services = {
        default = {
          # Runner configuration
          dockerImage = "infra/nixos/nix";
          registrationConfigFile = pkgs.writeText "runner-config" ''
            CI_SERVER_URL=http://localhost:3001
            REGISTRATION_TOKEN=rave-runner-token
          '';
        };
      };
    };
  };

  # Nginx reverse proxy
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      "localhost" = {
        locations = {
          "/gitlab/" = {
            proxyPass = "http://127.0.0.1:3001/";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };
      };
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    git
    curl
    htop
    vim
    docker
    docker-compose
  ];

  # Docker for GitLab runner
  virtualisation.docker.enable = true;

  # System version
  system.stateVersion = "24.11";
}