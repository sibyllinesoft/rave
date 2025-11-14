#!/bin/bash

echo "🔧 RAVE Demo Fix - Starting HTTP-only nginx..."

# Wait for system to be fully ready
sleep 30

# Kill any existing nginx processes  
pkill nginx 2>/dev/null || true

# Create simple HTTP-only nginx config
cat > /tmp/nginx-demo.conf << 'EOF'
user root;
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    upstream gitlab-workhorse {
        server unix:/run/gitlab/gitlab-workhorse.socket fail_timeout=0;
    }

    server {
        listen 8080 default_server;
        server_name _;
        
        # Health check endpoint
        location /health {
            return 200 'RAVE Demo Ready - GitLab HTTP Access Working\n';
            add_header Content-Type text/plain;
            access_log off;
        }
        
        # GitLab main application
        location / {
            proxy_pass http://gitlab-workhorse;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Ssl off;
            
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            
            client_max_body_size 1024m;
        }
        
        # Prometheus proxy
        location /prometheus/ {
            proxy_pass http://127.0.0.1:9090/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            rewrite ^/prometheus/(.*) /$1 break;
        }
    }
}
EOF

# Test config and start nginx
echo "Testing nginx configuration..."
nginx -t -c /tmp/nginx-demo.conf

if [ $? -eq 0 ]; then
    echo "Starting nginx with HTTP-only config..."
    nginx -c /tmp/nginx-demo.conf
    
    echo "Checking nginx status..."
    ps aux | grep nginx | grep -v grep
    
    echo "Checking if port 8080 is listening..."
    netstat -tlnp | grep 8080
    
    echo "✅ RAVE Demo should be accessible at http://localhost:8080"
    echo "✅ Health check: http://localhost:8080/health"
    echo "✅ Prometheus: http://localhost:8080/prometheus/"
else
    echo "❌ nginx configuration test failed"
fi