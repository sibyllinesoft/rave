# Matrix-Synapse Service Configuration for RAVE P4
# Implements Matrix homeserver with Element web client and GitLab OIDC integration
{ config, pkgs, lib, ... }:

{
  # P4.1: Matrix-Synapse homeserver configuration
  services.matrix-synapse = {
    enable = true;
    
    # Server configuration
    settings = {
      # Server identity
      server_name = "rave.local";
      public_baseurl = "https://rave.local:3002/matrix/";
      serve_server_wellknown = true;
      
      # Web client configuration
      web_client_location = "https://rave.local:3002/element/";
      
      # Listeners configuration
      listeners = [
        {
          port = 8008;
          type = "http";
          tls = false;  # TLS handled by nginx
          x_forwarded = true;
          
          # HTTP resources
          resources = [
            {
              names = [ "client" "federation" ];
              compress = false;
            }
            {
              names = [ "metrics" ];
              compress = false;
            }
          ];
        }
      ];
      
      # Database configuration - use existing PostgreSQL
      database = {
        name = "psycopg2";
        args = {
          host = "/run/postgresql";
          database = "synapse";
          user = "synapse";
          password = if config.sops.secrets ? "database/matrix-password"
                     then config.sops.secrets."database/matrix-password".path
                     else null;
          cp_min = 5;
          cp_max = 10;
        };
      };
      
      # Media configuration
      media_store_path = "/var/lib/matrix-synapse/media_store";
      uploads_path = "/var/lib/matrix-synapse/uploads";
      max_upload_size = "100M";
      max_image_pixels = "32M";
      
      # URL preview configuration (disabled for security)
      url_preview_enabled = false;
      
      # User registration and limits
      enable_registration = false;  # Use OIDC only
      registration_requires_token = true;
      
      # Rate limiting configuration
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
      
      # Security configuration
      require_auth_for_profile_requests = true;
      limit_profile_requests_to_users_who_share_rooms = true;
      include_profile_data_on_invite = false;
      
      # Metrics configuration
      enable_metrics = true;
      
      # Logging configuration
      log_config = pkgs.writeText "matrix-synapse-log-config.yaml" ''
        version: 1
        formatters:
          precise:
            format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
        
        handlers:
          console:
            class: logging.StreamHandler
            formatter: precise
            level: INFO
            stream: ext://sys.stdout
          
          file:
            class: logging.handlers.TimedRotatingFileHandler
            formatter: precise
            level: INFO
            filename: /var/log/matrix-synapse/homeserver.log
            when: midnight
            backupCount: 7
            encoding: utf8
        
        loggers:
          synapse.storage.SQL:
            level: WARNING
          synapse.access:
            level: INFO
        
        root:
          level: INFO
          handlers: [console, file]
      '';
      
      # Federation configuration (disabled for security in closed environment)
      federation_domain_whitelist = [];
      allow_public_rooms_without_auth = false;
      allow_public_rooms_over_federation = false;
      
      # Room configuration
      default_room_version = "10";  # Latest stable room version
      
      # Presence configuration (disabled for performance)
      use_presence = false;
      
      # Push configuration (disabled - no external push gateways)
      push = {
        include_content = false;
      };
      
      # Stats configuration
      enable_room_list_search = false;  # Disabled for privacy
      
      # App service configuration (for future P5 bridge integration)
      app_service_config_files = [];
      
      # Admin contact
      admin_contact = "admin@rave.local";
      
      # Worker configuration (disabled - single process for resource efficiency)
      send_federation = false;  # No federation
      federation_sender_instances = [];
      
      # OIDC providers configuration (GitLab integration)
      oidc_providers = [
        {
          idp_id = "gitlab";
          idp_name = "GitLab";
          discover = true;
          issuer = "https://rave.local:3002/gitlab";
          client_id = "matrix-synapse";  # Must match GitLab OAuth app
          client_secret_path = if config.sops.secrets ? "oidc/matrix-client-secret"
                               then config.sops.secrets."oidc/matrix-client-secret".path
                               else null;
          
          # User attribute mapping
          user_mapping_provider = {
            config = {
              localpart_template = "{{ user.preferred_username }}";
              display_name_template = "{{ user.name }}";
              email_template = "{{ user.email }}";
            };
          };
          
          # Authorization endpoint parameters
          authorization_endpoint = "https://rave.local:3002/gitlab/oauth/authorize";
          token_endpoint = "https://rave.local:3002/gitlab/oauth/token";
          userinfo_endpoint = "https://rave.local:3002/gitlab/oauth/userinfo";
          
          # Scopes to request from GitLab
          scopes = [ "openid" "profile" "email" ];
          
          # Skip verification for development (disable in production)
          skip_verification = true;  # TODO: Set to false with proper certs
          
          # Enable PKCE for security
          pkce_method = "S256";
        }
      ];
      
      # User directory configuration
      user_directory = {
        enabled = false;  # Disabled for privacy in closed environment
      };
      
      # Retention configuration
      retention = {
        enabled = false;  # No automatic message deletion
      };
    };
    
    # Configuration file is managed automatically by NixOS
    
    # Data directory
    dataDir = "/var/lib/matrix-synapse";
    
    # Log directory and user handled automatically by NixOS
  };
  
  # P4.2: Element Web client configuration
  services.nginx.virtualHosts."rave.local".locations = lib.mkMerge [
    {
      # Matrix Synapse server
      "/matrix/" = {
        proxyPass = "http://127.0.0.1:8008/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Matrix-specific headers
          proxy_set_header X-Forwarded-Ssl on;
          proxy_buffering off;
          
          # WebSocket support for real-time messaging
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Timeout configuration for long polling
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;
          
          # Handle large media uploads
          client_max_body_size 100M;
          proxy_request_buffering off;
        '';
      };
      
      # Matrix redirect
      "= /matrix" = {
        return = "301 /matrix/";
      };
      
      # Matrix federation (disabled but configured for future)
      "/.well-known/matrix/server" = {
        return = ''200 '{"m.server": "rave.local:443"}'';
        extraConfig = ''
          add_header Content-Type application/json;
          add_header Access-Control-Allow-Origin *;
        '';
      };
      
      "/.well-known/matrix/client" = {
        return = ''200 '{"m.homeserver": {"base_url": "https://rave.local:3002/matrix"}}'';
        extraConfig = ''
          add_header Content-Type application/json;
          add_header Access-Control-Allow-Origin *;
        '';
      };
      
      # Element web client
      "/element/" = {
        alias = "${pkgs.element-web}/";
        index = "index.html";
        extraConfig = ''
          # Handle Element routing (SPA)
          try_files $uri $uri/ /element/index.html;
          
          # Cache configuration for Element assets (simplified)
          expires 1y;
        '';
      };
      
      # Element redirect
      "= /element" = {
        return = "301 /element/";
      };
    }
  ];
  
  # P4.3: Element Web configuration
  environment.etc."element-web/config.json" = {
    text = builtins.toJSON {
      default_server_config = {
        "m.homeserver" = {
          base_url = "https://rave.local:3002/matrix";
          server_name = "rave.local";
        };
        "m.identity_server" = {
          base_url = "";  # No identity server for privacy
        };
      };
      
      # Branding configuration
      brand = "RAVE Matrix";
      default_country_code = "US";
      
      # Feature configuration
      features = {
        feature_spaces = true;
        feature_voice_messages = true;
        feature_location_share = false;  # Disabled for privacy
        feature_polls = true;
        feature_threads = true;
      };
      
      # Room directory configuration
      room_directory = {
        servers = [ "rave.local" ];
      };
      
      # Integration configuration (disabled for security)
      integrations_ui_url = "";
      integrations_rest_url = "";
      integrations_widgets_urls = [];
      
      # Widget configuration (disabled for security)
      widget_build_url = "";
      
      # Jitsi configuration (disabled - no video conferencing for now)
      jitsi = {
        preferred_domain = "";
      };
      
      # Bug reporting (disabled)
      bug_report_endpoint_url = "";
      
      # Analytics (disabled for privacy)
      piwik = false;
      
      # Default theme
      default_theme = "light";
      
      # Element call configuration (disabled)
      element_call = {
        url = "";
        use_exclusively = false;
      };
      
      # Map configuration (disabled)
      map_style_url = "";
      
      # Permalink configuration
      permalink_prefix = "https://rave.local:3002/element";
      
      # Security settings
      disable_guests = true;
      disable_login_language_selector = false;
      disable_3pid_login = true;  # No third-party ID login
      
      # Privacy settings
      privacy_policy_url = "";
      terms_and_conditions_url = "";
      
      # Help menu
      help_menu_links = [];
      
      # Mobile guide (disabled - web only for now)
      mobile_guide_toast = false;
      
      # Voice broadcast (disabled to save bandwidth)
      voice_broadcast = false;
    };
    
    target = "${pkgs.element-web}/config.json";
  };
  
  # P4.4: PostgreSQL database configuration for Matrix
  services.postgresql.ensureDatabases = lib.mkAfter [ "synapse" ];
  services.postgresql.ensureUsers = lib.mkAfter [
    {
      name = "synapse";
      ensureDBOwnership = true;
    }
  ];
  
  # Additional PostgreSQL configuration for Matrix workload  
  services.postgresql.settings = lib.mkMerge [
    {
      # Matrix-specific performance tuning
      shared_preload_libraries = "pg_stat_statements";
      
      # Memory configuration for Matrix workload
      work_mem = "16MB";
      
      # Connection configuration for Matrix
      idle_in_transaction_session_timeout = 300000;
      
      # Logging for Matrix debugging (disable in production)
      log_statement = "none";
      log_min_duration_statement = 5000;
    }
  ];
  
  # P4.5: Matrix service dependencies and resource limits
  systemd.services.matrix-synapse = {
    after = [ "postgresql.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "postgresql.service" ];
    
    # Resource limits for Matrix Synapse
    serviceConfig = {
      MemoryMax = "4G";  # Matrix can be memory-intensive
      CPUQuota = "200%";  # Allow burst CPU usage for initial sync
      TasksMax = 2048;
      
      # Security hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ 
        "/var/lib/matrix-synapse" 
        "/var/log/matrix-synapse" 
        "/tmp"  # Needed for media processing
      ];
      
      # Process limits
      LimitNOFILE = 32768;
      LimitNPROC = 16384;
      
      # Restart configuration
      Restart = lib.mkDefault "always";
      RestartSec = "10s";
    };
    
    # Environment variables
    environment = {
      SYNAPSE_CONFIG_PATH = "${config.services.matrix-synapse.configFile}";
      PYTHONPATH = "${pkgs.matrix-synapse}/lib/python*/site-packages";
    };
    
    # Pre-start script for database initialization
    preStart = ''
      # Ensure log directory exists
      mkdir -p /var/log/matrix-synapse
      chown matrix-synapse:matrix-synapse /var/log/matrix-synapse
      
      # Ensure media directories exist
      mkdir -p /var/lib/matrix-synapse/{media_store,uploads}
      chown -R matrix-synapse:matrix-synapse /var/lib/matrix-synapse
      
      # Initialize database if needed
      if ! ${pkgs.postgresql}/bin/psql -h /run/postgresql -U synapse -d synapse -c '\dt' > /dev/null 2>&1; then
        echo "Initializing Matrix Synapse database..."
        ${pkgs.matrix-synapse}/bin/synapse_homeserver \
          --config-path=${config.services.matrix-synapse.configFile} \
          --generate-keys
      fi
    '';
  };
  
  # P4.6: Log rotation for Matrix services
  services.logrotate.settings.matrix-synapse = {
    files = "/var/log/matrix-synapse/*.log";
    frequency = "daily";
    rotate = 14;
    missingok = true;
    compress = true;
    delaycompress = true;
    notifempty = true;
    copytruncate = true;
    postrotate = "systemctl reload matrix-synapse || true";
  };
  
  # P4.7: Matrix backup configuration
  systemd.services.matrix-backup = {
    description = "Matrix Synapse backup service";
    serviceConfig = {
      Type = "oneshot";
      User = "matrix-synapse";
      Group = "matrix-synapse";
      
      ExecStart = pkgs.writeScript "matrix-backup" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        BACKUP_DIR="/var/lib/matrix-synapse/backups"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        
        # Create backup directory
        mkdir -p "$BACKUP_DIR"
        
        # Backup database
        ${pkgs.postgresql}/bin/pg_dump -h /run/postgresql -U synapse synapse > "$BACKUP_DIR/synapse_db_$TIMESTAMP.sql"
        
        # Backup media store (if not too large)
        if [ $(du -s /var/lib/matrix-synapse/media_store | cut -f1) -lt 1000000 ]; then
          tar czf "$BACKUP_DIR/media_store_$TIMESTAMP.tar.gz" -C /var/lib/matrix-synapse media_store
        fi
        
        # Backup configuration
        cp ${config.services.matrix-synapse.configFile} "$BACKUP_DIR/homeserver_config_$TIMESTAMP.yaml"
        
        # Clean old backups (keep 7 days)
        find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
        find "$BACKUP_DIR" -name "*.yaml" -mtime +7 -delete
        
        echo "Matrix backup completed: $TIMESTAMP"
      '';
      
      # Resource limits for backup process
      MemoryMax = "1G";
      CPUQuota = "25%";
    };
  };
  
  systemd.timers.matrix-backup = {
    description = "Matrix daily backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      AccuracySec = "1h";
    };
  };
  
  # P4.8: Firewall configuration for Matrix
  networking.firewall = lib.mkMerge [
    {
      # Matrix-specific ports (internal access only)
      allowedTCPPorts = [ 8008 ];  # Matrix Synapse HTTP port
      
      # Matrix federation port (disabled but configured)
      # allowedTCPPorts = [ 8448 ];  # Matrix federation HTTPS port
    }
  ];
  
  # P4.9: Monitoring integration for Matrix
  services.prometheus.scrapeConfigs = lib.mkAfter [
    {
      job_name = "matrix-synapse";
      static_configs = [
        {
          targets = [ "127.0.0.1:8008" ];
        }
      ];
      metrics_path = "/_synapse/metrics";
      scrape_interval = "30s";
    }
  ];
  
  # P4.10: Additional packages for Matrix functionality
  environment.systemPackages = with pkgs; [
    # Matrix administration tools
    matrix-synapse
    
    # Element web client
    element-web
    
    # Database tools for Matrix management
    postgresql
    
    # Media processing tools (for Matrix media handling)
    imagemagick
    ffmpeg-headless
    
    # Monitoring and debugging tools
    htop
    netcat
    curl
  ];
  
  # P4.11: User and group configuration handled automatically by Matrix service
  
  # P4.12: System tuning for Matrix performance
  # Increase file descriptor limits for Matrix
  systemd.extraConfig = ''
    DefaultLimitNOFILE=32768
  '';
  
  # Kernel parameters for Matrix performance
  boot.kernel.sysctl = {
    "net.core.somaxconn" = 1024;
    "net.ipv4.tcp_max_syn_backlog" = 1024;
    "vm.swappiness" = 10;  # Reduce swapping for better Matrix performance
  };
}