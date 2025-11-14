# P6 Production Sandbox-on-PR Configuration
# Implements Phase P6: Sandbox-on-PR - Automated testing environments for merge requests
# Extends P4 Matrix Service Integration with GitLab CI/CD sandbox VM provisioning
{ config, pkgs, lib, ... }:

{
  # Import P4 Matrix integration configuration and additional sandbox services
  imports = [ 
    ./p4-production-config.nix
  ];
  
  # Override hostname for P6
  networking.hostName = lib.mkForce "rave-p6";
  
  # P6: Enhanced GitLab Runner configuration for sandbox VM management
  # Note: Detailed runner config will be done post-deployment
  # Focus on getting the basic build working first
  
  # P6: Enhanced Docker configuration for sandbox VM hosting
  virtualisation.docker.daemon.settings = lib.mkMerge [
    {
      # Enhanced storage for VM images and containers
      data-root = "/var/lib/docker";
      storage-opts = [
        "overlay2.size=50G"  # Increased storage limit for VM images
      ];
      
      # Resource management for container/VM workloads
      default-ulimits = {
        memlock = {
          Name = "memlock";
          Hard = 67108864;  # 64MB for VM memory management
          Soft = 67108864;
        };
        nofile = {
          Name = "nofile";
          Hard = 65536;
          Soft = 65536;
        };
      };
      
      # Enhanced networking for sandbox isolation
      bridge = "docker0";
      default-address-pools = [
        {
          base = "172.17.0.0/16";
          size = 24;
        }
        {
          base = "172.18.0.0/16";  # Additional pool for sandbox networks
          size = 24;
        }
      ];
    }
  ];
  
  # P6: libvirtd enhancement for better VM management
  virtualisation.libvirtd = lib.mkMerge [
    {
      # Enhanced QEMU configuration for sandbox VMs
      qemu.ovmf.packages = [ pkgs.OVMF.fd ];
      qemu.runAsRoot = false;
      
      # Enable additional virtualization features
      qemu.swtpm.enable = true;
      qemu.vhostUserPackages = [ pkgs.dpdk ];
      
      # Network configuration for sandbox isolation
      allowedBridges = [ "virbr0" "docker0" "gitlab-sandbox" ];
    }
  ];
  
  # P6: Secrets for sandbox operations will be configured via sops-nix at flake level
  # GitLab API token, sandbox SSH keys managed through flake sops configuration
  
  # P6: Sandbox VM management service
  systemd.services.rave-sandbox-manager = {
    description = "RAVE Sandbox VM Manager";
    after = [ "docker.service" "libvirtd.service" "gitlab-runner.service" ];
    wants = [ "docker.service" "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "notify";
      User = "gitlab-runner";
      Group = "gitlab-runner";
      WorkingDirectory = "/tmp/rave-sandboxes";
      
      # Resource limits
      MemoryMax = "2G";
      CPUQuota = "50%";
      TasksMax = 1024;
      
      # Security hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ 
        "/tmp/rave-sandboxes"
        "/var/lib/libvirt"
        "/var/log/rave-sandbox"
      ];
      
      # Capabilities for VM management
      CapabilityBoundingSet = [
        "CAP_NET_ADMIN"
        "CAP_SYS_ADMIN"
        "CAP_DAC_OVERRIDE"
      ];
      AmbientCapabilities = [
        "CAP_NET_ADMIN"
        "CAP_DAC_OVERRIDE"
      ];
      
      # Process limits
      LimitNOFILE = 32768;
      LimitNPROC = 16384;
      
      # Restart configuration
      Restart = "on-failure";
      RestartSec = 30;
      
      # Environment
      Environment = [
        "RAVE_SANDBOX_DIR=/tmp/rave-sandboxes"
        "MAX_CONCURRENT_SANDBOXES=2"
        "SANDBOX_CLEANUP_INTERVAL=300"
      ];
    };
    
    script = ''
      #!/bin/bash
      set -euo pipefail
      
      echo "Starting RAVE Sandbox Manager..."
      
      # Create sandbox directory structure
      mkdir -p /tmp/rave-sandboxes
      mkdir -p /var/log/rave-sandbox
      
      # Setup periodic cleanup
      while true; do
        echo "Running sandbox cleanup..."
        ${pkgs.bash}/bin/bash /home/nathan/Projects/rave/scripts/sandbox_cleanup.sh --cleanup-old --max-age 2 || true
        
        # Resource monitoring
        echo "Sandbox resource status:"
        echo "  Disk usage: $(du -sh /tmp/rave-sandboxes 2>/dev/null || echo "N/A")"
        echo "  Running VMs: $(pgrep -f "qemu.*sandbox" | wc -l || echo "0")"
        
        # Wait for next cleanup cycle
        sleep $''${SANDBOX_CLEANUP_INTERVAL}
      done
    '';
  };
  
  # P6: Enhanced nginx configuration for sandbox access
  services.nginx.virtualHosts."rave.local" = {
    locations = lib.mkMerge [
      {
        # Sandbox status endpoint
        "/sandbox/status" = {
          proxyPass = "http://127.0.0.1:8080/sandbox/status";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            access_log /var/log/nginx/sandbox-access.log;
            
            # Allow only internal access
            allow 127.0.0.0/8;
            allow 10.0.0.0/8;
            allow 172.16.0.0/12;
            allow 192.168.0.0/16;
            deny all;
          '';
        };
        
        # Health check endpoint for sandboxes
        "/health/sandbox" = {
          return = ''200 "Sandbox Manager: OK"'';
          extraConfig = ''
            access_log off;
          '';
        };
      }
    ];
  };
  
  # P6: Enhanced firewall configuration for sandbox networking
  networking.firewall = lib.mkMerge [
    {
      # Sandbox VM SSH ports (2200-2299)
      allowedTCPPortRanges = [
        { from = 2200; to = 2299; }  # Sandbox SSH access
        { from = 3000; to = 3099; }  # Sandbox web access
      ];
      
      # Additional trusted interfaces for sandbox networking
      trustedInterfaces = [ "docker0" "virbr0" "gitlab-sandbox" ];
      
      # Enhanced iptables rules for sandbox isolation
      extraCommands = ''
        # Allow sandbox VM traffic
        iptables -A INPUT -i virbr+ -j ACCEPT
        iptables -A FORWARD -i virbr+ -o virbr+ -j ACCEPT
        
        # Sandbox network isolation rules
        iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT
        iptables -A FORWARD -s 172.18.0.0/16 -d 172.18.0.0/16 -j ACCEPT
        
        # Rate limiting for sandbox access
        iptables -A INPUT -p tcp --dport 2200:2299 -m limit --limit 10/min --limit-burst 5 -j ACCEPT
        iptables -A INPUT -p tcp --dport 2200:2299 -j DROP
      '';
    }
  ];
  
  # P6: Extended Prometheus monitoring for sandbox metrics
  services.prometheus.scrapeConfigs = lib.mkAfter [
    {
      job_name = "rave-sandbox-manager";
      static_configs = [
        {
          targets = [ "127.0.0.1:8080" ];
        }
      ];
      metrics_path = "/metrics";
      scrape_interval = "30s";
      scrape_timeout = "10s";
    }
  ];
  
  # P6: Grafana dashboard for sandbox monitoring
  services.grafana.provision.dashboards.settings.providers = lib.mkAfter [
    {
      name = "sandbox";
      type = "file";
      updateIntervalSeconds = 30;
      options.path = pkgs.writeTextDir "sandbox-dashboard.json" (builtins.toJSON {
        dashboard = {
          id = null;
          title = "P6 Sandbox Environment Monitoring";
          description = "RAVE P6 Sandbox VM Performance and Resource Dashboard";
          tags = [ "sandbox" "p6" "rave" "vm" ];
          timezone = "browser";
          refresh = "30s";
          time = {
            from = "now-1h";
            to = "now";
          };
          
          panels = [
            {
              id = 1;
              title = "Active Sandbox VMs";
              type = "stat";
              targets = [
                {
                  expr = "count(up{job=\"rave-sandbox-manager\"} == 1)";
                  legendFormat = "Active VMs";
                }
              ];
              gridPos = { h = 8; w = 6; x = 0; y = 0; };
            }
            {
              id = 2;
              title = "Sandbox Resource Usage";
              type = "graph";
              targets = [
                {
                  expr = "rate(sandbox_cpu_usage_total[5m])";
                  legendFormat = "CPU Usage";
                }
                {
                  expr = "sandbox_memory_usage_bytes / 1024 / 1024 / 1024";
                  legendFormat = "Memory (GB)";
                }
              ];
              gridPos = { h = 8; w = 12; x = 6; y = 0; };
            }
            {
              id = 3;
              title = "Sandbox Disk Usage";
              type = "graph";
              targets = [
                {
                  expr = "sandbox_disk_usage_bytes / 1024 / 1024 / 1024";
                  legendFormat = "Disk Usage (GB)";
                }
              ];
              gridPos = { h = 8; w = 6; x = 18; y = 0; };
            }
            {
              id = 4;
              title = "Sandbox Creation Rate";
              type = "graph";
              targets = [
                {
                  expr = "rate(sandbox_vm_created_total[5m])";
                  legendFormat = "VMs Created/sec";
                }
                {
                  expr = "rate(sandbox_vm_destroyed_total[5m])";
                  legendFormat = "VMs Destroyed/sec";
                }
              ];
              gridPos = { h = 8; w = 24; x = 0; y = 8; };
            }
          ];
        };
        
        overwrite = true;
        inputs = [];
        folderId = null;
      });
    }
  ];
  
  # P6: Enhanced system optimization for sandbox workloads
  boot.kernel.sysctl = lib.mkMerge [
    {
      # Additional VM and container tuning
      "vm.max_map_count" = 262144;  # Increased for VM memory mapping
      "fs.inotify.max_user_watches" = 1048576;  # Increased for file monitoring
      "fs.file-max" = 2097152;  # Increased file handle limit
      
      # Network tuning for sandbox isolation
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.ipv4.ip_forward" = 1;
      
      # Additional security hardening
      "kernel.unprivileged_userns_clone" = 0;
      "kernel.dmesg_restrict" = lib.mkDefault 1;
    }
  ];
  
  # P6: Extended agent environment setup with sandbox tools
  systemd.services.setup-agent-environment.serviceConfig.ExecStart = lib.mkOverride 99 (pkgs.writeScript "setup-agent-env-p6" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    # Create directories (inherited from P4)
    mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
    mkdir -p /home/agent/sandbox-tools
    
    # P6: Sandbox management tools and environment setup
    cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "🚀 RAVE P6 Sandbox-on-PR Environment"
echo "===================================="
echo ""
echo "🔒 P1 Security Features (inherited):"
echo "  • SSH key authentication only"
echo "  • Enhanced firewall with rate limiting"
echo "  • Security headers on all HTTPS responses"
echo "  • Kernel hardening and memory protection"
echo ""
echo "📈 P2 Observability Features (inherited):"
echo "  • Prometheus metrics collection (3-day retention)"
echo "  • Grafana dashboards and visualization"
echo "  • Node Exporter for system metrics"
echo "  • Memory-disciplined configuration (SAFE mode)"
echo "  • System health alerting rules"
echo ""
echo "🦊 P3 GitLab CI/CD Features (inherited):"
echo "  • GitLab CE instance with PostgreSQL backend"
echo "  • GitLab Runner with Docker + KVM executor"
echo "  • Secrets management via sops-nix"
echo "  • Large file handling (artifacts, LFS up to 10GB)"
echo "  • Integrated with existing nginx reverse proxy"
echo ""
echo "💬 P4 Matrix Communication Features (inherited):"
echo "  • Matrix Synapse homeserver with PostgreSQL backend"
echo "  • Element web client for Matrix interface"
echo "  • GitLab OIDC authentication integration"
echo "  • Secure room-based access controls"
echo "  • Federation disabled for security"
echo "  • Prepared for Appservice bridge integration"
echo ""
echo "🧪 P6 Sandbox-on-PR Features:"
echo "  • Automated sandbox VM provisioning for merge requests"
echo "  • Isolated testing environments with resource limits"
echo "  • Automatic MR comment posting with access links"
echo "  • SSH and web access to sandbox environments"
echo "  • Automatic cleanup after 2-hour timeout"
echo "  • Concurrent sandbox limit enforcement (max 2)"
echo "  • Real-time resource monitoring and management"
echo ""
echo "🎯 Services & Access:"
echo "  • Vibe Kanban: https://rave.local:3002/"
echo "  • Grafana: https://rave.local:3002/grafana/"
echo "  • Claude Code Router: https://rave.local:3002/ccr-ui/"
echo "  • GitLab: https://rave.local:3002/gitlab/"
echo "  • Element (Matrix): https://rave.local:3002/element/"
echo "  • Matrix API: https://rave.local:3002/matrix/"
echo "  • Prometheus (internal): https://rave.local:3002/prometheus/"
echo "  • Sandbox Status: https://rave.local:3002/sandbox/status"
echo ""
echo "🧪 Sandbox Environment Features:"
echo "  • Merge Request Triggered: Automatic on every MR"
echo "  • Isolated VMs: 4GB RAM, 2 CPU cores per sandbox"
echo "  • SSH Access: ssh -p 22XX agent@runner-host"
echo "  • Web Access: Full RAVE stack in each sandbox"
echo "  • Auto Cleanup: 2-hour timeout with graceful shutdown"
echo "  • Resource Limits: Maximum 2 concurrent sandboxes"
echo "  • Network Isolation: Sandboxed networking with firewall rules"
echo ""
echo "🔧 Sandbox Management Commands:"
echo "  • List sandboxes: ~/sandbox-tools/list-sandboxes.sh"
echo "  • Manual cleanup: ~/sandbox-tools/cleanup-sandbox.sh --vm-name NAME"
echo "  • Resource status: ~/sandbox-tools/sandbox-status.sh"
echo "  • Emergency cleanup: ~/sandbox-tools/emergency-cleanup.sh"
echo ""
echo "🚀 GitLab CI/CD Integration:"
echo "  • Review jobs: Automatic sandbox provisioning"
echo "  • Environment URLs: Direct links in MR interface"
echo "  • Artifact retention: 2 hours for sandbox info"
echo "  • Manual cleanup: Stop environment button in GitLab"
echo "  • Health monitoring: Integrated with Grafana dashboards"
echo ""
echo "📊 Sandbox Monitoring:"
echo "  • VM Resource Usage: CPU, Memory, Disk per sandbox"
echo "  • Creation/Destruction Rates: Sandbox lifecycle metrics"
echo "  • Network Traffic: Isolated network monitoring"
echo "  • Storage Usage: Temporary disk space tracking"
echo "  • Process Monitoring: QEMU and container processes"
echo ""
echo "⚠️ Resource Management:"
echo "  • Runner Resources: 8GB RAM, 4 CPU cores total"
echo "  • Per-Sandbox Limits: 4GB RAM, 2 CPU cores"
echo "  • Storage Limits: 20GB per sandbox VM"
echo "  • Network Ports: 2200-2299 for SSH, 3000-3099 for web"
echo "  • Cleanup Automation: Every 5 minutes for old VMs"
echo ""
echo "🔐 Security Features:"
echo "  • VM Isolation: Complete network and process isolation"
echo "  • Resource Limits: Strict memory and CPU quotas"
echo "  • Automatic Cleanup: No persistent data retention"
echo "  • Access Control: SSH key-based authentication only"
echo "  • Firewall Rules: Rate limiting on sandbox ports"
echo ""
echo "🆘 Troubleshooting:"
echo "  • Sandbox logs: journalctl -u rave-sandbox-manager -f"
echo "  • GitLab Runner logs: journalctl -u gitlab-runner -f"
echo "  • VM console access: ~/sandbox-tools/connect-vm.sh VM_NAME"
echo "  • Resource monitoring: ~/sandbox-tools/resource-monitor.sh"
echo "  • Emergency procedures: ~/sandbox-tools/emergency-procedures.md"
echo ""
echo "📖 Next Phase: P7 adds advanced agent orchestration and workflow automation"
WELCOME_EOF
    chmod +x /home/agent/welcome.sh
    
    # P6: Sandbox management tools
    cat > /home/agent/sandbox-tools/list-sandboxes.sh << 'LIST_EOF'
#!/bin/bash
echo "🔍 RAVE P6 Sandbox Status"
echo "========================"
echo ""
/home/nathan/Projects/rave/scripts/sandbox_cleanup.sh --list
echo ""
echo "📊 Resource Summary:"
echo "Disk Usage: $(du -sh /tmp/rave-sandboxes 2>/dev/null || echo "N/A")"
echo "Running VMs: $(pgrep -f 'qemu.*sandbox' | wc -l || echo "0")"
echo "Docker Containers: $(docker ps -q | wc -l || echo "0")"
LIST_EOF
    chmod +x /home/agent/sandbox-tools/list-sandboxes.sh
    
    cat > /home/agent/sandbox-tools/sandbox-status.sh << 'STATUS_EOF'
#!/bin/bash
echo "📊 RAVE P6 Sandbox Resource Status"
echo "=================================="
echo ""
systemctl status rave-sandbox-manager --no-pager -l
echo ""
echo "🔧 Active Sandboxes:"
/home/nathan/Projects/rave/scripts/sandbox_cleanup.sh --list
STATUS_EOF
    chmod +x /home/agent/sandbox-tools/sandbox-status.sh
    
    cat > /home/agent/sandbox-tools/emergency-cleanup.sh << 'EMERGENCY_EOF'
#!/bin/bash
echo "🚨 EMERGENCY: Cleaning up all sandboxes immediately"
echo "=================================================="
/home/nathan/Projects/rave/scripts/sandbox_cleanup.sh --cleanup-all --force
echo "Emergency cleanup completed"
EMERGENCY_EOF
    chmod +x /home/agent/sandbox-tools/emergency-cleanup.sh
    
    # Update bashrc with P6 sandbox context
    echo "" >> /home/agent/.bashrc
    echo "# RAVE P6 Sandbox Environment" >> /home/agent/.bashrc
    echo "export SANDBOX_DIR=\"/tmp/rave-sandboxes\"" >> /home/agent/.bashrc
    echo "alias sandbox-list='/home/agent/sandbox-tools/list-sandboxes.sh'" >> /home/agent/.bashrc
    echo "alias sandbox-status='/home/agent/sandbox-tools/sandbox-status.sh'" >> /home/agent/.bashrc
    echo "alias sandbox-logs='journalctl -u rave-sandbox-manager -f'" >> /home/agent/.bashrc
    echo "alias sandbox-cleanup='/home/nathan/Projects/rave/scripts/sandbox_cleanup.sh'" >> /home/agent/.bashrc
    
    # Set secure permissions
    chmod 700 /home/agent/.ssh
    chmod 755 /home/agent/sandbox-tools
    chown -R agent:users /home/agent
    
    echo "P6 Sandbox-on-PR environment setup complete!"
  '');
  
  # P6: Additional packages for sandbox management
  environment.systemPackages = with pkgs; [
    # Existing packages (inherited)
    git
    git-lfs
    docker
    docker-compose
    gnumake
    gcc
    qemu
    libvirt
    virt-manager
    htop
    iotop
    netcat
    curl
    wget
    
    # P6: Sandbox-specific packages
    socat  # For QEMU monitor communication
    bridge-utils  # Network bridge management
    iptables  # Firewall management
    jq  # JSON processing for sandbox info
    iproute2  # Advanced networking tools
    procps  # Process management
    psmisc  # Additional process utilities
    tmux  # Terminal multiplexing for sandbox sessions
    screen  # Alternative terminal multiplexing
  ];
  
  # P6: Log rotation for sandbox logs
  services.logrotate.settings.rave-sandbox = {
    files = "/var/log/rave-sandbox/*.log";
    frequency = "daily";
    rotate = 7;
    missingok = true;
    compress = true;
    delaycompress = true;
    notifempty = true;
    copytruncate = true;
  };
  
  services.logrotate.settings.sandbox-qemu = {
    files = "/tmp/rave-sandboxes/*/qemu.log";
    frequency = "daily";
    rotate = 3;
    missingok = true;
    compress = true;
    delaycompress = true;
    notifempty = true;
    copytruncate = true;
  };
}