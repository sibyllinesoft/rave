#!/bin/bash
# Send commands to VM via QEMU monitor/console

echo "🖥️  Sending commands to VM console..."

# The VM is listening on ttyS0 (serial console)
# We need to send keystrokes to login and diagnose nginx

VM_PID=$(cat vm-development.pid)
echo "VM PID: $VM_PID"

# Since we can see the VM console log, let's restart it with monitor console access
echo "🔄 Stopping VM to restart with monitor access..."
kill $VM_PID 2>/dev/null
sleep 3

echo "🚀 Starting VM with monitor console..."

# Start VM with monitor access
qemu-system-x86_64 \
    -machine accel=kvm -cpu host -smp 4 -m 4096 \
    -drive file=development-vm.qcow2,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::2224-:22,hostfwd=tcp::8889-:8080 \
    -device virtio-net,netdev=net0 \
    -vnc :1 \
    -serial mon:stdio \
    -daemonize \
    -pidfile vm-development.pid &

sleep 10

# Check if we can connect now
echo "✅ VM restarted. Testing connections in 20 seconds..."
sleep 20

echo "🔍 Testing SSH connection..."
if timeout 10 ssh -p 2224 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost 'systemctl status nginx' 2>/dev/null; then
    echo "✅ SSH connection successful!"
else
    echo "❌ SSH still not working"
    echo "💡 Try VNC on localhost:5901 or check console directly"
fi