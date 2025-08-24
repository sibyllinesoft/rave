# P6 Demo Configuration - HTTP only for quick demo
# Based on P6 production but with simplified nginx config without SSL
{ config, pkgs, lib, ... }:

{
  # Import P4 Matrix integration configuration
  imports = [ 
    ./p4-production-config.nix
  ];
  
  # Override hostname for P6 demo
  networking.hostName = lib.mkForce "rave-p6-demo";
  
  # Override nginx config to remove SSL requirements
  services.nginx = lib.mkForce {
    enable = true;
    package = pkgs.nginx;
    
    # Simple HTTP configuration without SSL
    virtualHosts = {
      "localhost" = {
        listen = [{
          addr = "0.0.0.0";
          port = 8080;
          ssl = false;
        }];
        
        locations = {
          "/" = {
            return = "200 'RAVE System Demo - All Services Running!'";
            extraConfig = ''
              add_header Content-Type text/plain;
            '';
          };
          
          "/health" = {
            return = "200 'OK'";
            extraConfig = ''
              add_header Content-Type text/plain;
            '';
          };
          
          "/gitlab/" = {
            proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto http;
            '';
          };
          
          "/prometheus/" = {
            proxyPass = "http://127.0.0.1:9090/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
            '';
          };
          
          "/vibe/" = {
            proxyPass = "http://127.0.0.1:3000/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
            '';
          };
        };
      };
    };
  };
  
  # Ensure all services start correctly
  systemd.services.nginx = {
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
  };
}