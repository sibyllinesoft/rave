# P2 Production Observability Configuration  
# Implements Phase P2: CI/CD & Build Automation + Observability
# Extends P1 security foundation with comprehensive monitoring
{ config, pkgs, lib, ... }:

{
  # Import P1 baseline configuration
  imports = [ ./p1-production-config.nix ];
  
  # Override hostname for P2
  networking.hostName = lib.mkForce "rave-p2";
  
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
    
    # P2.3: Basic scrape configurations for system monitoring
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
    ];
    
    # P2.3: Basic alerting rules for system health
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
  
  # P2.3: Enhanced Grafana configuration with Prometheus datasource
  services.grafana.provision.datasources.settings = {
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
  
  # P2.3: Update nginx configuration for internal Prometheus access
  services.nginx.virtualHosts."rave.local".locations = lib.mkMerge [
    {
      # Prometheus endpoint (internal only)
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
  
  # P2.3: SAFE mode memory discipline - limit monitoring service memory usage  
  systemd.services.prometheus.serviceConfig = {
    MemoryMax = "256M";
    CPUQuota = "25%";
    OOMScoreAdjust = "100";  # Prefer killing Prometheus over critical services
  };
  
  systemd.services.grafana.serviceConfig = lib.mkForce {
    MemoryMax = "128M";
    CPUQuota = "15%";
    OOMScoreAdjust = "50";   # Less likely to be killed than Prometheus
  };
  
  # P2.3: Enhanced observability environment setup
  systemd.services.setup-agent-environment.serviceConfig.ExecStart = lib.mkForce (pkgs.writeScript "setup-agent-env-p2" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    # Create directories
    mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
    
    # P2.3: Enhanced observability notice
    cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "📊 RAVE P2 Observability Environment"
echo "===================================="
echo ""
echo "🔒 P1 Security Features (inherited):"
echo "  • SSH key authentication only"
echo "  • Enhanced firewall with rate limiting"
echo "  • Security headers on all HTTPS responses"
echo "  • Kernel hardening and memory protection"
echo ""
echo "📈 P2 Observability Features:"
echo "  • Prometheus metrics collection (3-day retention)"
echo "  • Grafana dashboards and visualization"
echo "  • Node Exporter for system metrics"
echo "  • Memory-disciplined configuration (SAFE mode)"
echo "  • System health alerting rules"
echo ""
echo "🎯 Services & Monitoring:"
echo "  • Vibe Kanban: https://rave.local:3002/"
echo "  • Grafana: https://rave.local:3002/grafana/"
echo "  • Claude Code Router: https://rave.local:3002/ccr-ui/"
echo "  • Prometheus (internal): https://rave.local:3002/prometheus/"
echo ""
echo "📊 Metrics & Alerting:"
echo "  • System health alerts (memory, CPU, services)"
echo "  • Service availability monitoring"
echo "  • Resource usage tracking with limits"
echo ""
echo "🔧 Memory Management (SAFE Mode):"
echo "  • Prometheus: 256M memory limit, 25% CPU"
echo "  • Grafana: 128M memory limit, 15% CPU"
echo "  • 3-day metrics retention for memory efficiency"
echo ""
echo "⚠️ Production Setup Required:"
echo "  • Configure Grafana OIDC authentication"
echo "  • Set up external alerting (email/Slack)"
echo "  • Add more comprehensive dashboards"
echo "  • Configure log aggregation"
echo ""
echo "📖 Next Steps: Advanced monitoring and alerting integration"
WELCOME_EOF
    chmod +x /home/agent/welcome.sh
    
    # Update bashrc with observability context
    echo "" >> /home/agent/.bashrc
    echo "# RAVE P2 Observability Environment" >> /home/agent/.bashrc
    echo "export BROWSER=chromium" >> /home/agent/.bashrc
    echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
    echo "export SAFE=1" >> /home/agent/.bashrc
    echo "export FULL_PIPE=0" >> /home/agent/.bashrc
    echo "export NODE_OPTIONS=\"--max-old-space-size=1536\"" >> /home/agent/.bashrc
    echo "~/welcome.sh" >> /home/agent/.bashrc
    
    # Set secure permissions
    chmod 700 /home/agent/.ssh
    chown -R agent:users /home/agent
    
    echo "P2 observability environment setup complete!"
  '');
}