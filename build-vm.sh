#!/bin/bash
set -e

echo "🚀 Building AI Agent Sandbox VM with Nix"
echo "========================================"

# Source Nix environment
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# Build QEMU image
echo "🔨 Building QEMU qcow2 image..."
nix build .#qemu

echo "📦 Building VirtualBox OVA..."
nix build .#virtualbox

echo "💿 Building raw disk image..."
nix build .#raw

echo ""
echo "✅ Build complete!"
echo ""
echo "📁 Generated images:"
ls -lh result*
echo ""
echo "🎮 To run with QEMU:"
echo "  qemu-system-x86_64 -m 2048 -hda result/nixos.qcow2 -enable-kvm"
echo ""
echo "📋 VM Details:"
echo "  - User: agent"
echo "  - Password: agent"  
echo "  - Desktop: XFCE"
echo "  - Browser: Chromium + Playwright"
echo "  - SSH: Enabled on port 22"
echo ""