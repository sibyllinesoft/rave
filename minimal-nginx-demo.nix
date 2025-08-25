# Minimal RAVE Demo - nginx + Certificate Infrastructure
# Proves the HTTPS automation works without GitLab complexity

{ config, pkgs, lib, ... }:

{
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim wget curl git htop tree jq openssl
  ];

  # Boot configuration for VM
  boot.loader.grub.enable = lib.mkDefault true;
  boot.loader.grub.device = lib.mkDefault "/dev/vda";
  boot.kernelParams = lib.mkDefault [ "console=ttyS0,115200n8" "console=tty0" ];
  boot.loader.timeout = lib.mkDefault 3;

  # Certificate Generation Service
  systemd.services.rave-cert-generator = {
    description = "RAVE Development SSL Certificate Generator";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      CERT_DIR="/var/lib/nginx/certs"
      mkdir -p "$CERT_DIR"
      
      if [[ ! -f "$CERT_DIR/cert.pem" ]] || [[ ! -f "$CERT_DIR/key.pem" ]]; then
        echo "🔑 Generating HTTPS certificates for RAVE demo..."
        
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

        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/csr.pem" -config "$CERT_DIR/dev-cert.conf"
        ${pkgs.openssl}/bin/openssl x509 -req -in "$CERT_DIR/csr.pem" -signkey "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 365 -extensions v3_ca -extfile "$CERT_DIR/dev-cert.conf"
        
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true
        rm -f "$CERT_DIR/csr.pem"
        
        echo "✅ HTTPS certificates generated successfully!"
      else
        echo "✅ HTTPS certificates already exist"
      fi
    '';
  };

  # Simple nginx with both HTTP and HTTPS
  services.nginx = {
    enable = true;
    package = pkgs.nginx;
    
    virtualHosts."localhost" = {
      listen = [
        { addr = "0.0.0.0"; port = 8080; ssl = true; }   # HTTPS primary
        { addr = "0.0.0.0"; port = 8081; ssl = false; }  # HTTP fallback  
      ];
      
      sslCertificate = "/var/lib/nginx/certs/cert.pem";
      sslCertificateKey = "/var/lib/nginx/certs/key.pem";
      
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
      '';

      locations = {
        "/health" = {
          return = "200 'RAVE HTTPS Demo Ready - Certificate automation working!'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
        
        "/" = {
          return = "200 'Welcome to RAVE HTTPS Demo!\n\nThis proves:\n✅ Automated certificate generation\n✅ HTTPS configuration\n✅ nginx running successfully\n\nAccess:\n- HTTPS: https://localhost:8080/\n- HTTP:  http://localhost:8081/\n- Health: https://localhost:8080/health\n\nCertificate covers: localhost, *.localhost, rave-demo, gitlab.local, rave.local\n\nLogin for full GitLab demo: root / rave-development-password\n'";
          extraConfig = ''
            add_header Content-Type text/plain;
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
  networking.hostName = "rave-https-demo";

  # Simple MOTD
  environment.etc."motd".text = lib.mkForce ''
    
    🎉 RAVE HTTPS Demo - Certificate Automation Success!
    ================================================
    
    🔒 HTTPS Demo: https://localhost:8080/
    🌐 HTTP Demo:  http://localhost:8081/
    
    📍 Endpoints:
    - Main Demo: https://localhost:8080/
    - Health:    https://localhost:8080/health
    
    ✅ Automated HTTPS certificate generation working!
    ✅ Browser warnings are normal for self-signed certs
    
    🔧 Browser: Click "Advanced" → "Proceed to localhost"
    
  '';

  # Auto-login root user to console (for demo purposes)
  services.getty.autologinUser = "root";
}