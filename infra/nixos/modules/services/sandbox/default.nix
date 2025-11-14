# nixos/modules/services/sandbox/default.nix
# Sandbox management service - extracted from P6 production config
{ config, pkgs, lib, ... }:

with lib;

{
  options = {
    services.rave.sandbox = {
      enable = mkEnableOption "Sandbox VM management for GitLab CI/CD";
      
      maxConcurrent = mkOption {
        type = types.int;
        default = 2;
        description = "Maximum number of concurrent sandbox VMs";
      };
      
      cleanupInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Cleanup interval in seconds";
      };
      
      vmResources = {
        memory = mkOption {
          type = types.str;
          default = "4G";
          description = "Memory allocation per sandbox VM";
        };
        
        cpus = mkOption {
          type = types.int;
          default = 2;
          description = "CPU cores per sandbox VM";
        };
        
        diskSize = mkOption {
          type = types.str;
          default = "20G";
          description = "Disk size per sandbox VM";
        };
      };
      
      networking = {
        sshPortRange = {
          start = mkOption {
            type = types.int;
            default = 2200;
            description = "Start of SSH port range for sandboxes";
          };
          
          end = mkOption {
            type = types.int;
            default = 2299;
            description = "End of SSH port range for sandboxes";
          };
        };
        
        webPortRange = {
          start = mkOption {
            type = types.int;
            default = 3000;
            description = "Start of web port range for sandboxes";
          };
          
          end = mkOption {
            type = types.int;
            default = 3099;
            description = "End of web port range for sandboxes";
          };
        };
      };
    };
  };
  
  config = mkIf config.services.rave.sandbox.enable {
    # P6: Enhanced Docker configuration for sandbox VM hosting
    virtualisation.docker.daemon.settings = mkMerge [
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
    virtualisation.libvirtd = mkMerge [
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
          "MAX_CONCURRENT_SANDBOXES=${toString config.services.rave.sandbox.maxConcurrent}"
          "SANDBOX_CLEANUP_INTERVAL=${toString config.services.rave.sandbox.cleanupInterval}"
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
          sleep ''${SANDBOX_CLEANUP_INTERVAL}
        done
      '';
    };
    
    # P6: Enhanced nginx configuration for sandbox access
    services.nginx.virtualHosts."rave.local".locations = mkMerge [
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
          return = "200 \"Sandbox Manager: OK\"";
          extraConfig = ''
            access_log off;
          '';
        };
      }
    ];
    
    # P6: Enhanced firewall configuration for sandbox networking
    networking.firewall = mkMerge [
      {
        # Sandbox VM SSH ports
        allowedTCPPortRanges = [
          { 
            from = config.services.rave.sandbox.networking.sshPortRange.start; 
            to = config.services.rave.sandbox.networking.sshPortRange.end; 
          }
          { 
            from = config.services.rave.sandbox.networking.webPortRange.start; 
            to = config.services.rave.sandbox.networking.webPortRange.end; 
          }
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
          iptables -A INPUT -p tcp --dport ${toString config.services.rave.sandbox.networking.sshPortRange.start}:${toString config.services.rave.sandbox.networking.sshPortRange.end} -m limit --limit 10/min --limit-burst 5 -j ACCEPT
          iptables -A INPUT -p tcp --dport ${toString config.services.rave.sandbox.networking.sshPortRange.start}:${toString config.services.rave.sandbox.networking.sshPortRange.end} -j DROP
        '';
      }
    ];
    
    # P6: Extended Prometheus monitoring for sandbox metrics
    services.prometheus.scrapeConfigs = mkIf config.services.rave.monitoring.enable (mkAfter [
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
    ]);
    
    # P6: Enhanced system optimization for sandbox workloads
    boot.kernel.sysctl = mkMerge [
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
        "kernel.dmesg_restrict" = mkDefault 1;
      }
    ];
    
    # P6: Additional packages for sandbox management
    environment.systemPackages = with pkgs; [
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
  };
}