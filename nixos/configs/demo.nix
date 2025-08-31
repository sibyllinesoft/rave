# nixos/configs/demo.nix
# Demo configuration - minimal services for demonstrations and testing
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules (required for all VMs)
    ../modules/foundation/base.nix
    ../modules/foundation/nix-config.nix
    ../modules/foundation/networking.nix
    
    # Minimal service set for demos
    ../modules/services/gitlab
    
    # Basic security
    ../modules/security/certificates.nix
  ];

  # Demo-specific settings
  networking.hostName = "rave-demo";
  
  # Certificate configuration for demo
  rave.certificates = {
    domain = "rave.local";
    useACME = false; # Self-signed certs for demo
    email = "demo@rave.local";
  };

  # Enable only essential services for demo
  services = {
    postgresql.enable = true;
    nginx.enable = true;
    redis.servers.default.enable = true;
  };

  # Demo-friendly authentication
  security.sudo.wheelNeedsPassword = false;
  services.openssh.settings.PasswordAuthentication = true;

  # Simplified nginx configuration for demo
  services.nginx.virtualHosts."rave.local" = {
    # Enable HTTPS for demo but with simplified config
    forceSSL = true;
    
    # Custom welcome page for demo
    locations."/" = {
      return = lib.mkForce "200 '🚀 Welcome to RAVE Demo System\\n\\nAvailable Services:\\n- GitLab: https://rave.local/gitlab/\\n- Health Check: https://rave.local/-/health\\n\\nDemo System Status: Online'";
      extraConfig = ''
        access_log off;
      '';
    };
    
    # Demo system status endpoint
    locations."/status" = {
      return = "200 '{\"status\": \"online\", \"services\": [\"gitlab\"], \"mode\": \"demo\"}'";
    };
  };

  # Demo networking (open ports needed for demo)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (redirects to HTTPS)
      443   # HTTPS
      8080  # GitLab direct access
    ];
  };

  # Demo-specific environment
  environment.systemPackages = with pkgs; [
    # Demo utilities
    curl
    wget
    jq
    tree
    git
    
    # For demo presentations
    figlet  # ASCII art text
    cowsay  # Fun output formatting
  ];

  # Demo welcome message
  environment.etc."motd".text = ''
    
    ╭──────────────────────────────────────╮
    │         🚀 RAVE Demo System          │
    ╰──────────────────────────────────────╯
    
    Welcome to the RAVE AI Agent Control System Demo!
    
    🔗 Services Available:
    • GitLab:      https://rave.local/gitlab/
    • System:      https://rave.local/status
    • Health:      https://rave.local/-/health
    
    🛠 Demo Commands:
    • systemctl status gitlab     - Check GitLab status  
    • journalctl -u gitlab -f     - Follow GitLab logs
    • curl https://rave.local/status - Check system status
    
    📚 For full documentation, see: docs/
    
  '';

  # Disable complex services not needed for demo
  services.gitlab.extraConfig.registry.enable = false; # Disable container registry
  services.fail2ban.enable = false; # Disable intrusion prevention for demo
  
  # Simpler logging for demo
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=50M
  '';

  # Demo system information service
  systemd.services.demo-info = {
    description = "RAVE Demo Information Service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "demo-info" ''
        #!${pkgs.bash}/bin/bash
        
        echo "🚀 RAVE Demo System initialized at $(date)"
        echo "📊 System Information:"
        echo "   - Hostname: $(hostname)"
        echo "   - IP: $(ip route get 1 | awk '{print $7}' | head -1)"
        echo "   - Memory: $(free -h | grep '^Mem:' | awk '{print $2}') total"
        echo "   - Services: GitLab enabled"
        
        # Create demo status file
        cat > /tmp/demo-status.json << EOF
        {
          "demo": true,
          "status": "ready",
          "services": ["gitlab"],
          "initialized": "$(date -Iseconds)",
          "hostname": "$(hostname)",
          "version": "RAVE Demo v1.0"
        }
        EOF
      '';
    };
  };
}