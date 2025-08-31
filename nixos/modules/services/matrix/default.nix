# nixos/modules/services/matrix/default.nix
# Matrix Synapse server configuration module - extracted from P4 production config
{ config, pkgs, lib, ... }:

with lib;

{
  imports = [
    ./bridge.nix
    ./element.nix
  ];

  options = {
    services.rave.matrix = {
      enable = mkEnableOption "Matrix Synapse homeserver with Element client";
      
      serverName = mkOption {
        type = types.str;
        default = "rave.local";
        description = "Matrix server name";
      };
      
      useSecrets = mkOption {
        type = types.bool;
        default = true;
        description = "Use sops-nix secrets instead of plain text (disable for development)";
      };
      
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable OIDC integration with GitLab";
        };
        
        gitlabUrl = mkOption {
          type = types.str;
          default = "https://rave.local/gitlab";
          description = "GitLab base URL for OIDC";
        };
      };
      
      federation = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable Matrix federation (disabled by default for security)";
        };
      };
    };
  };
  
  config = mkIf config.services.rave.matrix.enable {
    # P4: Matrix Service Integration
    services.matrix-synapse = {
      enable = true;
      
      settings = {
        server_name = config.services.rave.matrix.serverName;
        public_baseurl = "https://${config.services.rave.matrix.serverName}/matrix/";
        
        # Listener configuration from P4
        listeners = [{
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [{
            names = if config.services.rave.matrix.federation.enable 
              then [ "client" "federation" ] 
              else [ "client" ];  # Disable federation by default
            compress = true;
          }];
        }];

        # Registration and authentication - P4 config
        enable_registration = false; # Disable open registration (OIDC only)
        enable_registration_without_verification = false;
        
        # Federation control
        federation_domain_whitelist = mkIf (!config.services.rave.matrix.federation.enable) [];
        disable_federation = !config.services.rave.matrix.federation.enable;
        
        # Database configuration with connection pooling
        database = {
          name = "psycopg2";
          args = {
            user = "matrix-synapse";
            database = "matrix-synapse";
            host = "localhost";
            cp_min = 5;
            cp_max = 10;
            # Password will be set via secrets
          };
        };

        # Media and uploads - enhanced from P4
        max_upload_size = "100M";
        media_store_path = "/var/lib/matrix-synapse/media";
        
        # Media retention policy
        media_retention = {
          local_media_lifetime = "30d";
          remote_media_lifetime = "14d";
        };
        
        # Rate limiting
        rc_message = {
          per_second = 0.2;
          burst_count = 10;
        };
        
        rc_registration = {
          per_second = 0.17;
          burst_count = 3;
        };
        
        rc_login = {
          address = {
            per_second = 0.17;
            burst_count = 3;
          };
          account = {
            per_second = 0.17;
            burst_count = 3;
          };
          failed_attempts = {
            per_second = 0.17;
            burst_count = 3;
          };
        };

        # Logging
        log_config = pkgs.writeText "matrix-synapse-log-config" ''
          version: 1
          formatters:
            precise:
              format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
          handlers:
            file:
              class: logging.handlers.RotatingFileHandler
              formatter: precise
              filename: /var/log/matrix-synapse/homeserver.log
              maxBytes: 104857600
              backupCount: 3
          root:
            level: INFO
            handlers: [file]
        '';

        # OIDC configuration for GitLab integration - from P4
        oidc_providers = mkIf config.services.rave.matrix.oidc.enable [{
          idp_id = "gitlab";
          idp_name = "GitLab";
          discover = true;
          issuer = config.services.rave.matrix.oidc.gitlabUrl;
          client_id = "matrix-synapse";
          
          client_secret_path = if config.services.rave.matrix.useSecrets
            then config.sops.secrets."oidc/matrix-client-secret".path or "/run/secrets/matrix-oidc-secret"
            else pkgs.writeText "matrix-oidc-secret" "development-oidc-secret";
            
          scopes = ["openid" "profile" "email"];
          
          user_mapping_provider = {
            config = {
              localpart_template = "{{ user.preferred_username }}";
              display_name_template = "{{ user.name }}";
              email_template = "{{ user.email }}";
            };
          };
          
          # Additional OIDC settings
          allow_existing_users = true;
          user_profile_method = "userinfo_endpoint";
        }];
        
        # App service configuration for bridges
        app_service_config_files = [
          # Will be populated by bridge configurations
        ];
        
        # Shared secret for app service registration
        registration_shared_secret_path = if config.services.rave.matrix.useSecrets
          then config.sops.secrets."matrix/shared-secret".path or "/run/secrets/matrix-shared-secret"
          else pkgs.writeText "matrix-shared-secret" "development-shared-secret";
      };
    };

    # Required dependencies for Matrix
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "matrix-synapse" ];
      ensureUsers = [{
        name = "matrix-synapse";
        ensureDBOwnership = true;
      }];
      
      # Enhanced settings for Matrix workload
      settings = {
        max_connections = 100;
        shared_buffers = "256MB";
        effective_cache_size = "1GB";
        maintenance_work_mem = "64MB";
        checkpoint_completion_target = 0.9;
        wal_buffers = "16MB";
        default_statistics_target = 100;
        random_page_cost = 1.1;
        effective_io_concurrency = 200;
      };
    };

    # Nginx configuration for Matrix - from P4 config
    services.nginx.virtualHosts."${config.services.rave.matrix.serverName}".locations = mkMerge [
      {
        # Matrix client API
        "/matrix/" = {
          proxyPass = "http://127.0.0.1:8008/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Handle WebSocket connections
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Timeouts for Matrix sync requests
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            
            # Rate limiting
            limit_req zone=matrix_api burst=10 nodelay;
          '';
        };

        # Matrix federation endpoints (only if federation enabled)
        "/.well-known/matrix/server" = mkIf config.services.rave.matrix.federation.enable {
          return = "200 '{\"m.server\": \"${config.services.rave.matrix.serverName}:443\"}'";
          extraConfig = "add_header Content-Type application/json;";
        };

        "/.well-known/matrix/client" = {
          return = "200 '{\"m.homeserver\": {\"base_url\": \"https://${config.services.rave.matrix.serverName}/matrix/\"}}'";
          extraConfig = "add_header Content-Type application/json;";
        };
        
        # Health check endpoint for Matrix - from P4
        "/health/matrix" = {
          proxyPass = "http://127.0.0.1:8008/_matrix/client/versions";
          extraConfig = ''
            proxy_set_header Host $host;
            access_log off;
            
            # Return simplified health status
            proxy_intercept_errors on;
            error_page 200 = @matrix_healthy;
            error_page 500 502 503 504 = @matrix_unhealthy;
          '';
        };
        
        "@matrix_healthy" = {
          return = "200 \"Matrix: OK\"";
        };
        
        "@matrix_unhealthy" = {
          return = "503 \"Matrix: Unavailable\"";
        };
      }
    ];
    
    # Rate limiting configuration
    services.nginx.appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=matrix_api:10m rate=10r/s;
    '';

    # Firewall configuration for Matrix
    networking.firewall.allowedTCPPorts = [ 8008 ]; # Matrix Synapse
    
    # Service resource limits from P4
    systemd.services.matrix-synapse.serviceConfig = {
      MemoryMax = "4G";
      CPUQuota = "200%";  # 2 CPU cores
      OOMScoreAdjust = "50";
    };
    
    # System optimization for Matrix workload from P4
    boot.kernel.sysctl = {
      "net.ipv4.tcp_keepalive_time" = 600;
      "net.ipv4.tcp_keepalive_intvl" = 60;
      "net.ipv4.tcp_keepalive_probes" = 3;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
    };
  };
}