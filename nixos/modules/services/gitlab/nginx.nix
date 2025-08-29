# nixos/modules/services/gitlab/nginx.nix
# Nginx configuration for GitLab reverse proxy - extracted from P3 production config
{ config, pkgs, lib, ... }:

with lib;

{
  # Only configure nginx if GitLab service is enabled
  config = mkIf config.services.rave.gitlab.enable {
    services.nginx.virtualHosts."${config.services.rave.gitlab.host}" = {
      locations = mkMerge [
        {
          # GitLab main interface - from P3 config
          "/gitlab/" = {
            proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Ssl on;
              
              # GitLab specific headers
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              
              # Handle large file uploads (artifacts, LFS)
              client_max_body_size 1G;
              proxy_request_buffering off;
              proxy_read_timeout 300;
              proxy_connect_timeout 300;
              proxy_send_timeout 300;
            '';
          };
          
          # GitLab redirect
          "= /gitlab" = {
            return = "301 /gitlab/";
          };
          
          # GitLab CI/CD artifacts and LFS - from P3 config
          "~ ^/gitlab/.*/-/(artifacts|archive|raw)/" = {
            proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # Large file handling
              client_max_body_size 10G;
              proxy_request_buffering off;
            '';
          };
          
          # GitLab Container Registry
          "/registry/" = {
            proxyPass = "http://127.0.0.1:5000/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # Registry-specific headers
              proxy_set_header Docker-Distribution-Api-Version registry/2.0;
              
              client_max_body_size 0; # No limit for container images
              chunked_transfer_encoding on;
            '';
          };
          
          # Health check endpoint
          "/health/gitlab" = {
            proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/-/health";
            extraConfig = ''
              access_log off;
              proxy_set_header Host $host;
              
              # Return simplified health status
              proxy_intercept_errors on;
              error_page 200 = @gitlab_healthy;
              error_page 500 502 503 504 = @gitlab_unhealthy;
            '';
          };
          
          "@gitlab_healthy" = {
            return = "200 \"GitLab: OK\"";
          };
          
          "@gitlab_unhealthy" = {
            return = "503 \"GitLab: Unavailable\"";
          };
        }
      ];
    };
  };
}