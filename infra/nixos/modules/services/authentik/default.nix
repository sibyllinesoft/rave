{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types mkDefault optionalString;
  cfg = config.services.rave.authentik;

  pathOrString = types.either types.path types.str;

  hostFromUrl = url:
    let matchResult = builtins.match "https?://([^/:]+).*" url;
    in if matchResult == null || matchResult == [] then null else builtins.head matchResult;

  schemeFromUrl = url:
    let matchResult = builtins.match "([^:]+)://.*" url;
    in if matchResult == null || matchResult == [] then "https" else builtins.head matchResult;

  pathFromUrl = url:
    let
      normalized = if url == null then "" else if lib.hasSuffix "/" url then url else "${url}/";
      matchResult = builtins.match "https?://[^/]+(.*)" normalized;
      tail =
        if matchResult == null || matchResult == [] then "/"
        else
          let candidate = builtins.head matchResult;
          in if candidate == "" then "/" else candidate;
    in tail;

  publicHost = hostFromUrl cfg.publicUrl;
  publicScheme = schemeFromUrl cfg.publicUrl;
  publicPath = pathFromUrl cfg.publicUrl;

  blueprintsPath = cfg.blueprintsPath or ./blueprints;

in {
  options.services.rave.authentik = {
    enable = mkEnableOption "Authentik identity provider (native NixOS module)";

    environmentFile = mkOption {
      type = types.nullOr pathOrString;
      default = if config ? sops.secrets then (config.sops.secrets."authentik/env".path or null) else null;
      description = "Environment file containing AUTHENTIK_* secrets (usually provided by sops-nix).";
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
      description = "Loopback port that exposes Authentik metrics.";
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
      description = "Authentik log level.";
    };

    bootstrap = {
      email = mkOption {
        type = types.str;
        default = "admin@example.com";
        description = "Bootstrap administrator email address.";
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
    };

    redis = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Redis host.";
      };
      port = mkOption {
        type = types.int;
        default = 6379;
        description = "Redis port.";
      };
      database = mkOption {
        type = types.int;
        default = 12;
        description = "Redis database number used by Authentik.";
      };
    };

    email = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP notifications.";
      };
      host = mkOption {
        type = types.str;
        default = "smtp.example.com";
        description = "SMTP host.";
      };
      port = mkOption {
        type = types.int;
        default = 587;
        description = "SMTP port.";
      };
      username = mkOption {
        type = types.str;
        default = "";
        description = "SMTP username (password supplied via environmentFile).";
      };
      useTls = mkOption {
        type = types.bool;
        default = true;
        description = "Use TLS for SMTP.";
      };
      fromAddress = mkOption {
        type = types.str;
        default = "noreply@example.com";
        description = "From address used by Authentik emails.";
      };
      fromName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional display name for email sender.";
      };
    };

    allowedEmails = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Optional allowlist of user emails allowed to sign in.";
    };

    allowedDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Optional allowlist of domains allowed to sign in.";
    };

    extraSettings = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = "Free-form Authentik settings merged into generated config.";
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to expose Authentik through the built-in nginx helper.";
      };
      enableACME = mkOption {
        type = types.bool;
        default = false;
        description = "Enable ACME for the nginx helper.";
      };
      host = mkOption {
        type = types.str;
        default = mkDefault "auth.localtest.me";
        description = "Hostname served by the nginx helper.";
      };
    };

    blueprintsPath = mkOption {
      type = types.path;
      default = ./blueprints;
      description = "Path containing Authentik blueprint YAML files to apply declaratively.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [{
        assertion = cfg.environmentFile != null;
        message = "services.rave.authentik.environmentFile must be set (usually a sops-nix secret).";
      }];

      services.authentik = {
        enable = true;
        environmentFile = cfg.environmentFile;
        nginx = {
          enable = cfg.nginx.enable;
          enableACME = cfg.nginx.enableACME;
          host = cfg.nginx.host;
        };
        settings = mkMerge [
          {
            log_level = cfg.logLevel;
            default_user_enabled = cfg.bootstrap.enableDefaultUser;
            default_http_scheme = publicScheme;
            default_http_host = if publicHost != null then publicHost else cfg.rootDomain;
            default_http_port = cfg.defaultExternalPort;
            root_domain = cfg.rootDomain;
            cookie_domain = if cfg.cookieDomain != null then cfg.cookieDomain else if publicHost != null then publicHost else cfg.rootDomain;
            avatars = "gravatar";
            disable_startup_analytics = true;
            listen = {
              http = "0.0.0.0:${toString cfg.hostPort}";
              metrics = "0.0.0.0:${toString cfg.metricsPort}";
            };
            postgresql = {
              host = cfg.database.host;
              port = cfg.database.port;
              name = cfg.database.name;
              user = cfg.database.user;
            };
            redis = {
              host = cfg.redis.host;
              port = cfg.redis.port;
              db = cfg.redis.database;
            };
            email = mkIf cfg.email.enable (mkMerge [
              {
                host = cfg.email.host;
                port = cfg.email.port;
                username = cfg.email.username;
                use_tls = cfg.email.useTls;
                from = cfg.email.fromAddress;
              }
              (mkIf (cfg.email.fromName != null) { from_name = cfg.email.fromName; })
            ]);
          }
          cfg.extraSettings
        ];
      };

      systemd.services.authentik-apply-blueprints = {
        description = "Apply Authentik blueprints declaratively";
        wantedBy = [ "multi-user.target" ];
        after = [ "authentik-worker.service" "authentik.service" ];
        requires = [ "authentik.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "authentik";
          WorkingDirectory = "/var/lib/authentik";
        };
        path = [ pkgs.findutils pkgs.gnused pkgs.coreutils pkgs.authentik ];
        script = ''
          set -euo pipefail
          if [ ! -d ${blueprintsPath} ]; then
            echo "[authentik-blueprints] no blueprints directory at ${blueprintsPath}, skipping"
            exit 0
          fi
          found=false
          for f in ${blueprintsPath}/*.yaml ${blueprintsPath}/*.yml; do
            if [ ! -f "$f" ]; then continue; fi
            found=true
            echo "[authentik-blueprints] applying $f"
            ak apply_blueprint "$f"
          done
          if [ "$found" = false ]; then
            echo "[authentik-blueprints] no blueprint files to apply"
          fi
        '';
      };
    }
  ]);
}
