#!/bin/bash
set -e

# Set XDG_RUNTIME_DIR if not set
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/tmp/runtime-$USER"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

echo "🚀 Starting AI Agent Sandbox VM (Headless + VNC)"
echo "================================================"

VM_IMAGE="nixos-vm.qcow2"

if [ ! -f "$VM_IMAGE" ]; then
    echo "❌ VM image not found at $VM_IMAGE"
    exit 1
fi

echo "🖥️ Starting headless VM..."
echo "💡 SSH: ssh -p 2222 agent@localhost" 
echo "💡 VNC: Connect to localhost:5901 after VM boots"
echo ""

qemu-system-x86_64 \
    -M q35 \
    -m 2048 \
    -smp 2 \
    -cpu host \
    -enable-kvm \
    -hda "$VM_IMAGE" \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -vnc :1 \
    -device virtio-vga \
    -device qemu-xhci \
    -device usb-tablet \
    -audiodev alsa,id=audio0 \
    -device intel-hda \
    -device hda-duplex,audiodev=audio0 \
    -daemonize \
    -pidfile vm.pid

echo "✅ VM started in background"
echo "🔌 Connect with VNC viewer to: localhost:5901"
echo "🛑 Stop with: kill $(cat vm.pid)"