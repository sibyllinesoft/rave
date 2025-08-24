#!/bin/bash

echo "Sending commands to VM via QEMU monitor to fix nginx certificates..."

# Send Enter to get to login prompt
echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 1

# Type root and press enter to login
for char in r o o t; do
    echo "sendkey $char" | nc -w 1 -U /tmp/qemu-p6.sock
    sleep 0.2
done
echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 2

# Create certificates directory and generate certificates
commands=(
    "mkdir -p /var/lib/nginx/certs"
    "cd /var/lib/nginx/certs"
    "openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx.key -out nginx.crt -subj '/C=US/ST=Demo/L=Demo/O=RAVE/CN=localhost'"
    "chown -R nginx:nginx /var/lib/nginx/certs"
    "chmod 600 /var/lib/nginx/certs/*"
    "systemctl restart nginx"
    "systemctl status nginx"
)

for cmd in "${commands[@]}"; do
    echo "Sending command: $cmd"
    for char in $(echo "$cmd" | sed 's/./& /g'); do
        if [ "$char" = " " ]; then
            echo "sendkey spc" | nc -w 1 -U /tmp/qemu-p6.sock
        else
            echo "sendkey $char" | nc -w 1 -U /tmp/qemu-p6.sock
        fi
        sleep 0.1
    done
    echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
    sleep 3
done

echo "Commands sent! Nginx should now be fixed."