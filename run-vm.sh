#!/bin/bash
set -e

# Set XDG_RUNTIME_DIR if not set
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/tmp/runtime-$USER"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

echo "🚀 Starting RAVE P0.3 Production VM (SAFE Mode)"
echo "=============================================="

# P0.3: Use production-ready image as default
VM_IMAGE="ai-sandbox-nginx-redirect-fix.qcow2"

# Check for P0 production image first
if [ -f "result-p0-production/nixos.qcow2" ]; then
    VM_IMAGE="result-p0-production/nixos.qcow2"
    echo "✅ Using P0 production image"
elif [ -f "result/nixos.qcow2" ]; then
    VM_IMAGE="result/nixos.qcow2"
    echo "✅ Using latest built image"
elif [ ! -f "$VM_IMAGE" ]; then
    echo "❌ No VM image found"
    echo "💡 Build with: nix build .#p0-production -o result-p0-production"
    echo "💡 Or run: nix build .#qemu -o result"
    exit 1
fi

# P0.3: SAFE mode resource limits
SAFE=${SAFE:-1}
if [ "$SAFE" = "1" ]; then
    VM_MEMORY=${QEMU_RAM_MB:-3072}
    VM_CPUS=${QEMU_CPUS:-2}
    echo "🛡️ SAFE Mode Active (Memory Disciplined)"
else
    VM_MEMORY=4096
    VM_CPUS=4
    echo "⚡ FULL_PIPE Mode (High Performance)"
fi

echo "🖥️ VM Configuration:"
echo "  - Image: $VM_IMAGE ($(du -h $VM_IMAGE | cut -f1))"
echo "  - Memory: ${VM_MEMORY}MB RAM (SAFE=${SAFE})"
echo "  - CPUs: ${VM_CPUS} cores"
echo "  - User: agent/agent"
echo "  - Desktop: XFCE with auto-login"
echo "  - SSH: Port 2225 (forwarded from guest port 22)"
echo ""
echo "🌐 Available Services (P0.3 TLS-enabled):"
echo "  - 🔒 HTTPS Services: https://localhost:7893/ (accept cert warning)"
echo "  - 📊 Vibe Kanban: https://localhost:7893/"
echo "  - 🤖 Claude Code Router: https://localhost:7893/ccr-ui/"
echo "  - 📈 Grafana: https://localhost:7893/grafana/ (admin/admin)"
echo "  - 🔧 SSH Access: ssh -p 2225 agent@localhost"
echo ""
echo "🛡️ P0.3 Security Features Active:"
echo "  - Self-signed TLS certificates"
echo "  - SSH key-only authentication"
echo "  - SystemD OOMD memory protection"
echo "  - Service memory limits enforced"
echo ""

echo "🎮 Starting QEMU with SAFE mode limits..."
echo "💡 Environment: SAFE=${SAFE}, Memory=${VM_MEMORY}MB, CPUs=${VM_CPUS}"
echo "💡 Services will be available after ~45 seconds"
echo ""

# P0.3: Use SAFE mode memory and CPU limits
qemu-system-x86_64 \
    -M q35 \
    -m $VM_MEMORY \
    -smp $VM_CPUS \
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