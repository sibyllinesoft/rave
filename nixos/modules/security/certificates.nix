# nixos/modules/security/certificates.nix
# TLS certificate management for RAVE services
{ config, pkgs, lib, ... }:

let
  # Development certificate generation script
  generateDevCerts = pkgs.writeScript "generate-dev-certs.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    CERT_DIR="/var/lib/acme/rave.local"
    
    echo "🔐 Generating development certificates for rave.local..."
    
    # Create certificate directory
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR"
    
    # Generate CA private key
    if [ ! -f "ca-key.pem" ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out ca-key.pem 4096
    fi
    
    # Generate CA certificate
    if [ ! -f "ca.pem" ]; then
      ${pkgs.openssl}/bin/openssl req -new -x509 -days 365 -key ca-key.pem -out ca.pem -subj "/C=US/ST=Development/L=Local/O=RAVE/OU=Development/CN=RAVE Development CA"
    fi
    
    # Generate server private key
    if [ ! -f "key.pem" ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out key.pem 4096
    fi
    
    # Generate certificate signing request
    if [ ! -f "cert.csr" ]; then
      ${pkgs.openssl}/bin/openssl req -new -key key.pem -out cert.csr -subj "/C=US/ST=Development/L=Local/O=RAVE/OU=Development/CN=rave.local" -config <(
        echo '[req]'
        echo 'distinguished_name = req_distinguished_name'
        echo 'req_extensions = v3_req'
        echo '[req_distinguished_name]'
        echo '[v3_req]'
        echo 'basicConstraints = CA:FALSE'
        echo 'keyUsage = nonRepudiation, digitalSignature, keyEncipherment'
        echo 'subjectAltName = @alt_names'
        echo '[alt_names]'
        echo 'DNS.1 = rave.local'
        echo 'DNS.2 = *.rave.local'
        echo 'DNS.3 = localhost'
        echo 'IP.1 = 127.0.0.1'
        echo 'IP.2 = ::1'
      )
    fi
    
    # Generate server certificate
    if [ ! -f "cert.pem" ]; then
      ${pkgs.openssl}/bin/openssl x509 -req -days 365 -in cert.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out cert.pem -extensions v3_req -extfile <(
        echo '[v3_req]'
        echo 'basicConstraints = CA:FALSE'
        echo 'keyUsage = nonRepudiation, digitalSignature, keyEncipherment'
        echo 'subjectAltName = @alt_names'
        echo '[alt_names]'
        echo 'DNS.1 = rave.local'
        echo 'DNS.2 = *.rave.local'
        echo 'DNS.3 = localhost'
        echo 'IP.1 = 127.0.0.1'
        echo 'IP.2 = ::1'
      )
    fi
    
    # Set proper permissions for nginx access
    chmod 755 "$CERT_DIR"
    chmod 644 "$CERT_DIR"/cert.pem
    chmod 644 "$CERT_DIR"/ca.pem
    chmod 640 "$CERT_DIR"/key.pem
    
    # Make certificates readable by nginx
    chgrp -f nginx "$CERT_DIR"/cert.pem "$CERT_DIR"/key.pem 2>/dev/null || true
    
    echo "✅ Development certificates generated successfully!"
    echo "📁 Certificates location: $CERT_DIR"
    echo "🔧 To trust the CA certificate, add ca.pem to your system's trust store"
  '';
in
{
  # Certificate management options
  options = {
    rave.certificates = {
      domain = lib.mkOption {
        type = lib.types.str;
        default = "rave.local";
        description = "Primary domain for certificate generation";
      };
      
      useACME = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use ACME (Let's Encrypt) for certificate generation";
      };
      
      email = lib.mkOption {
        type = lib.types.str;
        default = "admin@rave.local";
        description = "Email address for ACME registration";
      };
    };
  };

  config = {
    # ACME configuration for production
    security.acme = lib.mkIf config.rave.certificates.useACME {
      acceptTerms = true;
      defaults.email = config.rave.certificates.email;
      
      certs."${config.rave.certificates.domain}" = {
        domain = config.rave.certificates.domain;
        extraDomainNames = [
          "*.${config.rave.certificates.domain}"
          "gitlab.${config.rave.certificates.domain}"
          "matrix.${config.rave.certificates.domain}"
          "element.${config.rave.certificates.domain}"
          "grafana.${config.rave.certificates.domain}"
        ];
        
        # Use DNS challenge for wildcard certificates
        dnsProvider = "cloudflare"; # Configure as needed
        credentialsFile = "/var/lib/acme/cloudflare-credentials"; # Manage with sops-nix
        
        group = "nginx";
        reloadServices = [ "nginx" ];
      };
    };

    # Development certificate generation
    systemd.services.generate-dev-certs = lib.mkIf (!config.rave.certificates.useACME) {
      description = "Generate development TLS certificates";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      after = [ "local-fs.target" ];
      wants = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = generateDevCerts;
        # Ensure directory creation
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/acme/rave.local";
      };
    };

    # Create ACME directories and users
    users.users.nginx.extraGroups = lib.optionals config.rave.certificates.useACME [ "acme" ];

    # Nginx SSL configuration
    services.nginx = {
      enable = true;
      
      # SSL configuration
      sslProtocols = "TLSv1.2 TLSv1.3";
      sslCiphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384";
      sslDhparam = pkgs.runCommand "dhparams.pem" {} ''
        ${pkgs.openssl}/bin/openssl dhparam -out $out 2048
      '';
      
      # Security headers
      commonHttpConfig = ''
        # Security headers - only for HTTPS sites
        map $scheme $security_headers {
          "https" "1";
          default "";
        }
        
        # Rate limiting
        limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
        limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
        
        # Connection limiting
        limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
        limit_conn conn_limit_per_ip 20;
      '';

      virtualHosts."${config.rave.certificates.domain}" = {
        # SSL configuration
        forceSSL = true;
        
        # Certificate configuration
        sslCertificate = lib.mkIf (!config.rave.certificates.useACME) "/var/lib/acme/rave.local/cert.pem";
        sslCertificateKey = lib.mkIf (!config.rave.certificates.useACME) "/var/lib/acme/rave.local/key.pem";
        useACMEHost = lib.mkIf config.rave.certificates.useACME config.rave.certificates.domain;
        
        # Default location
        locations."/" = {
          extraConfig = ''
            access_log off;
            # Security headers for HTTPS
            add_header X-Frame-Options DENY always;
            add_header X-Content-Type-Options nosniff always;
            add_header X-XSS-Protection "1; mode=block" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
            add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' wss: https:;" always;
            add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
            add_header Content-Type text/html;
            return 200 'RAVE System Online';
          '';
        };
        
        # Security-related endpoints
        locations."/.well-known/security.txt" = {
          return = "200 'Contact: admin@rave.local\nExpires: 2025-12-31T23:59:59.000Z\nPreferred-Languages: en'";
        };
        
        locations."/robots.txt" = {
          return = "200 'User-agent: *\nDisallow: /'";
        };
      };

      # HTTP to HTTPS redirect
      virtualHosts."${config.rave.certificates.domain}-http" = {
        serverName = config.rave.certificates.domain;
        listen = [{ addr = "0.0.0.0"; port = 80; }];
        locations."/" = {
          return = "301 https://$host$request_uri";
        };
      };

      # Localhost-only HTTP listener (no SSL warnings) - GitLab proxy
      virtualHosts."localhost-plain" = {
        serverName = "_"; # Default server - matches any hostname
        listen = [{ addr = "0.0.0.0"; port = 8888; }];
        default = true; # Make this the default server for port 8888
        locations."/" = {
          proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Ssl off;
            # GitLab specific headers
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            # Handle large file uploads (artifacts, LFS)
            client_max_body_size 1G;
            proxy_request_buffering off;
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
            proxy_send_timeout 300;
          '';
        };
        locations."/health" = {
          extraConfig = ''
            access_log off;
            add_header Content-Type text/plain;
            return 200 'OK';
          '';
        };
      };
    };

    # Certificate renewal monitoring
    systemd.services.cert-renewal-monitor = lib.mkIf config.rave.certificates.useACME {
      description = "Monitor certificate renewal";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "cert-renewal-monitor" ''
          #!${pkgs.bash}/bin/bash
          
          CERT_DIR="/var/lib/acme/${config.rave.certificates.domain}"
          CERT_FILE="$CERT_DIR/cert.pem"
          
          if [ -f "$CERT_FILE" ]; then
            EXPIRY=$(${pkgs.openssl}/bin/openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
            CURRENT_EPOCH=$(date +%s)
            DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
            
            echo "Certificate expires in $DAYS_UNTIL_EXPIRY days"
            
            if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
              echo "WARNING: Certificate expires in less than 30 days!"
              # Send notification (implement as needed)
            fi
          else
            echo "ERROR: Certificate file not found: $CERT_FILE"
          fi
        '';
      };
    };

    systemd.timers.cert-renewal-monitor = lib.mkIf config.rave.certificates.useACME {
      description = "Monitor certificate renewal daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # Open HTTPS port in firewall
    networking.firewall.allowedTCPPorts = [ 443 8888 ];
  };
}