# Grafana Visualization Configuration for RAVE
# Extracted from P2 configuration for modular architecture
{ config, pkgs, lib, ... }:

{
  # P2.3: Enhanced Grafana configuration with Prometheus datasource
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3030;
        domain = "rave.local";
        root_url = "https://rave.local:3002/grafana/";
        serve_from_sub_path = true;
      };
      
      # Basic authentication for now - OIDC can be configured later
      security = {
        admin_user = "admin";
        admin_password = "admin";  # Change in production
        secret_key = "CHANGE_THIS_IN_PRODUCTION";  # Should use sops secret
      };
      
      # Disable anonymous access
      "auth.anonymous" = {
        enabled = false;
      };
      
      # Database configuration (using PostgreSQL)
      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
        ssl_mode = "disable";
      };
      
      # P3: Enhanced logging for GitLab integration debugging
      log = {
        mode = "console file";
        level = "info";
      };
      
      # Feature flags
      feature_toggles = {
        enable = "publicDashboards";
      };
      
      # Plugin configuration
      plugins = {
        allow_loading_unsigned_plugins = "";
        enable_alpha = false;
      };
      
      # Session configuration
      session = {
        provider = "file";
        cookie_name = "grafana_sess";
        cookie_secure = true;
        session_life_time = 86400;  # 24 hours
      };
    };
    
    # Provision datasources
    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
          jsonData = {
            timeInterval = "30s";
            queryTimeout = "60s";
            httpMethod = "POST";
          };
        }
      ];
    };
    
    # P3: Provision default dashboards for GitLab monitoring
    provision.dashboards.settings = {
      apiVersion = 1;
      providers = [
        {
          name = "RAVE System Dashboards";
          type = "file";
          folder = "System Monitoring";
          options = {
            path = "/var/lib/grafana/dashboards/system";
          };
        }
        {
          name = "RAVE GitLab Dashboards";
          type = "file";
          folder = "GitLab Monitoring";
          options = {
            path = "/var/lib/grafana/dashboards/gitlab";
          };
        }
      ];
    };
  };
  
  # P3: Apply memory limits to Grafana service
  systemd.services.grafana.serviceConfig = lib.mkForce {
    MemoryMax = "128M";
    CPUQuota = "15%";
    OOMScoreAdjust = "50";   # Less likely to be killed than Prometheus
    
    # Security hardening
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadWritePaths = [ "/var/lib/grafana" "/var/log/grafana" ];
    PrivateTmp = true;
    NoNewPrivileges = true;
  };
  
  # P3: Create dashboard directories and example dashboards
  systemd.services.setup-grafana-dashboards = {
    description = "Setup Grafana dashboards for RAVE";
    wantedBy = [ "multi-user.target" ];
    before = [ "grafana.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "setup-grafana-dashboards" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Create dashboard directories
        mkdir -p /var/lib/grafana/dashboards/{system,gitlab}
        
        # System monitoring dashboard
        cat > /var/lib/grafana/dashboards/system/system-overview.json << 'SYSTEM_DASHBOARD_EOF'
{
  "dashboard": {
    "id": null,
    "title": "RAVE System Overview",
    "tags": ["rave", "system"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
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
        "fieldConfig": {
          "defaults": {
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
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
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
SYSTEM_DASHBOARD_EOF
        
        # GitLab monitoring dashboard
        cat > /var/lib/grafana/dashboards/gitlab/gitlab-overview.json << 'GITLAB_DASHBOARD_EOF'
{
  "dashboard": {
    "id": null,
    "title": "RAVE GitLab Overview", 
    "tags": ["rave", "gitlab"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "GitLab Service Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"gitlab\"}",
            "legendFormat": "GitLab"
          }
        ],
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "GitLab Runner Status",
        "type": "stat", 
        "targets": [
          {
            "expr": "up{job=\"gitlab-runner\"}",
            "legendFormat": "Runner"
          }
        ],
        "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
      },
      {
        "id": 3,
        "title": "GitLab Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "gitlab_ruby_sampler_rss_bytes / 1024 / 1024",
            "legendFormat": "GitLab RSS (MB)"
          }
        ],
        "yAxes": [
          {"label": "Memory (MB)"}
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s"
  }
}
GITLAB_DASHBOARD_EOF
        
        # Set proper permissions
        chown -R grafana:grafana /var/lib/grafana/dashboards
        chmod -R 755 /var/lib/grafana/dashboards
        
        echo "Grafana dashboards setup complete!"
      '';
    };
  };
}