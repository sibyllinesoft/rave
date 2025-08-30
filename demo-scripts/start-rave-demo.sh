#!/bin/bash
echo "🚀 Starting RAVE GitLab Demo..."
echo "This will start the VM with HTTP access on localhost:8080"
echo ""

# Kill any existing QEMU processes
pkill -f qemu 2>/dev/null || true

# Start VM in daemon mode
echo "Starting VM..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 2G \
  -drive file=gitlab-https-debug.qcow2 \
  -netdev user,id=net0,hostfwd=tcp::8080-:8080,hostfwd=tcp::8081-:8081,hostfwd=tcp::2222-:22 \
  -device virtio-net,netdev=net0 \
  -daemonize

echo "VM starting..."
echo "Waiting for services to be available..."
echo ""

# Wait for VM to boot and services to start
for i in {1..60}; do
    if curl -s --connect-timeout 2 http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ nginx is running!"
        break
    fi
    echo "Waiting for VM to boot... ($i/60)"
    sleep 5
done

# Check GitLab status
echo ""
echo "Testing GitLab status..."
if curl -s --connect-timeout 10 http://localhost:8080/ | grep -q "GitLab"; then
    echo "✅ GitLab is responding!"
elif curl -s --connect-timeout 10 http://localhost:8080/ | grep -q "Waiting for GitLab"; then
    echo "🔄 GitLab is still initializing (this is normal)"
    echo "   GitLab can take 3-10 minutes to fully start"
else
    echo "⚠️  GitLab status unknown"
fi

echo ""
echo "🌐 RAVE Demo is ready!"
echo ""
echo "Access points:"
echo "  Health check: http://localhost:8080/health"
echo "  GitLab Demo:  http://localhost:8080/"
echo "  Fallback:     http://localhost:8081/"
echo ""
echo "Login credentials:"
echo "  Username: root"
echo "  Password: rave-development-password"
echo ""
echo "To stop the VM: pkill -f qemu"
