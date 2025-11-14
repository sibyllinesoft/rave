{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.authentik;

  pathOrString = types.either types.path types.str;

  redisPlatform = config.services.rave.redis.platform or {};
  redisAllocations = redisPlatform.allocations or {};
  redisDbDefault = redisAllocations.authentik or 12;

  redisDb =
    if cfg.redis.database != null then cfg.redis.database else redisDbDefault;
  redisUnit = redisPlatform.unit or "redis-main.service";
  redisDockerHost =
    if cfg.redis.host != null then cfg.redis.host else redisPlatform.dockerHost or "host.docker.internal";
  redisPort =
    if cfg.redis.port != null then cfg.redis.port else redisPlatform.port or 6379;

  trimNewline = "${pkgs.coreutils}/bin/tr -d \"\\n\"";

  hostFromUrl = url:
    let matchResult = builtins.match "https?://([^/:]+).*" url;
    in if matchResult == null || matchResult == [] then null else builtins.head matchResult;

  schemeFromUrl = url:
    let matchResult = builtins.match "([^:]+)://.*" url;
    in if matchResult == null || matchResult == [] then "https" else builtins.head matchResult;

  pathFromUrl =
    url:
    let
      normalized = if url == null then "" else if lib.hasSuffix "/" url then url else "${url}/";
      matchResult = builtins.match "https?://[^/]+(.*)" normalized;
      tail =
        if matchResult == null || matchResult == [] then "/"
        else
          let candidate = builtins.head matchResult;
          in if candidate == "" then "/" else candidate;
    in tail;

  publicUrlNormalized =
    let val = cfg.publicUrl or "";
    in if lib.hasSuffix "/" val then val else "${val}/";

  publicHost = hostFromUrl publicUrlNormalized;
  publicScheme = schemeFromUrl publicUrlNormalized;
  publicPath = pathFromUrl publicUrlNormalized;

  cookieDomain =
    if cfg.cookieDomain != null then cfg.cookieDomain
    else if publicHost != null then publicHost
    else cfg.rootDomain;

  secretProvided = value: file: (value != null && value != "") || (file != null);

  readSecretSnippet = name: inline: file:
    if file != null then ''
      if [ -s ${lib.escapeShellArg file} ]; then
        ${name}="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg file} | ${trimNewline})"
      else
        ${name}=${lib.escapeShellArg (if inline != null then inline else "")}
      fi
    '' else ''
      ${name}=${lib.escapeShellArg (if inline != null then inline else "")}
    '';

  dbPasswordSqlExpr =
    if cfg.database.passwordFile != null
    then "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.database.passwordFile} | ${trimNewline})"
    else cfg.database.password;

  redisPasswordConfigured =
    (cfg.redis.password != null && cfg.redis.password != "") || (cfg.redis.passwordFile != null);

  bootstrapTokenConfigured =
    (cfg.bootstrap.token != null && cfg.bootstrap.token != "") || (cfg.bootstrap.tokenFile != null);

  emailPasswordConfigured =
    cfg.email.enable && ((cfg.email.password != null && cfg.email.password != "") || (cfg.email.passwordFile != null));

  dockerVolumeMounts = [
    { name = "authentik-media"; mount = "/media"; }
    { name = "authentik-templates"; mount = "/templates"; }
    { name = "authentik-geoip"; mount = "/geoip"; }
    { name = "authentik-blueprints"; mount = "/blueprints"; }
  ];

  volumeCreateCommands =
    map (vol: "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create ${vol.name} >/dev/null || true'") dockerVolumeMounts;

  volumeRunArgs =
    lib.concatStrings (map (vol: "            -v ${vol.name}:${vol.mount} \\\n") dockerVolumeMounts);

  extraEnvArgs =
    lib.concatStrings (
      map
        (name: "            -e ${name}=${lib.escapeShellArg cfg.extraEnv.${name}} \\\n")
        (builtins.attrNames cfg.extraEnv)
    );

  commonEnvArgs = ''
            -e AUTHENTIK_SECRET_KEY="$AUTHENTIK_SECRET_KEY" \
            -e AUTHENTIK_BOOTSTRAP_EMAIL=${lib.escapeShellArg cfg.bootstrap.email} \
            -e AUTHENTIK_BOOTSTRAP_PASSWORD="$AUTHENTIK_BOOTSTRAP_PASSWORD" \
            ${optionalString bootstrapTokenConfigured "-e AUTHENTIK_BOOTSTRAP_TOKEN=\"$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE\" \\\n            "}
            -e AUTHENTIK_POSTGRESQL__HOST=${lib.escapeShellArg cfg.database.host} \
            -e AUTHENTIK_POSTGRESQL__PORT=${toString cfg.database.port} \
            -e AUTHENTIK_POSTGRESQL__NAME=${lib.escapeShellArg cfg.database.name} \
            -e AUTHENTIK_POSTGRESQL__USER=${lib.escapeShellArg cfg.database.user} \
            -e AUTHENTIK_POSTGRESQL__PASSWORD="$AUTHENTIK_DB_PASSWORD" \
            -e AUTHENTIK_POSTGRESQL__SSL_MODE=${lib.escapeShellArg cfg.database.sslMode} \
            -e AUTHENTIK_REDIS__HOST=${lib.escapeShellArg redisDockerHost} \
            -e AUTHENTIK_REDIS__PORT=${toString redisPort} \
            -e AUTHENTIK_REDIS__DB=${toString redisDb} \
            ${optionalString redisPasswordConfigured "-e AUTHENTIK_REDIS__PASSWORD=\"$AUTHENTIK_REDIS_PASSWORD\" \\\n            "}
            -e AUTHENTIK_LOG_LEVEL=${lib.escapeShellArg cfg.logLevel} \
            -e AUTHENTIK_DISABLE_UPDATE_CHECK=${boolToString cfg.disableUpdateCheck} \
            -e AUTHENTIK_ERROR_REPORTING__ENABLED=false \
            -e AUTHENTIK_USE_X_FORWARDED_HOST=true \
            -e AUTHENTIK_HTTP__TRUSTED_IPS=0.0.0.0/0 \
            -e AUTHENTIK_ROOT_DOMAIN=${lib.escapeShellArg cfg.rootDomain} \
            -e AUTHENTIK_COOKIE_DOMAIN=${lib.escapeShellArg cookieDomain} \
            -e AUTHENTIK_DEFAULT_HTTP_SCHEME=${lib.escapeShellArg publicScheme} \
            -e AUTHENTIK_DEFAULT_HTTP_HOST=${lib.escapeShellArg (if publicHost != null then publicHost else cfg.rootDomain)} \
            -e AUTHENTIK_DEFAULT_HTTP_PORT=${lib.escapeShellArg cfg.defaultExternalPort} \
            -e AUTHENTIK_ROOT__PATH=${lib.escapeShellArg publicPath} \
            -e AUTHENTIK_DEFAULT_USER__ENABLED=${boolToString cfg.bootstrap.enableDefaultUser} \
            -e AUTHENTIK_EVENTS__STATE__RETENTION_DAYS=${toString cfg.retentionDays} \
            -e TZ=${lib.escapeShellArg (config.time.timeZone or "UTC")} \
            ${optionalString cfg.email.enable "-e AUTHENTIK_EMAIL__FROM=${lib.escapeShellArg cfg.email.fromAddress} \\\n            -e AUTHENTIK_EMAIL__HOST=${lib.escapeShellArg cfg.email.host} \\\n            -e AUTHENTIK_EMAIL__PORT=${toString cfg.email.port} \\\n            -e AUTHENTIK_EMAIL__USERNAME=${lib.escapeShellArg cfg.email.username} \\\n            -e AUTHENTIK_EMAIL__USE_TLS=${boolToString cfg.email.useTls} \\\n            ${optionalString emailPasswordConfigured "-e AUTHENTIK_EMAIL__PASSWORD=\"$AUTHENTIK_EMAIL_PASSWORD\" \\\n            "}"}${optionalString (cfg.email.fromName != null) "-e AUTHENTIK_EMAIL__FROM_NAME=${lib.escapeShellArg cfg.email.fromName} \\\n            "}
            ${extraEnvArgs}\
  '';

in
{
  options.services.rave.authentik = {
    enable = mkEnableOption "Authentik identity provider (Dockerized)";

    dockerImage = mkOption {
      type = types.str;
      default = "ghcr.io/goauthentik/server:2024.6.2";
      description = "Container image tag used for both authentik server and worker.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://auth.localtest.me:8443/";
      description = "External URL (including trailing slash) routed to Authentik via Traefik.";
    };

    rootDomain = mkOption {
      type = types.str;
      default = "auth.localtest.me";
      description = "Canonical domain Authentik should treat as its root domain.";
    };

    defaultExternalPort = mkOption {
      type = types.str;
      default = "8443";
      description = "Port advertised inside Authentik for generated callback URLs.";
    };

    cookieDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional override for the cookie domain (defaults to the host portion of publicUrl).";
    };

    hostPort = mkOption {
      type = types.int;
      default = 9130;
      description = "Loopback HTTP port exposed for Authentik inside the VM.";
    };

    metricsPort = mkOption {
      type = types.int;
      default = 9131;
      description = "Loopback port that exposes Authentik metrics (mapped from container port 9300).";
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
      description = "Log level passed to Authentik (debug, info, warning, error).";
    };

    disableUpdateCheck = mkOption {
      type = types.bool;
      default = true;
      description = "Disable upstream update checks/telemetry inside the container.";
    };

    secretKey = mkOption {
      type = types.nullOr types.str;
      default = "authentik-development-secret-key";
      description = "Inline Authentik secret key (ignored when secretKeyFile is set).";
    };

    secretKeyFile = mkOption {
      type = types.nullOr pathOrString;
      default = null;
      description = "Path to a file containing the Authentik secret key.";
    };

    bootstrap = {
      email = mkOption {
        type = types.str;
        default = "admin@example.com";
        description = "Bootstrap administrator email address.";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = "authentik-admin-password";
        description = "Bootstrap administrator password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "File containing the bootstrap administrator password.";
      };

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional bootstrap token value (ignored when tokenFile is set).";
      };

      tokenFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Optional file path for the bootstrap token.";
      };

      enableDefaultUser = mkOption {
        type = types.bool;
        default = true;
        description = "Keep the default bootstrap user enabled after first run.";
      };
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host used by Authentik.";
      };

      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port.";
      };

      name = mkOption {
        type = types.str;
        default = "authentik";
        description = "Database name used by Authentik.";
      };

      user = mkOption {
        type = types.str;
        default = "authentik";
        description = "Database user Authentik authenticates as.";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = "authentik-db-password";
        description = "Database password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to a file containing the database password.";
      };

      sslMode = mkOption {
        type = types.str;
        default = "disable";
        description = "PostgreSQL SSL mode string.";
      };
    };

    redis = {
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host accessible from Docker containers for Redis (defaults to redis platform dockerHost).";
      };

      port = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Redis port override (defaults to redis platform port).";
      };

      database = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Logical Redis database index (defaults to redis.allocations.authentik when set).";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional Redis password.";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Optional Redis password file.";
      };
    };

    email = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP settings for Authentik email notifications.";
      };

      fromAddress = mkOption {
        type = types.str;
        default = "authentik@localhost";
        description = "Default From address used for Authentik emails.";
      };

      fromName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional display name for the From header.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "SMTP host.";
      };

      port = mkOption {
        type = types.int;
        default = 25;
        description = "SMTP port.";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "SMTP username (optional).";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "File containing the SMTP password.";
      };

      useTls = mkOption {
        type = types.bool;
        default = false;
        description = "Enable STARTTLS/TLS for the SMTP transport.";
      };
    };

    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Event log retention window in days.";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables passed to both server and worker containers.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = secretProvided cfg.secretKey cfg.secretKeyFile;
        message = "services.rave.authentik.secretKey or secretKeyFile must be provided.";
      }
      {
        assertion = secretProvided cfg.database.password cfg.database.passwordFile;
        message = "services.rave.authentik.database.password or passwordFile must be provided.";
      }
      {
        assertion = secretProvided cfg.bootstrap.password cfg.bootstrap.passwordFile;
        message = "services.rave.authentik.bootstrap.password or passwordFile must be provided.";
      }
      {
        assertion = !(cfg.email.enable && cfg.email.username != "" && !secretProvided cfg.email.password cfg.email.passwordFile);
        message = "services.rave.authentik.email.password or passwordFile must be set when email is enabled with a username.";
      }
    ];

    services.postgresql.ensureDatabases = lib.mkAfter [ cfg.database.name ];
    services.postgresql.ensureUsers = lib.mkAfter [
      { name = cfg.database.user; ensureDBOwnership = true; }
    ];
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER ${cfg.database.user} PASSWORD '${dbPasswordSqlExpr}';" || true
    '';

    systemd.services."docker-pull-authentik" = {
      description = "Pre-pull Authentik Docker image";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = ''
          ${pkgs.docker}/bin/docker pull ${cfg.dockerImage}
        '';
      };
    };

    systemd.services.authentik-server = {
      description = "Authentik server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "docker.service" "postgresql.service" redisUnit "docker-pull-authentik.service" ];
      requires = [ "docker.service" "postgresql.service" redisUnit "docker-pull-authentik.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre =
          [
            "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f authentik-server >/dev/null 2>&1 || true'"
          ]
          ++ volumeCreateCommands;
        ExecStart = pkgs.writeShellScript "authentik-server-start" ''
          set -euo pipefail

          ${readSecretSnippet "AUTHENTIK_SECRET_KEY" cfg.secretKey cfg.secretKeyFile}
          ${readSecretSnippet "AUTHENTIK_DB_PASSWORD" cfg.database.password cfg.database.passwordFile}
          ${readSecretSnippet "AUTHENTIK_BOOTSTRAP_PASSWORD" cfg.bootstrap.password cfg.bootstrap.passwordFile}
          ${optionalString bootstrapTokenConfigured (readSecretSnippet "AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" cfg.bootstrap.token cfg.bootstrap.tokenFile)}
          ${optionalString redisPasswordConfigured (readSecretSnippet "AUTHENTIK_REDIS_PASSWORD" cfg.redis.password cfg.redis.passwordFile)}
          ${optionalString emailPasswordConfigured (readSecretSnippet "AUTHENTIK_EMAIL_PASSWORD" cfg.email.password cfg.email.passwordFile)}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name authentik-server \
            --add-host host.docker.internal:host-gateway \
            -p 127.0.0.1:${toString cfg.hostPort}:9000 \
            -p 127.0.0.1:${toString cfg.metricsPort}:9300 \
${volumeRunArgs}${commonEnvArgs}            ${cfg.dockerImage} server
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop authentik-server";
      };
    };

    systemd.services.authentik-worker = {
      description = "Authentik worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "authentik-server.service" ];
      requires = [ "authentik-server.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre =
          [
            "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f authentik-worker >/dev/null 2>&1 || true'"
          ]
          ++ volumeCreateCommands;
        ExecStart = pkgs.writeShellScript "authentik-worker-start" ''
          set -euo pipefail

          ${readSecretSnippet "AUTHENTIK_SECRET_KEY" cfg.secretKey cfg.secretKeyFile}
          ${readSecretSnippet "AUTHENTIK_DB_PASSWORD" cfg.database.password cfg.database.passwordFile}
          ${readSecretSnippet "AUTHENTIK_BOOTSTRAP_PASSWORD" cfg.bootstrap.password cfg.bootstrap.passwordFile}
          ${optionalString bootstrapTokenConfigured (readSecretSnippet "AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" cfg.bootstrap.token cfg.bootstrap.tokenFile)}
          ${optionalString redisPasswordConfigured (readSecretSnippet "AUTHENTIK_REDIS_PASSWORD" cfg.redis.password cfg.redis.passwordFile)}
          ${optionalString emailPasswordConfigured (readSecretSnippet "AUTHENTIK_EMAIL_PASSWORD" cfg.email.password cfg.email.passwordFile)}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name authentik-worker \
            --add-host host.docker.internal:host-gateway \
${volumeRunArgs}${commonEnvArgs}            ${cfg.dockerImage} worker
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop authentik-worker";
      };
    };
  };
}
