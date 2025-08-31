#!/bin/bash
# Quick fix script to configure the running VM without full rebuild

echo "🔧 Attempting to fix GitLab configuration on running VM..."

# Kill current VM
echo "🛑 Stopping current VM..."
VM_PID=$(cat vm-development.pid 2>/dev/null)
if [ -n "$VM_PID" ]; then
    kill $VM_PID 2>/dev/null
    sleep 3
    kill -9 $VM_PID 2>/dev/null || true
fi

# Copy current development-vm.qcow2 to a backup
cp development-vm.qcow2 development-vm-backup-$(date +%Y%m%d-%H%M%S).qcow2

echo "🚀 Starting VM with console access to manually configure..."
# Start with console so we can interact
qemu-system-x86_64 \
    -machine accel=kvm -cpu host -smp 4 -m 4096 \
    -drive file=development-vm.qcow2,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::2224-:22,hostfwd=tcp::8889-:8080 \
    -device virtio-net,netdev=net0 \
    -vnc :1 \
    -nographic \
    -serial mon:stdio &

VM_PID=$!
echo $VM_PID > vm-development.pid

echo "✅ VM started with PID: $VM_PID"
echo "🖥️  Console is attached - you should see boot messages"
echo "📝 Once you see login prompt, you can:"
echo "   1. Login as root (should be passwordless)"
echo "   2. Run: systemctl status gitlab"
echo "   3. Run: systemctl status nginx" 
echo "   4. Check logs: journalctl -u nginx -f"
echo ""
echo "🔍 The issue is likely nginx config conflict or GitLab not enabled"
echo "   GitLab might not be enabled in the current VM image"
echo ""
echo "Press Ctrl+A then C to access QEMU monitor"
echo "Press Ctrl+A then X to quit"
echo "Or use 'fg' to bring this back to foreground if backgrounded"