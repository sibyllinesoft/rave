#!/bin/bash
set -e

echo "🎯 Installing Nix as user"
echo "========================"

# Install Nix (multi-user)
echo "📥 Installing Nix..."
sh <(curl -L https://nixos.org/nix/install) --daemon

# Source Nix environment
echo "🔧 Setting up Nix environment..."
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# Add to shell profiles
echo ". /home/nathan/.nix-profile/etc/profile.d/nix.sh" >> ~/.bashrc

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