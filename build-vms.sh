#!/bin/bash
# RAVE VM Builder - Builds VM images directly to external storage
# This script configures Nix to build directly to /media/nathan/Seagate Hub/images/

set -euo pipefail

# Configuration
TARGET_DIR="/media/nathan/Seagate Hub/images"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Set NIX_BUILD_DIRECTORY to build directly to target
export TMPDIR="$TARGET_DIR/nix-build-tmp"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if target directory exists and is writable
    if [[ ! -d "$TARGET_DIR" ]]; then
        log_error "Target directory does not exist: $TARGET_DIR"
        exit 1
    fi
    
    if [[ ! -w "$TARGET_DIR" ]]; then
        log_error "Target directory is not writable: $TARGET_DIR"
        exit 1
    fi
    
    # Check if nix is available
    if ! command -v nix >/dev/null 2>&1; then
        log_error "Nix is not installed or not in PATH"
        exit 1
    fi
    
    # Check available disk space (require at least 10GB)
    available_space=$(df "$TARGET_DIR" | tail -1 | awk '{print $4}')
    required_space=10485760  # 10GB in KB
    if [[ $available_space -lt $required_space ]]; then
        log_warn "Low disk space. Available: $(($available_space / 1024 / 1024))GB, Recommended: 10GB"
    fi
    
    # Create temp directory for Nix builds
    mkdir -p "$TMPDIR"
    
    log_success "Prerequisites check passed"
}

# Build a specific VM image directly to target directory
build_vm() {
    local vm_type="$1"
    local image_name="rave-${vm_type}-${TIMESTAMP}"
    
    log_info "Building $vm_type VM image directly to external drive..."
    
    cd "$PROJECT_DIR"
    
    # Clean up any existing result symlinks
    rm -f result*
    
    # Build the VM with custom output directory
    log_info "Building with Nix (this may take a while)..."
    if ! nix build ".#packages.x86_64-linux.$vm_type" --out-link "$TARGET_DIR/nix-result-$vm_type"; then
        log_error "Failed to build $vm_type VM"
        return 1
    fi
    
    # Find the built image file
    local source_path="$TARGET_DIR/nix-result-$vm_type"
    if [[ -L "$source_path" ]]; then
        local store_path=$(readlink -f "$source_path")
        
        # Find the actual image file (usually .qcow2, .vmdk, etc.)
        local image_file
        if [[ -f "$store_path/nixos.qcow2" ]]; then
            image_file="$store_path/nixos.qcow2"
        elif [[ -f "$store_path"/*.qcow2 ]]; then
            image_file="$store_path"/*.qcow2
        elif [[ -f "$store_path"/*.vmdk ]]; then
            image_file="$store_path"/*.vmdk
        elif [[ -f "$store_path"/*.ova ]]; then
            image_file="$store_path"/*.ova
        elif [[ -f "$store_path"/*.iso ]]; then
            image_file="$store_path"/*.iso
        elif [[ -f "$store_path"/*.raw ]]; then
            image_file="$store_path"/*.raw
        else
            log_error "Could not find image file in $store_path"
            return 1
        fi
        
        # Get the file extension
        local ext="${image_file##*.}"
        local target_file="$TARGET_DIR/${image_name}.${ext}"
        
        log_info "Creating symlink to built image..."
        
        # Create a hard link or symlink to the image (no copying!)
        ln -sf "$(realpath "$image_file")" "$target_file"
        
        # Create a symlink to the latest version
        local latest_link="$TARGET_DIR/rave-${vm_type}-latest.${ext}"
        ln -sf "$(basename "$target_file")" "$latest_link"
        
        # Get file size for reporting
        local size=$(du -h "$image_file" | cut -f1)
        
        log_success "$vm_type VM built and linked: $target_file ($size)"
        
        # Create metadata file
        cat > "$TARGET_DIR/${image_name}.meta" << EOF
{
  "vm_type": "$vm_type",
  "build_date": "$(date -Iseconds)",
  "build_timestamp": "$TIMESTAMP",
  "file_name": "$(basename "$target_file")",
  "file_size_bytes": $(stat -f%z "$image_file" 2>/dev/null || stat -c%s "$image_file"),
  "file_size_human": "$size",
  "nix_store_path": "$store_path",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo "unknown")",
  "git_branch": "$(git branch --show-current 2>/dev/null || echo "unknown")"
}
EOF
        
    else
        log_error "No result symlink found after build"
        return 1
    fi
    
    return 0
}

# List available VM types
list_vm_types() {
    echo "Available VM types:"
    echo "  production  - Full security hardening and all services"
    echo "  development - HTTP-only, minimal security for local testing"
    echo "  demo        - Minimal services for demonstrations"
    echo "  virtualbox  - VirtualBox OVA format"
    echo "  vmware      - VMware VMDK format"
    echo "  raw         - Raw disk image"
    echo "  iso         - ISO installation image"
}

# Clean old images
clean_old_images() {
    local keep_count=${1:-5}
    log_info "Cleaning old images (keeping $keep_count most recent)..."
    
    # Clean each VM type separately
    for vm_type in production development demo virtualbox vmware raw iso; do
        # Find images for this VM type, sort by timestamp, and remove old ones
        find "$TARGET_DIR" -name "rave-${vm_type}-*.qcow2" -o -name "rave-${vm_type}-*.vmdk" -o -name "rave-${vm_type}-*.ova" -o -name "rave-${vm_type}-*.iso" -o -name "rave-${vm_type}-*.raw" | \
        sort -r | \
        tail -n +$((keep_count + 1)) | \
        while read -r old_image; do
            log_info "Removing old image: $(basename "$old_image")"
            rm -f "$old_image"
            # Also remove metadata file
            rm -f "${old_image%.*}.meta"
        done
    done
}

# Show usage
usage() {
    echo "RAVE VM Builder"
    echo "Usage: $0 [OPTIONS] [VM_TYPES...]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -l, --list     List available VM types"
    echo "  -c, --clean N  Clean old images (keep N most recent, default: 5)"
    echo "  -a, --all      Build all VM types"
    echo ""
    echo "VM Types:"
    echo "  If no VM types are specified, 'production' is built by default."
    echo ""
    list_vm_types
    echo ""
    echo "Examples:"
    echo "  $0                          # Build production VM"
    echo "  $0 development demo         # Build development and demo VMs"
    echo "  $0 --all                    # Build all VM types"
    echo "  $0 --clean 3                # Clean old images, keep 3 most recent"
}

# Main function
main() {
    local vm_types=()
    local build_all=false
    local clean_count=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--list)
                list_vm_types
                exit 0
                ;;
            -c|--clean)
                clean_count="$2"
                shift 2
                ;;
            -a|--all)
                build_all=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                vm_types+=("$1")
                shift
                ;;
        esac
    done
    
    # Clean old images if requested
    if [[ -n "$clean_count" ]]; then
        clean_old_images "$clean_count"
        if [[ ${#vm_types[@]} -eq 0 && "$build_all" == false ]]; then
            exit 0
        fi
    fi
    
    # Set VM types to build
    if [[ "$build_all" == true ]]; then
        vm_types=(production development demo virtualbox vmware raw iso)
    elif [[ ${#vm_types[@]} -eq 0 ]]; then
        vm_types=(production)
    fi
    
    # Check prerequisites
    check_prerequisites
    
    log_info "Starting VM build process..."
    log_info "Target directory: $TARGET_DIR"
    log_info "VM types to build: ${vm_types[*]}"
    
    # Build each VM type
    local failed_builds=()
    for vm_type in "${vm_types[@]}"; do
        if ! build_vm "$vm_type"; then
            failed_builds+=("$vm_type")
        fi
    done
    
    # Clean up temporary files
    log_info "Cleaning up temporary files..."
    rm -rf "$TMPDIR" 2>/dev/null || true
    
    # Report results
    echo ""
    log_info "Build process completed"
    
    if [[ ${#failed_builds[@]} -eq 0 ]]; then
        log_success "All VM builds completed successfully!"
    else
        log_error "Some builds failed: ${failed_builds[*]}"
        exit 1
    fi
    
    # Show final directory contents
    echo ""
    log_info "VM images in $TARGET_DIR:"
    ls -lh "$TARGET_DIR"/*.qcow2 "$TARGET_DIR"/*.vmdk "$TARGET_DIR"/*.ova "$TARGET_DIR"/*.iso "$TARGET_DIR"/*.raw 2>/dev/null | head -20 || log_warn "No VM images found"
}

# Run main function
main "$@"