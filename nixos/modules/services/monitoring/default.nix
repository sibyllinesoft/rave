# nixos/modules/services/monitoring/default.nix
# Monitoring stack coordination module - extracted from P2 production config
{ config, pkgs, lib, ... }:

with lib;

{
  imports = [
    ./prometheus.nix
    ./grafana.nix
  ];

  options = {
    services.rave.monitoring = {
      enable = mkEnableOption "Prometheus + Grafana monitoring stack";
      
      safeMode = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SAFE mode with memory-disciplined configuration";
      };
      
      retention = {
        time = mkOption {
          type = types.str;
          default = "3d";
          description = "Prometheus data retention time";
        };
        
        size = mkOption {
          type = types.str;
          default = "512MB";
          description = "Prometheus data retention size";
        };
      };
      
      scrapeInterval = mkOption {
        type = types.str;
        default = "30s";
        description = "Default scrape interval";
      };
    };
  };
  
  config = mkIf config.services.rave.monitoring.enable {
    # P2: Observability and Monitoring Stack
    # This module coordinates the monitoring services and ensures they work together

    # Common monitoring configuration
    environment.systemPackages = with pkgs; [
      prometheus
      grafana
    ];

    # Create monitoring user for shared access
    users.users.monitoring = {
      isSystemUser = true;
      group = "monitoring";
      home = "/var/lib/monitoring";
      createHome = true;
    };

    users.groups.monitoring = {};
    
    # Enhanced monitoring system users
    users.users.prometheus.extraGroups = [ "monitoring" ];
    users.users.grafana.extraGroups = [ "monitoring" ];

    # Firewall configuration for monitoring services
    networking.firewall.allowedTCPPorts = [
      3000  # Grafana
      9090  # Prometheus (internal only in production)
      9100  # Node Exporter
    ];

    # Log rotation for monitoring logs
    services.logrotate.settings = {
      prometheus = {
        files = "/var/log/prometheus/*.log";
        frequency = "daily";
        rotate = if config.services.rave.monitoring.safeMode then 7 else 30;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        create = "644 prometheus prometheus";
      };
      
      grafana = {
        files = "/var/log/grafana/*.log";
        frequency = "daily";
        rotate = if config.services.rave.monitoring.safeMode then 7 else 30;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        create = "644 grafana grafana";
      };
    };

    # Nginx configuration for monitoring services - from P2 config
    services.nginx.virtualHosts."rave.local".locations = mkMerge [
      {
        # Grafana dashboard
        "/grafana/" = {
          proxyPass = "http://127.0.0.1:3000/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Handle WebSocket connections for live updates
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };
        
        # Prometheus (internal access only) - from P2
        "/prometheus/" = {
          proxyPass = "http://127.0.0.1:9090/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Restrict access to internal monitoring
            allow 127.0.0.1;
            allow ::1;
            deny all;
          '';
        };
      }
    ];
    
    # Resource limits for monitoring services - SAFE mode from P2
    systemd.services.prometheus.serviceConfig = mkIf config.services.rave.monitoring.safeMode {
      MemoryMax = "256M";
      CPUQuota = "25%";
      OOMScoreAdjust = "100";  # Prefer killing Prometheus over critical services
    };
    
    systemd.services.grafana.serviceConfig = mkIf config.services.rave.monitoring.safeMode {
      MemoryMax = "128M";
      CPUQuota = "15%";
      OOMScoreAdjust = "50";   # Less likely to be killed than Prometheus
    };
  };
}