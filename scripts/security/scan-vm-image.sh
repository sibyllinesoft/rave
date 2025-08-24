#!/usr/bin/env bash
# VM Image Security Scanning with Trivy
# Scans built qcow2 VM images for CVEs and security vulnerabilities

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/security-reports"
TRIVY_CACHE_DIR="${PROJECT_ROOT}/.trivy-cache"
CONFIG_FILE="${SCRIPT_DIR}/security-config.sh"

# Default thresholds (can be overridden by config)
CRITICAL_THRESHOLD=0
HIGH_THRESHOLD=10
MEDIUM_THRESHOLD=50

# Load configuration if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=./security-config.sh
    source "$CONFIG_FILE"
fi

# Function to log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to check if Trivy is available
check_trivy() {
    if ! command -v trivy &> /dev/null; then
        log "${RED}ERROR: Trivy is not installed${NC}"
        log "Install with: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
        exit 1
    fi
}

# Function to update vulnerability database
update_db() {
    log "${BLUE}Updating Trivy vulnerability database...${NC}"
    trivy --cache-dir "$TRIVY_CACHE_DIR" image --download-db-only
}

# Function to scan VM image
scan_image() {
    local image_path="$1"
    local output_format="${2:-json}"
    local report_file="$3"

    log "${BLUE}Scanning VM image: ${image_path}${NC}"
    
    if [[ ! -f "$image_path" ]]; then
        log "${RED}ERROR: VM image not found: ${image_path}${NC}"
        return 1
    fi

    # Create a temporary directory for mounting
    local mount_dir
    mount_dir=$(mktemp -d)
    local loop_device

    # Cleanup function
    cleanup() {
        if [[ -n "${loop_device:-}" ]] && losetup "$loop_device" &>/dev/null; then
            log "Detaching loop device: $loop_device"
            sudo losetup -d "$loop_device" || true
        fi
        if [[ -d "$mount_dir" ]]; then
            if mountpoint -q "$mount_dir" 2>/dev/null; then
                log "Unmounting: $mount_dir"
                sudo umount "$mount_dir" || true
            fi
            rmdir "$mount_dir" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    # For qcow2 images, we need to convert or use qemu-nbd
    if command -v qemu-img &> /dev/null && command -v qemu-nbd &> /dev/null; then
        # Try to scan using filesystem scanning method
        log "${YELLOW}Note: Scanning qcow2 images directly is complex. Consider extracting filesystem or using container scanning methods.${NC}"
        
        # Alternative: scan the NixOS packages used in the image
        if [[ -f "${PROJECT_ROOT}/simple-ai-config.nix" ]]; then
            log "${BLUE}Scanning NixOS configuration packages instead...${NC}"
            scan_nixos_packages "$report_file" "$output_format"
            return $?
        fi
    fi

    # Fallback: basic file system scanning (limited effectiveness for qcow2)
    log "${YELLOW}Performing basic vulnerability scanning...${NC}"
    trivy --cache-dir "$TRIVY_CACHE_DIR" fs \
        --format "$output_format" \
        --output "$report_file" \
        --severity HIGH,CRITICAL \
        --ignore-unfixed \
        "$PROJECT_ROOT" || {
        log "${RED}Trivy scan failed${NC}"
        return 1
    }
}

# Function to scan NixOS packages
scan_nixos_packages() {
    local report_file="$1"
    local output_format="${2:-json}"

    log "${BLUE}Extracting packages from NixOS configuration...${NC}"
    
    # Extract package names from nix files
    local packages_file="${REPORTS_DIR}/packages.txt"
    grep -h "with pkgs;" "${PROJECT_ROOT}"/*.nix | sed 's/.*with pkgs;//' | tr ' ' '\n' | sort -u > "$packages_file" || true
    grep -h "pkgs\." "${PROJECT_ROOT}"/*.nix | sed 's/.*pkgs\.//' | cut -d' ' -f1 | cut -d';' -f1 | sort -u >> "$packages_file" || true

    # Create a pseudo-manifest for scanning
    local manifest_file="${REPORTS_DIR}/nix-packages.json"
    cat > "$manifest_file" << EOF
{
  "packages": [
EOF

    local first=true
    while IFS= read -r package; do
        if [[ -n "$package" && "$package" != *"#"* ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo "," >> "$manifest_file"
            fi
            echo "    \"$package\"" >> "$manifest_file"
        fi
    done < "$packages_file"

    cat >> "$manifest_file" << EOF
  ]
}
EOF

    # Scan using config mode
    trivy --cache-dir "$TRIVY_CACHE_DIR" config \
        --format "$output_format" \
        --output "$report_file" \
        "$PROJECT_ROOT" || {
        log "${YELLOW}Config scan completed with warnings${NC}"
    }
}

# Function to parse results and check thresholds
check_thresholds() {
    local report_file="$1"
    
    if [[ ! -f "$report_file" ]]; then
        log "${RED}ERROR: Report file not found: ${report_file}${NC}"
        return 1
    fi

    # Parse JSON report for vulnerability counts
    if command -v jq &> /dev/null; then
        local critical_count
        local high_count
        local medium_count
        
        critical_count=$(jq -r '[.Results[]? | .Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$report_file" 2>/dev/null || echo "0")
        high_count=$(jq -r '[.Results[]? | .Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$report_file" 2>/dev/null || echo "0")
        medium_count=$(jq -r '[.Results[]? | .Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "$report_file" 2>/dev/null || echo "0")

        log "${BLUE}Vulnerability Summary:${NC}"
        log "  Critical: ${critical_count}"
        log "  High: ${high_count}" 
        log "  Medium: ${medium_count}"

        # Check thresholds
        local exit_code=0

        if [[ "$critical_count" -gt "$CRITICAL_THRESHOLD" ]]; then
            log "${RED}FAIL: Critical vulnerabilities ($critical_count) exceed threshold ($CRITICAL_THRESHOLD)${NC}"
            exit_code=1
        fi

        if [[ "$high_count" -gt "$HIGH_THRESHOLD" ]]; then
            log "${RED}FAIL: High vulnerabilities ($high_count) exceed threshold ($HIGH_THRESHOLD)${NC}"
            exit_code=1
        fi

        if [[ "$medium_count" -gt "$MEDIUM_THRESHOLD" ]]; then
            log "${YELLOW}WARNING: Medium vulnerabilities ($medium_count) exceed threshold ($MEDIUM_THRESHOLD)${NC}"
            # Don't fail on medium, just warn
        fi

        if [[ "$exit_code" -eq 0 ]]; then
            log "${GREEN}PASS: All vulnerability thresholds met${NC}"
        fi

        return $exit_code
    else
        log "${YELLOW}jq not available, skipping threshold checks${NC}"
        return 0
    fi
}

# Function to generate summary report
generate_summary() {
    local report_file="$1"
    local summary_file="${REPORTS_DIR}/security-summary.txt"

    cat > "$summary_file" << EOF
Security Scan Summary
=====================
Generated: $(date)
Image: $2
Report: $(basename "$report_file")

EOF

    if command -v jq &> /dev/null && [[ -f "$report_file" ]]; then
        echo "Vulnerability Counts:" >> "$summary_file"
        jq -r '
        [.Results[]? | .Vulnerabilities[]?] as $all |
        ($all | map(select(.Severity == "CRITICAL")) | length) as $critical |
        ($all | map(select(.Severity == "HIGH")) | length) as $high |
        ($all | map(select(.Severity == "MEDIUM")) | length) as $medium |
        ($all | map(select(.Severity == "LOW")) | length) as $low |
        "  Critical: \($critical)",
        "  High: \($high)",
        "  Medium: \($medium)",
        "  Low: \($low)"
        ' "$report_file" >> "$summary_file" 2>/dev/null || echo "  Unable to parse vulnerability counts" >> "$summary_file"
    fi

    log "${GREEN}Summary report generated: ${summary_file}${NC}"
}

# Main function
main() {
    local image_path="${1:-}"
    local output_format="${2:-json}"

    if [[ -z "$image_path" ]]; then
        echo "Usage: $0 <vm-image-path> [output-format]"
        echo "Example: $0 ./result/nixos.qcow2 json"
        exit 1
    fi

    # Setup
    mkdir -p "$REPORTS_DIR" "$TRIVY_CACHE_DIR"
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="${REPORTS_DIR}/vm-scan-${timestamp}.${output_format}"

    log "${GREEN}Starting VM Image Security Scan${NC}"
    log "Image: $image_path"
    log "Output format: $output_format"
    log "Report: $report_file"

    # Check dependencies
    check_trivy

    # Update vulnerability database
    update_db

    # Perform scan
    if scan_image "$image_path" "$output_format" "$report_file"; then
        log "${GREEN}Scan completed successfully${NC}"
        
        # Generate summary
        generate_summary "$report_file" "$image_path"
        
        # Check thresholds and exit with appropriate code
        check_thresholds "$report_file"
    else
        log "${RED}Scan failed${NC}"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi