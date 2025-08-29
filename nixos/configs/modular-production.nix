# nixos/configs/modular-production.nix
# Modular production configuration using extracted service modules
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix
    
    # Security modules
    ../modules/security/certificates.nix
    ../modules/security/hardening.nix
    
    # Service modules
    ../modules/services/monitoring/default.nix
    ../modules/services/gitlab/default.nix
    ../modules/services/matrix/default.nix
    ../modules/services/sandbox/default.nix
    ../modules/services/nats/default.nix
  ];

  # Enable all services for production
  services.rave = {
    # P1: Security hardening
    security = {
      enable = true;
      ssh.enable = true;
      firewall.enable = true;
      auditd.enable = true;
      fail2ban.enable = true;
    };
    
    # P2: Monitoring stack
    monitoring = {
      enable = true;
      safeMode = true;  # Memory-disciplined configuration
      retention = {
        time = "3d";
        size = "512MB";
      };
      scrapeInterval = "30s";
    };
    
    # P3: GitLab CI/CD
    gitlab = {
      enable = true;
      host = "rave.local";
      useSecrets = true;  # Use sops-nix secrets
      runner = {
        enable = true;
        token = ""; # Set via secrets
      };
    };
    
    # P4: Matrix communication
    matrix = {
      enable = true;
      serverName = "rave.local";
      useSecrets = true;  # Use sops-nix secrets
      oidc = {
        enable = true;
        gitlabUrl = "https://rave.local/gitlab";
      };
      federation.enable = false;  # Disabled for security
    };
    
    # P6: Sandbox management
    sandbox = {
      enable = true;
      maxConcurrent = 2;
      cleanupInterval = 300;
      vmResources = {
        memory = "4G";
        cpus = 2;
        diskSize = "20G";
      };
    };
    
    # P7: NATS JetStream messaging
    nats = {
      enable = true;
      serverName = "rave-prod-nats";
      debug = false;
      safeMode = true;  # Production resource limits
      jetstream = {
        maxMemory = "512MB";
        maxFileStore = "2GB";
      };
      limits = {
        maxConnections = 100000;
        maxPayload = 2097152; # 2MB for production
      };
      auth = {
        enable = true;
        users = [
          {
            name = "gitlab";
            password = ""; # Set via secrets
            publish = ["gitlab.*" "build.*" "deploy.*"];
            subscribe = ["gitlab.*" "build.*" "deploy.*"];
          }
          {
            name = "matrix";
            password = ""; # Set via secrets
            publish = ["matrix.*" "notifications.*"];
            subscribe = ["matrix.*" "notifications.*"];
          }
          {
            name = "monitoring";
            password = ""; # Set via secrets
            publish = ["metrics.*" "alerts.*"];
            subscribe = ["metrics.*" "alerts.*"];
          }
        ];
      };
    };
  };

  # Host configuration
  networking.hostName = lib.mkDefault "rave-modular";

  # Enhanced nginx configuration with security headers (P4 consolidation)
  services.nginx = {
    enable = true;
    
    virtualHosts."rave.local" = {
      # SSL configuration
      forceSSL = lib.mkDefault true;
      enableACME = lib.mkDefault false; # Use manual certs for development
      
      # Global security headers applied to all responses from P4
      extraConfig = lib.mkAfter ''
        # Global security headers applied to all responses
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;  
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;
      '';
    };
  };

  # Open HTTP/HTTPS ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  
  # System user configuration with enhanced security (P1 based)
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent - Production Modular Environment";
    extraGroups = [ "wheel" "docker" "kvm" "libvirtd" ];
    hashedPassword = null;  # SSH key only
    password = null;
    shell = pkgs.bash;
    
    # SSH public keys will be configured via sops-nix or manually
    openssh.authorizedKeys.keys = [
      # Add actual team SSH public keys here before production deployment
      "# WARNING: Configure actual SSH keys before production use"
    ];
  };

  # Environment setup service
  systemd.services.setup-agent-environment = {
    description = "Setup modular agent environment";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      #!${pkgs.bash}/bin/bash
      set -e
      
      # Create directories
      mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
      
      # Modular environment welcome script
      cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "🔧 RAVE Modular Production Environment"
echo "====================================="
echo ""
echo "🏗️ Modular Architecture:"
echo "  • Foundation: Base system, networking, Nix configuration"
echo "  • Security: Enhanced SSH, firewall, auditing, fail2ban"
echo "  • Monitoring: Prometheus + Grafana with SAFE mode"
echo "  • GitLab: CI/CD with Docker + KVM runner support"
echo "  • Matrix: Synapse homeserver with OIDC integration"
echo "  • NATS JetStream: Native messaging with authenticated users"
echo "  • Sandbox: VM management for GitLab CI/CD testing"
echo ""
echo "🎯 Services & Access:"
echo "  • Vibe Kanban: https://rave.local/"
echo "  • Grafana: https://rave.local/grafana/"
echo "  • Claude Code Router: https://rave.local/ccr-ui/"
echo "  • GitLab: https://rave.local/gitlab/"
echo "  • Element (Matrix): https://rave.local/element/"
echo "  • Matrix API: https://rave.local/matrix/"
echo "  • NATS Monitoring: https://rave.local/nats/ (Server: rave-prod-nats:4222)"
echo "  • Prometheus (internal): https://rave.local/prometheus/"
echo "  • Sandbox Status: https://rave.local/sandbox/status"
echo ""
echo "🔧 Configuration Features:"
echo "  • Modular service architecture"
echo "  • Independent service enable/disable"
echo "  • Comprehensive options system"
echo "  • Production-ready security defaults"
echo "  • Resource-optimized configurations"
echo "  • Integrated secrets management"
echo ""
echo "⚙️ Module Management:"
echo "  • Security hardening: services.rave.security.*"
echo "  • Monitoring stack: services.rave.monitoring.*" 
echo "  • GitLab CI/CD: services.rave.gitlab.*"
echo "  • Matrix comms: services.rave.matrix.*"
echo "  • Sandbox mgmt: services.rave.sandbox.*"
echo ""
echo "🔐 Security Features:"
echo "  • SSH key authentication only"
echo "  • Enhanced firewall with rate limiting"
echo "  • Comprehensive audit logging"
echo "  • Fail2ban intrusion prevention"
echo "  • Kernel and system hardening"
echo ""
echo "📊 Resource Management:"
echo "  • SAFE mode memory limits"
echo "  • Service-specific resource quotas"
echo "  • Automatic log rotation"
echo "  • Efficient monitoring retention"
echo ""
echo "📖 Modular Benefits:"
echo "  • Independent service management"
echo "  • Clear separation of concerns"
echo "  • Easier maintenance and updates"
echo "  • Flexible deployment configurations"
echo "  • Better testing and validation"
echo ""
WELCOME_EOF
      chmod +x /home/agent/welcome.sh
      
      # Update bashrc with modular context
      echo "" >> /home/agent/.bashrc
      echo "# RAVE Modular Environment" >> /home/agent/.bashrc
      echo "export BROWSER=chromium" >> /home/agent/.bashrc
      echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
      echo "export SAFE=1" >> /home/agent/.bashrc
      echo "export FULL_PIPE=0" >> /home/agent/.bashrc
      echo "export NODE_OPTIONS=\"--max-old-space-size=1536\"" >> /home/agent/.bashrc
      echo "~/welcome.sh" >> /home/agent/.bashrc
      
      # Set secure permissions
      chmod 700 /home/agent/.ssh
      chown -R agent:users /home/agent
      
      echo "Modular production environment setup complete!"
    '';
  };

  # System configuration
  system.stateVersion = "24.11";
}