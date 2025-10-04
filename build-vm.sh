#!/bin/bash
# RAVE VM Build Script
# Alternative build method that handles Nix issues

set -e

echo "🔨 RAVE VM Build Script"
echo "======================="

# Check if Nix is available
if ! command -v nix >/dev/null 2>&1; then
    echo "❌ Nix not found. Please install Nix first:"
    echo "   curl -L https://nixos.org/nix/install | sh"
    echo "   source ~/.nix-profile/etc/profile.d/nix.sh"
    exit 1
fi

# Source Nix environment
if [[ -f ~/.nix-profile/etc/profile.d/nix.sh ]]; then
    source ~/.nix-profile/etc/profile.d/nix.sh
fi

echo "✅ Nix available: $(nix --version)"

# Check if flake.lock exists and is valid
if [[ ! -f flake.lock ]]; then
    echo "🔧 Creating flake.lock..."
    nix flake lock || {
        echo "❌ Failed to create flake.lock"
        echo "🛠️  Trying to fix dependencies..."
        
        # Clean up any corrupted state
        rm -f flake.lock
        nix-collect-garbage
        
        # Try again
        nix flake lock || {
            echo "❌ Still failing. Using manual fallback..."
            exit 1
        }
    }
fi

echo "🔍 Checking flake integrity..."
nix flake check --show-trace || {
    echo "⚠️  Flake check failed, but attempting build anyway..."
}

# Attempt to build
echo "🚀 Building VM image..."
echo "   This may take 15-30 minutes for a complete build..."

if nix build --show-trace; then
    echo "✅ Build successful!"
    
    # Copy result to a usable name
    if [[ -L result ]]; then
        echo "📦 Copying VM image..."
        cp result/nixos.qcow2 rave-complete-$(date +%Y%m%d).qcow2
        chmod 644 rave-complete-$(date +%Y%m%d).qcow2
        
        # Create or update the main image symlink
        ln -sf rave-complete-$(date +%Y%m%d).qcow2 rave-complete-localhost.qcow2
        
        echo "✅ VM image ready: rave-complete-localhost.qcow2"
        echo "🚀 To launch: ./launch-vm.sh"
    else
        echo "❌ Build result not found"
        exit 1
    fi
else
    echo "❌ Build failed"
    echo ""
    echo "🔧 Troubleshooting options:"
    echo "1. Clean and retry:"
    echo "   nix-collect-garbage && rm flake.lock && ./build-vm.sh"
    echo ""
    echo "2. Use existing VM image:"
    echo "   ./launch-vm.sh"
    echo ""
    echo "3. Check system resources (build needs ~4GB RAM)"
    echo ""
    exit 1
fi