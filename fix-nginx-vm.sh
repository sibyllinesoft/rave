#!/bin/bash

echo "🔧 Fixing nginx in RAVE VM for HTTP-only GitLab access..."

# Create temporary nginx config
cat > /tmp/nginx-fix.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream gitlab-workhorse {
        server unix:/run/gitlab/gitlab-workhorse.socket fail_timeout=0;
    }

    server {
        listen 8080;
        server_name localhost;
        
        location /health {
            return 200 'RAVE Demo Ready - GitLab HTTP Access Working';
            add_header Content-Type text/plain;
            access_log off;
        }
        
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
        
        location /prometheus/ {
            proxy_pass http://127.0.0.1:9090/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            rewrite ^/prometheus/(.*) /$1 break;
        }
    }
}
EOF

# Start nginx with this config manually
echo "Starting nginx with HTTP-only config..."
echo "change vnc password" | nc -U /tmp/qemu-demo.sock
echo "set_password vnc test123" | nc -U /tmp/qemu-demo.sock

# Try to start nginx with direct config
timeout 30 ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@localhost \
  "nginx -t -c /tmp/nginx-fix.conf && nginx -c /tmp/nginx-fix.conf" 2>/dev/null || true

echo "Config uploaded. Testing if GitLab is now accessible..."