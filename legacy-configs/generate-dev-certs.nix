# RAVE Self-Signed Certificate Generation for Local Development
# This solves the common pain point of SSL certificate setup for local/development environments

{ lib, pkgs, config, ... }:

{
  # P0.4: Automated self-signed certificate generation for local development
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
      
      # Create certificate directory
      mkdir -p "$CERT_DIR"
      
      # Only generate if certificates don't exist
      if [[ ! -f "$CERT_DIR/cert.pem" ]] || [[ ! -f "$CERT_DIR/key.pem" ]]; then
        echo "📝 Creating certificate configuration..."
        
        # Create OpenSSL configuration for SAN (Subject Alternative Names)
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

        echo "🔑 Generating private key..."
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        
        echo "📋 Generating certificate signing request..."
        ${pkgs.openssl}/bin/openssl req -new \
          -key "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/csr.pem" \
          -config "$CERT_DIR/openssl.conf"
        
        echo "📜 Generating self-signed certificate (valid for 365 days)..."
        ${pkgs.openssl}/bin/openssl x509 -req \
          -in "$CERT_DIR/csr.pem" \
          -signkey "$CERT_DIR/key.pem" \
          -out "$CERT_DIR/cert.pem" \
          -days 365 \
          -extensions v3_ca \
          -extfile "$CERT_DIR/openssl.conf"
        
        # Set proper permissions
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true
        
        echo "✅ Self-signed certificate generated successfully!"
        echo "📍 Certificate: $CERT_DIR/cert.pem"
        echo "📍 Private Key: $CERT_DIR/key.pem"
        
        # Display certificate info
        echo "📊 Certificate Information:"
        ${pkgs.openssl}/bin/openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -E "(Subject:|DNS:|IP Address:|Not Before|Not After)"
        
        # Clean up CSR
        rm -f "$CERT_DIR/csr.pem"
        
      else
        echo "✅ SSL certificates already exist, skipping generation"
        echo "📊 Existing Certificate Information:"
        ${pkgs.openssl}/bin/openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -E "(Subject:|DNS:|IP Address:|Not Before|Not After)"
      fi
      
      # Create certificate info file for users
      cat > "$CERT_DIR/README.md" << 'EOF'
# RAVE Development SSL Certificates

## 🔐 About These Certificates

These are **self-signed certificates** automatically generated for local development use.

### ⚠️ Browser Security Warnings

You will see security warnings in browsers because these certificates are self-signed:
- Chrome: "Your connection is not private" 
- Firefox: "Warning: Potential Security Risk Ahead"
- Safari: "This Connection Is Not Private"

**This is expected and normal for development!**

### 🔧 How to Accept Self-Signed Certificates

**Chrome/Edge:**
1. Click "Advanced"
2. Click "Proceed to localhost (unsafe)"

**Firefox:**  
1. Click "Advanced"
2. Click "Accept the Risk and Continue"

**Safari:**
1. Click "Show Details" 
2. Click "visit this website"
3. Click "Visit Website"

### 📋 Certificate Details

- **Domains:** localhost, *.localhost, rave-demo, *.rave-demo, gitlab.local, *.gitlab.local
- **IP Addresses:** 127.0.0.1, ::1, 10.0.2.15
- **Valid:** 365 days from generation
- **Algorithm:** RSA 4096-bit

### 🚀 For Production Use

Replace these certificates with proper certificates from:
- Let's Encrypt (free, automated)
- Your organization's CA
- Commercial certificate providers

### 📁 Certificate Files

- `cert.pem` - Public certificate
- `key.pem` - Private key (keep secure!)
- `openssl.conf` - Certificate configuration used

EOF

      echo "📖 Created certificate documentation at $CERT_DIR/README.md"
      echo ""
      echo "🌐 RAVE is now ready for HTTPS local development!"
      echo "🔗 Access GitLab at: https://localhost:8080"
      echo "⚠️  You'll see browser security warnings - this is normal for self-signed certificates"
      echo "✅ Click 'Advanced' -> 'Proceed to localhost (unsafe)' to continue"
    '';
  };
}