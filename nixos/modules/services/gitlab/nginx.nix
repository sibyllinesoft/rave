# nixos/modules/services/gitlab/nginx.nix
# Nginx configuration for GitLab reverse proxy - extracted from P3 production config
{ config, pkgs, lib, ... }:

with lib;

{
  # Only configure nginx if GitLab service is enabled
  config = mkIf config.services.rave.gitlab.enable
    (let
      host = config.services.rave.gitlab.host;
      gitlabPackage = config.services.gitlab.packages.gitlab;
    in {
      services.nginx.virtualHosts."${host}".locations."/gitlab/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;

          # GitLab specific headers
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_cache_bypass $http_upgrade;

          # Preserve sub-path context for relative_url_root
          proxy_set_header X-Script-Name /gitlab;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;

          # File upload support
          client_max_body_size 10G;
          proxy_connect_timeout 300s;
          proxy_send_timeout 300s;
          proxy_read_timeout 300s;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."= /gitlab" = {
        return = "301 /gitlab/";
      };

      services.nginx.virtualHosts."${host}".locations."~ ^/gitlab/assets/(.*)$" = {
        alias = "${gitlabPackage}/share/gitlab/public/assets/$1";
        extraConfig = ''
          expires 1y;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."~ ^/gitlab/(-/.*)$" = {
        alias = "${gitlabPackage}/share/gitlab/public$1";
        extraConfig = ''
          expires 1y;
          try_files $uri =404;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."~ ^/gitlab/(uploads|files)/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header X-Script-Name /gitlab;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."~ ^/gitlab/.*/-/(artifacts|archive|raw)/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header X-Script-Name /gitlab;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;

          client_max_body_size 10G;
          proxy_request_buffering off;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."/registry/" = {
        proxyPass = "http://127.0.0.1:5000/";
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;

          proxy_set_header Docker-Distribution-Api-Version registry/2.0;

          client_max_body_size 0; # No limit for container images
          chunked_transfer_encoding on;
        '';
      };

      services.nginx.virtualHosts."${host}".locations."/health/gitlab" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/-/health";
        extraConfig = ''
          access_log off;
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;

          proxy_intercept_errors on;
          error_page 500 502 503 504 = @gitlab_unhealthy;
        '';
      };
      services.nginx.virtualHosts."${host}".locations."@gitlab_unhealthy" = {
        return = "503 \"GitLab: Unavailable\"";
      };
    });
}
