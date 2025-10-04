#!/bin/bash
# RAVE VM Launch Script
# Simple launcher for the development VM stack

set -e

# Configuration
VM_IMAGE="./rave-complete-localhost.qcow2"
VM_NAME="rave-dev"
MEMORY="8G"
CPUS="4"

# Port forwarding
HTTP_PORT="8081"
HTTPS_PORT="8443"
SSH_PORT="2224"
STATUS_PORT="8889"

echo "🚀 RAVE Development VM Launcher"
echo "================================="

# Check if VM image exists
if [[ ! -f "$VM_IMAGE" ]]; then
    echo "❌ VM image not found: $VM_IMAGE"
    echo "🔨 To build a new VM image, run: nix build"
    exit 1
fi

# Check if QEMU is available
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "❌ QEMU not found. Please install qemu-system-x86_64"
    exit 1
fi

# Check if ports are available
check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "⚠️  Port $port is already in use"
        return 1
    fi
    return 0
}

echo "🔍 Checking port availability..."
PORTS_OK=true
for port in $HTTP_PORT $HTTPS_PORT $SSH_PORT $STATUS_PORT; do
    if ! check_port $port; then
        PORTS_OK=false
    fi
done

if [[ "$PORTS_OK" != "true" ]]; then
    echo "❌ Some ports are in use. Please stop conflicting services or change ports."
    exit 1
fi

echo "✅ All ports available"

# Launch VM
echo "🖥️  Launching RAVE VM..."
echo "   Memory: $MEMORY"
echo "   CPUs: $CPUS"
echo "   Image: $VM_IMAGE"
echo ""
echo "📊 Service URLs (available after boot):"
echo "   🌐 Dashboard:  https://localhost:$HTTPS_PORT/"
echo "   🦊 GitLab:     https://localhost:$HTTPS_PORT/gitlab/"
echo "   📊 Grafana:    https://localhost:$HTTPS_PORT/grafana/"
echo "   🔍 Prometheus: https://localhost:$HTTPS_PORT/prometheus/"
echo "   ⚡ NATS:       https://localhost:$HTTPS_PORT/nats/"
echo ""
echo "🔑 SSH Access: ssh -p $SSH_PORT root@localhost (password: debug123)"
echo "🔴 To stop: Press Ctrl+C or use 'sudo killall qemu-system-x86_64'"
echo ""

# Create backup if this is first run
if [[ ! -f "${VM_IMAGE}.backup" ]]; then
    echo "💾 Creating backup of original VM image..."
    cp "$VM_IMAGE" "${VM_IMAGE}.backup"
    echo "✅ Backup created: ${VM_IMAGE}.backup"
fi

# Launch QEMU
exec qemu-system-x86_64 \
    -drive file="$VM_IMAGE",format=qcow2 \
    -m "$MEMORY" \
    -smp "$CPUS" \
    -netdev user,id=net0,hostfwd=tcp::${HTTP_PORT}-:80,hostfwd=tcp::${HTTPS_PORT}-:443,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${STATUS_PORT}-:8080 \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial stdio \
    -name "$VM_NAME"