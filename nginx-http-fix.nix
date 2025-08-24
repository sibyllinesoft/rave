# Quick HTTP-only nginx fix for GitLab demo
{ config, pkgs, lib, ... }:

{
  # Override nginx to work without SSL for demo
  services.nginx = lib.mkForce {
    enable = true;
    package = pkgs.nginx;
    
    virtualHosts = {
      "default" = {
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
              
              # GitLab specific headers
              proxy_set_header X-Forwarded-Host $http_host;
              proxy_set_header X-Forwarded-Server $host;
              proxy_pass_header Server;
              
              # Increase timeouts for GitLab
              proxy_connect_timeout 300s;
              proxy_send_timeout 300s;
              proxy_read_timeout 300s;
              
              # Handle large uploads
              client_max_body_size 1024m;
            '';
          };
          
          "/health" = {
            return = "200 'RAVE System OK - GitLab Ready'";
            extraConfig = ''
              add_header Content-Type text/plain;
            '';
          };
          
          "/prometheus/" = {
            proxyPass = "http://127.0.0.1:9090/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto http;
              
              # Remove /prometheus prefix when forwarding
              rewrite ^/prometheus/(.*) /$1 break;
            '';
          };
        };
      };
    };
  };
}