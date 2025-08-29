# nixos/modules/services/monitoring/grafana.nix
# Grafana dashboard configuration
{ config, pkgs, lib, ... }:

{
  # Grafana configuration
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        domain = "rave.local";
        root_url = "https://rave.local/grafana/";
        serve_from_sub_path = true;
      };

      # Database configuration (using SQLite for simplicity, PostgreSQL for production)
      database = {
        type = "sqlite3";
        path = "/var/lib/grafana/grafana.db";
      };

      # Authentication configuration
      auth = {
        disable_login_form = false;
        oauth_auto_login = false;
      };

      # Security configuration
      security = {
        admin_user = "admin";
        admin_password = "admin"; # Change in production
        secret_key = "grafana-secret-key"; # Change in production
        cookie_secure = true;
        cookie_samesite = "strict";
      };

      # Analytics and reporting
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };

      # Plugin configuration
      plugins = {
        enable_alpha = true;
      };

      # SMTP configuration (for alerts)
      smtp = {
        enabled = false;
        host = "localhost:587";
        user = "";
        password = "";
        from_address = "grafana@rave.local";
        from_name = "RAVE Grafana";
      };
    };

    # Provision datasources
    provision = {
      enable = true;
      
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
          jsonData = {
            httpMethod = "POST";
            exemplarTraceIdDestinations = [];
          };
        }
        {
          name = "PostgreSQL";
          type = "postgres";
          access = "proxy";
          url = "localhost:5432";
          database = "postgres";
          user = "grafana";
          secureJsonData = {
            password = "grafana-db-password"; # Use sops-nix in production
          };
          jsonData = {
            sslmode = "disable";
            postgresVersion = 1300;
            timescaledb = false;
          };
        }
      ];

      # Provision dashboards
      dashboards.settings.providers = [
        {
          name = "RAVE Dashboards";
          type = "file";
          updateIntervalSeconds = 30;
          options.path = "/var/lib/grafana/dashboards";
          disableDeletion = false;
          editable = true;
        }
      ];
    };
  };

  # Create dashboard directory and copy dashboards
  systemd.services.grafana-setup-dashboards = {
    description = "Setup Grafana dashboards";
    wantedBy = [ "grafana.service" ];
    before = [ "grafana.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/lib/grafana/dashboards
      
      # Create dashboard directory (dashboards will be created inline below)
      # Note: External dashboards directory not yet implemented
      
      # Create default system dashboard if none exists
      cat > /var/lib/grafana/dashboards/system-overview.json << 'EOF'
      {
        "dashboard": {
          "id": null,
          "title": "RAVE System Overview",
          "tags": ["rave", "system"],
          "timezone": "browser",
          "refresh": "30s",
          "time": {
            "from": "now-1h",
            "to": "now"
          },
          "panels": [
            {
              "id": 1,
              "title": "CPU Usage",
              "type": "stat",
              "targets": [
                {
                  "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                  "legendFormat": "CPU Usage %"
                }
              ],
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
            },
            {
              "id": 2,
              "title": "Memory Usage",
              "type": "stat",
              "targets": [
                {
                  "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
                  "legendFormat": "Memory Usage %"
                }
              ],
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
            },
            {
              "id": 3,
              "title": "Service Status",
              "type": "stat",
              "targets": [
                {
                  "expr": "up",
                  "legendFormat": "{{job}}"
                }
              ],
              "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
            }
          ]
        }
      }
      EOF
      
      chown -R grafana:grafana /var/lib/grafana/dashboards
    '';
  };

  # Create grafana user for PostgreSQL access
  services.postgresql.ensureUsers = [{
    name = "grafana";
    ensureDBOwnership = false;
  }];

  # Grant necessary permissions to grafana user
  services.postgresql.initialScript = pkgs.writeText "grafana-init.sql" ''
    GRANT CONNECT ON DATABASE postgres TO grafana;
    GRANT USAGE ON SCHEMA public TO grafana;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;
  '';
}