#!/bin/bash
set -e

echo "🎯 Installing Nix (Single User Mode)"
echo "===================================="

# Install Nix in single-user mode (no sudo required)
echo "📥 Installing Nix in single-user mode..."
sh <(curl -L https://nixos.org/nix/install) --no-daemon

# Source Nix environment
echo "🔧 Setting up Nix environment..."
if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then
    . ~/.nix-profile/etc/profile.d/nix.sh
fi

# Add to shell profiles
echo ". ~/.nix-profile/etc/profile.d/nix.sh" >> ~/.bashrc

# Enable flakes and new nix command
echo "⚡ Enabling experimental features..."
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" > ~/.config/nix/nix.conf

echo ""
echo "✅ Nix installation complete!"
echo ""
echo "🔄 Please run: source ~/.bashrc"
echo "🧪 Then test with: nix --version"
echo ""