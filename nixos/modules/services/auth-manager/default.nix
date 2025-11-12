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
    enable = mkEnableOption "Auth Manager bridge service";

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

    sourceIdp = mkOption {
      type = types.str;
      default = "gitlab";
      description = "Informational label for the upstream IdP (passed via AUTH_MANAGER_SOURCE_IDP).";
    };

    databaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional PostgreSQL URL. When null, the in-memory store is used.";
    };

    signingKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Inline signing key used to mint JWTs.";
    };

    signingKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the signing key.";
    };

    pomeriumSharedSecret = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Inline shared secret that matches Pomerium's JWT assertion secret.";
    };

    pomeriumSharedSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the Pomerium shared secret.";
    };

    mattermost = {
      url = mkOption {
        type = types.str;
        default = "http://127.0.0.1:8065";
        description = "Mattermost base URL used by Auth Manager.";
      };

      adminToken = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Mattermost admin/bot token.";
      };

      adminTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing the Mattermost admin/bot token.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = secretSatisfied cfg.signingKey cfg.signingKeyFile;
        message = "services.rave.auth-manager.signingKey or signingKeyFile must be provided.";
      }
      {
        assertion = secretSatisfied cfg.pomeriumSharedSecret cfg.pomeriumSharedSecretFile;
        message = "services.rave.auth-manager.pomeriumSharedSecret or pomeriumSharedSecretFile must be provided.";
      }
      {
        assertion = secretSatisfied cfg.mattermost.adminToken cfg.mattermost.adminTokenFile;
        message = "services.rave.auth-manager.mattermost.adminToken or adminTokenFile must be provided.";
      }
    ];

    systemd.services.auth-manager = {
      description = "Auth Manager Bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/auth-manager";
        Restart = "on-failure";
        Environment =
          [
            "AUTH_MANAGER_LISTEN_ADDR=${cfg.listenAddress}"
            "AUTH_MANAGER_MATTERMOST_URL=${cfg.mattermost.url}"
            "AUTH_MANAGER_SOURCE_IDP=${cfg.sourceIdp}"
          ]
          ++ lib.optional (cfg.databaseUrl != null) "AUTH_MANAGER_DATABASE_URL=${cfg.databaseUrl}"
          ++ lib.optional (cfg.signingKey != null) "AUTH_MANAGER_SIGNING_KEY=${cfg.signingKey}"
          ++ lib.optional (cfg.signingKeyFile != null) "AUTH_MANAGER_SIGNING_KEY_FILE=${cfg.signingKeyFile}"
          ++ lib.optional (cfg.pomeriumSharedSecret != null) "AUTH_MANAGER_POMERIUM_SHARED_SECRET=${cfg.pomeriumSharedSecret}"
          ++ lib.optional (cfg.pomeriumSharedSecretFile != null) "AUTH_MANAGER_POMERIUM_SHARED_SECRET_FILE=${cfg.pomeriumSharedSecretFile}"
          ++ lib.optional (cfg.mattermost.adminToken != null) "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN=${cfg.mattermost.adminToken}"
          ++ lib.optional (cfg.mattermost.adminTokenFile != null) "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN_FILE=${cfg.mattermost.adminTokenFile}";
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ listenPort ];
  };
}
