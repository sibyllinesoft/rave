{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.outline;
  pathOrString = types.either types.path types.str;
  redisPlatform = config.services.rave.redis.platform or {};
  sharedAllocations = redisPlatform.allocations or {};
  sharedRedisUnit = redisPlatform.unit or "redis-main.service";
  redisDatabase = if cfg.redisDb != null then cfg.redisDb else sharedAllocations.outline or 5;
  redisUrl = "redis://${cfg.redisHost}:${toString cfg.redisPort}/${toString redisDatabase}";
  trimNewline = "${pkgs.coreutils}/bin/tr -d \"\\n\"";
  publicUrlNormalized =
    let val = cfg.publicUrl;
    in if lib.hasSuffix "/" val then val else "${val}/";
  dbPasswordExpr = if cfg.dbPasswordFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.dbPasswordFile} | ${trimNewline})"
    else cfg.dbPassword;
  secretKeyExpr = if cfg.secretKeyFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.secretKeyFile} | ${trimNewline})"
    else cfg.secretKey;
  utilsSecretExpr = if cfg.utilsSecretFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.utilsSecretFile} | ${trimNewline})"
    else cfg.utilsSecret;
  webhookSecretExpr = if cfg.webhook.enable && cfg.webhook.secretFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.webhook.secretFile} | ${trimNewline})"
    else cfg.webhook.secret;
  oidcSecretExpr = if cfg.oidc.enable && cfg.oidc.clientSecretFile != null
    then "$(${pkgs.coreutils}/bin/cat ${cfg.oidc.clientSecretFile} | ${trimNewline})"
    else cfg.oidc.clientSecret;
in {
  options.services.rave.outline = {
    enable = mkEnableOption "Outline wiki (native)";

    package = mkOption {
      type = types.package;
      default = pkgs.outline;
      description = "Outline package to run.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://localhost:8443/outline/";
      description = "External URL (including base path) for Outline.";
    };

    hostPort = mkOption {
      type = types.int;
      default = 8310;
      description = "Loopback port exposed by Outline.";
    };

    dbHost = mkOption { type = types.str; default = "127.0.0.1"; description = "PostgreSQL host."; };
    dbPort = mkOption { type = types.int; default = 5432; description = "PostgreSQL port."; };
    dbPassword = mkOption { type = types.str; default = "outline-production-password"; description = "Database password."; };
    dbPasswordFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing database password."; };

    secretKey = mkOption { type = types.str; default = "outline-secret-key"; description = "Outline SECRET_KEY."; };
    secretKeyFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing SECRET_KEY."; };
    utilsSecret = mkOption { type = types.str; default = "outline-utils-secret"; description = "Outline UTILS_SECRET."; };
    utilsSecretFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing UTILS_SECRET."; };

    redisHost = mkOption { type = types.str; default = "127.0.0.1"; description = "Redis host."; };
    redisPort = mkOption { type = types.int; default = 6379; description = "Redis port."; };
    redisDb = mkOption { type = types.nullOr types.int; default = null; description = "Redis DB index."; };

    webhook = {
      enable = mkOption { type = types.bool; default = true; description = "Enable webhook delivery."; };
      endpoint = mkOption { type = types.str; default = "http://127.0.0.1:4195/hooks/outline"; description = "Webhook endpoint URL."; };
      secret = mkOption { type = types.str; default = "outline-webhook-secret"; description = "Webhook shared secret."; };
      secretFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing webhook secret."; };
    };

    oidc = {
      enable = mkOption { type = types.bool; default = false; description = "Enable OIDC login."; };
      clientId = mkOption { type = types.str; default = "rave-outline"; description = "OIDC client ID."; };
      clientSecret = mkOption { type = types.str; default = "outline-oidc-secret"; description = "Fallback OIDC client secret."; };
      clientSecretFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing OIDC client secret."; };
      displayName = mkOption { type = types.str; default = "Authentik"; description = "Provider display name."; };
      authUrl = mkOption { type = types.str; default = ""; description = "OIDC authorization endpoint."; };
      tokenUrl = mkOption { type = types.str; default = ""; description = "OIDC token endpoint."; };
      userInfoUrl = mkOption { type = types.str; default = ""; description = "OIDC userinfo endpoint."; };
      scopes = mkOption { type = types.str; default = "openid profile email"; description = "OIDC scopes."; };
      usernameClaim = mkOption { type = types.str; default = "preferred_username"; description = "OIDC username claim."; };
    };
  };

  config = mkIf cfg.enable {
    services.postgresql.ensureDatabases = mkAfter [ "outline" ];
    services.postgresql.ensureUsers = mkAfter [ { name = "outline"; ensureDBOwnership = true; } ];
    systemd.services.postgresql.postStart = mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER outline PASSWORD '${dbPasswordExpr}';" || true
    '';

    systemd.services.outline = {
      description = "Outline wiki (native)";
      after = [ "postgresql.service" sharedRedisUnit "network-online.target" ];
      requires = [ "postgresql.service" sharedRedisUnit ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "outline";
        Group = "outline";
        StateDirectory = "outline";
        WorkingDirectory = "/var/lib/outline";
        Environment = [
          "URL=${publicUrlNormalized}"
          "CDN_URL=${publicUrlNormalized}"
          "PORT=${toString cfg.hostPort}"
          "SECRET_KEY=${secretKeyExpr}"
          "UTILS_SECRET=${utilsSecretExpr}"
          "DATABASE_URL=postgresql://outline:''${dbPasswordExpr}@${cfg.dbHost}:${toString cfg.dbPort}/outline"
          "PGSSLMODE=disable"
          "REDIS_URL=${redisUrl}"
          "FILE_STORAGE=local"
          "FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data"
          "FILE_STORAGE_LOCAL_SERVER_ROOT=${publicUrlNormalized}uploads"
        ] ++ lib.optionals cfg.webhook.enable [
          "WEBHOOK_ENDPOINT=${cfg.webhook.endpoint}"
          "WEBHOOK_SECRET=${webhookSecretExpr}"
        ] ++ lib.optionals cfg.oidc.enable [
          "OIDC_CLIENT_ID=${cfg.oidc.clientId}"
          "OIDC_CLIENT_SECRET=${oidcSecretExpr}"
          "OIDC_AUTH_URI=${cfg.oidc.authUrl}"
          "OIDC_TOKEN_URI=${cfg.oidc.tokenUrl}"
          "OIDC_USERINFO_URI=${cfg.oidc.userInfoUrl}"
          "OIDC_DISPLAY_NAME=${cfg.oidc.displayName}"
          "OIDC_SCOPES=${cfg.oidc.scopes}"
          "OIDC_USERNAME_CLAIM=${cfg.oidc.usernameClaim}"
        ];
        ExecStart = "${cfg.package}/bin/outline";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = false;
      };
    };

    users.users.outline = {
      isSystemUser = true;
      home = "/var/lib/outline";
      group = "outline";
    };
    users.groups.outline = { };

    networking.firewall.allowedTCPPorts = mkAfter [ cfg.hostPort ];
  };
}
