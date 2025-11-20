#!/bin/bash
echo "🚀 RAVE Final Demo - Fixing Host Connectivity"
echo "============================================"

# Kill any existing QEMU
killall -9 qemu-system-x86_64 2>/dev/null || true
sleep 3

echo "Starting VM with explicit host binding..."

# Start with explicit host interface binding
qemu-system-x86_64 \
  -enable-kvm \
  -m 2G \
  -drive file=gitlab-https-debug.qcow2 \
  -netdev user,id=net0,hostfwd=tcp:0.0.0.0:8080-:8080,hostfwd=tcp:0.0.0.0:8081-:8081,hostfwd=tcp:0.0.0.0:2222-:22 \
  -device virtio-net,netdev=net0 \
  -display none \
  -daemonize

echo "VM starting..."

# Wait and test connectivity
sleep 10

echo "Testing connectivity..."
for i in {1..20}; do
    if timeout 5 curl -s http://127.0.0.1:8080/health >/dev/null 2>&1; then
        echo "✅ Port 8080 responding on 127.0.0.1"
        break
    fi
    echo "Waiting for connectivity... ($i/20)"
    sleep 3
done

# Test both localhost and 127.0.0.1
echo ""
echo "Connection test results:"
echo "127.0.0.1:8080 -> $(timeout 5 curl -s http://127.0.0.1:8080/health 2>/dev/null || echo 'FAILED')"
echo "localhost:8080 -> $(timeout 5 curl -s http://localhost:8080/health 2>/dev/null || echo 'FAILED')"

echo ""
echo "Checking port listeners:"
ss -tlnp | grep -E ":(8080|8081)" || echo "No listeners found"

echo ""
echo "🌐 Try accessing:"
echo "  http://127.0.0.1:8080/health"
echo "  http://localhost:8080/health"
echo "  http://127.0.0.1:8080/"
echo "  http://localhost:8080/"

