# RAVE Demo Ready Configuration - HTTP-only for immediate access
{ config, pkgs, lib, ... }:

{
  # Import P6 base configuration but override nginx
  imports = [ 
    ./p6-production-config.nix
    ./nginx-http-fix.nix  # Override nginx with HTTP-only config
  ];
  
  # Override hostname for demo
  networking.hostName = lib.mkForce "rave-demo";
  
  # Ensure GitLab is configured for HTTP access
  services.gitlab = lib.mkMerge [
    {
      # Override any HTTPS requirements for demo
      https = lib.mkForce false;
      port = lib.mkForce 8080;
      
      extraConfig = {
        # Disable HTTPS redirects for demo
        gitlab = {
          https = false;
          port = 8080;
          host = "localhost";
        };
        
        # Allow HTTP for demo purposes
        omniauth = {
          allow_single_sign_on = false;
          block_auto_created_users = false;
        };
      };
    }
  ];
  
  # Add a startup message
  systemd.services.demo-ready = {
    description = "RAVE Demo Ready Notification";
    after = [ "gitlab.service" "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "demo-ready" ''
        sleep 10  # Wait for services to stabilize
        echo "🎉 RAVE DEMO IS READY!"
        echo "GitLab: http://localhost:8080/"
        echo "Prometheus: http://localhost:8080/prometheus/"
        echo "Health Check: http://localhost:8080/health"
      '';
    };
  };
}