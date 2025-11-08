{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.monitoring;
  baseHttpsPort = toString config.services.rave.ports.https;

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
        static_configs = [{ targets = [ targetStr cfg.prometheus.port ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ targetStr cfg.exporters.node.port ]; }];
      }
    ]
    ++ optionals cfg.exporters.nginx.enable [
      {
        job_name = "nginx";
        static_configs = [{ targets = [ targetStr cfg.exporters.nginx.port ]; }];
      }
    ]
    ++ optionals cfg.exporters.postgres.enable [
      {
        job_name = "postgres";
        static_configs = [{ targets = [ targetStr cfg.exporters.postgres.port ]; }];
      }
    ]
    ++ optionals cfg.exporters.redis.enable [
      {
        job_name = "redis";
        static_configs = [{ targets = [ targetStr cfg.exporters.redis.port ]; }];
      }
    ]
    ++ optionals cfg.nats.enable [
      {
        job_name = "nats";
        static_configs = [{ targets = [ targetStr cfg.nats.metricsPort ]; }];
      }
    ];

  grafanaHost = cfg.nginx.host;
  monitoringProxyEnabled = cfg.nginx.addProxyLocations;

  grafanaLocationAttr = grafanaLocation;
  promLocationAttr = promLocation;

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

      secretKey = mkOption {
        type = types.str;
        default = "grafana-secret-key";
        description = "Grafana secret key for signing cookies.";
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
        description = "Path Grafana/Prometheus are exposed under in nginx.";
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

      nginx = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable nginx exporter scrape target.";
        };
        port = mkOption {
          type = types.int;
          default = 9113;
          description = "Nginx exporter port.";
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

    nginx = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Virtual host key to augment with /grafana and /prometheus locations.";
      };
      addProxyLocations = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to inject nginx proxy locations for Grafana and Prometheus.";
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

    services.prometheus.exporters.nginx = mkIf cfg.exporters.nginx.enable {
      enable = true;
      port = cfg.exporters.nginx.port;
    };

    services.prometheus.exporters.postgres = mkIf cfg.exporters.postgres.enable {
      enable = true;
      port = cfg.exporters.postgres.port;
      dataSourceName = cfg.exporters.postgres.dataSourceName;
    };

    services.prometheus.exporters.redis = mkIf cfg.exporters.redis.enable {
      enable = true;
      port = cfg.exporters.redis.port;
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = grafanaListenPort;
          domain = grafanaDomain;
          root_url = grafanaPublicUrl;
          serve_from_sub_path = true;
        };
        database = {
          inherit (cfg.grafana.database) type host name user password;
        };
        security = {
          admin_user = cfg.grafana.adminUser;
          admin_password = cfg.grafana.adminPassword;
          secret_key = cfg.grafana.secretKey;
          cookie_secure = true;
          cookie_samesite = "strict";
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
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
            password = cfg.grafana.database.password;
          }
        ];
      };
    };

    systemd.services.grafana.after = mkAfter [ "postgresql.service" "generate-localhost-certs.service" ];
    systemd.services.grafana.requires = mkAfter [ "postgresql.service" ];

    services.nginx.virtualHosts."${grafanaHost}".locations."${grafanaLocationAttr}" =
      mkIf monitoringProxyEnabled {
        proxyPass = "http://127.0.0.1:${toString grafanaListenPort}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };

    services.nginx.virtualHosts."${grafanaHost}".locations."${promLocationAttr}" =
      mkIf monitoringProxyEnabled {
        proxyPass = "http://127.0.0.1:${promPortStr}/";
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
  };
}
