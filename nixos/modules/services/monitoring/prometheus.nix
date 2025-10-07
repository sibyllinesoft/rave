# nixos/modules/services/monitoring/prometheus.nix
# Prometheus monitoring configuration - extracted from P2 production config
{ config, pkgs, lib, ... }:

with lib;

{
  # Only configure Prometheus if monitoring is enabled
  config = mkIf config.services.rave.monitoring.enable {
    # P2: Prometheus monitoring with SAFE mode configuration
    services.prometheus = {
      enable = true;
      port = 9090;
      
      # P2: SAFE mode memory-disciplined configuration
      extraFlags = [
        "--storage.tsdb.retention.time=${config.services.rave.monitoring.retention.time}"
        "--storage.tsdb.retention.size=${config.services.rave.monitoring.retention.size}"
        "--query.max-concurrency=2"
        "--query.max-samples=25000000"
        "--web.max-connections=256"
        "--storage.tsdb.wal-compression"
      ];
      
      # Global configuration from P2
      globalConfig = {
        scrape_interval = config.services.rave.monitoring.scrapeInterval;
        evaluation_interval = config.services.rave.monitoring.scrapeInterval;
      };

      # P2: Basic scrape configurations for system monitoring
      scrapeConfigs = [
        # Node exporter for system metrics
        {
          job_name = "node";
          static_configs = [
            {
              targets = [ "localhost:9100" ];
              labels = {
                instance = "rave-vm";
                service = "system";
              };
            }
          ];
          scrape_interval = config.services.rave.monitoring.scrapeInterval;
          metrics_path = "/metrics";
        }
        
        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:9090" ];
              labels = {
                instance = "rave-vm";
                service = "prometheus";
              };
            }
          ];
          scrape_interval = config.services.rave.monitoring.scrapeInterval;
          metrics_path = "/metrics";
        }
      ] ++ optionals config.services.rave.gitlab.enable [
        # GitLab metrics (if GitLab enabled)
        {
          job_name = "gitlab";
          static_configs = [{
            targets = [ "localhost:8080" ];
          }];
          metrics_path = "/gitlab/-/metrics";
          scrape_interval = "30s";
        }
      ];

      # P2: Basic alerting rules for system health
      rules = [
        ''
          groups:
            - name: rave_system_health
              rules:
                - alert: HighMemoryUsage
                  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
                  for: 5m
                  labels:
                    severity: warning
                    service: system
                  annotations:
                    summary: "High memory usage detected"
                    description: "Memory usage is {{ $value }}% on {{ $labels.instance }}"
                
                - alert: HighCPUUsage
                  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                  for: 10m
                  labels:
                    severity: warning
                    service: system
                  annotations:
                    summary: "High CPU usage detected"
                    description: "CPU usage is {{ $value }}% on {{ $labels.instance }}"
                
                - alert: ServiceDown
                  expr: up == 0
                  for: 2m
                  labels:
                    severity: critical
                    service: "{{ $labels.job }}"
                  annotations:
                    summary: "Service is down"
                    description: "{{ $labels.job }} on {{ $labels.instance }} has been down for more than 2 minutes"
        ''
      ];

      # Alertmanager configuration (minimal for development)
      alertmanager = {
        enable = mkDefault false;  # Enable in production with proper config
        port = 9093;
        configuration = {
          global = {
            smtp_smarthost = "localhost:587";
            smtp_from = "alerts@rave.local";
          };
          
          route = {
            group_by = [ "alertname" ];
            group_wait = "10s";
            group_interval = "10s";
            repeat_interval = "1h";
            receiver = "default";
          };
          
          receivers = [{
            name = "default";
            # Configure actual notification methods in production
            # email_configs = [{
            #   to = "admin@rave.local";
            #   subject = "RAVE Alert: {{ .GroupLabels.alertname }}";
            #   body = "{{ range .Alerts }}{{ .Annotations.summary }}: {{ .Annotations.description }}{{ end }}";
            # }];
          }];
        };
      };

    };

    # P2: Enable Node Exporter for system metrics
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes" 
        "meminfo"
        "loadavg"
        "filesystem"
        "diskstats"
        "netdev"
        "cpu"
      ];
    };

    # Configure Nginx for Prometheus metrics
    services.nginx.statusPage = true;
  };
}
