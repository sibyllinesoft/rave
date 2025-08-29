# nixos/configs/monitoring-only.nix
# Minimal configuration with only monitoring stack enabled
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix
    
    # Only monitoring service
    ../modules/services/monitoring/default.nix
  ];

  # Enable only monitoring
  services.rave = {
    monitoring = {
      enable = true;
      safeMode = true;  # Memory-disciplined configuration
      retention = {
        time = "7d";      # Week retention for monitoring-only setup
        size = "1GB";     # More storage since it's the only service
      };
      scrapeInterval = "15s";
    };
  };

  # Host configuration
  networking.hostName = lib.mkDefault "rave-monitoring";

  # Minimal nginx for Grafana access
  services.nginx = {
    enable = true;
    virtualHosts."rave.local" = {
      forceSSL = false;
      enableACME = false;
    };
  };

  # Open HTTP port
  networking.firewall.allowedTCPPorts = [ 80 ];

  # Basic user setup
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent - Monitoring Only";
    extraGroups = [ "wheel" ];
    hashedPassword = lib.mkDefault (pkgs.mkPasswd "monitoring");
    shell = pkgs.bash;
  };

  # Basic SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # Monitoring-focused environment
  systemd.services.setup-agent-environment = {
    description = "Setup monitoring-only environment";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    script = ''
      mkdir -p /home/agent/{.config,.ssh}
      cat > /home/agent/welcome.sh << 'EOF'
#!/bin/bash
echo "📊 RAVE Monitoring-Only Environment"
echo "==================================="
echo ""
echo "Services:"
echo "  • Grafana: http://rave.local/grafana/"
echo "  • Prometheus: http://rave.local/prometheus/"
echo ""
echo "Login: agent / monitoring"
EOF
      chmod +x /home/agent/welcome.sh
      echo "~/welcome.sh" >> /home/agent/.bashrc
      chown -R agent:users /home/agent
    '';
  };

  system.stateVersion = "24.11";
}