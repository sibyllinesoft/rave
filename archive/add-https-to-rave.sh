#!/bin/bash
# RAVE HTTPS Certificate Generator & Nginx Configurator
# Adds automated self-signed certificate generation to any RAVE VM
# Solves the SSL certificate pain point for local development

set -euo pipefail

echo "🚀 RAVE HTTPS Certificate Generator"
echo "=================================="
echo "Adding automated HTTPS support to your RAVE environment..."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root inside the RAVE VM"
   echo "💡 Run: sudo $0"
   exit 1
fi

echo "🔐 Step 1: Setting up certificate directory..."
CERT_DIR="/var/lib/nginx/certs"
mkdir -p "$CERT_DIR"

echo "📝 Step 2: Creating OpenSSL configuration..."
cat > "$CERT_DIR/rave-dev.conf" << 'EOF'
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

echo "🔑 Step 3: Generating SSL certificates..."
cd "$CERT_DIR"

# Generate private key
echo "  - Generating 4096-bit RSA private key..."
openssl genrsa -out key.pem 4096

# Generate certificate signing request
echo "  - Creating certificate signing request..."
openssl req -new -key key.pem -out csr.pem -config rave-dev.conf

# Generate self-signed certificate
echo "  - Generating self-signed certificate (365 days)..."
openssl x509 -req -in csr.pem -signkey key.pem -out cert.pem -days 365 -extensions v3_ca -extfile rave-dev.conf

# Set permissions
chmod 600 key.pem
chmod 644 cert.pem
chown -R nginx:nginx "$CERT_DIR" 2>/dev/null || true

# Clean up
rm -f csr.pem

echo "✅ Step 3: SSL certificates generated successfully!"

echo "🌐 Step 4: Configuring nginx for HTTPS..."

# Create HTTPS nginx configuration
cat > /tmp/nginx-https.conf << 'EOF'
user root;
worker_processes auto;

events {
    worker_connections 1024;
    use epoll;
}

http {
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # GitLab upstream
    upstream gitlab-workhorse {
        server unix:/run/gitlab/gitlab-workhorse.socket fail_timeout=0;
    }

    # HTTPS server configuration
    server {
        listen 8080 ssl http2;
        listen 8081;  # HTTP fallback
        server_name localhost rave-demo *.rave-demo gitlab.local *.gitlab.local;

        # SSL configuration
        ssl_certificate /var/lib/nginx/certs/cert.pem;
        ssl_certificate_key /var/lib/nginx/certs/key.pem;
        
        # Modern SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        
        # Security headers (development-friendly)
        add_header Strict-Transport-Security "max-age=300; includeSubDomains" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-src 'self';" always;

        # Health check
        location /health {
            return 200 'RAVE HTTPS Development Ready\nSSL: $ssl_protocol / $ssl_cipher\nTime: $time_iso8601\n\nEndpoints:\n- GitLab: https://localhost:8080/\n- Health: https://localhost:8080/health\n- SSL Info: https://localhost:8080/ssl-info\n- Prometheus: https://localhost:8080/prometheus/\n';
            add_header Content-Type text/plain;
            access_log off;
        }
        
        # SSL certificate info
        location /ssl-info {
            return 200 'RAVE Development SSL Certificate\n\nIssuer: RAVE Development Environment\nSubject: localhost\n\nValid Domains:\n- localhost, *.localhost\n- rave-demo, *.rave-demo\n- gitlab.local, *.gitlab.local\n- rave.local, *.rave.local\n\nValid IPs: 127.0.0.1, ::1, 10.0.2.15, 192.168.122.1\n\n⚠️  BROWSER WARNINGS ARE NORMAL\nThis is a self-signed certificate for development.\nClick "Advanced" → "Proceed to localhost" in your browser.\n';
            add_header Content-Type text/plain;
        }

        # GitLab application
        location / {
            proxy_pass http://gitlab-workhorse;
            
            # HTTPS proxy headers
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Ssl on;
            proxy_set_header X-Forwarded-Port $server_port;
            
            # WebSocket support
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_http_version 1.1;
            
            # GitLab timeouts
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            
            # Large uploads
            client_max_body_size 1024m;
            client_body_buffer_size 128k;
            proxy_buffer_size 8k;
            proxy_buffers 16 8k;
            proxy_busy_buffers_size 16k;
        }

        # Prometheus
        location /prometheus/ {
            proxy_pass http://127.0.0.1:9090/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            rewrite ^/prometheus/(.*) /$1 break;
        }
    }
    
    # Logging
    log_format detailed '$remote_addr - $remote_user [$time_local] '
                       '"$request" $status $body_bytes_sent '
                       '"$http_referer" "$http_user_agent" '
                       'ssl="$ssl_protocol/$ssl_cipher"';
    access_log /var/log/nginx/access.log detailed;
    error_log /var/log/nginx/error.log info;
}
EOF

echo "🔄 Step 5: Restarting nginx with HTTPS configuration..."

# Stop nginx
systemctl stop nginx 2>/dev/null || killall nginx 2>/dev/null || true

# Test configuration
nginx -t -c /tmp/nginx-https.conf

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration valid!"
    
    # Start nginx with new config
    nginx -c /tmp/nginx-https.conf
    
    echo "🎯 Step 6: Verifying HTTPS setup..."
    sleep 2
    
    # Check if nginx is running
    if pgrep nginx > /dev/null; then
        echo "✅ Nginx is running with HTTPS support!"
        
        # Check if port 8080 is listening
        if netstat -tlnp | grep -q ":8080 "; then
            echo "✅ HTTPS port 8080 is listening!"
            
            # Create user documentation
            cat > "$CERT_DIR/README.md" << 'EOF'
# RAVE HTTPS Development Environment

## 🎉 HTTPS is now enabled!

Your RAVE environment now supports HTTPS with automatically generated self-signed certificates.

### 🔗 Access URLs

- **Primary HTTPS**: https://localhost:8080
- **HTTP Fallback**: http://localhost:8081
- **Health Check**: https://localhost:8080/health
- **SSL Info**: https://localhost:8080/ssl-info
- **Prometheus**: https://localhost:8080/prometheus/

### ⚠️ Expected Browser Warnings

You **will** see security warnings because these are self-signed certificates:
- Chrome: "Your connection is not private"
- Firefox: "Warning: Potential Security Risk Ahead"
- Safari: "This Connection Is Not Private"

**This is completely normal for development environments!**

### 🔧 How to Proceed in Browsers

**Chrome/Chromium:**
1. Click "Advanced"
2. Click "Proceed to localhost (unsafe)"

**Firefox:**
1. Click "Advanced..."
2. Click "Accept the Risk and Continue"

**Safari:**
1. Click "Show Details"
2. Click "visit this website"

### 📋 Certificate Details

- **Valid for**: localhost, *.localhost, rave-demo, gitlab.local, and common local IPs
- **Algorithm**: RSA 4096-bit
- **Validity**: 365 days from generation
- **Location**: /var/lib/nginx/certs/

### 🚀 For Production

Replace self-signed certificates with proper certificates from:
- Let's Encrypt (free, automated)
- Your organization's Certificate Authority
- Commercial certificate providers

Never use self-signed certificates in production!
EOF
            
            echo ""
            echo "🎉 SUCCESS! RAVE HTTPS is now ready!"
            echo ""
            echo "🔗 Access your RAVE environment at: https://localhost:8080"
            echo "🔗 HTTP fallback available at: http://localhost:8081"
            echo "⚠️  You'll see browser security warnings - this is normal!"
            echo "✅ Click 'Advanced' → 'Proceed to localhost (unsafe)' to continue"
            echo ""
            echo "📖 Documentation created at: $CERT_DIR/README.md"
            echo "📁 Certificate files: $CERT_DIR/"
            echo ""
            echo "🎯 GitLab login: root / (check your configuration)"
            
        else
            echo "❌ Port 8080 is not listening. Check nginx logs:"
            tail -20 /var/log/nginx/error.log 2>/dev/null || echo "No nginx error log found"
        fi
    else
        echo "❌ Nginx failed to start. Check configuration:"
        nginx -t -c /tmp/nginx-https.conf
    fi
else
    echo "❌ Nginx configuration test failed!"
    nginx -t -c /tmp/nginx-https.conf
    exit 1
fi