# Demo HTTPS Configuration - Simplified for Demonstration
# Based on P0 production with minimal HTTPS additions

{ config, pkgs, lib, ... }:

{
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  # P0.3: SAFE mode memory discipline  
  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 1;
    cores = 2;
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    sandbox = true;
    extra-substituters = [ "https://nix-community.cachix.org" ];
  };

  # Boot configuration for VM
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
  boot.kernelParams = lib.mkDefault [ "console=ttyS0,115200n8" "console=tty0" ];
  boot.loader.timeout = lib.mkDefault 3;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim wget curl git htop tree jq
    openssl # For certificate operations
  ];

  # Simple certificate generation service
  systemd.services.rave-cert-generator = {
    description = "RAVE Development SSL Certificate Generator";
    wantedBy = [ "nginx.service" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      CERT_DIR="/var/lib/nginx/certs"
      
      echo "🔐 RAVE Certificate Generator: Starting..."
      mkdir -p "$CERT_DIR"
      
      # Only generate if certificates don't exist
      if [[ ! -f "$CERT_DIR/cert.pem" ]] || [[ ! -f "$CERT_DIR/key.pem" ]]; then
        echo "📝 Creating OpenSSL configuration..."
        
        cat > "$CERT_DIR/dev-cert.conf" << 'EOF'
[req]
default_bits = 4096
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_ca

[req_distinguished_name]
C=US
ST=Development
L=LocalDev
O=RAVE Development Environment
OU=Infrastructure Team
CN=localhost

[v3_req]
keyUsage = critical, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[v3_ca]
keyUsage = critical, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
basicConstraints = CA:false

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
DNS.3 = rave-demo
DNS.4 = *.rave-demo
DNS.5 = gitlab.local
DNS.6 = *.gitlab.local
DNS.7 = rave.local
DNS.8 = *.rave.local
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 10.0.2.15
IP.4 = 192.168.122.1
EOF

        echo "🔑 Generating certificates..."
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/csr.pem" -config "$CERT_DIR/dev-cert.conf"
        ${pkgs.openssl}/bin/openssl x509 -req -in "$CERT_DIR/csr.pem" -signkey "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 365 -extensions v3_ca -extfile "$CERT_DIR/dev-cert.conf"
        
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true
        rm -f "$CERT_DIR/csr.pem"
        
        echo "✅ Certificates generated successfully!"
      else
        echo "✅ Certificates already exist"
      fi
      
      echo "🌐 RAVE HTTPS Demo Ready!"
    '';
  };

  # Simplified nginx configuration for demo
  services.nginx = {
    enable = true;
    package = pkgs.nginx;
    
    # Simple configuration without complex headers
    appendConfig = ''
      worker_processes auto;
      worker_connections 1024;
      keepalive_timeout 65;
      gzip on;
    '';

    virtualHosts.localhost = {
      listen = [
        { addr = "0.0.0.0"; port = 8080; ssl = true; }   # HTTPS primary
        { addr = "0.0.0.0"; port = 8081; ssl = false; }  # HTTP fallback  
      ];
      
      # Use generated self-signed certificates
      sslCertificate = "/var/lib/nginx/certs/cert.pem";
      sslCertificateKey = "/var/lib/nginx/certs/key.pem";
      
      # Simple SSL configuration
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
      '';

      locations = {
        # Simple health check
        "/health" = {
          return = "200 'RAVE HTTPS Demo Ready!'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
        
        # GitLab main application  
        "/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Ssl on;
            proxy_set_header X-Forwarded-Port 8080;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_http_version 1.1;
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            client_max_body_size 1024m;
          '';
        };
      };
    };
  };

  # Ensure nginx user and certificate directories exist
  users.users.nginx = {
    isSystemUser = true;
    group = "nginx"; 
  };
  users.groups.nginx = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/nginx 0755 nginx nginx -"
    "d /var/lib/nginx/certs 0755 nginx nginx -"
  ];

  # GitLab CE Configuration  
  services.gitlab = {
    enable = true;
    host = "localhost";
    port = 8080;
    https = true;  # Enable HTTPS mode
    
    initialRootPasswordFile = pkgs.writeText "gitlab-root-password" "rave-demo-password";
    
    secrets = {
      secretFile = pkgs.writeText "gitlab-secret" "rave-demo-secret-key";
      otpFile = pkgs.writeText "gitlab-otp" "rave-demo-otp-key";
      dbFile = pkgs.writeText "gitlab-db" "rave-demo-db-key";
      jwsFile = pkgs.writeText "gitlab-jws" "rave-demo-jws-key";
      activeRecordPrimaryKeyFile = pkgs.writeText "gitlab-ar-primary" "rave-demo-ar-primary-key";
      activeRecordDeterministicKeyFile = pkgs.writeText "gitlab-ar-deterministic" "rave-demo-ar-deterministic-key";
      activeRecordSaltFile = pkgs.writeText "gitlab-ar-salt" "rave-demo-ar-salt";
    };
    
    databasePasswordFile = pkgs.writeText "gitlab-db-password" "rave-demo-db-password";
    
    extraConfig = {
      gitlab = {
        email_enabled = false;
        default_projects_features = {
          issues = true;
          merge_requests = true;
          wiki = true;
          snippets = true;
        };
      };
      
      external_url = "https://localhost:8080";
      
      nginx = {
        enable = false;  # Use system nginx instead
      };
    };
  };

  # PostgreSQL for GitLab
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    ensureDatabases = [ "gitlab" ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
      }
    ];
  };

  # Redis for GitLab
  services.redis.servers.gitlab = {
    enable = true;
    user = "gitlab";
  };

  # SSH access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Networking
  networking.firewall.allowedTCPPorts = [ 8080 8081 2222 ];
  networking.hostName = "rave-demo-https";

  # Demo MOTD
  environment.etc."motd".text = lib.mkForce ''
    
    🚀 RAVE HTTPS Demo Environment
    =============================
    
    🔒 GitLab HTTPS: https://localhost:8080
    🌐 GitLab HTTP:  http://localhost:8081
    
    📍 Health Check: https://localhost:8080/health
    
    ⚠️  BROWSER SECURITY WARNINGS ARE EXPECTED!
    This uses self-signed certificates for demonstration.
    
    🔧 To Accept Certificate:
    Chrome:  Advanced → Proceed to localhost (unsafe)
    Firefox: Advanced → Accept Risk and Continue
    Safari:  Show Details → Visit Website
    
    🎯 GitLab Login: root / rave-demo-password
    
  '';
}