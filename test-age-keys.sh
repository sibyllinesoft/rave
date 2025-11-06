#!/bin/bash
set -euo pipefail

echo "🔑 Testing AGE key mounting functionality..."

# Check if AGE keys exist
AGE_KEY_DIR="/home/nathan/.config/sops/age"
if [[ ! -f "$AGE_KEY_DIR/keys.txt" ]]; then
    echo "❌ AGE keys not found at $AGE_KEY_DIR/keys.txt"
    exit 1
fi

echo "✅ AGE keys found at $AGE_KEY_DIR"

# Copy existing VM image to test
cp result/nixos.qcow2 test-age-keys.qcow2
chmod 644 test-age-keys.qcow2

echo "🚀 Starting VM with AGE key mounting..."

# Start VM with virtfs AGE key mounting
qemu-system-x86_64 \
  -drive file=test-age-keys.qcow2,format=qcow2 \
  -m 8G \
  -smp 4 \
  -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::8889-:8080,hostfwd=tcp::2224-:22,hostfwd=tcp::8443-:443 \
  -device virtio-net-pci,netdev=net0 \
  -virtfs local,path="$AGE_KEY_DIR",mount_tag=sops-keys,security_model=none \
  -display none \
  -daemonize

echo "⏱️  Waiting for VM to boot..."
sleep 30

echo "🔍 Testing VM connectivity..."
if ! timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2224 root@localhost "echo 'VM is accessible'" 2>/dev/null; then
    echo "❌ VM not accessible via SSH yet, waiting longer..."
    sleep 30
    if ! timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p 2224 root@localhost "echo 'VM is accessible'" 2>/dev/null; then
        echo "❌ VM failed to become accessible"
        pkill -f test-age-keys.qcow2 || true
        exit 1
    fi
fi

echo "✅ VM is accessible"

echo "🔍 Checking AGE key mounting inside VM..."
ssh -o StrictHostKeyChecking=no -p 2224 root@localhost "
    echo '=== Checking mount-sops-keys service ==='
    systemctl status mount-sops-keys.service || true
    
    echo -e '\n=== Checking if virtfs is mounted ==='
    mountpoint -q /host-keys && echo 'virtfs mounted' || echo 'virtfs not mounted'
    
    echo -e '\n=== Checking for AGE keys in mounted directory ==='
    if [[ -f /host-keys/keys.txt ]]; then
        echo 'AGE keys found in virtfs mount'
        ls -la /host-keys/keys.txt
    else
        echo 'AGE keys not found in virtfs mount'
        ls -la /host-keys/ || echo 'Mount directory does not exist'
    fi
    
    echo -e '\n=== Checking install-age-key service ==='
    systemctl status install-age-key.service || true
    
    echo -e '\n=== Checking for installed AGE key ==='
    if [[ -f /var/lib/sops-nix/key.txt ]]; then
        echo 'AGE key installed successfully'
        ls -la /var/lib/sops-nix/key.txt
    else
        echo 'AGE key not installed'
    fi
    
    echo -e '\n=== Checking SOPS functionality ==='
    systemctl status sops-init.service || true
"

echo "🧹 Cleaning up..."
pkill -f test-age-keys.qcow2 || true
rm -f test-age-keys.qcow2

echo "✅ Test completed!"