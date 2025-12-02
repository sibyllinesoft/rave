{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.outline;
  redisPlatform = config.services.rave.redis.platform or {};
  sharedAllocations = redisPlatform.allocations or {};
  sharedRedisHost = redisPlatform.dockerHost or "host.docker.internal";
  sharedRedisPort = redisPlatform.port or 6379;
  sharedRedisUnit = redisPlatform.unit or "redis-main.service";
  redisDatabase = if cfg.redisDb != null then cfg.redisDb else sharedAllocations.outline or 5;
  redisUrl = "redis://${sharedRedisHost}:${toString sharedRedisPort}/${toString redisDatabase}";
  trimNewline = "${pkgs.coreutils}/bin/tr -d \"\\n\"";
  publicUrlNormalized =
    let val = cfg.publicUrl or "";
    in if lib.hasSuffix "/" val then val else "${val}/";
  dbPasswordExpr = if cfg.dbPasswordFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.dbPasswordFile} | ${trimNewline})"
    else cfg.dbPassword;
in
{
  options.services.rave.outline = {
    enable = lib.mkEnableOption "Outline wiki service";

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://localhost:8443/outline";
      description = "External URL (including base path) for Outline.";
    };

    dockerImage = lib.mkOption {
      type = lib.types.str;
      default = "outlinewiki/outline:latest";
      description = "Container image to run for Outline.";
    };

    hostPort = lib.mkOption {
      type = lib.types.int;
      default = 8310;
      description = "Loopback port exposed by the Outline container.";
    };

    dbPassword = lib.mkOption {
      type = lib.types.str;
      default = "outline-production-password";
      description = "Database password for the Outline PostgreSQL user.";
    };

    dbHost = lib.mkOption {
      type = lib.types.str;
      default = "host.docker.internal";
      description = "Hostname containers should use to reach PostgreSQL.";
    };

    dbPort = lib.mkOption {
      type = lib.types.int;
      default = 5432;
      description = "PostgreSQL port for Outline.";
    };

    dbPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the Outline database password.";
    };

    secretKey = lib.mkOption {
      type = lib.types.str;
      default = "outline-secret-key";
      description = "Outline SECRET_KEY value.";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing Outline's SECRET_KEY.";
    };

    utilsSecret = lib.mkOption {
      type = lib.types.str;
      default = "outline-utils-secret";
      description = "Outline UTILS_SECRET value.";
    };

    utilsSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing Outline's UTILS_SECRET.";
    };

    redisDb = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Redis database number used by Outline (defaults to services.rave.redis.allocations.outline).";
    };

    webhook = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Outline's outgoing webhook integration and point it at the Benthos ingress.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:4195/hooks/outline";
        description = "Endpoint Outline uses for outgoing webhook deliveries.";
      };

      secret = lib.mkOption {
        type = lib.types.str;
        default = "outline-webhook-secret";
        description = "Shared secret Outline attaches to outgoing webhook payloads.";
      };

      secretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional file containing the webhook secret (preferred for production).";
      };
    };

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OIDC authentication (e.g. via Authentik)";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "rave-outline";
        description = "OAuth2/OIDC client ID";
      };

      clientSecret = lib.mkOption {
        type = lib.types.str;
        default = "outline-oidc-secret";
        description = "Fallback OAuth2/OIDC client secret";
      };

      clientSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing OIDC client secret (preferred for production)";
      };

      displayName = lib.mkOption {
        type = lib.types.str;
        default = "Authentik";
        description = "Display name for the OIDC provider on the login screen";
      };

      authUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC authorization endpoint";
      };

      tokenUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC token endpoint";
      };

      userInfoUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC userinfo endpoint";
      };

      scopes = lib.mkOption {
        type = lib.types.str;
        default = "openid profile email";
        description = "OIDC scopes to request (space-separated)";
      };

      usernameClaim = lib.mkOption {
        type = lib.types.str;
        default = "preferred_username";
        description = "OIDC claim to use for username";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.ensureDatabases = lib.mkAfter [ "outline" ];
    services.postgresql.ensureUsers = lib.mkAfter [
      { name = "outline"; ensureDBOwnership = true; }
    ];
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER outline PASSWORD '${dbPasswordExpr}';" || true
    '';

    systemd.services."docker-pull-outline" = {
      description = "Pre-pull Outline Docker image";
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
          ${pkgs.docker}/bin/docker pull ${cfg.dockerImage}
        '';
      };
    };

    systemd.services.outline = {
      description = "Outline wiki (Docker)";
      after = [ "docker.service" "postgresql.service" sharedRedisUnit "docker-pull-outline.service" ];
      requires = [ "docker.service" "postgresql.service" sharedRedisUnit "docker-pull-outline.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre = [
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f outline || true'"
          "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create outline-data || true'"
        ];
        ExecStart = pkgs.writeShellScript "outline-start" ''
          set -euo pipefail
${optionalString (cfg.dbPasswordFile != null) ''
          if [ -s ${cfg.dbPasswordFile} ]; then
            DB_PASSWORD="$(${pkgs.coreutils}/bin/cat ${cfg.dbPasswordFile} | ${trimNewline})"
          else
            DB_PASSWORD=${lib.escapeShellArg cfg.dbPassword}
          fi
''}${optionalString (cfg.dbPasswordFile == null) ''
          DB_PASSWORD=${lib.escapeShellArg cfg.dbPassword}
''}
${optionalString (cfg.secretKeyFile != null) ''
          if [ -s ${cfg.secretKeyFile} ]; then
            SECRET_KEY="$(${pkgs.coreutils}/bin/cat ${cfg.secretKeyFile} | ${trimNewline})"
          else
            SECRET_KEY=${lib.escapeShellArg cfg.secretKey}
          fi
''}${optionalString (cfg.secretKeyFile == null) ''
          SECRET_KEY=${lib.escapeShellArg cfg.secretKey}
''}
${optionalString (cfg.utilsSecretFile != null) ''
          if [ -s ${cfg.utilsSecretFile} ]; then
            UTILS_SECRET="$(${pkgs.coreutils}/bin/cat ${cfg.utilsSecretFile} | ${trimNewline})"
          else
            UTILS_SECRET=${lib.escapeShellArg cfg.utilsSecret}
          fi
''}${optionalString (cfg.utilsSecretFile == null) ''
          UTILS_SECRET=${lib.escapeShellArg cfg.utilsSecret}
''}
${optionalString (cfg.webhook.enable && cfg.webhook.secretFile != null) ''
          if [ -s ${cfg.webhook.secretFile} ]; then
            WEBHOOK_SECRET="$(${pkgs.coreutils}/bin/cat ${cfg.webhook.secretFile} | ${trimNewline})"
          else
            WEBHOOK_SECRET=${lib.escapeShellArg cfg.webhook.secret}
          fi
''}${optionalString (cfg.webhook.enable && cfg.webhook.secretFile == null) ''
          WEBHOOK_SECRET=${lib.escapeShellArg cfg.webhook.secret}
''}
${optionalString (cfg.oidc.enable && cfg.oidc.clientSecretFile != null) ''
          if [ -s ${cfg.oidc.clientSecretFile} ]; then
            OIDC_SECRET="$(${pkgs.coreutils}/bin/cat ${cfg.oidc.clientSecretFile} | ${trimNewline})"
          else
            OIDC_SECRET=${lib.escapeShellArg cfg.oidc.clientSecret}
          fi
''}${optionalString (cfg.oidc.enable && cfg.oidc.clientSecretFile == null) ''
          OIDC_SECRET=${lib.escapeShellArg cfg.oidc.clientSecret}
''}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name outline \
            -p 127.0.0.1:${toString cfg.hostPort}:3000 \
            -v outline-data:/var/lib/outline/data \
            --add-host host.docker.internal:host-gateway \
            -e URL=${publicUrlNormalized} \
            -e CDN_URL=${publicUrlNormalized} \
            -e PORT=3000 \
            -e SECRET_KEY="$SECRET_KEY" \
            -e UTILS_SECRET="$UTILS_SECRET" \
            -e DATABASE_URL="postgresql://outline:''${DB_PASSWORD}@${cfg.dbHost}:${toString cfg.dbPort}/outline" \
            -e PGSSLMODE=disable \
            -e REDIS_URL=${redisUrl} \
            -e FILE_STORAGE=local \
            -e FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data \
            -e FILE_STORAGE_LOCAL_SERVER_ROOT=${publicUrlNormalized}uploads \
            ${optionalString cfg.webhook.enable ''-e WEBHOOK_ENDPOINT="${cfg.webhook.endpoint}" \''}
            ${optionalString cfg.webhook.enable ''-e WEBHOOK_SECRET="$WEBHOOK_SECRET" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_CLIENT_ID="${cfg.oidc.clientId}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_CLIENT_SECRET="$OIDC_SECRET" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_AUTH_URI="${cfg.oidc.authUrl}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_TOKEN_URI="${cfg.oidc.tokenUrl}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_USERINFO_URI="${cfg.oidc.userInfoUrl}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_DISPLAY_NAME="${cfg.oidc.displayName}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_SCOPES="${cfg.oidc.scopes}" \''}
            ${optionalString cfg.oidc.enable ''-e OIDC_USERNAME_CLAIM="${cfg.oidc.usernameClaim}" \''}
            ${cfg.dockerImage}
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop outline";
      };
    };

  };
}
