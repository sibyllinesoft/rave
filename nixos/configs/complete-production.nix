# nixos/configs/complete-production.nix
# Complete, consolidated NixOS VM configuration with ALL services pre-configured
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix

    # Service modules
    ../modules/services/gitlab/default.nix

    # Security modules
    # ../modules/security/certificates.nix  # DISABLED: Using inline certificate generation instead
    ../modules/security/hardening.nix
  ];

  sops = {
    defaultSopsFile = ../../config/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # ===== SYSTEM FOUNDATION =====
  
  # Boot configuration
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" "vmw_pvscsi" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # System
  system.stateVersion = "24.11";
  networking.hostName = "rave-complete";
  system.autoUpgrade.enable = lib.mkForce false;

  # Virtual filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # User configuration
  users.users.root = {
    hashedPassword = "$6$QswyhoJG6qLe.KXH$gc29VHyMSsYAWzs8EcahO2mqYCFJBuu4JQmgGFfrEK6T0tw.hJ95WUEQ4vWGrltRSVCq7FRFBEO42sN8FTCrj/";  # "rave-root"
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAmBj5iZFV2inopUhgTX++Wue6g5ePry+DiE3/XLxe2 rave-vm-access"
    ];
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true;  # Override security hardening
      PermitRootLogin = lib.mkForce "yes";       # Override networking module
      X11Forwarding = false;
    };
  };

  # ===== CORE SERVICES =====

  # PostgreSQL with ALL required databases pre-configured
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    
    # Pre-create ALL required databases and users
    ensureDatabases = [ "gitlab" "grafana" "penpot" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "penpot"; ensureDBOwnership = true; }
      { name = "prometheus"; ensureDBOwnership = false; }
    ];
    
    # Optimized settings for VM environment
    settings = {
      max_connections = 200;
      shared_buffers = "512MB";
      effective_cache_size = "2GB";
      maintenance_work_mem = "128MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "32MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      work_mem = "8MB";
      max_wal_size = "1GB";
      min_wal_size = "80MB";
    };
    
    # Initialize all databases with proper permissions
    initialScript = pkgs.writeText "postgres-init.sql" ''
      -- GitLab database setup
      ALTER USER gitlab CREATEDB;
      ALTER USER gitlab WITH PASSWORD 'gitlab-production-password';
      GRANT ALL PRIVILEGES ON DATABASE gitlab TO gitlab;
      
      -- Grafana permissions
      GRANT CONNECT ON DATABASE grafana TO grafana;
      GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;
      ALTER DATABASE grafana OWNER TO grafana;
      GRANT USAGE, CREATE ON SCHEMA public TO grafana;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO grafana;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO grafana;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO grafana;
      ALTER USER grafana WITH PASSWORD 'grafana-production-password';

      -- Penpot database setup  
      GRANT ALL PRIVILEGES ON DATABASE penpot TO penpot;
      ALTER USER penpot WITH PASSWORD 'penpot-production-password';

      -- Prometheus exporter
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'prometheus') THEN
          CREATE ROLE prometheus WITH LOGIN PASSWORD 'prometheus_pass';
        ELSE
          ALTER ROLE prometheus WITH PASSWORD 'prometheus_pass';
        END IF;
      END
      $$;
      GRANT pg_monitor TO prometheus;
    '';
  };

  # Single Redis instance (simplified - no clustering)
  services.redis.servers.main = {
    enable = true;
    port = 6379;
    settings = {
      maxmemory = "1GB";
      maxmemory-policy = "allkeys-lru";
      save = [ "900 1" "300 10" "60 10000" ];
      # Allow multiple databases
      databases = 16;
    };
  };

  # ===== MESSAGING & MONITORING =====

  # NATS with JetStream
  services.nats = {
    enable = true;
    serverName = "rave-nats";
    port = 4222;
    
    settings = {
      # JetStream configuration
      jetstream = {
        store_dir = "/var/lib/nats/jetstream";
        max_memory_store = 512 * 1024 * 1024;  # 512MB
        max_file_store = 2 * 1024 * 1024 * 1024;  # 2GB
      };
      
      # Connection limits
      max_connections = 1000;
      max_payload = 2 * 1024 * 1024;  # 2MB
      
      # Monitoring
      http_port = 8222;
      
      # Cluster configuration disabled for single-node VM deployment
    };
  };

  # Prometheus monitoring
  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "3d";
    
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "localhost:9090" ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
      {
        job_name = "nginx";
        static_configs = [{ targets = [ "localhost:9113" ]; }];
      }
      {
        job_name = "postgres";
        static_configs = [{ targets = [ "localhost:9187" ]; }];
      }
      {
        job_name = "redis";
        static_configs = [{ targets = [ "localhost:9121" ]; }];
      }
      {
        job_name = "nats";
        static_configs = [{ targets = [ "localhost:7777" ]; }];
      }
    ];
  };

  # Prometheus exporters
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" "processes" "cpu" "meminfo" "diskstats" "filesystem" ];
    };
    
    nginx = {
      enable = true;
      port = 9113;
    };
    
    postgres = {
      enable = true;
      port = 9187;
      dataSourceName = "postgresql://prometheus:prometheus_pass@localhost:5432/postgres?sslmode=disable";
    };
    
    redis = {
      enable = true;
      port = 9121;
    };
  };

  # ===== GITLAB SERVICE =====


  # ===== GRAFANA SERVICE =====

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        domain = "localhost";  # Changed from rave.local to localhost  
        root_url = "https://localhost:8221/grafana/";
        serve_from_sub_path = true;
      };

      database = {
        type = "postgres";
        host = "localhost:5432";
        name = "grafana";
        user = "grafana";
        password = "grafana-production-password";
      };

      security = {
        admin_user = "admin";
        admin_password = "admin123";
        secret_key = "grafana-production-secret-key";
        cookie_secure = true;
        cookie_samesite = "strict";
      };

      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
    };

    # Pre-configured datasources
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
        }
        {
          name = "PostgreSQL";
          type = "postgres";
          access = "proxy";
          url = "localhost:5432";
          database = "postgres";
          user = "grafana";
          password = "grafana-production-password";
        }
      ];
    };
  };

  # ===== MATTERMOST CHAT =====

  services.mattermost = {
    enable = true;
    siteUrl = "https://localhost:8231/mattermost";
    siteName = "RAVE Mattermost";
    # Use Mattermost defaults for data and log directories

    environmentFile = if config.services.rave.gitlab.useSecrets
      then config.sops.secrets."mattermost/env".path
      else pkgs.writeText "mattermost-env" ''
        MM_SERVICESETTINGS_SITEURL=https://localhost:8231/mattermost
        MM_SERVICESETTINGS_ENABLELOCALMODE=true
        MM_SQLSETTINGS_DRIVERNAME=postgres
        MM_SQLSETTINGS_DATASOURCE=postgres://mattermost:mmpgsecret@localhost:5432/mattermost?sslmode=disable&connect_timeout=10
        MM_BLEVESETTINGS_INDEXDIR=/var/lib/mattermost/bleve-indexes
      '';

  };

  services.rave.gitlab = {
    enable = true;
    host = "localhost";
    useSecrets = false;
    runner.enable = false;
    oauth = {
      enable = true;
      provider = "google";
      clientId = "729118765955-o2kri2vjcjms4s59tjaeidrf2fvskcfn.apps.googleusercontent.com";
      clientSecretFile = if config.services.rave.gitlab.useSecrets
        then config.sops.secrets."gitlab/oauth-provider-client-secret".path
        else pkgs.writeText "gitlab-oauth-client-secret" "development-client-secret";
      autoSignIn = true;
      autoLinkUsers = true;
      allowLocalSignin = false;
    };
  };

  sops.secrets."mattermost/env" = {
    owner = "mattermost";
    group = "mattermost";
    mode = "0600";
  };

  sops.secrets."mattermost/admin-username" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."mattermost/admin-email" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."mattermost/admin-password" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."oidc/chat-control-client-secret" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."gitlab/api-token" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."gitlab/oauth-provider-client-secret" = {
    owner = "gitlab";
    group = "gitlab";
    mode = "0400";
  };

  # ===== NGINX CONFIGURATION =====

  services.nginx = {
    enable = true;
    commonHttpConfig = ''
      map $http_host $rave_forwarded_port {
        default 443;
        ~:(?<port>\d+)$ $port;
      }
    '';
    
    # Global configuration
    clientMaxBodySize = "10G";
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = false;
    recommendedTlsSettings = true;
    logError = "/var/log/nginx/error.log debug";
    
    # Status page for monitoring
    statusPage = true;
    
    virtualHosts."localhost" = {
      forceSSL = true;
      enableACME = false;
      listen = [
        {
          addr = "0.0.0.0";
          port = 8221;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 8220;
          ssl = false;
        }
        {
          addr = "0.0.0.0";
          port = 8231;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 8230;
          ssl = false;
        }
      ];

      # Use manual certificate configuration
      sslCertificate = "/var/lib/acme/localhost/cert.pem";
      sslCertificateKey = "/var/lib/acme/localhost/key.pem";
      
      # Root location - dashboard
      locations."/" = {
        root = pkgs.writeTextDir "index.html" ''
          <!DOCTYPE html>
          <html lang="en">
          <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>RAVE - Complete Production Environment</title>
              <style>
                  * { margin: 0; padding: 0; box-sizing: border-box; }
                  body { 
                      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                      color: #333; min-height: 100vh; padding: 20px;
                  }
                  .container { max-width: 1200px; margin: 0 auto; }
                  .header { text-align: center; color: white; margin-bottom: 40px; }
                  .header h1 { font-size: 3rem; margin-bottom: 10px; }
                  .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
                  .service-card {
                      background: white; border-radius: 10px; padding: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.1);
                      transition: transform 0.3s ease; text-decoration: none; color: #333;
                  }
                  .service-card:hover { transform: translateY(-5px); }
                  .service-title { font-size: 1.5rem; margin-bottom: 10px; color: #667eea; }
                  .service-desc { color: #666; margin-bottom: 15px; }
                  .service-url { color: #764ba2; font-weight: bold; }
                  .status { display: inline-block; padding: 4px 8px; border-radius: 20px; font-size: 0.8rem; }
                  .status.active { background: #4ade80; color: white; }
              </style>
          </head>
          <body>
              <div class="container">
                  <div class="header">
                      <h1>🚀 RAVE</h1>
                      <p>Complete Production Environment - All Services Ready</p>
                  </div>
                  <div class="services">
                      <a href="/gitlab/" class="service-card">
                          <div class="service-title">🦊 GitLab</div>
                          <div class="service-desc">Git repository management and CI/CD</div>
                          <div class="service-url">https://localhost:8221/gitlab/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/grafana/" class="service-card">
                          <div class="service-title">📊 Grafana</div>
                          <div class="service-desc">Monitoring dashboards and analytics</div>
                          <div class="service-url">https://localhost:8221/grafana/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/mattermost/" class="service-card">
                          <div class="service-title">💬 Mattermost</div>
                          <div class="service-desc">Secure team chat and agent control</div>
                          <div class="service-url">https://chat.localtest.me:8221/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/prometheus/" class="service-card">
                          <div class="service-title">🔍 Prometheus</div>
                          <div class="service-desc">Metrics collection and monitoring</div>
                          <div class="service-url">https://localhost:8221/prometheus/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/nats/" class="service-card">
                          <div class="service-title">⚡ NATS JetStream</div>
                          <div class="service-desc">High-performance messaging system</div>
                          <div class="service-url">https://localhost:8221/nats/</div>
                          <span class="status active">Active</span>
                      </a>
                  </div>
              </div>
          </body>
          </html>
        '';
      };

      # Mattermost reverse proxy
      locations."/mattermost/" = {
        proxyPass = "http://127.0.0.1:8065/mattermost/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $http_host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Ssl on;
          proxy_redirect off;
          proxy_read_timeout 3600s;
        '';
      };

      # Grafana reverse proxy
      locations."/grafana/" = {
        proxyPass = "http://127.0.0.1:3000/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
      
      # Prometheus reverse proxy
      locations."/prometheus/" = {
        proxyPass = "http://127.0.0.1:9090/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
      
      # NATS monitoring reverse proxy  
      locations."/nats/" = {
        proxyPass = "http://127.0.0.1:8222/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
      
      # Global security headers
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;  
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        absolute_redirect off;
      '';
    };
    
    # HTTP redirect to HTTPS
    virtualHosts."localhost-http" = {
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      locations."/" = {
        return = "301 https://localhost$request_uri";
      };
    };

    virtualHosts."chat.localtest.me" = {
      forceSSL = false;
      enableACME = false;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      http2 = true;
      sslCertificate = "/var/lib/acme/localhost/cert.pem";
      sslCertificateKey = "/var/lib/acme/localhost/key.pem";
      extraConfig = ''
        ssl_certificate /var/lib/acme/localhost/cert.pem;
        ssl_certificate_key /var/lib/acme/localhost/key.pem;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:8065";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          client_max_body_size 100M;
          proxy_redirect off;
        '';
      };
    };

    virtualHosts."chat.localtest.me-http" = {
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      serverName = "chat.localtest.me";
      locations."/" = {
        return = "301 https://chat.localtest.me$request_uri";
      };
    };
  };

  # Ensure GitLab is started after the database configuration completes.
  systemd.services."gitlab-db-config".unitConfig.OnSuccess = [ "gitlab-autostart.service" ];

  systemd.services."gitlab-autostart" = {
    description = "Ensure GitLab starts after database configuration";
    wantedBy = [ "multi-user.target" ];
    after = [
      "postgresql.service"
      "redis-main.service"
      "gitlab-config.service"
      "gitlab-db-config.service"
    ];
    wants = [ "gitlab-db-config.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "gitlab-autostart.sh" ''
        set -euo pipefail

        systemctl_bin='${lib.getExe' pkgs.systemd "systemctl"}'
        attempts=0
        max_attempts=12

        # Wait (with retries) for gitlab-db-config to report active.
        while ! "$systemctl_bin" is-active --quiet gitlab-db-config.service; do
          if (( attempts >= max_attempts )); then
            echo "gitlab-db-config.service did not become active" >&2
            exit 1
          fi

          # If the config unit is in failed state, reset it so systemd can retry.
          if "$systemctl_bin" is-failed --quiet gitlab-db-config.service; then
            "$systemctl_bin" reset-failed gitlab-db-config.service || true
            "$systemctl_bin" start gitlab-db-config.service || true
          fi

          attempts=$(( attempts + 1 ))
          sleep $(( 5 * attempts ))
        done

        "$systemctl_bin" reset-failed gitlab.service || true
        "$systemctl_bin" start gitlab.service
      '';
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  # ===== SSL CERTIFICATE CONFIGURATION =====

  # Generate self-signed certificates for localhost
  systemd.services.generate-localhost-certs = {
    description = "Generate self-signed SSL certificates for localhost";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      set -e
      
      CERT_DIR="/var/lib/acme/localhost"
      
      # Create certificate directory
      mkdir -p "$CERT_DIR"
      
      # Only generate if certificates don't exist
      if [[ ! -f "$CERT_DIR/cert.pem" ]]; then
        echo "Generating SSL certificates for localhost..."
        
        # Generate CA private key
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/ca-key.pem" 4096
        
        # Generate CA certificate
        ${pkgs.openssl}/bin/openssl req -new -x509 -days 365 -key "$CERT_DIR/ca-key.pem" -out "$CERT_DIR/ca.pem" -subj "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=RAVE-CA"
        
        # Generate server private key  
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        
        # Generate certificate signing request
        ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.csr" -subj "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=localhost"
        
        # Create certificate with SAN for localhost
        cat > "$CERT_DIR/cert.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = SF
O = RAVE
OU = Dev
CN = localhost

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = rave.local
DNS.3 = chat.localtest.me
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
        
        # Generate final certificate
        ${pkgs.openssl}/bin/openssl x509 -req -in "$CERT_DIR/cert.csr" -CA "$CERT_DIR/ca.pem" -CAkey "$CERT_DIR/ca-key.pem" -CAcreateserial -out "$CERT_DIR/cert.pem" -days 365 -extensions v3_req -extfile "$CERT_DIR/cert.conf"
        
        # Set proper permissions
        chmod 755 "$CERT_DIR"
        chmod 644 "$CERT_DIR"/{cert.pem,ca.pem}
        chmod 640 "$CERT_DIR/key.pem"
        
        # Set nginx group ownership for key access
        chgrp nginx "$CERT_DIR"/{cert.pem,key.pem} || true
        
        echo "SSL certificates generated successfully!"
      else
        echo "SSL certificates already exist, skipping generation."
      fi
    '';
  };

  # ===== SYSTEM CONFIGURATION =====

  # Enable required services
  services.dbus.enable = true;
  
  # Environment packages
  environment.systemPackages = with pkgs; [
    # System utilities
    curl wget htop btop tree vim nano
    git jq yq-go
    
    # Network utilities
    netcat-gnu nmap tcpdump
    
    # Monitoring tools
    prometheus-node-exporter
    
    # Development tools
    docker-compose
    python3 nodejs nodePackages.npm
    
    # SSL utilities
    openssl
  ];

  # Enable Docker
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/var/lib/docker";
      storage-driver = "overlay2";
    };
  };


  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      22    # SSH
      80    # HTTP
      443   # HTTPS
      8443  # HTTPS (alternate)
      8220  # HTTP (VM forwarded)
      8221  # HTTPS (VM forwarded)
      8230  # Mattermost HTTP
      8231  # Mattermost HTTPS
      8080  # GitLab internal
      3000  # Grafana internal
      8065  # Mattermost internal
      9090  # Prometheus internal
      8222  # NATS monitoring
      5000  # GitLab registry
      4222  # NATS
    ];
  };

  # System services dependency management
  systemd.services = {
    # Ensure PostgreSQL users exist before other services start
    postgresql.postStart = ''
      # Wait for PostgreSQL to be ready
      sleep 10
      
      # Set passwords for database users (development only)
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER gitlab PASSWORD 'gitlab-production-password';" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER grafana PASSWORD 'grafana-production-password';" || true  
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER penpot PASSWORD 'penpot-production-password';" || true
      
      # Grant additional permissions
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT CONNECT ON DATABASE postgres TO grafana;" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT USAGE ON SCHEMA public TO grafana;" || true
    '';
    
    # GitLab depends on database and certificates
    gitlab.after = [ "postgresql.service" "redis-main.service" "generate-localhost-certs.service" ];
    gitlab.requires = [ "postgresql.service" "redis-main.service" ];
    
    # Grafana depends on database and certificates
    grafana.after = [ "postgresql.service" "generate-localhost-certs.service" ];
    grafana.requires = [ "postgresql.service" ];
    
    # nginx depends on certificates and all backend services
    nginx.after = [ 
      "generate-localhost-certs.service" 
      "gitlab.service"
      "grafana.service" 
      "mattermost.service"
      "prometheus.service"
      "nats.service"
    ];
    nginx.requires = [ "generate-localhost-certs.service" ];
  };

  system.activationScripts.installRootWelcome = {
    text = ''
      cat <<'WELCOME' > /root/welcome.sh
#!/bin/sh
echo "Welcome to the RAVE complete VM"
echo "Forwarded ports:"
echo "  SSH          : localhost:12222 (user root, password rave-root)"
echo "  GitLab HTTPS : https://localhost:18221/gitlab/"
echo "  Mattermost   : https://localhost:18231/mattermost/"
echo "  Grafana      : https://localhost:18221/grafana/"
echo "  Prometheus   : http://localhost:19090/"
echo ""
WELCOME
      chmod 0755 /root/welcome.sh
    '';
  };

  # Create welcome script
  systemd.services.create-welcome-script = {
    description = "Create system welcome script";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      cat > /root/welcome.sh << 'EOF'
#!/bin/bash
echo "🚀 RAVE Complete Production Environment"
echo "====================================="
echo ""
echo "✅ All Services Ready:"
echo "   🦊 GitLab:      https://localhost:8221/gitlab/"
echo "   📊 Grafana:     https://localhost:8221/grafana/"  
echo "   💬 Mattermost:  https://chat.localtest.me:8221/"
echo "   🔍 Prometheus:  https://localhost:8221/prometheus/"
echo "   ⚡ NATS:        https://localhost:8221/nats/"
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status postgresql redis-main nats prometheus grafana gitlab mattermost rave-chat-bridge nginx --no-pager -l
echo ""
echo "🌐 Dashboard: https://localhost:8221/"
echo ""
EOF
      chmod +x /root/welcome.sh
      echo "/root/welcome.sh" >> /root/.bashrc
    '';
  };
}
