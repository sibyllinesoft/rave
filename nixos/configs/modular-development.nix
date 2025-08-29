# nixos/configs/modular-development.nix
# Modular development configuration with selective service enabling
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix
    
    # Security modules (minimal for development)
    ../modules/security/certificates.nix
    
    # Service modules (selective)
    ../modules/services/monitoring/default.nix
    ../modules/services/gitlab/default.nix
    ../modules/services/matrix/default.nix
    ../modules/services/sandbox/default.nix
    ../modules/services/nats/default.nix
  ];

  # Development-focused service configuration
  services.rave = {
    # P1: Minimal security for development
    # Note: security module not imported, using basic settings
    
    # P2: Monitoring stack (enabled but relaxed)
    monitoring = {
      enable = true;
      safeMode = false;  # More resources for development
      retention = {
        time = "1d";     # Shorter retention for development
        size = "256MB";
      };
      scrapeInterval = "15s";  # More frequent scraping for development
    };
    
    # P3: GitLab CI/CD (with development secrets)
    gitlab = {
      enable = true;
      host = "rave.local";
      useSecrets = false;  # Use plain text secrets for development
      runner = {
        enable = true;
        token = "development-runner-token";
      };
    };
    
    # P4: Matrix communication (disabled for lightweight development)
    matrix = {
      enable = false;  # Disabled to save resources
    };
    
    # P6: Sandbox management (disabled for development)
    sandbox = {
      enable = false;  # Disabled to save resources
    };
    
    # P7: NATS JetStream messaging (enabled for development)
    nats = {
      enable = true;
      serverName = "rave-dev-nats";
      debug = true;  # Enable debug logging for development
      safeMode = false;  # More resources for development
      jetstream = {
        maxMemory = "128MB";
        maxFileStore = "512MB";
      };
      auth = {
        enable = false;  # Disabled for development simplicity
      };
    };
  };

  # Host configuration
  networking.hostName = lib.mkForce "rave-dev";

  # Development nginx configuration (HTTP only)
  services.nginx = {
    enable = true;
    
    virtualHosts."rave.local" = {
      # Development: HTTP only (no SSL)
      forceSSL = lib.mkForce false;
      enableACME = lib.mkForce false;
      
      # Minimal security headers for development
      extraConfig = ''
        add_header X-Content-Type-Options "nosniff";
        add_header X-Frame-Options "SAMEORIGIN";
      '';
    };
  };

  # Open HTTP port only (no HTTPS for development)
  networking.firewall.allowedTCPPorts = [ 80 ];
  
  # Development user configuration (less restrictive)
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent - Development Environment";
    extraGroups = [ "wheel" "docker" "kvm" "libvirtd" ];
    
    # Development: Use plain password for simplicity
    password = "development";
    shell = pkgs.bash;
    
    # Development SSH keys (if needed)
    openssh.authorizedKeys.keys = [
      # Add development SSH keys here
    ];
  };

  # Basic SSH for development (more permissive)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = lib.mkForce true;  # Allowed for development
      PubkeyAuthentication = true;
      MaxAuthTries = lib.mkForce 5;               # More attempts for development
      X11Forwarding = lib.mkForce true;           # Allowed for development
    };
  };

  # Development environment setup
  systemd.services.setup-agent-environment = {
    description = "Setup development agent environment";
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
      
      # Development environment welcome script
      cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "🛠️ RAVE Modular Development Environment"
echo "======================================"
echo ""
echo "🏗️ Development Configuration:"
echo "  • Lightweight: Only essential services enabled"
echo "  • HTTP Only: No SSL/TLS overhead"
echo "  • Relaxed Security: Development-friendly settings"
echo "  • Fast Iteration: Shorter retention, faster scraping"
echo ""
echo "✅ Enabled Services:"
echo "  • Foundation: Base system, networking, Nix configuration"
echo "  • Monitoring: Prometheus + Grafana (relaxed mode)"
echo "  • GitLab: CI/CD with simplified authentication"
echo "  • NATS JetStream: Native messaging with debug logging"
echo ""
echo "❌ Disabled Services (to save resources):"
echo "  • Security Hardening: Minimal security for development"
echo "  • Matrix: Communication service disabled"
echo "  • Sandbox Management: VM provisioning disabled"
echo ""
echo "🎯 Services & Access:"
echo "  • Vibe Kanban: http://rave.local/"
echo "  • Grafana: http://rave.local/grafana/"
echo "  • Claude Code Router: http://rave.local/ccr-ui/"
echo "  • GitLab: http://rave.local/gitlab/"
echo "  • Prometheus: http://rave.local/prometheus/"
echo "  • NATS Monitoring: http://rave.local/nats/ (Server: rave-dev-nats:4222)"
echo ""
echo "🔧 Development Features:"
echo "  • Plain text secrets (no sops-nix complexity)"
echo "  • Password + SSH key authentication"
echo "  • Relaxed resource limits"
echo "  • Fast monitoring refresh rates"
echo "  • X11 forwarding enabled"
echo ""
echo "⚙️ Configuration:"
echo "  • File: nixos/configs/modular-development.nix"
echo "  • Enable more services by setting .enable = true"
echo "  • Switch to production config for full security"
echo ""
echo "📝 Development Notes:"
echo "  • Use 'development' as password for agent user"
echo "  • All secrets are plain text (development-* values)"
echo "  • GitLab runner uses development token"
echo "  • Monitoring retention is 1 day only"
echo ""
echo "🚀 To enable additional services:"
echo "  services.rave.matrix.enable = true;"
echo "  services.rave.sandbox.enable = true;"
echo "  services.rave.security.enable = true;"
echo ""
WELCOME_EOF
      chmod +x /home/agent/welcome.sh
      
      # Update bashrc with development context
      echo "" >> /home/agent/.bashrc
      echo "# RAVE Modular Development Environment" >> /home/agent/.bashrc
      echo "export BROWSER=chromium" >> /home/agent/.bashrc
      echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
      echo "export SAFE=0" >> /home/agent/.bashrc
      echo "export FULL_PIPE=1" >> /home/agent/.bashrc
      echo "export NODE_OPTIONS=\"--max-old-space-size=2048\"" >> /home/agent/.bashrc
      echo "~/welcome.sh" >> /home/agent/.bashrc
      
      # Set permissions
      chmod 755 /home/agent/.ssh  # Less restrictive for development
      chown -R agent:users /home/agent
      
      echo "Modular development environment setup complete!"
    '';
  };

  # Additional development tools
  environment.systemPackages = with pkgs; [
    # Development tools
    git
    vim
    curl
    wget
    jq
    htop
    tree
    
    # Build tools
    gnumake
    gcc
    
    # Container tools
    docker
    docker-compose
  ];

  # System configuration
  system.stateVersion = "24.11";
}