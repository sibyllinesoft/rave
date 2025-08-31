# nixos/modules/services/penpot/default.nix
# Penpot design service configuration module
{ config, pkgs, lib, ... }:

with lib;

{
  imports = [
    ./nginx.nix
  ];

  options = {
    services.rave.penpot = {
      enable = mkEnableOption "Penpot design tool with PostgreSQL and Redis backends";
      
      host = mkOption {
        type = types.str;
        default = "rave.local";
        description = "Penpot hostname";
      };
      
      useSecrets = mkOption {
        type = types.bool;
        default = true;
        description = "Use sops-nix secrets instead of plain text (disable for development)";
      };
      
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable OIDC integration with GitLab";
        };
        
        gitlabUrl = mkOption {
          type = types.str;
          default = "https://rave.local/gitlab";
          description = "GitLab base URL for OIDC";
        };
        
        clientId = mkOption {
          type = types.str;
          default = "penpot";
          description = "GitLab OAuth application client ID";
        };
      };
      
      database = {
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "PostgreSQL database host";
        };
        
        port = mkOption {
          type = types.int;
          default = 5432;
          description = "PostgreSQL database port";
        };
        
        name = mkOption {
          type = types.str;
          default = "penpot";
          description = "PostgreSQL database name";
        };
        
        username = mkOption {
          type = types.str;
          default = "penpot";
          description = "PostgreSQL database username";
        };
      };
      
      redis = {
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Redis host";
        };
        
        port = mkOption {
          type = types.int;
          default = 6380;
          description = "Redis port for Penpot";
        };
      };
    };
  };
  
  config = mkIf config.services.rave.penpot.enable {
    # Penpot services using separate systemd services for each component
    systemd.services.penpot-backend = {
      description = "Penpot Backend Service";
      after = [ "docker.service" "postgresql.service" "redis.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        PENPOT_FLAGS = "enable-registration enable-login-with-oidc disable-email-verification enable-smtp enable-prepl-server";
        PENPOT_PUBLIC_URI = "https://${config.services.rave.penpot.host}/penpot/";
        PENPOT_DATABASE_URI = "postgresql://${config.services.rave.penpot.database.username}:${if config.services.rave.penpot.useSecrets then "$(cat ${config.sops.secrets."penpot/db-password".path or "/run/secrets/penpot-db-password"})" else "penpotdbpass"}@${config.services.rave.penpot.database.host}:${toString config.services.rave.penpot.database.port}/${config.services.rave.penpot.database.name}";
        PENPOT_REDIS_URI = "redis://${config.services.rave.penpot.redis.host}:${toString config.services.rave.penpot.redis.port}/0";
        PENPOT_ASSETS_STORAGE_BACKEND = "assets-fs";
        PENPOT_STORAGE_ASSETS_FS_DIRECTORY = "/opt/data/assets";
        PENPOT_TELEMETRY_ENABLED = "false";
        PENPOT_SMTP_DEFAULT_FROM = "noreply@${config.services.rave.penpot.host}";
        PENPOT_SMTP_DEFAULT_REPLY_TO = "noreply@${config.services.rave.penpot.host}";
        PENPOT_SMTP_HOST = "localhost";
        PENPOT_SMTP_PORT = "1025";
        PENPOT_SMTP_TLS = "false";
        PENPOT_SMTP_SSL = "false";
      } // optionalAttrs config.services.rave.penpot.oidc.enable {
        PENPOT_OIDC_CLIENT_ID = config.services.rave.penpot.oidc.clientId;
        PENPOT_OIDC_CLIENT_SECRET = if config.services.rave.penpot.useSecrets then "$(cat ${config.sops.secrets."oidc/penpot-client-secret".path or "/run/secrets/penpot-oidc-secret"})" else "development-penpot-oidc-secret";
        PENPOT_OIDC_BASE_URI = config.services.rave.penpot.oidc.gitlabUrl;
        PENPOT_OIDC_CLIENT_NAME = "GitLab";
        PENPOT_OIDC_AUTH_URI = "${config.services.rave.penpot.oidc.gitlabUrl}/oauth/authorize";
        PENPOT_OIDC_TOKEN_URI = "${config.services.rave.penpot.oidc.gitlabUrl}/oauth/token";
        PENPOT_OIDC_USER_URI = "${config.services.rave.penpot.oidc.gitlabUrl}/api/v4/user";
        PENPOT_OIDC_SCOPES = "openid profile email";
        PENPOT_OIDC_NAME_ATTR = "name";
        PENPOT_OIDC_EMAIL_ATTR = "email";
      };
      
      serviceConfig = {
        Type = "exec";
        ExecStartPre = [
          "${pkgs.docker}/bin/docker network create penpot-network --driver bridge || true"
          "${pkgs.docker}/bin/docker volume create penpot-assets || true"
          "${pkgs.docker}/bin/docker pull penpotapp/backend:latest"
        ];
        ExecStart = pkgs.writeShellScript "penpot-backend-start" ''
          ${pkgs.docker}/bin/docker run --rm --name penpot-backend --network penpot-network -p 6060:6060 -v penpot-assets:/opt/data/assets \
            -e PENPOT_FLAGS \
            -e PENPOT_PUBLIC_URI \
            -e PENPOT_DATABASE_URI \
            -e PENPOT_REDIS_URI \
            -e PENPOT_ASSETS_STORAGE_BACKEND \
            -e PENPOT_STORAGE_ASSETS_FS_DIRECTORY \
            -e PENPOT_TELEMETRY_ENABLED \
            -e PENPOT_SMTP_DEFAULT_FROM \
            -e PENPOT_SMTP_DEFAULT_REPLY_TO \
            -e PENPOT_SMTP_HOST \
            -e PENPOT_SMTP_PORT \
            -e PENPOT_SMTP_TLS \
            -e PENPOT_SMTP_SSL \
            ${optionalString config.services.rave.penpot.oidc.enable "-e PENPOT_OIDC_CLIENT_ID -e PENPOT_OIDC_CLIENT_SECRET -e PENPOT_OIDC_BASE_URI -e PENPOT_OIDC_CLIENT_NAME -e PENPOT_OIDC_AUTH_URI -e PENPOT_OIDC_TOKEN_URI -e PENPOT_OIDC_USER_URI -e PENPOT_OIDC_SCOPES -e PENPOT_OIDC_NAME_ATTR -e PENPOT_OIDC_EMAIL_ATTR"} \
            penpotapp/backend:latest
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-backend";
        ExecStopPost = "${pkgs.docker}/bin/docker rm penpot-backend || true";
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.services.penpot-frontend = {
      description = "Penpot Frontend Service";
      after = [ "docker.service" "penpot-backend.service" ];
      wants = [ "penpot-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "exec";
        ExecStartPre = "${pkgs.docker}/bin/docker pull penpotapp/frontend:latest";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name penpot-frontend --network penpot-network -p 3449:80 penpotapp/frontend:latest";
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-frontend";
        ExecStopPost = "${pkgs.docker}/bin/docker rm penpot-frontend || true";
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.services.penpot-exporter = {
      description = "Penpot Exporter Service";
      after = [ "docker.service" "penpot-backend.service" ];
      wants = [ "penpot-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        PENPOT_PUBLIC_URI = "https://${config.services.rave.penpot.host}/penpot/";
      };
      
      serviceConfig = {
        Type = "exec";
        ExecStartPre = "${pkgs.docker}/bin/docker pull penpotapp/exporter:latest";
        ExecStart = "${pkgs.docker}/bin/docker run --rm --name penpot-exporter --network penpot-network -p 6061:6061 -e PENPOT_PUBLIC_URI penpotapp/exporter:latest";
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-exporter";
        ExecStopPost = "${pkgs.docker}/bin/docker rm penpot-exporter || true";
        Restart = "always";
        RestartSec = 10;
      };
    };

    # Required dependencies for Penpot
    services.postgresql = {
      enable = true;
      ensureDatabases = [ config.services.rave.penpot.database.name ];
      ensureUsers = [{
        name = config.services.rave.penpot.database.username;
        ensureDBOwnership = true;
      }];
      
      # PostgreSQL settings optimized for Penpot
      settings = {
        max_connections = 100;
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
        maintenance_work_mem = "64MB";
        checkpoint_completion_target = 0.9;
        wal_buffers = "16MB";
        default_statistics_target = 100;
        random_page_cost = 1.1;
        effective_io_concurrency = 200;
      };
    };

    # Redis instance for Penpot
    services.redis.servers.penpot = {
      enable = true;
      port = config.services.rave.penpot.redis.port;
      
      # Memory configuration for Penpot sessions and cache
      settings = {
        maxmemory = "256MB";
        maxmemory-policy = "allkeys-lru";
        save = mkForce "60 1000"; # Save every minute if at least 1000 keys changed
      };
    };

    # Enable Docker for Penpot containers
    virtualisation.docker = {
      enable = true;
      
      # Docker daemon settings for Penpot
      daemon.settings = {
        data-root = "/var/lib/docker";
        storage-driver = "overlay2";
        
        # Resource management for Penpot containers
        default-ulimits = {
          memlock = {
            Name = "memlock";
            Hard = 67108864;  # 64MB
            Soft = 67108864;
          };
          nofile = {
            Name = "nofile";
            Hard = 65536;
            Soft = 65536;
          };
        };
      };
    };

    # Firewall configuration for Penpot services
    networking.firewall.allowedTCPPorts = [ 
      3449  # Penpot Frontend
      6060  # Penpot Backend
      6061  # Penpot Exporter
    ];
    
  };
}