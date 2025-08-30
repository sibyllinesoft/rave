#!/bin/bash
# Restart GitLab Development VM

echo "🔄 Restarting GitLab Development VM..."

# Kill existing VM if running
if [ -f vm-development.pid ]; then
    VM_PID=$(cat vm-development.pid)
    echo "🛑 Stopping existing VM (PID: $VM_PID)..."
    kill $VM_PID 2>/dev/null
    sleep 3
    kill -9 $VM_PID 2>/dev/null
    rm -f vm-development.pid
fi

# Clean up any other QEMU processes for this VM
pkill -f "development-vm.qcow2" 2>/dev/null || true

echo "🚀 Starting fresh VM instance..."

# Start VM with proper logging
qemu-system-x86_64 \
    -machine accel=kvm -cpu host -smp 4 -m 4096 \
    -drive file=development-vm.qcow2,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::2224-:22,hostfwd=tcp::8889-:8080 \
    -device virtio-net,netdev=net0 \
    -vnc :1 \
    -serial file:vm-console.log \
    -daemonize \
    -pidfile vm-development.pid

sleep 5

if [ -f vm-development.pid ] && ps -p $(cat vm-development.pid) > /dev/null; then
    echo "✅ VM started successfully (PID: $(cat vm-development.pid))"
    echo "🌐 Port mappings:"
    echo "   Host:8081 -> VM:80 (nginx)"
    echo "   Host:8889 -> VM:8080 (nginx alternate)"
    echo "   Host:2224 -> VM:22 (SSH)"
    echo "🖥️  VNC console: localhost:5901"
    
    echo "⏳ Waiting for VM to boot (30 seconds)..."
    sleep 30
    
    echo "🔍 Testing connections..."
    ./vm-interact.sh
else
    echo "❌ Failed to start VM"
    exit 1
fi