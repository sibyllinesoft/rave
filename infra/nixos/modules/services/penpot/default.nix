# Penpot design service configuration module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.penpot;
  redisPlatform = config.services.rave.redis.platform or {};
  sharedAllocations = redisPlatform.allocations or {};
  sharedRedisUnit = redisPlatform.unit or "redis-main.service";
  sharedRedisHost = redisPlatform.dockerHost or "host.docker.internal";
  sharedRedisPort = redisPlatform.port or 6379;
  sharedRedisDb = sharedAllocations.penpot or 10;
  useLocalDatabase = config.services.rave.postgresql.enable or true;

  dbPasswordExpr = if cfg.database.passwordFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.database.passwordFile} | ${trimNewline})"
    else cfg.database.password;

  trimNewline = "${pkgs.coreutils}/bin/tr -d '\\n'";
  readSecretSnippet = { var, file, fallback }: if file != null then ''
    if [ -s ${file} ]; then
      ${var}="$(${pkgs.coreutils}/bin/cat ${file} | ${trimNewline})"
    else
      ${var}=${lib.escapeShellArg fallback}
    fi
  '' else ''
    ${var}=${lib.escapeShellArg fallback}
  '';
  dbPasswordSnippet = readSecretSnippet {
    var = "PENPOT_DB_PASSWORD";
    file = cfg.database.passwordFile;
    fallback = cfg.database.password;
  };
  oidcSecretSnippet = if cfg.oidc.enable then readSecretSnippet {
    var = "PENPOT_OIDC_SECRET";
    file = cfg.oidc.clientSecretFile;
    fallback = cfg.oidc.clientSecret;
  } else "";

  # Derive OIDC endpoints based on provider type and configuration
  oidcBaseUrl =
    if cfg.oidc.baseUrl != "" then cfg.oidc.baseUrl
    else if cfg.oidc.provider == "gitlab" then cfg.oidc.gitlabUrl
    else "";
  oidcBaseUrlNormalized =
    if oidcBaseUrl != "" && lib.hasSuffix "/" oidcBaseUrl then oidcBaseUrl
    else if oidcBaseUrl != "" then "${oidcBaseUrl}/"
    else "";
  # For Authentik: /application/o/<slug>/authorize/, etc.
  # For GitLab: /oauth/authorize, etc.
  oidcAuthUri =
    if cfg.oidc.authUri != null then cfg.oidc.authUri
    else if cfg.oidc.provider == "authentik" then "${oidcBaseUrlNormalized}application/o/authorize/"
    else "${oidcBaseUrlNormalized}oauth/authorize";
  oidcTokenUri =
    if cfg.oidc.tokenUri != null then cfg.oidc.tokenUri
    else if cfg.oidc.provider == "authentik" then "${oidcBaseUrlNormalized}application/o/token/"
    else "${oidcBaseUrlNormalized}oauth/token";
  oidcUserUri =
    if cfg.oidc.userUri != null then cfg.oidc.userUri
    else if cfg.oidc.provider == "authentik" then "${oidcBaseUrlNormalized}application/o/userinfo/"
    else "${oidcBaseUrlNormalized}api/v4/user";

  redisHost = if cfg.redis.host != null then cfg.redis.host else sharedRedisHost;
  defaultRedisPort = if cfg.managedRedis then 6380 else sharedRedisPort;
  redisPort = if cfg.redis.port != null then cfg.redis.port else defaultRedisPort;
  redisDatabase = if cfg.redis.database != null then cfg.redis.database else sharedRedisDb;
  redisUri = "redis://${redisHost}:${toString redisPort}/${toString redisDatabase}";
  useSharedRedisUnit = cfg.redis.host == null && !cfg.managedRedis;
  redisDependencyUnits =
    if cfg.managedRedis then [ "redis-penpot.service" ]
    else (if useSharedRedisUnit then [ sharedRedisUnit ] else []);
  dbDependencyUnits = if useLocalDatabase then [ "postgresql.service" ] else [];

  backendPortStr = toString cfg.backendPort;
  exporterPortStr = toString cfg.exporterPort;
  frontendPortStr = toString cfg.frontendPort;
  publicUrl = cfg.publicUrl;
  ensureTrailingSlash = url: if lib.hasSuffix "/" url then url else "${url}/";
  publicUrlNormalized = ensureTrailingSlash publicUrl;
  backendEnvVars = [
    "PENPOT_FLAGS"
    "PENPOT_PUBLIC_URI"
    "PENPOT_DATABASE_URI"
    "PENPOT_REDIS_URI"
    "PENPOT_ASSETS_STORAGE_BACKEND"
    "PENPOT_STORAGE_ASSETS_FS_DIRECTORY"
    "PENPOT_TELEMETRY_ENABLED"
    "PENPOT_SMTP_DEFAULT_FROM"
    "PENPOT_SMTP_DEFAULT_REPLY_TO"
    "PENPOT_SMTP_HOST"
    "PENPOT_SMTP_PORT"
    "PENPOT_SMTP_TLS"
    "PENPOT_SMTP_SSL"
  ];
  backendEnvFlags = concatStringsSep " " (map (var: "-e ${var}") backendEnvVars);
  backendOidcVars = [
    "PENPOT_OIDC_CLIENT_ID"
    "PENPOT_OIDC_CLIENT_SECRET"
    "PENPOT_OIDC_BASE_URI"
    "PENPOT_OIDC_CLIENT_NAME"
    "PENPOT_OIDC_AUTH_URI"
    "PENPOT_OIDC_TOKEN_URI"
    "PENPOT_OIDC_USER_URI"
    "PENPOT_OIDC_SCOPES"
    "PENPOT_OIDC_NAME_ATTR"
    "PENPOT_OIDC_EMAIL_ATTR"
  ];
  backendOidcFlags = concatStringsSep " " (map (var: "-e ${var}") backendOidcVars);
  backendAllEnvFlags = backendEnvFlags + optionalString cfg.oidc.enable " ${backendOidcFlags}";
  frontendEnvVars = [
    "PENPOT_FRONTEND_URI"
    "PENPOT_BACKEND_URI"
    "PENPOT_EXPORTER_URI"
  ];
  frontendEnvFlags = concatStringsSep " " (map (var: "-e ${var}") frontendEnvVars);
  hostGatewayArg = "--add-host host.docker.internal:host-gateway";
in {
  options.services.rave.penpot = {
    enable = mkEnableOption "Penpot design tool with PostgreSQL and Redis backends";

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "Penpot hostname used by the ingress proxy";
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
        default = "host.docker.internal";
        description = "PostgreSQL host reachable from the Docker containers";
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
        type = types.nullOr types.str;
        default = null;
        description = ''Override for the Redis host Penpot should reach (defaults to the shared platform Redis host).'';
      };

      port = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Override for the Redis port Penpot should reach (defaults to the shared platform Redis port).";
      };

      database = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Redis database index (defaults to services.rave.redis.allocations.penpot).";
      };
    };

    managedRedis = mkOption {
      type = types.bool;
      default = false;
      description = "Provision a dedicated redis-penpot.service instead of using the shared platform Redis.";
    };

    oidc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable OIDC login (via Authentik or other provider)";
      };

      provider = mkOption {
        type = types.enum [ "authentik" "gitlab" ];
        default = "authentik";
        description = "OIDC provider type (affects default endpoint configuration)";
      };

      baseUrl = mkOption {
        type = types.str;
        default = "";
        description = "Base URL for the OIDC provider (e.g. https://auth.example.com/ for Authentik)";
      };

      # Legacy option for backward compatibility
      gitlabUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab";
        description = "GitLab base URL (deprecated, use baseUrl instead)";
      };

      clientId = mkOption {
        type = types.str;
        default = "rave-penpot";
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

      clientName = mkOption {
        type = types.str;
        default = "Authentik";
        description = "Display name for the OIDC provider";
      };

      authUri = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom authorization endpoint (auto-derived from baseUrl if not set)";
      };

      tokenUri = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom token endpoint (auto-derived from baseUrl if not set)";
      };

      userUri = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom userinfo endpoint (auto-derived from baseUrl if not set)";
      };

      scopes = mkOption {
        type = types.str;
        default = "openid profile email";
        description = "OIDC scopes to request";
      };

      nameAttr = mkOption {
        type = types.str;
        default = "name";
        description = "OIDC claim for user's display name";
      };

      emailAttr = mkOption {
        type = types.str;
        default = "email";
        description = "OIDC claim for user's email";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (mkIf useLocalDatabase {
      services.postgresql.ensureDatabases = mkAfter [ cfg.database.name ];
      services.postgresql.ensureUsers = mkAfter [
        { name = cfg.database.username; ensureDBOwnership = true; }
      ];
      systemd.services.postgresql.postStart = mkAfter ''
        ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER ${cfg.database.username} PASSWORD '${dbPasswordExpr}';" || true
      '';
    })

    {
      services.redis.servers.penpot = mkIf cfg.managedRedis {
      enable = true;
      port = redisPort;
      bind = "0.0.0.0";
      databases = redisDatabase + 1;
      settings = {
        maxmemory = "256MB";
        maxmemory-policy = "allkeys-lru";
        save = mkForce "60 1000";
      };
    };

    networking.firewall.allowedTCPPorts = mkAfter [ cfg.frontendPort cfg.backendPort cfg.exporterPort ];

    systemd.services."docker-pull-penpot-backend" = {
      description = "Pre-pull Penpot backend Docker image";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "0";
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = ''
          ${pkgs.docker}/bin/docker pull ${cfg.backendImage}
        '';
      };
    };

    systemd.services."docker-pull-penpot-frontend" = {
      description = "Pre-pull Penpot frontend Docker image";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "0";
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = ''
          ${pkgs.docker}/bin/docker pull ${cfg.frontendImage}
        '';
      };
    };

    systemd.services."docker-pull-penpot-exporter" = {
      description = "Pre-pull Penpot exporter Docker image";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "0";
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = ''
          ${pkgs.docker}/bin/docker pull ${cfg.exporterImage}
        '';
      };
    };

    systemd.services.penpot-backend = {
      description = "Penpot Backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "docker-pull-penpot-backend.service" ] ++ dbDependencyUnits ++ redisDependencyUnits;
      requires = [ "docker.service" "docker-pull-penpot-backend.service" ] ++ dbDependencyUnits ++ redisDependencyUnits;

      environment = {
        PENPOT_FLAGS = "enable-registration enable-login-with-oidc disable-email-verification enable-prepl-server";
        PENPOT_PUBLIC_URI = publicUrlNormalized;
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
        PENPOT_OIDC_BASE_URI = oidcBaseUrlNormalized;
        PENPOT_OIDC_CLIENT_NAME = cfg.oidc.clientName;
        PENPOT_OIDC_AUTH_URI = oidcAuthUri;
        PENPOT_OIDC_TOKEN_URI = oidcTokenUri;
        PENPOT_OIDC_USER_URI = oidcUserUri;
        PENPOT_OIDC_SCOPES = cfg.oidc.scopes;
        PENPOT_OIDC_NAME_ATTR = cfg.oidc.nameAttr;
        PENPOT_OIDC_EMAIL_ATTR = cfg.oidc.emailAttr;
      };

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f penpot-backend || true'"
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker network create penpot-network --driver bridge || true'"
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create penpot-assets || true'"
        ];
        ExecStart = pkgs.writeShellScript "penpot-backend-start" ''
          set -euo pipefail
          urlencode() {
            RAW="$1" ${pkgs.python3}/bin/python3 - <<'PY'
import os, urllib.parse
print(urllib.parse.quote(os.environ["RAW"], safe='._-~'))
PY
          }
          ${dbPasswordSnippet}
          PENPOT_DB_USER_ENC="$(urlencode ${lib.escapeShellArg cfg.database.username})"
          PENPOT_DB_PASS_ENC="$(urlencode "''${PENPOT_DB_PASSWORD}")"
          export PENPOT_DATABASE_URI="postgresql://${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}?user=''${PENPOT_DB_USER_ENC}&password=''${PENPOT_DB_PASS_ENC}"
          ${optionalString cfg.oidc.enable ''
            ${oidcSecretSnippet}
            export PENPOT_OIDC_CLIENT_SECRET="''${PENPOT_OIDC_SECRET}"
          ''}
          exec ${pkgs.docker}/bin/docker run --rm --name penpot-backend --network penpot-network \
            ${hostGatewayArg} \
            -p 127.0.0.1:${backendPortStr}:6060 \
            -v penpot-assets:/opt/data/assets \
            ${backendAllEnvFlags} \
            ${cfg.backendImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-backend";
      };
    };

    systemd.services.penpot-frontend = {
      description = "Penpot Frontend";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "penpot-backend.service"
        "penpot-exporter.service"
        "docker-pull-penpot-frontend.service"
      ];
      requires = [
        "docker.service"
        "docker-pull-penpot-frontend.service"
      ];

      environment = {
        PENPOT_FRONTEND_URI = publicUrlNormalized;
        PENPOT_BACKEND_URI = "http://penpot-backend:6060";
        PENPOT_EXPORTER_URI = "http://penpot-exporter:6061";
      };

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f penpot-frontend || true'"
        ];
        ExecStart = pkgs.writeShellScript "penpot-frontend-start" ''
          wait_for_container() {
            local name="$1"
            local attempts=0
            local max_attempts=30
            while true; do
              if ${pkgs.docker}/bin/docker inspect -f '{{.State.Running}}' "$name" >/dev/null 2>&1; then
                break
              fi
              attempts=$((attempts + 1))
              if [ "$attempts" -ge "$max_attempts" ]; then
                echo "Container $name not ready after $max_attempts attempts" >&2
                exit 1
              fi
              sleep 2
            done
          }

          wait_for_container penpot-backend
          wait_for_container penpot-exporter

          exec ${pkgs.docker}/bin/docker run --rm --name penpot-frontend --network penpot-network \
            ${hostGatewayArg} \
            -p 127.0.0.1:${frontendPortStr}:8080 \
            ${frontendEnvFlags} \
            ${cfg.frontendImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-frontend";
      };
    };

    systemd.services.penpot-exporter = {
      description = "Penpot Exporter";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "penpot-backend.service"
        "docker-pull-penpot-exporter.service"
      ];
      requires = [
        "docker.service"
        "docker-pull-penpot-exporter.service"
      ];

      environment = {
        PENPOT_PUBLIC_URI = publicUrlNormalized;
      };

      serviceConfig = {
        Type = "exec";
        Restart = "always";
        RestartSec = 10;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f penpot-exporter || true'"
        ];
        ExecStart = pkgs.writeShellScript "penpot-exporter-start" ''
          exec ${pkgs.docker}/bin/docker run --rm --name penpot-exporter --network penpot-network \
            ${hostGatewayArg} \
            -p 127.0.0.1:${exporterPortStr}:6061 \
            -e PENPOT_PUBLIC_URI \
            ${cfg.exporterImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop penpot-exporter";
      };
    };
  }
  ]);
}
