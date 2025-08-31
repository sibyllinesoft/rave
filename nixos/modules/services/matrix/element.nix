# nixos/modules/services/matrix/element.nix
# Element Web client configuration for Matrix
{ config, pkgs, lib, ... }:

let
  # Element Web configuration
  elementConfig = pkgs.writeText "element-config.json" ''
    {
      "default_server_config": {
        "m.homeserver": {
          "base_url": "https://rave.local/matrix/",
          "server_name": "rave.local"
        },
        "m.identity_server": {
          "base_url": "https://vector.im"
        }
      },
      "default_country_code": "US",
      "show_labs_settings": true,
      "features": {
        "feature_new_spinner": true,
        "feature_pinning": true,
        "feature_custom_status": true,
        "feature_custom_tags": true,
        "feature_state_counters": true
      },
      "default_federate": true,
      "default_theme": "light",
      "room_directory": {
        "servers": [
          "rave.local"
        ]
      },
      "welcome_user_id": "@admin:rave.local",
      "map_style_url": "https://api.maptiler.com/maps/streets/style.json?key=YOUR_API_KEY_HERE",
      "branding": {
        "welcome_background_url": null,
        "auth_header_logo_url": null,
        "auth_footer_links": []
      },
      "oidc_static_registration_info": {
        "issuer": "https://rave.local/gitlab",
        "client_name": "Element",
        "client_id": "element-web",
        "response_types": ["code"],
        "grant_types": ["authorization_code", "refresh_token"],
        "redirect_uris": ["https://rave.local/element/"],
        "token_endpoint_auth_method": "client_secret_post"
      }
    }
  '';

  # Custom Element build with our configuration
  elementWithConfig = pkgs.element-web.override {
    conf = elementConfig;
  };
in
{
  # Nginx configuration for Element Web client
  services.nginx.virtualHosts."rave.local".locations = {
    # Element Web client
    "/element/" = {
      alias = "${elementWithConfig}/";
      index = "index.html";
      tryFiles = "$uri $uri/ /element/index.html";
      extraConfig = ''
        # Security headers
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
          expires 1y;
          add_header Cache-Control "public, immutable";
          access_log off;
        }
        
        # Don't cache the main HTML file
        location = /element/index.html {
          add_header Cache-Control "no-cache, no-store, must-revalidate";
          add_header Pragma "no-cache";
          add_header Expires "0";
        }
      '';
    };
    
    # Element configuration endpoint
    "/element/config.json" = {
      alias = "${elementConfig}";
      extraConfig = ''
        add_header Content-Type application/json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
      '';
    };
  };
}