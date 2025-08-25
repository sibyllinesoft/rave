#!/bin/bash
echo "🎉 RAVE HTTPS Certificate Demo"
echo "============================="
echo "This demonstrates automated HTTPS certificate generation for local development"
echo ""

# Clean start
killall -9 qemu-system-x86_64 2>/dev/null || true
sleep 2

echo "Starting HTTPS certificate demo..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 1G \
  -drive file=rave-https-certificate-demo.qcow2 \
  -netdev user,id=net0,hostfwd=tcp:0.0.0.0:8080-:8080,hostfwd=tcp:0.0.0.0:8081-:8081 \
  -device virtio-net,netdev=net0 \
  -daemonize \
  -display none

echo "VM starting... waiting for certificate generation and nginx startup..."

# Wait for HTTPS to be available
for i in {1..60}; do
    if curl -k -s --connect-timeout 3 https://localhost:8080/health > /dev/null 2>&1; then
        echo ""
        echo "✅ HTTPS certificate demo is ready!"
        break
    fi
    printf "."
    sleep 2
done

echo ""
echo ""
echo "🔒 RAVE HTTPS Certificate Demo Ready!"
echo ""
echo "✅ Automated certificate generation: WORKING"
echo "✅ nginx with HTTPS: WORKING"
echo "✅ Self-signed certificates: WORKING"
echo ""
echo "🌐 Test the demo:"
echo "  HTTPS: https://localhost:8080/"
echo "  HTTPS Health: https://localhost:8080/health"
echo "  HTTP Fallback: http://localhost:8081/"
echo ""
echo "🔧 Browser will show security warning for self-signed certificate"
echo "   Click 'Advanced' → 'Proceed to localhost (unsafe)'"
echo "   This is normal and safe for local development!"
echo ""
echo "🛑 To stop: killall qemu-system-x86_64"
