# P0 Development Configuration with HTTPS Self-Signed Certificates
# Solves the certificate pain point for local development environments
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

  # P0.4: Certificate Generation Service - Automated self-signed certificates for local development
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
        echo "📝 Creating OpenSSL configuration for development certificates..."
        
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

        echo "🔑 Generating 4096-bit RSA private key..."
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        
        echo "📋 Creating certificate signing request..."
        ${pkgs.openssl}/bin/openssl req -new \
          -key "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/csr.pem" \
          -config "$CERT_DIR/dev-cert.conf"
        
        echo "📜 Generating self-signed certificate (365 days validity)..."
        ${pkgs.openssl}/bin/openssl x509 -req \
          -in "$CERT_DIR/csr.pem" \
          -signkey "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/cert.pem" \
          -days 365 \
          -extensions v3_ca \
          -extfile "$CERT_DIR/dev-cert.conf"
        
        # Set secure permissions
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true
        
        # Clean up temporary files
        rm -f "$CERT_DIR/csr.pem"
        
        echo "✅ Self-signed development certificate generated successfully!"
        echo ""
        echo "📊 Certificate Details:"
        ${pkgs.openssl}/bin/openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | \
          grep -E "(Subject:|Issuer:|DNS:|IP Address:|Not Before|Not After)" | \
          head -10
        
        # Create user documentation
        cat > "$CERT_DIR/CERTIFICATE-INFO.md" << 'EOF'
# RAVE Development SSL Certificate

## ⚠️ Important: This is a SELF-SIGNED Certificate

This certificate was automatically generated for **local development use only**.

### Expected Browser Warnings

You **will** see security warnings like:
- Chrome: "Your connection is not private" / NET::ERR_CERT_AUTHORITY_INVALID
- Firefox: "Warning: Potential Security Risk Ahead"
- Safari: "This Connection Is Not Private"

**This is normal and expected for self-signed certificates!**

### How to Proceed in Browsers

**Chrome/Chromium:**
1. Click "Advanced"
2. Click "Proceed to localhost (unsafe)"

**Firefox:**
1. Click "Advanced..."  
2. Click "Accept the Risk and Continue"

**Safari:**
1. Click "Show Details"
2. Click "visit this website"
3. Click "Visit Website"

### Certificate Coverage

This certificate is valid for:
- localhost (IPv4/IPv6)
- *.localhost
- rave-demo / *.rave-demo
- gitlab.local / *.gitlab.local
- rave.local / *.rave.local
- Common local IPs (127.0.0.1, ::1, 10.0.2.15, 192.168.122.1)

### For Production

**Never use self-signed certificates in production!**

Use proper certificates from:
- Let's Encrypt (free, automated)
- Your organization's Certificate Authority
- Commercial certificate providers (DigiCert, GlobalSign, etc.)

### Files

- `cert.pem` - Public certificate
- `key.pem` - Private key (**keep secure!**)
- `dev-cert.conf` - OpenSSL configuration used
EOF

      else
        echo "✅ Development certificates already exist"
        echo "📊 Current Certificate Info:"
        ${pkgs.openssl}/bin/openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | \
          grep -E "(Not Before|Not After)" || echo "  Certificate validity info not available"
      fi
      
      echo ""
      echo "🌐 RAVE HTTPS Development Environment Ready!"
      echo "🔗 Access at: https://localhost:8080"
      echo "⚠️  Browser warnings are normal - click through them safely"
    '';
  };

  # Nginx configuration with HTTPS using generated certificates
  services.nginx = {
    enable = true;
    package = pkgs.nginx;
    
    virtualHosts."localhost" = {
      listen = [
        { addr = "0.0.0.0"; port = 8080; ssl = true; }   # HTTPS primary
        { addr = "0.0.0.0"; port = 8081; ssl = false; }  # HTTP fallback  
      ];
      
      # Use generated self-signed certificates
      sslCertificate = "/var/lib/nginx/certs/cert.pem";
      sslCertificateKey = "/var/lib/nginx/certs/key.pem";
      
      # Simple SSL configuration for development
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
      '';

      locations = {
        # Simple health check
        "/health" = {
          return = "200 'RAVE Ready'";
        };

        # GitLab main application  
        "/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
          extraConfig = ''
            # HTTPS proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Ssl on;
            proxy_set_header X-Forwarded-Port 8080;
            
            # WebSocket support for GitLab
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_http_version 1.1;
            
            # GitLab timeouts and buffering
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            
            # Large upload support
            client_max_body_size 1024m;
            client_body_buffer_size 128k;
            proxy_buffer_size 8k;
            proxy_buffers 16 8k;
            proxy_busy_buffers_size 16k;
          '';
        };

        # Prometheus monitoring
        "/prometheus/" = {
          proxyPass = "http://127.0.0.1:9090/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            rewrite ^/prometheus/(.*) /$1 break;
          '';
        };
      };
    };

    # Enhanced logging for development debugging
    logError = "stderr info";
    appendHttpConfig = ''
      log_format detailed_ssl '$remote_addr - $remote_user [$time_local] '
                             '"$request" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent" '
                             'ssl_protocol="$ssl_protocol" ssl_cipher="$ssl_cipher" '
                             'ssl_session_id="$ssl_session_id"';
      access_log /var/log/nginx/access.log detailed_ssl;
    '';
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
    
    initialRootPasswordFile = pkgs.writeText "gitlab-root-password" "rave-development-password";
    
    secrets = {
      secretFile = pkgs.writeText "gitlab-secret" "rave-development-secret-key";
      otpFile = pkgs.writeText "gitlab-otp" "rave-development-otp-key";
      dbFile = pkgs.writeText "gitlab-db" "rave-development-db-key";
      jwsFile = pkgs.writeText "gitlab-jws" "rave-development-jws-key";
      activeRecordPrimaryKeyFile = pkgs.writeText "gitlab-ar-primary" "rave-development-ar-primary-key";
      activeRecordDeterministicKeyFile = pkgs.writeText "gitlab-ar-deterministic" "rave-development-ar-deterministic-key";
      activeRecordSaltFile = pkgs.writeText "gitlab-ar-salt" "rave-development-ar-salt";
    };
    
    databasePasswordFile = pkgs.writeText "gitlab-db-password" "rave-db-password";
    
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
      
      # HTTPS-specific external URL configuration
      external_url = "https://localhost:8080";
      
      nginx = {
        enable = false;  # Use system nginx instead
      };
      
      # Development-friendly settings
      monitoring = {
        prometheus = {
          enable = true;
          address = "localhost";
          port = 9090;
        };
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

  # Prometheus monitoring  
  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:9100" ];
        }];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [ "systemd" ];
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
  networking.hostName = "rave-dev-https";

  # Development-focused MOTD
  environment.etc."motd".text = lib.mkForce ''
    
    🚀 RAVE Development Environment - HTTPS Ready!
    ============================================
    
    🔒 Primary (HTTPS): https://localhost:8080
    🌐 Fallback (HTTP): http://localhost:8081
    
    📍 Service Endpoints:
    - Health Check:     https://localhost:8080/health
    - SSL Information:  https://localhost:8080/ssl-info  
    - Prometheus:       https://localhost:8080/prometheus/
    
    ⚠️  BROWSER SECURITY WARNINGS ARE EXPECTED!
    This uses self-signed certificates for development.
    
    🔧 To Accept Certificate:
    Chrome:  Advanced → Proceed to localhost (unsafe)
    Firefox: Advanced → Accept Risk and Continue
    Safari:  Show Details → Visit Website
    
    📁 Certificate Files: /var/lib/nginx/certs/
    📋 Documentation: /var/lib/nginx/certs/CERTIFICATE-INFO.md
    
    🎯 GitLab Login: root / rave-development-password
    
  '';
}