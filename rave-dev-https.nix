# RAVE Development Configuration with Automated HTTPS
# Complete local development setup with self-signed certificates

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./p0-production-config.nix  # Base RAVE configuration
    ./nginx-https-dev.nix       # HTTPS nginx with auto-generated certs
  ];

  # Override the base nginx configuration with our HTTPS development version
  services.nginx = lib.mkForce {
    enable = true;
    package = pkgs.nginx;
    
    appendConfig = ''
      worker_processes auto;
      worker_connections 1024;
      keepalive_timeout 65;
      
      gzip on;
      gzip_vary on;
      gzip_min_length 1024;
      gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    '';

    virtualHosts."localhost" = {
      listen = [
        { addr = "0.0.0.0"; port = 8080; ssl = true; }   # HTTPS
        { addr = "0.0.0.0"; port = 8081; ssl = false; }  # HTTP fallback
      ];
      
      sslCertificate = "/var/lib/nginx/certs/cert.pem";
      sslCertificateKey = "/var/lib/nginx/certs/key.pem";
      
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        
        add_header Strict-Transport-Security "max-age=300; includeSubDomains" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:;" always;
      '';

      locations = {
        "/health" = {
          return = "200 'RAVE HTTPS Demo Ready\\nSSL: $ssl_protocol $ssl_cipher\\nTimestamp: $time_iso8601\\n'";
          extraConfig = ''
            add_header Content-Type text/plain;
            access_log off;
          '';
        };
        
        "/ssl-info" = {
          return = "200 'RAVE Development SSL Certificate\\nIssuer: RAVE Development\\nSubject: localhost\\nValid for: localhost, *.localhost, rave-demo, gitlab.local\\n\\nThis is a SELF-SIGNED certificate for development use only.\\nYou will see browser security warnings - this is normal!\\n'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };

        "/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
          extraConfig = ''
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Ssl on;
            proxy_set_header X-Forwarded-Port 8080;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            
            client_max_body_size 1024m;
            client_body_buffer_size 128k;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
            proxy_busy_buffers_size 8k;
          '';
        };

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

    logError = "stderr info";
    appendHttpConfig = ''
      log_format detailed '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'ssl="$ssl_protocol/$ssl_cipher"';
      access_log /var/log/nginx/access.log detailed;
    '';
  };

  # Certificate generation service (from generate-dev-certs.nix)
  systemd.services.rave-generate-dev-certs = {
    description = "Generate RAVE development SSL certificates";
    wantedBy = [ "nginx.service" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      CERT_DIR="/var/lib/nginx/certs"
      
      echo "🔐 RAVE: Generating development SSL certificates..."
      mkdir -p "$CERT_DIR"
      
      if [[ ! -f "$CERT_DIR/cert.pem" ]] || [[ ! -f "$CERT_DIR/key.pem" ]]; then
        cat > "$CERT_DIR/openssl.conf" << 'EOF'
[req]
default_bits = 4096
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_ca

[req_distinguished_name]
C=US
ST=Development
L=Local
O=RAVE Development
OU=AI Infrastructure
CN=localhost

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[v3_ca]
keyUsage = keyEncipherment, dataEncipherment
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
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 10.0.2.15
EOF

        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/csr.pem" -config "$CERT_DIR/openssl.conf"
        ${pkgs.openssl}/bin/openssl x509 -req -in "$CERT_DIR/csr.pem" -signkey "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 365 -extensions v3_ca -extfile "$CERT_DIR/openssl.conf"
        
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true
        
        rm -f "$CERT_DIR/csr.pem"
        
        echo "✅ RAVE HTTPS Development certificates generated!"
        echo "🔗 Access RAVE at: https://localhost:8080 (HTTPS)"
        echo "🔗 Fallback HTTP at: http://localhost:8081 (HTTP)" 
        echo "⚠️  Browser will show security warnings - click 'Advanced' -> 'Proceed to localhost'"
      fi
    '';
  };

  # Ensure certificate directory and permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/nginx 0755 nginx nginx -"
    "d /var/lib/nginx/certs 0755 nginx nginx -" 
  ];

  # Development-specific system message
  environment.etc."motd".text = lib.mkForce ''
    
    🚀 RAVE Development Environment with HTTPS
    ==========================================
    
    GitLab:     https://localhost:8080 (HTTPS - self-signed cert)
    GitLab:     http://localhost:8081  (HTTP fallback)
    Health:     https://localhost:8080/health
    SSL Info:   https://localhost:8080/ssl-info
    Prometheus: https://localhost:8080/prometheus/
    
    ⚠️  BROWSER SECURITY WARNINGS ARE NORMAL
    Self-signed certificates will trigger warnings.
    Click "Advanced" -> "Proceed to localhost (unsafe)"
    
    📁 Certificates: /var/lib/nginx/certs/
    📋 Logs: /var/log/nginx/
    
  '';
}