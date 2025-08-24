# Prometheus Monitoring Configuration for RAVE
# Extracted from P2 configuration for modular architecture
{ config, pkgs, lib, ... }:

{
  # P2.3: Enable Prometheus monitoring with SAFE mode configuration
  services.prometheus = {
    enable = true;
    port = 9090;
    
    # P2.3: SAFE mode memory-disciplined configuration
    extraFlags = [
      "--storage.tsdb.retention.time=3d"
      "--storage.tsdb.retention.size=512MB"
      "--query.max-concurrency=2"
      "--query.max-samples=25000000"
      "--web.max-connections=256"
      "--storage.tsdb.wal-compression"
    ];
    
    # P2.3: Enhanced scrape configurations for system and GitLab monitoring
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
        scrape_interval = "30s";
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
        scrape_interval = "30s";
        metrics_path = "/metrics";
      }
      
      # P3: GitLab metrics monitoring
      {
        job_name = "gitlab";
        static_configs = [
          {
            targets = [ "localhost:9168" ];
            labels = {
              instance = "rave-vm";
              service = "gitlab";
            };
          }
        ];
        scrape_interval = "30s";
        metrics_path = "/metrics";
      }
      
      # P3: GitLab Runner metrics (if available)
      {
        job_name = "gitlab-runner";
        static_configs = [
          {
            targets = [ "localhost:9252" ];  # Default GitLab Runner metrics port
            labels = {
              instance = "rave-vm";
              service = "gitlab-runner";
            };
          }
        ];
        scrape_interval = "30s";
        metrics_path = "/metrics";
      }
    ];
    
    # P2.3: Enhanced alerting rules for system and GitLab health
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
          
          - name: rave_gitlab_health
            rules:
              - alert: GitLabDown
                expr: up{job="gitlab"} == 0
                for: 5m
                labels:
                  severity: critical
                  service: gitlab
                annotations:
                  summary: "GitLab service is down"
                  description: "GitLab has been down for more than 5 minutes"
              
              - alert: GitLabRunnerDown
                expr: up{job="gitlab-runner"} == 0
                for: 5m
                labels:
                  severity: warning
                  service: gitlab-runner
                annotations:
                  summary: "GitLab Runner is down"
                  description: "GitLab Runner has been down for more than 5 minutes"
              
              - alert: GitLabHighMemoryUsage
                expr: gitlab_ruby_sampler_rss_bytes / 1024 / 1024 / 1024 > 6
                for: 10m
                labels:
                  severity: warning
                  service: gitlab
                annotations:
                  summary: "GitLab high memory usage"
                  description: "GitLab is using more than 6GB of memory"
              
              - alert: GitLabDatabaseConnectionsHigh
                expr: gitlab_database_connection_pool_size - gitlab_database_connection_pool_available > 15
                for: 5m
                labels:
                  severity: warning
                  service: gitlab
                annotations:
                  summary: "GitLab database connections high"
                  description: "GitLab is using many database connections"
      ''
    ];
  };
  
  # P2.3: Enable Node Exporter for system metrics
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
  
  # P2.3: SAFE mode memory discipline - limit Prometheus service memory usage  
  systemd.services.prometheus.serviceConfig = {
    MemoryMax = "256M";
    CPUQuota = "25%";
    OOMScoreAdjust = "100";  # Prefer killing Prometheus over critical services
  };
  
  # Node exporter resource limits
  systemd.services.prometheus-node-exporter.serviceConfig = {
    MemoryMax = "64M";
    CPUQuota = "10%";
  };
}