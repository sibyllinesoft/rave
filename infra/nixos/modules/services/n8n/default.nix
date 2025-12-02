{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.n8n;
  pathOrString = types.either types.path types.str;
  publicUrl = cfg.publicUrl;
  dbPasswordExpr =
    if cfg.dbPasswordFile != null
    then "$(cat ${cfg.dbPasswordFile})"
    else cfg.dbPassword;

  ensureLeadingSlash = path: if lib.hasPrefix "/" path then path else "/${path}";
  ensureTrailingSlash = path: if lib.hasSuffix "/" path then path else "${path}/";
  normalizedBasePath = ensureTrailingSlash (ensureLeadingSlash (if cfg.basePath == "" then "/n8n" else cfg.basePath));
  normalizedPublicUrl = ensureTrailingSlash cfg.publicUrl;
in {
  options.services.rave.n8n = {
    enable = mkEnableOption "n8n automation service";

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://localhost:8443/n8n";
      description = "External URL (including base path) for n8n.";
    };

    dockerImage = lib.mkOption {
      type = lib.types.str;
      default = "n8nio/n8n:latest";
      description = "Container image to run";
    };

    hostPort = lib.mkOption {
      type = lib.types.int;
      default = 5678;
      description = "Loopback port for n8n";
    };

    dbPassword = lib.mkOption {
      type = lib.types.str;
      default = "n8n-production-password";
      description = "PostgreSQL password used by n8n";
    };

    dbHost = lib.mkOption {
      type = lib.types.str;
      default = "host.docker.internal";
      description = "Hostname containers should use to reach PostgreSQL.";
    };

    dbPort = lib.mkOption {
      type = lib.types.int;
      default = 5432;
      description = "PostgreSQL port for n8n.";
    };

    dbPasswordFile = lib.mkOption {
      type = lib.types.nullOr pathOrString;
      default = null;
      description = "Optional file containing the n8n database password.";
    };

    encryptionKey = lib.mkOption {
      type = lib.types.str;
      default = "n8n-encryption-key";
      description = "Value for N8N_ENCRYPTION_KEY";
    };

    basicAuthPassword = lib.mkOption {
      type = lib.types.str;
      default = "n8n-basic-auth-password";
      description = "Password for n8n basic auth";
    };

    basePath = lib.mkOption {
      type = lib.types.str;
      default = "/n8n";
      description = "Base path served via the ingress proxy";
    };

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OIDC authentication (e.g. via Authentik)";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "rave-n8n";
        description = "OAuth2/OIDC client ID";
      };

      clientSecret = lib.mkOption {
        type = lib.types.str;
        default = "n8n-oidc-secret";
        description = "Fallback OAuth2/OIDC client secret";
      };

      clientSecretFile = lib.mkOption {
        type = lib.types.nullOr pathOrString;
        default = null;
        description = "Path to file containing OIDC client secret (preferred for production)";
      };

      issuerUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC issuer URL (e.g. https://auth.example.com/application/o/n8n/)";
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
        description = "OIDC scopes to request";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql.ensureDatabases = mkAfter [ "n8n" ];
    services.postgresql.ensureUsers = mkAfter [ { name = "n8n"; ensureDBOwnership = true; } ];
    systemd.services.postgresql.postStart = mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER n8n PASSWORD '${dbPasswordExpr}';" || true
    '';

    systemd.services.n8n = {
      description = "n8n automation (Docker)";
          wantedBy = [ "multi-user.target" ];
          after = [ "docker.service" "postgresql.service" "docker-pull-n8n.service" ];
          requires = [ "docker.service" "postgresql.service" "docker-pull-n8n.service" ];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = 10;
            ExecStartPre = [
              "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f n8n || true'"
              "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create n8n-data || true'"
            ];
            ExecStart = pkgs.writeShellScript "n8n-start" ''
              set -euo pipefail
${lib.optionalString (cfg.oidc.enable && cfg.oidc.clientSecretFile != null) ''
              if [ -s ${cfg.oidc.clientSecretFile} ]; then
                OIDC_SECRET="$(cat ${cfg.oidc.clientSecretFile} | tr -d '\n')"
              else
                OIDC_SECRET=${lib.escapeShellArg cfg.oidc.clientSecret}
              fi
''}${lib.optionalString (cfg.oidc.enable && cfg.oidc.clientSecretFile == null) ''
              OIDC_SECRET=${lib.escapeShellArg cfg.oidc.clientSecret}
''}
              exec ${pkgs.docker}/bin/docker run \
                --name n8n \
                --rm \
                -p 127.0.0.1:${toString cfg.hostPort}:5678 \
                -v n8n-data:/home/node/.n8n \
                --add-host host.docker.internal:host-gateway \
                -e DB_TYPE=postgresdb \
                -e DB_POSTGRESDB_HOST=${cfg.dbHost} \
                -e DB_POSTGRESDB_PORT=${toString cfg.dbPort} \
                -e DB_POSTGRESDB_DATABASE=n8n \
                -e DB_POSTGRESDB_USER=n8n \
                -e DB_POSTGRESDB_PASSWORD=${dbPasswordExpr} \
                -e N8N_ENCRYPTION_KEY=${cfg.encryptionKey} \
                -e N8N_BASE_PATH=${normalizedBasePath} \
                -e N8N_PATH=${normalizedBasePath} \
                -e WEBHOOK_URL=${normalizedPublicUrl} \
                -e N8N_HOST=localhost \
                -e N8N_PORT=5678 \
                -e N8N_PROTOCOL=https \
                -e N8N_EDITOR_BASE_URL=${normalizedPublicUrl} \
                -e EXECUTIONS_DATA_SAVE_ON_ERROR=all \
                -e EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
                -e EXECUTIONS_DATA_PRUNE=true \
${lib.optionalString (!cfg.oidc.enable) ''                -e N8N_BASIC_AUTH_ACTIVE=true \
                -e N8N_BASIC_AUTH_USER=admin \
                -e N8N_BASIC_AUTH_PASSWORD=${cfg.basicAuthPassword} \
''}${lib.optionalString cfg.oidc.enable ''                -e N8N_AUTH_EXCLUDE_ENDPOINTS="/healthz" \
                -e N8N_USER_MANAGEMENT_DISABLED=false \
                -e N8N_SSO_ENABLED=true \
                -e N8N_SSO_JUST_IN_TIME_PROVISIONING=true \
                -e N8N_SSO_REDIRECT_LOGIN_TO_SSO=true \
                -e EXTERNAL_FRONTEND_HOOKS_URLS="" \
                -e N8N_OIDC_ENABLED=true \
                -e N8N_OIDC_CLIENT_ID=${cfg.oidc.clientId} \
                -e N8N_OIDC_CLIENT_SECRET="$OIDC_SECRET" \
                -e N8N_OIDC_ISSUER_URL=${cfg.oidc.issuerUrl} \
''}${lib.optionalString (cfg.oidc.enable && cfg.oidc.authUrl != "") ''                -e N8N_OIDC_AUTHORIZATION_URL=${cfg.oidc.authUrl} \
''}${lib.optionalString (cfg.oidc.enable && cfg.oidc.tokenUrl != "") ''                -e N8N_OIDC_TOKEN_URL=${cfg.oidc.tokenUrl} \
''}${lib.optionalString (cfg.oidc.enable && cfg.oidc.userInfoUrl != "") ''                -e N8N_OIDC_USERINFO_URL=${cfg.oidc.userInfoUrl} \
''}${lib.optionalString cfg.oidc.enable ''                -e N8N_OIDC_SCOPES="${cfg.oidc.scopes}" \
''}                ${cfg.dockerImage}
            '';
            ExecStop = "${pkgs.docker}/bin/docker stop n8n";
        };
      };

    systemd.services.docker-pull-n8n = {
      description = "Pre-pull n8n Docker image";
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

  };
}
