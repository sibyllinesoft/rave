#!/bin/bash
# VM Interaction Script for NixOS GitLab VM

# VM PID and connection details
VM_PID=$(cat vm-development.pid 2>/dev/null || echo "unknown")
echo "🖥️  VM Status Check - PID: $VM_PID"

# Check if VM process is running
if ! ps -p $VM_PID &>/dev/null; then
    echo "❌ VM process not running or PID file stale"
    exit 1
fi

echo "✅ VM process is running"

# Test network connectivity
echo "🌐 Testing VM network connectivity..."
echo "   Port 8081 (VM:80) -> $(curl -s --connect-timeout 3 http://localhost:8081 >/dev/null && echo "Connected" || echo "Failed")"
echo "   Port 8889 (VM:8080) -> $(curl -s --connect-timeout 3 http://localhost:8889 >/dev/null && echo "Connected" || echo "Failed")"
echo "   SSH 2224 (VM:22) -> $(timeout 3 nc -z localhost 2224 && echo "Connected" || echo "Failed")"

# Try to connect via SSH with a simple command using our key
echo "🔑 Attempting SSH connection..."
if timeout 10 ssh -i ~/.ssh/rave_vm_key -p 2224 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost 'echo "SSH_SUCCESS"' 2>/dev/null; then
    echo "✅ SSH connection successful"
    
    # Get VM status if SSH works
    echo "📊 VM System Status:"
    ssh -i ~/.ssh/rave_vm_key -p 2224 -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost '
        echo "Hostname: $(hostname)"
        echo "Uptime: $(uptime)"
        echo "Services:"
        systemctl is-active nginx || echo "nginx: inactive"
        systemctl is-active gitlab || echo "gitlab: inactive" 
        echo "Ports:"
        netstat -tlnp 2>/dev/null | grep ":80\|:8080\|:22" | head -5
    ' 2>/dev/null || echo "Failed to get VM status"
else
    echo "❌ SSH connection failed"
    
    # Try VNC if available
    echo "🖥️  VNC Console available on localhost:5901"
    echo "   You can connect with: vncviewer localhost:5901"
fi

# Check if VM needs restart
echo "💡 Troubleshooting suggestions:"
echo "   1. Connect via VNC: vncviewer localhost:5901"
echo "   2. If VM is stuck, restart it with: killall qemu-system-x86_64"
echo "   3. Boot fresh VM from: qemu-system-x86_64 -machine accel=kvm -cpu host -smp 4 -m 4096 -drive file=development-vm.qcow2,format=qcow2 -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::2224-:22,hostfwd=tcp::8889-:8080 -device virtio-net,netdev=net0 -vnc :1"