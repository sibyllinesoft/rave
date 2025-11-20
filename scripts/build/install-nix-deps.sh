#!/bin/bash
set -e

echo "🔧 Installing Nix dependencies and setting up environment"
echo "========================================================"

# Update system
echo "📦 Updating system packages..."
apt update && apt upgrade -y

# Install required dependencies for Nix
echo "🛠️ Installing Nix prerequisites..."
apt install -y curl xz-utils sudo git

# Create nix directory and set permissions
echo "📁 Preparing /nix directory..."
mkdir -p /nix
chown nathan:nathan /nix

# Create nixbld group and users for multi-user installation
echo "👥 Creating nixbld group and users..."
groupadd -g 30000 nixbld
for i in $(seq 1 32); do
    useradd -c "Nix build user $i" \
            -d /var/empty \
            -g nixbld \
            -G nixbld \
            -M \
            -N \
            -r \
            -s "$(which nologin)" \
            -u $((30000 + i)) \
            nixbld$i
done

# Install Docker for potential Nix containerized workflows
echo "🐳 Installing Docker..."
apt install -y ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add nathan to docker group
usermod -aG docker nathan

# Install QEMU for VM building
echo "💿 Installing QEMU for VM support..."
apt install -y qemu-system qemu-utils

echo ""
echo "✅ All dependencies installed successfully!"
echo ""
echo "📋 What was installed:"
echo "  - Nix prerequisites (curl, xz-utils, git)"
echo "  - nixbld group and 32 build users (nixbld1-32)"
echo "  - Docker with nathan user access"
echo "  - QEMU for VM building"
echo "  - Prepared /nix directory"
echo ""
echo "🔄 Next steps:"
echo "  1. Log out and back in (for docker group)"
echo "  2. Run Nix installer as nathan user"
echo "  3. Start building VM images!"
echo ""