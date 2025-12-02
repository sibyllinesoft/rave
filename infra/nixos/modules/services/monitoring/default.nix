{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.monitoring;
  baseHttpsPort = toString config.services.rave.ports.https;
  pathOrString = types.either types.path types.str;

  ensureLeadingSlash = path:
    if hasPrefix "/" path then path else "/${path}";

  ensureTrailingSlash = path:
    if hasSuffix "/" path then path else "${path}/";

  normalizePath = path: ensureTrailingSlash (ensureLeadingSlash path);

  pathFromUrl = url:
    let
      matchResult = builtins.match "https?://[^/]+(.*)" url;
      tail = if matchResult == null || matchResult == [] then "/" else builtins.head matchResult;
      cleaned = if tail == "" then "/" else tail;
    in normalizePath cleaned;

  grafanaDomain = cfg.grafana.domain;
  grafanaPublicUrl =
    if cfg.grafana.publicUrl != null then cfg.grafana.publicUrl
    else "https://${grafanaDomain}:${baseHttpsPort}/grafana/";

  grafanaLocation = pathFromUrl grafanaPublicUrl;
  grafanaListenPort = cfg.grafana.httpPort;

  promLocation = normalizePath cfg.prometheus.publicPath;
  promPortStr = toString cfg.prometheus.port;

  targetStr = port: "localhost:${toString port}";

  defaultScrapes =
    [
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ (targetStr cfg.prometheus.port) ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ (targetStr cfg.exporters.node.port) ]; }];
      }
    ]
    ++ optionals cfg.exporters.postgres.enable [
      {
        job_name = "postgres";
        static_configs = [{ targets = [ (targetStr cfg.exporters.postgres.port) ]; }];
      }
    ]
    ++ optionals cfg.exporters.redis.enable [
      {
        job_name = "redis";
        static_configs = [{ targets = [ (targetStr cfg.exporters.redis.port) ]; }];
      }
    ]
    ++ optionals cfg.nats.enable [
      {
        job_name = "nats";
        static_configs = [{ targets = [ (targetStr cfg.nats.metricsPort) ]; }];
      }
    ];

  fileProviderValue = path: "$__file{${path}}";
  postgresExporterNeedsSecret = cfg.exporters.postgres.enable && cfg.exporters.postgres.dsnEnvFile != null;

in
{
  options.services.rave.monitoring = {
    enable = mkEnableOption "Prometheus + Grafana monitoring stack";

    scrapeInterval = mkOption {
      type = types.str;
      default = "30s";
      description = "Default scrape/evaluation interval for Prometheus.";
    };

    retentionTime = mkOption {
      type = types.str;
      default = "3d";
      description = "How long Prometheus should keep samples.";
    };

    grafana = {
      domain = mkOption {
        type = types.str;
        default = "localhost";
        description = "Hostname Grafana should consider canonical (used in links).";
      };

      publicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "External URL for Grafana. When null it is derived from domain + HTTPS port.";
      };

      httpPort = mkOption {
        type = types.int;
        default = 3000;
        description = "Local port Grafana listens on.";
      };

      adminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Default Grafana admin username.";
      };

      adminPassword = mkOption {
        type = types.str;
        default = "admin";
        description = "Default Grafana admin password (override in production).";
      };

      adminPasswordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to a file containing the Grafana admin password (preferred for production).";
      };

      secretKey = mkOption {
        type = types.str;
        default = "grafana-secret-key";
        description = "Grafana secret key for signing cookies.";
      };

      secretKeyFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to a file containing the Grafana secret key.";
      };

      database = {
        type = mkOption {
          type = types.str;
          default = "postgres";
          description = "Grafana database backend.";
        };

        host = mkOption {
          type = types.str;
          default = "localhost:5432";
          description = "Database host:port Grafana should use.";
        };

        name = mkOption {
          type = types.str;
          default = "grafana";
          description = "Database name for Grafana.";
        };

        user = mkOption {
          type = types.str;
          default = "grafana";
          description = "Database user Grafana authenticates as.";
        };

        password = mkOption {
          type = types.str;
          default = "grafana-password";
          description = "Database password Grafana uses (store via sops-nix).";
        };

        passwordFile = mkOption {
          type = types.nullOr pathOrString;
          default = null;
          description = "Path to a file containing the Grafana database password.";
        };
      };

      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable OIDC authentication (e.g. via Authentik)";
        };

        clientId = mkOption {
          type = types.str;
          default = "rave-grafana";
          description = "OAuth2/OIDC client ID";
        };

        clientSecret = mkOption {
          type = types.str;
          default = "grafana-oidc-secret";
          description = "Fallback OAuth2/OIDC client secret";
        };

        clientSecretFile = mkOption {
          type = types.nullOr pathOrString;
          default = null;
          description = "Path to file containing OIDC client secret (preferred for production)";
        };

        name = mkOption {
          type = types.str;
          default = "Authentik";
          description = "Display name for the OAuth provider";
        };

        authUrl = mkOption {
          type = types.str;
          default = "";
          description = "OIDC authorization endpoint";
        };

        tokenUrl = mkOption {
          type = types.str;
          default = "";
          description = "OIDC token endpoint";
        };

        apiUrl = mkOption {
          type = types.str;
          default = "";
          description = "OIDC userinfo endpoint";
        };

        scopes = mkOption {
          type = types.str;
          default = "openid profile email";
          description = "OIDC scopes to request (space-separated)";
        };

        roleAttributePath = mkOption {
          type = types.str;
          default = "contains(groups[*], 'Grafana Admins') && 'Admin' || contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'";
          description = "JMESPath expression to determine user role from OIDC claims";
        };

        allowSignUp = mkOption {
          type = types.bool;
          default = true;
          description = "Allow new users to sign up via OIDC";
        };

        autoLogin = mkOption {
          type = types.bool;
          default = false;
          description = "Automatically redirect to OIDC login";
        };
      };
    };

    prometheus = {
      port = mkOption {
        type = types.int;
        default = 9090;
        description = "Prometheus listening port.";
      };

      publicPath = mkOption {
        type = types.str;
        default = "/prometheus/";
        description = "Path Grafana/Prometheus are exposed under in the ingress proxy.";
      };

      extraScrapeConfigs = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Additional scrape_configs to append to the defaults.";
      };
    };

    exporters = {
      node = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable node exporter.";
        };
        port = mkOption {
          type = types.int;
          default = 9100;
          description = "Node exporter port.";
        };
        collectors = mkOption {
          type = types.listOf types.str;
          default = [ "systemd" "processes" "cpu" "meminfo" "diskstats" "filesystem" ];
          description = "Collectors to enable for node exporter.";
        };
      };

      postgres = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable postgres exporter scrape target.";
        };
        port = mkOption {
          type = types.int;
          default = 9187;
          description = "Postgres exporter port.";
        };
        dataSourceName = mkOption {
          type = types.str;
          default = "postgresql://prometheus:prometheus_pass@localhost:5432/postgres?sslmode=disable";
          description = "DSN for the postgres exporter.";
        };
        dsnEnvFile = mkOption {
          type = types.nullOr pathOrString;
          default = null;
          description = "Environment file that provides DATA_SOURCE_NAME (preferred for secrets).";
        };
      };

      redis = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Redis exporter scrape target.";
        };
        port = mkOption {
          type = types.int;
          default = 9121;
          description = "Redis exporter port.";
        };
      };
    };

    nats = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Scrape the built-in NATS/JetStream monitoring endpoint.";
      };
      metricsPort = mkOption {
        type = types.int;
        default = 7777;
        description = "Port for the NATS monitoring endpoint.";
      };
    };

  };

  config = mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.prometheus.port;
      retentionTime = cfg.retentionTime;
      scrapeConfigs = defaultScrapes ++ cfg.prometheus.extraScrapeConfigs;
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = cfg.scrapeInterval;
      };
    };

    services.prometheus.exporters.node = mkIf cfg.exporters.node.enable {
      enable = true;
      port = cfg.exporters.node.port;
      enabledCollectors = cfg.exporters.node.collectors;
    };

    services.prometheus.exporters.postgres = mkIf cfg.exporters.postgres.enable (
      {
        enable = true;
        port = cfg.exporters.postgres.port;
      }
      // optionalAttrs (cfg.exporters.postgres.dsnEnvFile == null) {
        dataSourceName = cfg.exporters.postgres.dataSourceName;
      }
    );

    services.prometheus.exporters.redis = mkIf cfg.exporters.redis.enable {
      enable = true;
      port = cfg.exporters.redis.port;
    };

    systemd.services.prometheus-postgres-exporter = mkIf postgresExporterNeedsSecret {
      serviceConfig.EnvironmentFile = [ cfg.exporters.postgres.dsnEnvFile ];
    };

    users.users.prometheus-postgres-exporter = mkIf postgresExporterNeedsSecret {
      isSystemUser = true;
      group = "prometheus-postgres-exporter";
    };

    users.groups.prometheus-postgres-exporter = mkIf postgresExporterNeedsSecret {};

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = grafanaListenPort;
          domain = grafanaDomain;
          root_url = grafanaPublicUrl;
          serve_from_sub_path = true;
        };
        database =
          {
            inherit (cfg.grafana.database) type host name user;
          }
          # Use $__file providers when passwordFile is set so the secret stays out of the Nix store.
          # Development builds fall back to the literal password string.
          // optionalAttrs (cfg.grafana.database.passwordFile == null) {
            password = cfg.grafana.database.password;
          }
          // optionalAttrs (cfg.grafana.database.passwordFile != null) {
            password = fileProviderValue cfg.grafana.database.passwordFile;
          };
        security =
          {
            admin_user = cfg.grafana.adminUser;
            cookie_secure = true;
            cookie_samesite = "strict";
          }
          # Literal values keep dev builds simple.
          # Production builds should point at files so the secrets stay out of the Nix store.
          // optionalAttrs (cfg.grafana.adminPasswordFile == null) {
            admin_password = cfg.grafana.adminPassword;
          }
          // optionalAttrs (cfg.grafana.adminPasswordFile != null) {
            admin_password = fileProviderValue cfg.grafana.adminPasswordFile;
          }
          // optionalAttrs (cfg.grafana.secretKeyFile == null) {
            secret_key = cfg.grafana.secretKey;
          }
          // optionalAttrs (cfg.grafana.secretKeyFile != null) {
            secret_key = fileProviderValue cfg.grafana.secretKeyFile;
          };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
      } // optionalAttrs cfg.grafana.oidc.enable {
        "auth.generic_oauth" = {
          enabled = true;
          name = cfg.grafana.oidc.name;
          allow_sign_up = cfg.grafana.oidc.allowSignUp;
          auto_login = cfg.grafana.oidc.autoLogin;
          client_id = cfg.grafana.oidc.clientId;
          scopes = cfg.grafana.oidc.scopes;
          auth_url = cfg.grafana.oidc.authUrl;
          token_url = cfg.grafana.oidc.tokenUrl;
          api_url = cfg.grafana.oidc.apiUrl;
          role_attribute_path = cfg.grafana.oidc.roleAttributePath;
          use_pkce = true;
        } // optionalAttrs (cfg.grafana.oidc.clientSecretFile == null) {
          client_secret = cfg.grafana.oidc.clientSecret;
        } // optionalAttrs (cfg.grafana.oidc.clientSecretFile != null) {
          client_secret = fileProviderValue cfg.grafana.oidc.clientSecretFile;
        };
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${promPortStr}";
            isDefault = true;
          }
          {
            name = "PostgreSQL";
            type = "postgres";
            access = "proxy";
            url = cfg.grafana.database.host;
            database = cfg.grafana.database.name;
            user = cfg.grafana.database.user;
            password =
              if cfg.grafana.database.passwordFile != null
              then fileProviderValue cfg.grafana.database.passwordFile
              else cfg.grafana.database.password;
          }
        ];
      };
    };

    systemd.services.grafana.after = mkAfter [ "postgresql.service" "generate-localhost-certs.service" ];
    systemd.services.grafana.requires = mkAfter [ "postgresql.service" ];

  };
}
