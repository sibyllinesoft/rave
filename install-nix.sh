#!/bin/bash
# Install Nix package manager script
# Generated on: 2025-09-11
# Review this script before execution

set -euo pipefail  # Exit on any error

echo "🔍 Checking system requirements..."
if command -v nix >/dev/null 2>&1; then
    echo "✅ Nix already installed"
    nix --version
    exit 0
fi

echo "📦 Installing Nix package manager..."
echo "This will install Nix to /nix and add it to your shell profile"

# Download and install Nix
curl -L https://nixos.org/nix/install | sh

echo "🔧 Setting up Nix environment..."
# Source the Nix profile for immediate use
if [ -f ~/.nix-profile/etc/profile.d/nix.sh ]; then
    source ~/.nix-profile/etc/profile.d/nix.sh
fi

echo "✅ Verifying installation..."
if command -v nix >/dev/null 2>&1; then
    nix --version
    echo "🎉 Nix installation complete!"
    echo ""
    echo "To use Nix in this session, run:"
    echo "source ~/.nix-profile/etc/profile.d/nix.sh"
else
    echo "❌ Nix installation failed"
    exit 1
fi