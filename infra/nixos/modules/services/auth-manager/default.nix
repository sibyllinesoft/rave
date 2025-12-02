{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.auth-manager;

  secretSatisfied = value: file: (value != null) || (file != null);

  listenPort =
    let
      parts = lib.splitString ":" cfg.listenAddress;
      maybePort = lib.lists.last parts;
    in lib.toInt (if maybePort == "" then "8088" else maybePort);

in {
  options.services.rave.auth-manager = {
    enable = mkEnableOption "Auth Manager user provisioning service";

    package = mkOption {
      type = types.package;
      default = pkgs.auth-manager;
      description = "Auth Manager binary to run.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = ":8088";
      description = "Address/port the HTTP server should bind (e.g. 0.0.0.0:8088).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the firewall for the Auth Manager listen port.";
    };

    databaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional PostgreSQL URL. When null, the in-memory store is used.";
    };

    webhookSecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shared secret for validating Authentik webhook requests.";
    };

    webhookSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the webhook secret.";
    };

    mattermost = {
      url = mkOption {
        type = types.str;
        default = "https://localhost:8443/mattermost";
        description = "Public Mattermost URL.";
      };

      internalUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:8065";
        description = "Internal Mattermost base URL for API calls.";
      };

      adminToken = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Mattermost admin/bot token for user provisioning.";
      };

      adminTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the Mattermost admin/bot token.";
      };
    };

    n8n = {
      enable = mkEnableOption "n8n SSO integration";

      url = mkOption {
        type = types.str;
        default = "https://localhost:8443/n8n";
        description = "Public n8n URL.";
      };

      internalUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:5678";
        description = "Internal n8n base URL for API calls.";
      };

      ownerEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "n8n owner account email for user management.";
      };

      ownerEmailFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the n8n owner email.";
      };

      ownerPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "n8n owner account password for user management.";
      };

      ownerPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the n8n owner password.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = secretSatisfied cfg.mattermost.adminToken cfg.mattermost.adminTokenFile;
        message = "services.rave.auth-manager.mattermost.adminToken or adminTokenFile must be provided.";
      }
    ];

    systemd.services.auth-manager = {
      description = "Auth Manager - Authentik to Mattermost user provisioning";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/auth-manager";
        Restart = "on-failure";
        RestartSec = 5;
        # Security hardening
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        Environment =
          [
            "AUTH_MANAGER_LISTEN_ADDR=${cfg.listenAddress}"
            "AUTH_MANAGER_MATTERMOST_URL=${cfg.mattermost.url}"
            "AUTH_MANAGER_MATTERMOST_INTERNAL_URL=${cfg.mattermost.internalUrl}"
          ]
          ++ lib.optional (cfg.databaseUrl != null) "AUTH_MANAGER_DATABASE_URL=${cfg.databaseUrl}"
          ++ lib.optional (cfg.webhookSecret != null) "AUTH_MANAGER_WEBHOOK_SECRET=${cfg.webhookSecret}"
          ++ lib.optional (cfg.webhookSecretFile != null) "AUTH_MANAGER_WEBHOOK_SECRET_FILE=${cfg.webhookSecretFile}"
          ++ lib.optional (cfg.mattermost.adminToken != null) "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN=${cfg.mattermost.adminToken}"
          ++ lib.optional (cfg.mattermost.adminTokenFile != null) "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN_FILE=${cfg.mattermost.adminTokenFile}"
          # n8n configuration
          ++ lib.optional cfg.n8n.enable "AUTH_MANAGER_N8N_ENABLED=true"
          ++ lib.optional cfg.n8n.enable "AUTH_MANAGER_N8N_URL=${cfg.n8n.url}"
          ++ lib.optional cfg.n8n.enable "AUTH_MANAGER_N8N_INTERNAL_URL=${cfg.n8n.internalUrl}"
          ++ lib.optional (cfg.n8n.ownerEmail != null) "AUTH_MANAGER_N8N_OWNER_EMAIL=${cfg.n8n.ownerEmail}"
          ++ lib.optional (cfg.n8n.ownerEmailFile != null) "AUTH_MANAGER_N8N_OWNER_EMAIL_FILE=${cfg.n8n.ownerEmailFile}"
          ++ lib.optional (cfg.n8n.ownerPassword != null) "AUTH_MANAGER_N8N_OWNER_PASS=${cfg.n8n.ownerPassword}"
          ++ lib.optional (cfg.n8n.ownerPasswordFile != null) "AUTH_MANAGER_N8N_OWNER_PASS_FILE=${cfg.n8n.ownerPasswordFile}";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ listenPort ];
  };
}
