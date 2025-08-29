#!/bin/bash
# Build VM images using external drive as Nix store to avoid filling OS drive

set -euo pipefail

EXTERNAL_DIR="/media/nathan/Seagate Hub/images"
NIX_STORE_DIR="$EXTERNAL_DIR/nix-store"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }

if [[ ! -d "$EXTERNAL_DIR" ]]; then
    log_error "External directory not found: $EXTERNAL_DIR"
    exit 1
fi

VM_TYPE="${1:-production}"

log_info "Building $VM_TYPE VM using external Nix store to avoid filling OS drive"
log_info "External store: $NIX_STORE_DIR"

# Create external nix store directory
mkdir -p "$NIX_STORE_DIR"

cd "$PROJECT_DIR"

# Clean up any existing result symlinks
rm -f result*

# Build using external store - this prevents anything from going to your OS drive
log_info "Building with external Nix store (this may take a while)..."
if NIX_STORE_DIR="$NIX_STORE_DIR" nix build \
    --store "local?root=$NIX_STORE_DIR" \
    --extra-substituters "https://cache.nixos.org" \
    --extra-trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
    ".#packages.x86_64-linux.$VM_TYPE"; then
    
    log_success "VM built successfully using external store!"
    
    # Find the built image
    BUILT_IMAGE=$(find "$NIX_STORE_DIR" -name "*.qcow2" -o -name "*.vmdk" -o -name "*.ova" -o -name "*.iso" -o -name "*.raw" | head -1)
    
    if [[ -n "$BUILT_IMAGE" ]]; then
        SIZE=$(du -h "$BUILT_IMAGE" | cut -f1)
        log_success "VM image: $BUILT_IMAGE ($SIZE)"
        
        # Create a convenient symlink
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        EXT="${BUILT_IMAGE##*.}"
        SYMLINK="$EXTERNAL_DIR/rave-$VM_TYPE-$TIMESTAMP.$EXT"
        ln -sf "$BUILT_IMAGE" "$SYMLINK"
        
        # Create latest symlink
        LATEST_SYMLINK="$EXTERNAL_DIR/rave-$VM_TYPE-latest.$EXT"
        ln -sf "$(basename "$SYMLINK")" "$LATEST_SYMLINK"
        
        log_success "VM ready: $SYMLINK"
        log_info "Latest: $LATEST_SYMLINK"
    else
        log_warn "Built successfully but couldn't find image file"
        log_info "Check $NIX_STORE_DIR for the built VM"
    fi
    
else
    log_error "Build failed!"
    exit 1
fi

# Show disk usage
log_info "External drive usage:"
df -h "$EXTERNAL_DIR" | tail -1

log_info "OS drive usage (should be unchanged):"
df -h / | tail -1