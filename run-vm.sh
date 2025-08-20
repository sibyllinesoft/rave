#!/bin/bash
set -e

# Set XDG_RUNTIME_DIR if not set
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/tmp/runtime-$USER"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

echo "🚀 Starting AI Agent Sandbox VM"
echo "=============================="

VM_IMAGE="ai-sandbox-with-ccr-ui-fixed.qcow2"

if [ ! -f "$VM_IMAGE" ]; then
    echo "❌ VM image not found at $VM_IMAGE"
    echo "💡 Run './build-vm.sh' first to build the VM image"
    exit 1
fi

echo "🖥️ VM Configuration:"
echo "  - Image: $VM_IMAGE ($(du -h $VM_IMAGE | cut -f1))"
echo "  - Memory: 2GB RAM"
echo "  - CPUs: 2 cores"
echo "  - User: agent/agent"
echo "  - Desktop: XFCE with auto-login"
echo "  - SSH: Port 2225 (forwarded from guest port 22)"
echo ""
echo "🌐 Auto-starting Services:"
echo "  - Vibe Kanban: http://localhost:7893/ (nginx reverse proxy)"
echo "  - CCR UI: http://localhost:7893/ccr-ui (Claude Code Router)"
echo "  - Claude Code Router: http://localhost:3001 (inside VM only)"  
echo "  - Desktop shortcuts will be available"
echo ""

echo "🎮 Starting QEMU..."
echo "💡 Connect via SSH: ssh -p 2225 agent@localhost"
echo "💡 VNC will be available on :0 (port 5900)"
echo "💡 Web services will be available after ~30 seconds"
echo ""

qemu-system-x86_64 \
    -M q35 \
    -m 2048 \
    -smp 2 \
    -cpu host \
    -enable-kvm \
    -hda "$VM_IMAGE" \
    -netdev user,id=net0,hostfwd=tcp::2225-:22,hostfwd=tcp::7893-:3002 \
    -device virtio-net-pci,netdev=net0 \
    -display gtk,show-cursor=on \
    -device virtio-vga \
    -device qemu-xhci \
    -device usb-tablet \
    -device usb-kbd \
    -audiodev alsa,id=audio0 \
    -device intel-hda \
    -device hda-duplex,audiodev=audio0