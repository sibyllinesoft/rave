# P6 HTTP Demo Configuration - Working GitLab without SSL
{ config, pkgs, lib, ... }:

{
  # Import P6 but override nginx for HTTP-only demo
  imports = [ 
    ./p6-production-config.nix
  ];
  
  # Override hostname for demo
  networking.hostName = lib.mkForce "rave-demo";
  
  # Override nginx to work without SSL
  services.nginx = lib.mkForce {
    enable = true;
    package = pkgs.nginx;
    
    virtualHosts."localhost" = {
      listen = [{
        addr = "0.0.0.0";
        port = 8080;
        ssl = false;
      }];
      
      locations = {
        "/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
          extraConfig = ''
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Ssl off;
            
            # Increase timeouts for GitLab
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            
            # Handle large uploads
            client_max_body_size 1024m;
          '';
        };
        
        "/health" = {
          return = "200 'RAVE Demo Ready - GitLab HTTP Access Working'";
          extraConfig = ''
            add_header Content-Type text/plain;
            access_log off;
          '';
        };
        
        "/prometheus/" = {
          proxyPass = "http://127.0.0.1:9090/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            rewrite ^/prometheus/(.*) /$1 break;
          '';
        };
      };
    };
  };
  
  # Configure GitLab for HTTP access
  services.gitlab.https = lib.mkForce false;
  services.gitlab.port = lib.mkForce 8080;
}