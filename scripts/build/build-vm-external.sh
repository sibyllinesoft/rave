#!/bin/bash
# Simple VM builder that uses Nix's native --store option to build on external drive
# This avoids any copying by building directly on the external filesystem

set -euo pipefail

EXTERNAL_DIR="/media/nathan/Seagate Hub/images"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

if [[ ! -d "$EXTERNAL_DIR" ]]; then
    log_error "External directory not found: $EXTERNAL_DIR"
    exit 1
fi

VM_TYPE="${1:-production}"

log_info "Building $VM_TYPE VM image directly on external drive..."
log_info "Target: $EXTERNAL_DIR"

cd "$PROJECT_DIR"

# Clean up any existing result symlinks in project directory
rm -f result*

# Build with output link directly on external drive
RESULT_LINK="$EXTERNAL_DIR/rave-$VM_TYPE-$(date +%Y%m%d-%H%M%S)"

if nix build ".#packages.x86_64-linux.$VM_TYPE" --out-link "$RESULT_LINK"; then
    log_success "VM built successfully!"
    log_info "Result link: $RESULT_LINK"
    
    # Create a 'latest' symlink
    LATEST_LINK="$EXTERNAL_DIR/rave-$VM_TYPE-latest"
    ln -sf "$(basename "$RESULT_LINK")" "$LATEST_LINK"
    
    # Show the actual image files
    if [[ -L "$RESULT_LINK" ]]; then
        STORE_PATH=$(readlink -f "$RESULT_LINK")
        log_info "Nix store path: $STORE_PATH"
        log_info "Image files:"
        find "$STORE_PATH" -name "*.qcow2" -o -name "*.vmdk" -o -name "*.ova" -o -name "*.iso" -o -name "*.raw" | while read -r img; do
            SIZE=$(du -h "$img" | cut -f1)
            echo "  $img ($SIZE)"
        done
    fi
    
else
    log_error "Build failed!"
    exit 1
fi

log_success "VM image available at: $RESULT_LINK"
log_info "Use 'ls -la $EXTERNAL_DIR' to see all built images"