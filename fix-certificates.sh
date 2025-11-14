#!/bin/bash
# Script to fix certificate paths in running VM

set -e

echo "🔧 Fixing SSL certificate paths in RAVE VM..."

# Try to SSH in and fix the certificate paths
if sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" root@localhost -p 2224 true; then
    echo "✅ SSH connection successful"
    
    # Fix certificate directories
    sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" root@localhost -p 2224 "
        echo 'Creating localhost certificate directory...'
        mkdir -p /var/lib/acme/localhost
        
        # Check if rave.local directory exists and copy certificates
        if [ -d /var/lib/acme/rave.local ]; then
            echo 'Copying certificates from rave.local to localhost...'
            cp -r /var/lib/acme/rave.local/* /var/lib/acme/localhost/
        else
            echo 'Generating new certificates for localhost...'
            openssl req -x509 -newkey rsa:4096 -keyout /var/lib/acme/localhost/key.pem -out /var/lib/acme/localhost/cert.pem -days 365 -nodes -subj '/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=localhost'
        fi
        
        # Fix permissions
        chown -R traefik:traefik /var/lib/acme/localhost/
        chmod 640 /var/lib/acme/localhost/key.pem
        chmod 644 /var/lib/acme/localhost/cert.pem
        
        # Restart Traefik
        systemctl restart traefik
        
        echo 'Certificate fix complete!'
        systemctl status traefik --no-pager
    "
    echo "✅ Certificate fix applied successfully"
else
    echo "❌ Cannot SSH into VM - trying alternative approach"
    
    # Create certificates locally and inject them
    echo "🔧 Creating local certificates to inject..."
    
    mkdir -p /tmp/localhost-certs
    openssl req -x509 -newkey rsa:4096 -keyout /tmp/localhost-certs/key.pem -out /tmp/localhost-certs/cert.pem -days 365 -nodes -subj '/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=localhost'
    
    echo "✅ Certificates created locally"
    echo "❌ Cannot inject into running VM without SSH access"
    echo "🔧 Solution: Rebuild VM with fixed configuration"
fi
