#!/usr/bin/env bash
set -euo pipefail

# Configuration
PHYSICAL_ROOT="/mnt/data/nix"
NIX_ROOT="/nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() { printf "${GREEN}[setup-nix-store]${NC} %s\n" "$*"; }
err() { printf "${RED}[error]${NC} %s\n" "$*"; }

# 1. Sanity Checks
if [ "$EUID" -ne 0 ]; then
  err "Please run as root."
  exit 1
fi

if ! getent group nixbld >/dev/null; then
  err "Group 'nixbld' does not exist. Please create it or reinstall Nix."
  exit 1
fi

# 2. Stop Services
log "Stopping nix-daemon..."
systemctl stop nix-daemon.service nix-daemon.socket 2>/dev/null || true

# 3. Handle Mounts
log "Unmounting /nix if present..."
# Unmount if it's a mountpoint
if mountpoint -q "$NIX_ROOT"; then
    umount "$NIX_ROOT"
fi

# 4. The Wipe
log "Wiping physical directory $PHYSICAL_ROOT..."
rm -rf "$PHYSICAL_ROOT"
mkdir -p "$PHYSICAL_ROOT"

# 5. Setup Mount
log "Setting up bind mount..."
mkdir -p "$NIX_ROOT"
mount --bind "$PHYSICAL_ROOT" "$NIX_ROOT"

# Persist in fstab if not there
if ! grep -qs "$PHYSICAL_ROOT $NIX_ROOT" /etc/fstab; then
    log "Adding bind mount to /etc/fstab..."
    echo "$PHYSICAL_ROOT $NIX_ROOT none bind 0 0" >> /etc/fstab
fi

# 6. Create Directory Structure (Using Canonical Paths)
log "Creating directory layout..."

# Base Directories
mkdir -p /nix/store
mkdir -p /nix/var/nix
mkdir -p /nix/var/log/nix/drvs
mkdir -p /nix/var/nix/db
mkdir -p /nix/var/nix/gcroots
mkdir -p /nix/var/nix/profiles
mkdir -p /nix/var/nix/temproots
mkdir -p /nix/var/nix/userpool
mkdir -p /nix/var/nix/daemon-socket

# 7. Set Permissions (The Critical Part)
log "Applying strict permissions..."

# /nix (Root)
chown root:root /nix
chmod 0755 /nix

# /nix/store (The Store) - Must be 1775 root:nixbld
chown root:nixbld /nix/store
chmod 1775 /nix/store

# /nix/var (State)
chown root:root /nix/var
chmod 0755 /nix/var
chown root:root /nix/var/nix
chmod 0755 /nix/var/nix

# Profiles (Profiles allow users to have environments)
chown root:root /nix/var/nix/profiles
chmod 1777 /nix/var/nix/profiles

# GC Roots
chown root:root /nix/var/nix/gcroots
chmod 1777 /nix/var/nix/gcroots

# Database & Locks
chown -R root:nixbld /nix/var/nix/db
chmod 2775 /nix/var/nix/db

# Temp roots
chown root:root /nix/var/nix/temproots
chmod 1777 /nix/var/nix/temproots

# Daemon Socket location
chown root:root /nix/var/nix/daemon-socket
chmod 0755 /nix/var/nix/daemon-socket

# 8. Initialize DB
log "Initializing Nix Store DB..."
# We do this AFTER permissions and mounts are set
nix-store --init

# 9. Restart Daemon
log "Restarting nix-daemon..."
systemctl daemon-reload
systemctl enable --now nix-daemon

log "Done. Testing basic evaluation..."
nix-instantiate --eval -E '1 + 1' >/dev/null && echo "Nix is working!"
