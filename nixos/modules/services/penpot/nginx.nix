# nixos/modules/services/penpot/nginx.nix
# Nginx configuration for Penpot reverse proxy
{ config, pkgs, lib, ... }:

with lib;

{
  # Only configure nginx if Penpot service is enabled
  config = mkIf config.services.rave.penpot.enable {
    services.nginx.virtualHosts."${config.services.rave.penpot.host}".locations = mkMerge [
        {
          # Penpot main application - frontend at /penpot/
          "/penpot/" = {
            proxyPass = "http://127.0.0.1:3449/";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Ssl on;
              
              # WebSocket support for real-time collaboration
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              
              # Handle large design file uploads
              client_max_body_size 100M;
              proxy_request_buffering off;
              proxy_read_timeout 300;
              proxy_connect_timeout 300;
              proxy_send_timeout 300;
              
              # CORS headers for Penpot
              add_header Access-Control-Allow-Origin "https://${config.services.rave.penpot.host}" always;
              add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS, PATCH" always;
              add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-Auth-Token" always;
              add_header Access-Control-Allow-Credentials "true" always;
              
              # Handle preflight requests
              if ($request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin "https://${config.services.rave.penpot.host}";
                add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS, PATCH";
                add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-Auth-Token";
                add_header Access-Control-Allow-Credentials "true";
                add_header Access-Control-Max-Age 3600;
                add_header Content-Type "text/plain charset=UTF-8";
                add_header Content-Length 0;
                return 204;
              }
            '';
          };
          
          # Penpot redirect (without trailing slash)
          "= /penpot" = {
            return = "301 /penpot/";
          };
          
          # Penpot API endpoints - backend at /api/
          "~ ^/penpot/api/" = {
            proxyPass = "http://127.0.0.1:6060";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Ssl on;
              
              # Rewrite path to remove /penpot prefix for backend
              rewrite ^/penpot(/api/.*)$ $1 break;
              
              # Handle large API payloads (design data)
              client_max_body_size 100M;
              proxy_request_buffering off;
              
              # API timeouts
              proxy_read_timeout 120;
              proxy_connect_timeout 120;
              proxy_send_timeout 120;
              
              # CORS headers for API
              add_header Access-Control-Allow-Origin "https://${config.services.rave.penpot.host}" always;
              add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS, PATCH" always;
              add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-Auth-Token" always;
              add_header Access-Control-Allow-Credentials "true" always;
            '';
          };
          
          # Penpot export service endpoints
          "~ ^/penpot/export/" = {
            proxyPass = "http://127.0.0.1:6061";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # Rewrite path to remove /penpot prefix for exporter
              rewrite ^/penpot(/export/.*)$ $1 break;
              
              # Export service can take time for complex designs
              proxy_read_timeout 600;
              proxy_connect_timeout 300;
              proxy_send_timeout 300;
              
              # Handle large export files
              client_max_body_size 500M;
              proxy_request_buffering off;
              
              # CORS headers for export service
              add_header Access-Control-Allow-Origin "https://${config.services.rave.penpot.host}" always;
              add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
              add_header Access-Control-Allow-Headers "Origin, Content-Type, Accept, Authorization, X-Requested-With" always;
              add_header Access-Control-Allow-Credentials "true" always;
            '';
          };
          
          # Penpot assets and media files
          "~ ^/penpot/assets/" = {
            proxyPass = "http://127.0.0.1:6060";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # Rewrite path to remove /penpot prefix
              rewrite ^/penpot(/assets/.*)$ $1 break;
              
              # Large file handling for design assets
              client_max_body_size 500M;
              proxy_request_buffering off;
              
              # Caching for static assets
              proxy_cache_valid 200 30d;
              proxy_cache_valid 404 1m;
              add_header X-Cache-Status $upstream_cache_status;
              
              # Security headers for assets
              add_header X-Content-Type-Options nosniff;
              add_header X-Frame-Options SAMEORIGIN;
            '';
          };
          
          # Penpot WebSocket connections for real-time collaboration
          "~ ^/penpot/ws" = {
            proxyPass = "http://127.0.0.1:6060";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # WebSocket specific headers
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              
              # Rewrite path to remove /penpot prefix
              rewrite ^/penpot(/ws.*)$ $1 break;
              
              # WebSocket timeouts (keep connections alive)
              proxy_read_timeout 3600s;
              proxy_send_timeout 3600s;
              
              # No buffering for WebSocket
              proxy_buffering off;
            '';
          };
          
          # Health check endpoint for Penpot
          "/health/penpot" = {
            proxyPass = "http://127.0.0.1:6060/api/rpc/command/get-profile";
            extraConfig = ''
              access_log off;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              
              # Return simplified health status for error conditions only
              proxy_intercept_errors on;
              error_page 401 = @penpot_healthy;  # Unauthenticated is still healthy
              error_page 500 502 503 504 = @penpot_unhealthy;
              
              # Quick timeout for health checks
              proxy_connect_timeout 5s;
              proxy_read_timeout 5s;
            '';
          };
          
          "@penpot_healthy" = {
            return = "200 \"Penpot: OK\"";
            extraConfig = "add_header Content-Type text/plain;";
          };
          
          "@penpot_unhealthy" = {
            return = "503 \"Penpot: Unavailable\"";
            extraConfig = "add_header Content-Type text/plain;";
          };
        }
      ];
    
    # Add Penpot-specific nginx configuration
    services.nginx.appendHttpConfig = ''
      # Rate limiting for Penpot API
      limit_req_zone $binary_remote_addr zone=penpot_api:10m rate=30r/s;
      limit_req_zone $binary_remote_addr zone=penpot_upload:10m rate=5r/s;
      
      # Caching for Penpot static assets
      proxy_cache_path /var/cache/nginx/penpot levels=1:2 keys_zone=penpot_assets:10m max_size=1g inactive=30d use_temp_path=off;
    '';
  };
}