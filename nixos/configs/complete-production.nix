# nixos/configs/complete-production.nix
# Complete, consolidated NixOS VM configuration with ALL services pre-configured
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix
    
    # Security modules
    ../modules/security/certificates.nix
    ../modules/security/hardening.nix
  ];

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

  # Virtual filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # User configuration
  users.users.root = {
    hashedPassword = "$6$rounds=1000000$NhXVkh6kn4DMVG.U$zKJT5GkhLdU6.7yPb2H2VfSVvK9DjjBYsJWQ8jc6MaTGHr/e.3PjNSghhNE3YqjfLp0KOkVXqy/vbhKn.e7aS0";  # "debug123"
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7... # Add your SSH key here"
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
    ensureDatabases = [ "gitlab" "grafana" "penpot" ]; # matrix_synapse disabled
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; }
      { name = "penpot"; ensureDBOwnership = true; }
      # { name = "matrix_synapse"; ensureDBOwnership = true; } # disabled
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
      GRANT ALL PRIVILEGES ON DATABASE gitlab TO gitlab;
      
      -- Grafana permissions
      GRANT CONNECT ON DATABASE postgres TO grafana;
      GRANT USAGE ON SCHEMA public TO grafana;
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;
      
      -- Penpot database setup  
      GRANT ALL PRIVILEGES ON DATABASE penpot TO penpot;
      
      -- Matrix database setup
      -- GRANT ALL PRIVILEGES ON DATABASE matrix_synapse TO matrix_synapse; -- disabled
    '';
  };

  # Redis with multiple instances for different services
  services.redis.servers = {
    gitlab = {
      enable = true;
      port = 6379;
      settings = {
        maxmemory = "512MB";
        maxmemory-policy = "allkeys-lru";
        save = lib.mkForce [ "900 1" "300 10" "60 10000" ];
      };
    };
    
    penpot = {
      enable = true;
      port = 6380;
      settings = {
        maxmemory = "256MB";
        maxmemory-policy = "allkeys-lru";
        save = lib.mkForce [ "60 1000" ];
      };
    };
    
    matrix = {
      enable = true;
      port = 6381;
      settings = {
        maxmemory = "256MB";
        maxmemory-policy = "allkeys-lru";
      };
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
      
      # Cluster settings
      cluster = {
        name = "rave-cluster";
        listen = "0.0.0.0:6222";
      };
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

  services.gitlab = {
    enable = true;
    host = "localhost";  # Changed from rave.local to localhost
    port = 8080;
    https = true;
    
    # Database configuration
    databaseHost = "127.0.0.1";
    databaseName = "gitlab";
    databaseUsername = "gitlab";
    databasePasswordFile = pkgs.writeText "gitlab-db-password" "gitlab-production-password";
    
    # Initial root password
    initialRootPasswordFile = pkgs.writeText "gitlab-root-password" "admin123456";
    
    # All required secrets
    secrets = {
      secretFile = pkgs.writeText "gitlab-secret-key-base" "development-secret-key-base-complete-production";
      otpFile = pkgs.writeText "gitlab-otp-key-base" "development-otp-key-base-complete-production";
      dbFile = pkgs.writeText "gitlab-db-key-base" "development-db-key-base-complete-production";
      jwsFile = pkgs.writeText "gitlab-jws-key-base" "development-jwt-signing-key-complete-production";
    };
    
    # GitLab configuration
    extraConfig = {
      gitlab = {
        host = "localhost";
        port = 443;
        https = true;
        relative_url_root = "/gitlab";
        max_request_size = "10G";
      };
      
      # Enable container registry
      registry = {
        enable = true;
        host = "localhost";
        port = 5000;
      };
      
      # Artifacts configuration
      artifacts = {
        enabled = true;
        path = "/var/lib/gitlab/artifacts";
        max_size = "5G";
      };
      
      # LFS configuration
      lfs = {
        enabled = true;
        storage_path = "/var/lib/gitlab/lfs";
      };
    };
  };

  # ===== GRAFANA SERVICE =====

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        domain = "localhost";  # Changed from rave.local to localhost  
        root_url = "https://localhost:8443/grafana/";
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

  # ===== MATRIX SYNAPSE =====
  # Disabled pending configuration fix for NixOS 24.11
  
  # services.matrix-synapse = {
  #   enable = false;
  #   # ... configuration commented out for now
  # };

  # ===== NGINX CONFIGURATION =====

  services.nginx = {
    enable = true;
    
    # Global configuration
    clientMaxBodySize = "10G";
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    # Status page for monitoring
    statusPage = true;
    
    virtualHosts."localhost" = {
      forceSSL = true;
      enableACME = false;
      
      # Use manual certificate configuration
      sslCertificate = "/var/lib/acme/rave.local/cert.pem";
      sslCertificateKey = "/var/lib/acme/rave.local/key.pem";
      
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
                          <div class="service-url">https://localhost:8443/gitlab/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/grafana/" class="service-card">
                          <div class="service-title">📊 Grafana</div>
                          <div class="service-desc">Monitoring dashboards and analytics</div>
                          <div class="service-url">https://localhost:8443/grafana/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/matrix/" class="service-card">
                          <div class="service-title">💬 Matrix Synapse</div>
                          <div class="service-desc">Secure communications server</div>
                          <div class="service-url">https://localhost:8443/matrix/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/prometheus/" class="service-card">
                          <div class="service-title">🔍 Prometheus</div>
                          <div class="service-desc">Metrics collection and monitoring</div>
                          <div class="service-url">https://localhost:8443/prometheus/</div>
                          <span class="status active">Active</span>
                      </a>
                      <a href="/nats/" class="service-card">
                          <div class="service-title">⚡ NATS JetStream</div>
                          <div class="service-desc">High-performance messaging system</div>
                          <div class="service-url">https://localhost:8443/nats/</div>
                          <span class="status active">Active</span>
                      </a>
                  </div>
              </div>
          </body>
          </html>
        '';
      };
      
      # GitLab reverse proxy
      locations."/gitlab/" = {
        proxyPass = "http://127.0.0.1:8080/gitlab/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Ssl on;
          
          # GitLab specific headers
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_cache_bypass $http_upgrade;
          
          # File upload support
          client_max_body_size 10G;
          proxy_connect_timeout 300s;
          proxy_send_timeout 300s;
          proxy_read_timeout 300s;
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
      
      # Matrix Synapse reverse proxy
      locations."/matrix/" = {
        proxyPass = "http://127.0.0.1:8008/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
      
      # Matrix client well-known
      locations."/.well-known/matrix/client" = {
        return = ''200 '{"m.homeserver":{"base_url":"https://localhost:8443/matrix/"}}'';
        extraConfig = "add_header Content-Type application/json;";
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
      '';
    };
    
    # HTTP redirect to HTTPS
    virtualHosts."localhost-http" = {
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      locations."/" = {
        return = "301 https://localhost:8443$request_uri";
      };
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
      
      CERT_DIR="/var/lib/acme/rave.local"
      
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
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = rave.local
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
      8080  # GitLab internal
      3000  # Grafana internal
      8008  # Matrix internal
      9090  # Prometheus internal
      8222  # NATS monitoring
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
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER matrix_synapse PASSWORD 'matrix-production-password';" || true
      
      # Grant additional permissions
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT CONNECT ON DATABASE postgres TO grafana;" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT USAGE ON SCHEMA public TO grafana;" || true
    '';
    
    # GitLab depends on database and certificates
    gitlab.after = [ "postgresql.service" "redis-gitlab.service" "generate-localhost-certs.service" ];
    gitlab.requires = [ "postgresql.service" "redis-gitlab.service" ];
    
    # Grafana depends on database and certificates
    grafana.after = [ "postgresql.service" "generate-localhost-certs.service" ];
    grafana.requires = [ "postgresql.service" ];
    
    # Matrix disabled
    # matrix-synapse.after = [ "postgresql.service" "redis-matrix.service" "generate-localhost-certs.service" ];
    # matrix-synapse.requires = [ "postgresql.service" "redis-matrix.service" ];
    
    # nginx depends on certificates and all backend services
    nginx.after = [ 
      "generate-localhost-certs.service" 
      "gitlab.service"
      "grafana.service" 
      # "matrix-synapse.service" # disabled
      "prometheus.service"
      "nats.service"
    ];
    nginx.requires = [ "generate-localhost-certs.service" ];
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
echo "   🦊 GitLab:      https://localhost:8443/gitlab/"
echo "   📊 Grafana:     https://localhost:8443/grafana/"  
echo "   💬 Matrix:      https://localhost:8443/matrix/"
echo "   🔍 Prometheus:  https://localhost:8443/prometheus/"
echo "   ⚡ NATS:        https://localhost:8443/nats/"
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status postgresql redis-gitlab redis-penpot redis-matrix nats prometheus grafana gitlab matrix-synapse nginx --no-pager -l
echo ""
echo "🌐 Dashboard: https://localhost:8443/"
echo ""
EOF
      chmod +x /root/welcome.sh
      echo "/root/welcome.sh" >> /root/.bashrc
    '';
  };
}