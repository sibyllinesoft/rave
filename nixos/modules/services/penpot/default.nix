# Penpot design service configuration module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.penpot;

  dbPasswordExpr = if cfg.database.passwordFile != null
    then "$(cat ${cfg.database.passwordFile})"
    else cfg.database.password;

  oidcSecretExpr = if cfg.oidc.clientSecretFile != null
    then "$(cat ${cfg.oidc.clientSecretFile})"
    else cfg.oidc.clientSecret;

  redisUri = "redis://${cfg.redis.host}:${toString cfg.redis.port}/${toString cfg.redis.database}";
  backendPortStr = toString cfg.backendPort;
  exporterPortStr = toString cfg.exporterPort;
  frontendPortStr = toString cfg.frontendPort;
  publicUrl = cfg.publicUrl;

  mkEnableList = servers: map (name: "redis-${name}.service") servers;
in {
  options.services.rave.penpot = {
    enable = mkEnableOption "Penpot design tool with PostgreSQL and Redis backends";

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "Penpot hostname used by nginx";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://localhost:8443/penpot";
      description = "External URL published to users";
    };

    backendImage = mkOption {
      type = types.str;
      default = "penpotapp/backend:latest";
      description = "Docker image for the backend service";
    };

    frontendImage = mkOption {
      type = types.str;
      default = "penpotapp/frontend:latest";
      description = "Docker image for the frontend";
    };

    exporterImage = mkOption {
      type = types.str;
      default = "penpotapp/exporter:latest";
      description = "Docker image for the exporter service";
    };

    frontendPort = mkOption {
      type = types.int;
      default = 3449;
      description = "Loopback port exposed by the frontend container";
    };

    backendPort = mkOption {
      type = types.int;
      default = 6060;
      description = "Loopback port exposed by the backend container";
    };

    exporterPort = mkOption {
      type = types.int;
      default = 6061;
      description = "Loopback port exposed by the exporter container";
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL host";
      };

      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = mkOption {
        type = types.str;
        default = "penpot";
        description = "Database name";
      };

      username = mkOption {
        type = types.str;
        default = "penpot";
        description = "Database username";
      };

      password = mkOption {
        type = types.str;
        default = "penpot-production-password";
        description = "Database password when passwordFile is not provided";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional file containing the database password (e.g. from sops-nix)";
      };
    };

    redis = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Redis host for Penpot";
      };

      port = mkOption {
        type = types.int;
        default = 6380;
        description = "Redis port for Penpot";
      };

      database = mkOption {
        type = types.int;
        default = 0;
        description = "Redis database index";
      };
    };

    oidc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GitLab OIDC login";
      };

      gitlabUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab";
        description = "GitLab base URL";
      };

      clientId = mkOption {
        type = types.str;
        default = "penpot";
        description = "OAuth client ID";
      };

      clientSecret = mkOption {
        type = types.str;
        default = "development-penpot-oidc-secret";
        description = "Fallback OAuth client secret";
      };

      clientSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional secret file for the OAuth client secret";
      };
    };
  };

  config = mkIf cfg.enable {
    services.postgresql.ensureDatabases = mkAfter [ cfg.database.name ];
    services.postgresql.ensureUsers = mkAfter [
      { name = cfg.database.username; ensureDBOwnership = true; }
    ];
    services.postgresql.initialScript = mkAfter ''
      SELECT format('CREATE ROLE %I LOGIN', '${cfg.database.username}')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${cfg.database.username}')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', '${cfg.database.name}', '${cfg.database.username}')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${cfg.database.name}')
      \gexec

      GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO ${cfg.database.username};
      ALTER USER ${cfg.database.username} WITH PASSWORD '${dbPasswordExpr}';
    '';
    systemd.services.postgresql.postStart = mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER ${cfg.database.username} PASSWORD '${dbPasswordExpr}';" || true
    '';

    services.redis.servers.penpot = {
      enable = true;
      port = cfg.redis.port;
      bind = "127.0.0.1";
      databases = cfg.redis.database + 1;
      settings = {
        maxmemory = "256MB";
        maxmemory-policy = "allkeys-lru";
        save = mkForce "60 1000";
      };
    };

    networking.firewall.allowedTCPPorts = mkAfter [ cfg.frontendPort cfg.backendPort cfg.exporterPort ];

    systemd.services.penpot-backend = {
      description = "Penpot Backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "postgresql.service" "redis-penpot.service" ];
      requires = [ "docker.service" "postgresql.service" "redis-penpot.service" ];

      environment = {
        PENPOT_FLAGS = "enable-registration enable-login-with-oidc disable-email-verification enable-prepl-server";
        PENPOT_PUBLIC_URI = publicUrl;
        PENPOT_DATABASE_URI = "postgresql://${cfg.database.username}:${dbPasswordExpr}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
        PENPOT_REDIS_URI = redisUri;
        PENPOT_ASSETS_STORAGE_BACKEND = "assets-fs";
        PENPOT_STORAGE_ASSETS_FS_DIRECTORY = "/opt/data/assets";
        PENPOT_TELEMETRY_ENABLED = "false";
        PENPOT_SMTP_DEFAULT_FROM = "noreply@${cfg.host}";
        PENPOT_SMTP_DEFAULT_REPLY_TO = "noreply@${cfg.host}";
        PENPOT_SMTP_HOST = "localhost";
        PENPOT_SMTP_PORT = "1025";
        PENPOT_SMTP_TLS = "false";
        PENPOT_SMTP_SSL = "false";
      } // optionalAttrs cfg.oidc.enable {
        PENPOT_OIDC_CLIENT_ID = cfg.oidc.clientId;
        PENPOT_OIDC_CLIENT_SECRET = oidcSecretExpr;
        PENPOT_OIDC_BASE_URI = cfg.oidc.gitlabUrl;
        PENPOT_OIDC_CLIENT_NAME = "GitLab";
        PENPOT_OIDC_AUTH_URI = "${cfg.oidc.gitlabUrl}/oauth/authorize";
        PENPOT_OIDC_TOKEN_URI = "${cfg.oidc.gitlabUrl}/oauth/token";
        PENPOT_OIDC_USER_URI = "${cfg.oidc.gitlabUrl}/api/v4/user";
        PENPOT_OIDC_SCOPES = "openid profile email";
        PENPOT_OIDC_NAME_ATTR = "name";
        PENPOT_OIDC_EMAIL_ATTR = "email";
      };

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = [
          "${pkgs.docker}/bin/docker network create penpot-network --driver bridge || true"
          "${pkgs.docker}/bin/docker volume create penpot-assets || true"
          "${pkgs.docker}/bin/docker pull ${cfg.backendImage}"
        ];
        ExecStart = pkgs.writeShellScript "penpot-backend-start" ''
          exec ${pkgs.docker}/bin/docker run --rm --name penpot-backend --network penpot-network \
            -p 127.0.0.1:${backendPortStr}:6060 \
            -v penpot-assets:/opt/data/assets \
            ${concatStringsSep " \
            " (map (var: "-e ${var}") [
              "PENPOT_FLAGS" "PENPOT_PUBLIC_URI" "PENPOT_DATABASE_URI" "PENPOT_REDIS_URI"
              "PENPOT_ASSETS_STORAGE_BACKEND" "PENPOT_STORAGE_ASSETS_FS_DIRECTORY" "PENPOT_TELEMETRY_ENABLED"
              "PENPOT_SMTP_DEFAULT_FROM" "PENPOT_SMTP_DEFAULT_REPLY_TO" "PENPOT_SMTP_HOST" "PENPOT_SMTP_PORT"
              "PENPOT_SMTP_TLS" "PENPOT_SMTP_SSL"
            ])}
            ${optionalString cfg.oidc.enable "-e PENPOT_OIDC_CLIENT_ID -e PENPOT_OIDC_CLIENT_SECRET -e PENPOT_OIDC_BASE_URI -e PENPOT_OIDC_CLIENT_NAME -e PENPOT_OIDC_AUTH_URI -e PENPOT_OIDC_TOKEN_URI -e PENPOT_OIDC_USER_URI -e PENPOT_OIDC_SCOPES -e PENPOT_OIDC_NAME_ATTR -e PENPOT_OIDC_EMAIL_ATTR"} \
            ${cfg.backendImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-backend";
      };
    };

    systemd.services.penpot-frontend = {
      description = "Penpot Frontend";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "penpot-backend.service" ];
      requires = [ "docker.service" "penpot-backend.service" ];

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = "${pkgs.docker}/bin/docker pull ${cfg.frontendImage}";
        ExecStart = pkgs.writeShellScript "penpot-frontend-start" ''
          exec ${pkgs.docker}/bin/docker run --rm --name penpot-frontend --network penpot-network \
            -p 127.0.0.1:${frontendPortStr}:80 \
            ${cfg.frontendImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-frontend";
      };
    };

    systemd.services.penpot-exporter = {
      description = "Penpot Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "penpot-backend.service" ];
      requires = [ "docker.service" "penpot-backend.service" ];

      environment = {
        PENPOT_PUBLIC_URI = publicUrl;
      };

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = "${pkgs.docker}/bin/docker pull ${cfg.exporterImage}";
        ExecStart = pkgs.writeShellScript "penpot-exporter-start" ''
          exec ${pkgs.docker}/bin/docker run --rm --name penpot-exporter --network penpot-network \
            -p 127.0.0.1:${exporterPortStr}:6061 \
            -e PENPOT_PUBLIC_URI \
            ${cfg.exporterImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-exporter";
      };
    };
  };
}
