#!/usr/bin/env bash
# RAVE VM Test Runner - P2.3
# Quick testing script for local P2 development

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
RAVE VM Test Runner - Phase P2

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    build       Build P2 VM image
    test        Run NixOS VM integration tests
    run         Start P2 VM interactively
    ci          Run full CI-like pipeline locally
    health      Quick health check of built images

Options:
    --phase     Target phase (p0, p1, p2) [default: p2]
    --memory    VM memory in MB [default: 2048]
    --headless  Run VM without graphics
    --help      Show this help

Examples:
    $0 build                    # Build P2 image
    $0 test                     # Run integration tests
    $0 run --headless          # Start P2 VM headless
    $0 ci                      # Full local CI pipeline
    $0 build --phase p1        # Build P1 instead

EOF
}

# Default values
PHASE="p2"
MEMORY="2048"
HEADLESS=""
COMMAND=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        build|test|run|ci|health)
            COMMAND=$1
            shift
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --headless)
            HEADLESS="--headless"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    usage
    exit 1
fi

# Verify Nix is available
if ! command -v nix &> /dev/null; then
    log_error "Nix is not installed or not in PATH"
    exit 1
fi

# Check flake configuration
if [[ ! -f "flake.nix" ]]; then
    log_error "flake.nix not found. Run from RAVE project root."
    exit 1
fi

build_image() {
    local phase=$1
    log_info "Building ${phase}-production image..."
    
    # Memory-conscious build
    export NIX_CONFIG="max-jobs = 2
cores = 4
keep-outputs = true
experimental-features = nix-command flakes"
    
    local build_start=$(date +%s)
    
    if nix build ".#${phase}-production" --show-trace; then
        local build_end=$(date +%s)
        local duration=$((build_end - build_start))
        log_success "Build completed in ${duration}s"
        
        # Show image info
        local image_path=$(nix eval --impure --raw ".#${phase}-production.outPath")
        if [[ -f "$image_path" ]]; then
            log_info "Image: $image_path"
            log_info "Size: $(ls -lh "$image_path" | awk '{print $5}')"
        fi
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

run_vm_tests() {
    log_info "Running NixOS VM integration tests..."
    
    local test_start=$(date +%s)
    
    if nix build ".#tests.rave-vm" --show-trace; then
        log_success "VM tests built successfully"
        
        # Run the test
        log_info "Executing VM test runner..."
        if nix run ".#tests.rave-vm"; then
            local test_end=$(date +%s)
            local duration=$((test_end - test_start))
            log_success "All VM tests passed in ${duration}s"
            return 0
        else
            log_error "VM tests failed"
            return 1
        fi
    else
        log_error "Failed to build VM tests"
        return 1
    fi
}

run_vm_interactive() {
    local phase=$1
    local memory=$2
    local headless_flag=$3
    
    log_info "Starting ${phase}-production VM (${memory}MB RAM)"
    
    # Build if not present
    if ! nix build ".#${phase}-production" --no-link; then
        log_error "Failed to build ${phase} image"
        return 1
    fi
    
    local image_path=$(nix eval --impure --raw ".#${phase}-production.outPath")
    
    if [[ ! -f "$image_path" ]]; then
        log_error "VM image not found: $image_path"
        return 1
    fi
    
    # QEMU arguments
    local qemu_args=(
        "-m" "$memory"
        "-enable-kvm"
        "-netdev" "user,id=net0,hostfwd=tcp::3002-:3002,hostfwd=tcp::3030-:3030,hostfwd=tcp::9090-:9090"
        "-device" "virtio-net,netdev=net0"
        "-hda" "$image_path"
    )
    
    if [[ -n "$headless_flag" ]]; then
        qemu_args+=("-nographic")
        log_info "Starting VM in headless mode (Ctrl+A, X to exit)"
    else
        log_info "Starting VM with graphics (close window to exit)"
    fi
    
    log_info "VM will be accessible at:"
    log_info "  • Main UI: https://localhost:3002/"
    log_info "  • Grafana: https://localhost:3002/grafana/"
    log_info "  • Prometheus: http://localhost:9090/ (if P2)"
    
    qemu-system-x86_64 "${qemu_args[@]}"
}

run_ci_pipeline() {
    log_info "Running CI-like pipeline locally..."
    
    # Lint phase
    log_info "=== LINT PHASE ==="
    if nix flake check --show-trace; then
        log_success "Nix flake check passed"
    else
        log_error "Nix flake check failed"
        return 1
    fi
    
    # Build phase
    log_info "=== BUILD PHASE ==="
    if ! build_image "$PHASE"; then
        return 1
    fi
    
    # Test phase  
    log_info "=== TEST PHASE ==="
    if ! run_vm_tests; then
        return 1
    fi
    
    # Security scan (simplified)
    log_info "=== SECURITY SCAN ==="
    log_info "Checking for potential issues..."
    
    # Check for hardcoded secrets
    if grep -r -i "password\|secret\|key" --exclude="test-secrets.yaml" --exclude-dir=".git" . | grep -v "# " | head -5; then
        log_warning "Found potential hardcoded secrets (review manually)"
    else
        log_success "No obvious hardcoded secrets found"
    fi
    
    log_success "Local CI pipeline completed successfully!"
}

health_check() {
    log_info "Performing health check on built images..."
    
    local phases=("p0" "p1" "p2")
    
    for phase in "${phases[@]}"; do
        log_info "Checking ${phase}-production image..."
        
        if nix eval --impure --raw ".#${phase}-production.outPath" &>/dev/null; then
            local image_path=$(nix eval --impure --raw ".#${phase}-production.outPath")
            if [[ -f "$image_path" ]]; then
                local size=$(ls -lh "$image_path" | awk '{print $5}')
                log_success "${phase}: Available (${size})"
            else
                log_warning "${phase}: Built but file not found"
            fi
        else
            log_warning "${phase}: Not built"
        fi
    done
    
    # Check test infrastructure
    log_info "Checking test infrastructure..."
    if [[ -f "tests/rave-vm.nix" ]]; then
        log_success "VM tests: Available"
    else
        log_warning "VM tests: Missing"
    fi
    
    if [[ -f ".gitlab-ci.yml" ]]; then
        log_success "GitLab CI: Configured"
    else
        log_warning "GitLab CI: Missing"
    fi
    
    # Check dashboards
    local dashboard_count=$(find dashboards/ -name "*.json" 2>/dev/null | wc -l)
    if [[ $dashboard_count -gt 0 ]]; then
        log_success "Grafana dashboards: ${dashboard_count} available"
    else
        log_warning "Grafana dashboards: None found"
    fi
}

# Main execution
case $COMMAND in
    build)
        build_image "$PHASE"
        ;;
    test)
        run_vm_tests
        ;;
    run)
        run_vm_interactive "$PHASE" "$MEMORY" "$HEADLESS"
        ;;
    ci)
        run_ci_pipeline
        ;;
    health)
        health_check
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac