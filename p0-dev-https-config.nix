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
    wantedBy = [ "multi-user.target" ];
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
      
      # SSL configuration  
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
          return = "200 'RAVE HTTPS Certificate Demo - Working!'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };

        # RAVE Certificate Demo Page
        "/" = {
          return = "200 '🎉 RAVE HTTPS Certificate Demo Successfully Running!\n\n✅ Automated SSL Certificate Generation: WORKING\n✅ nginx with HTTPS Configuration: WORKING  \n✅ Self-signed Certificate Installation: WORKING\n✅ TLS 1.2/1.3 Support: WORKING\n\n📋 What This Demonstrates:\n• Automated certificate generation for local development\n• nginx configured with proper HTTPS support\n• Self-signed certificates with SAN (Subject Alternative Names)\n• Certificate covers: localhost, *.localhost, rave-demo, gitlab.local\n\n🌐 Access Points:\n• HTTPS Main: https://localhost:8080/\n• HTTPS Health: https://localhost:8080/health\n• HTTP Fallback: http://localhost:8081/\n\n🔧 Browser Security Warning:\nClick \"Advanced\" → \"Proceed to localhost (unsafe)\"\nThis is normal for self-signed certificates in development!\n\n🚀 Ready for GitLab or any web application deployment!\n'";
          extraConfig = ''
            add_header Content-Type text/plain;
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

  # Minimal services for certificate demo

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

  # Certificate Demo MOTD
  environment.etc."motd".text = lib.mkForce ''
    
    🎉 RAVE HTTPS Certificate Demo - SUCCESS!
    ========================================
    
    🔒 HTTPS Demo: https://localhost:8080/
    🌐 HTTP Demo:  http://localhost:8081/
    
    📍 Endpoints:
    - Main Demo: https://localhost:8080/
    - Health:    https://localhost:8080/health
    
    ✅ Automated certificate generation working!
    ✅ nginx with HTTPS configuration working!
    ✅ Self-signed certificates for local development!
    
    🔧 Browser: Click "Advanced" → "Proceed to localhost"
    
  '';
}