{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.n8n;
  pathOrString = types.either types.path types.str;
  normalizedBasePath =
    let ensureLeadingSlash = path: if lib.hasPrefix "/" path then path else "/${path}";
        ensureTrailingSlash = path: if lib.hasSuffix "/" path then path else "${path}/";
    in ensureTrailingSlash (ensureLeadingSlash (if cfg.basePath == "" then "/n8n" else cfg.basePath));
  normalizedPublicUrl =
    let val = cfg.publicUrl;
    in if lib.hasSuffix "/" val then val else "${val}/";
  dbPasswordExpr =
    if cfg.dbPasswordFile != null
    then "$(cat ${cfg.dbPasswordFile})"
    else cfg.dbPassword;
  oidcSecretExpr =
    if cfg.oidc.clientSecretFile != null
    then "$(cat ${cfg.oidc.clientSecretFile} | tr -d '\\n')"
    else cfg.oidc.clientSecret;
in {
  options.services.rave.n8n = {
    enable = mkEnableOption "n8n automation service (native systemd)";

    package = mkOption {
      type = types.package;
      default = pkgs.n8n;
      description = "n8n package to run.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://localhost:8443/n8n";
      description = "External URL (including base path) for n8n.";
    };

    hostPort = mkOption {
      type = types.int;
      default = 5678;
      description = "Loopback port for n8n.";
    };

    dbHost = mkOption { type = types.str; default = "127.0.0.1"; description = "PostgreSQL host."; };
    dbPort = mkOption { type = types.int; default = 5432; description = "PostgreSQL port."; };
    dbPassword = mkOption { type = types.str; default = "n8n-production-password"; description = "PostgreSQL password."; };
    dbPasswordFile = mkOption { type = types.nullOr pathOrString; default = null; description = "Optional file containing DB password."; };

    encryptionKey = mkOption { type = types.str; default = "n8n-encryption-key"; description = "N8N_ENCRYPTION_KEY."; };
    basicAuthPassword = mkOption { type = types.str; default = "n8n-basic-auth-password"; description = "Password for basic auth when OIDC disabled."; };
    basePath = mkOption { type = types.str; default = "/n8n"; description = "Base path served via ingress proxy."; };

    oidc = {
      enable = mkOption { type = types.bool; default = false; description = "Enable OIDC authentication."; };
      clientId = mkOption { type = types.str; default = "rave-n8n"; description = "OIDC client ID."; };
      clientSecret = mkOption { type = types.str; default = "n8n-oidc-secret"; description = "Fallback OIDC secret."; };
      clientSecretFile = mkOption { type = types.nullOr pathOrString; default = null; description = "File containing OIDC client secret."; };
      issuerUrl = mkOption { type = types.str; default = ""; description = "OIDC issuer URL."; };
      authUrl = mkOption { type = types.str; default = ""; description = "OIDC authorization endpoint (optional override)."; };
      tokenUrl = mkOption { type = types.str; default = ""; description = "OIDC token endpoint (optional override)."; };
      userInfoUrl = mkOption { type = types.str; default = ""; description = "OIDC userinfo endpoint (optional override)."; };
      scopes = mkOption { type = types.str; default = "openid profile email"; description = "OIDC scopes."; };
    };
  };

  config = mkIf cfg.enable {
    services.postgresql.ensureDatabases = mkAfter [ "n8n" ];
    services.postgresql.ensureUsers = mkAfter [ { name = "n8n"; ensureDBOwnership = true; } ];
    systemd.services.postgresql.postStart = mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER n8n PASSWORD '${dbPasswordExpr}';" || true
    '';

    systemd.services.n8n = {
      description = "n8n automation (native)";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "network-online.target" ];
      requires = [ "postgresql.service" ];

      serviceConfig = {
        Type = "simple";
        User = "n8n";
        Group = "n8n";
        StateDirectory = "n8n";
        WorkingDirectory = "/var/lib/n8n";
        Environment = [
          "DB_TYPE=postgresdb"
          "DB_POSTGRESDB_HOST=${cfg.dbHost}"
          "DB_POSTGRESDB_PORT=${toString cfg.dbPort}"
          "DB_POSTGRESDB_DATABASE=n8n"
          "DB_POSTGRESDB_USER=n8n"
          "DB_POSTGRESDB_PASSWORD=${dbPasswordExpr}"
          "N8N_ENCRYPTION_KEY=${cfg.encryptionKey}"
          "N8N_BASE_PATH=${normalizedBasePath}"
          "N8N_PATH=${normalizedBasePath}"
          "WEBHOOK_URL=${normalizedPublicUrl}"
          "N8N_HOST=localhost"
          "N8N_PORT=${toString cfg.hostPort}"
          "N8N_PROTOCOL=https"
          "N8N_EDITOR_BASE_URL=${normalizedPublicUrl}"
          "EXECUTIONS_DATA_SAVE_ON_ERROR=all"
          "EXECUTIONS_DATA_SAVE_ON_SUCCESS=none"
          "EXECUTIONS_DATA_PRUNE=true"
        ] ++ lib.optionals (!cfg.oidc.enable) [
          "N8N_BASIC_AUTH_ACTIVE=true"
          "N8N_BASIC_AUTH_USER=admin"
          "N8N_BASIC_AUTH_PASSWORD=${cfg.basicAuthPassword}"
        ] ++ lib.optionals cfg.oidc.enable [
          "N8N_AUTH_EXCLUDE_ENDPOINTS=/healthz"
          "N8N_USER_MANAGEMENT_DISABLED=false"
          "N8N_SSO_ENABLED=true"
          "N8N_SSO_JUST_IN_TIME_PROVISIONING=true"
          "N8N_SSO_REDIRECT_LOGIN_TO_SSO=true"
          "N8N_OIDC_ENABLED=true"
          "N8N_OIDC_CLIENT_ID=${cfg.oidc.clientId}"
          "N8N_OIDC_CLIENT_SECRET=${oidcSecretExpr}"
          "N8N_OIDC_ISSUER_URL=${cfg.oidc.issuerUrl}"
          "N8N_OIDC_AUTHORIZATION_URL=${cfg.oidc.authUrl}"
          "N8N_OIDC_TOKEN_URL=${cfg.oidc.tokenUrl}"
          "N8N_OIDC_USERINFO_URL=${cfg.oidc.userInfoUrl}"
          "N8N_OIDC_SCOPES=${cfg.oidc.scopes}"
        ];
        ExecStart = "${cfg.package}/bin/n8n start";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = false;
      };
      wants = [ "network-online.target" ];
    };

    users.users.n8n = {
      isSystemUser = true;
      home = "/var/lib/n8n";
      group = "n8n";
    };
    users.groups.n8n = { };

    networking.firewall.allowedTCPPorts = mkAfter [ cfg.hostPort ];
  };
}
