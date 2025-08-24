#!/bin/bash
# RAVE Phase P6: Sandbox VM Cleanup Script
# Manages cleanup of sandbox VMs and resource management

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="/tmp/rave-sandboxes"
MAX_AGE_HOURS="2"
FORCE_CLEANUP=false

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_info() {
    log "INFO: $*"
}

log_error() {
    log "ERROR: $*"
}

log_warn() {
    log "WARN: $*"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up sandbox VMs and manage resources.

OPTIONS:
    --vm-name NAME          Clean up specific VM by name
    --cleanup-old           Clean up VMs older than $MAX_AGE_HOURS hours
    --cleanup-all           Clean up all sandbox VMs (use with caution)
    --max-age HOURS         Maximum age in hours for cleanup-old (default: $MAX_AGE_HOURS)
    --force                 Force cleanup without confirmation
    --list                  List all sandbox VMs and their status
    --help                  Show this help message

EXAMPLES:
    $0 --vm-name sandbox-mr-123
    $0 --cleanup-old --max-age 1
    $0 --list
    $0 --cleanup-all --force

ENVIRONMENT VARIABLES:
    SANDBOX_DIR             Directory for sandbox VMs (default: $SANDBOX_DIR)
    
EOF
}

# Parse command line arguments
parse_args() {
    local action=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm-name)
                VM_NAME="$2"
                action="cleanup-vm"
                shift 2
                ;;
            --cleanup-old)
                action="cleanup-old"
                shift
                ;;
            --cleanup-all)
                action="cleanup-all"
                shift
                ;;
            --max-age)
                MAX_AGE_HOURS="$2"
                shift 2
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --list)
                action="list"
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
    
    if [[ -z "$action" ]]; then
        log_error "No action specified"
        usage
        exit 1
    fi
    
    ACTION="$action"
}

# List all sandbox VMs
list_sandboxes() {
    log_info "🔍 Listing sandbox VMs in $SANDBOX_DIR"
    
    if [[ ! -d "$SANDBOX_DIR" ]]; then
        log_info "No sandbox directory found"
        return 0
    fi
    
    local found=false
    
    printf "%-20s %-10s %-10s %-20s %-15s %s\n" "VM NAME" "STATUS" "AGE" "CREATED" "PORTS" "COMMIT"
    printf "%-20s %-10s %-10s %-20s %-15s %s\n" "--------" "------" "---" "-------" "-----" "------"
    
    for vm_dir in "$SANDBOX_DIR"/*/; do
        if [[ ! -d "$vm_dir" ]]; then
            continue
        fi
        
        found=true
        local vm_name
        vm_name=$(basename "$vm_dir")
        
        # Get VM info
        local status="UNKNOWN"
        local age="N/A"
        local created="N/A"
        local ports="N/A"
        local commit="N/A"
        
        if [[ -f "$vm_dir/vm-info.json" ]]; then
            local vm_info
            if vm_info=$(cat "$vm_dir/vm-info.json" 2>/dev/null); then
                created=$(echo "$vm_info" | jq -r '.created_at // "N/A"' 2>/dev/null)
                ports=$(echo "$vm_info" | jq -r '"\(.ssh_port):\(.web_port)"' 2>/dev/null)
                commit=$(echo "$vm_info" | jq -r '.commit_sha // "N/A"' 2>/dev/null | cut -c1-8)
                
                # Calculate age
                if [[ "$created" != "N/A" ]]; then
                    local created_epoch
                    created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
                    local now_epoch
                    now_epoch=$(date +%s)
                    local age_seconds=$((now_epoch - created_epoch))
                    local age_hours=$((age_seconds / 3600))
                    local age_minutes=$(((age_seconds % 3600) / 60))
                    
                    if [[ $age_hours -gt 0 ]]; then
                        age="${age_hours}h${age_minutes}m"
                    else
                        age="${age_minutes}m"
                    fi
                fi
            fi
        fi
        
        # Check if VM is running
        if [[ -f "$vm_dir/qemu.pid" ]]; then
            local qemu_pid
            qemu_pid=$(cat "$vm_dir/qemu.pid" 2>/dev/null || echo "")
            if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
                status="RUNNING"
            else
                status="STOPPED"
            fi
        else
            status="NO-PID"
        fi
        
        printf "%-20s %-10s %-10s %-20s %-15s %s\n" \
               "$vm_name" "$status" "$age" "$created" "$ports" "$commit"
    done
    
    if [[ "$found" != "true" ]]; then
        log_info "No sandbox VMs found"
    fi
}

# Clean up a specific VM
cleanup_vm() {
    local vm_name="$1"
    local vm_dir="$SANDBOX_DIR/$vm_name"
    
    log_info "🧹 Cleaning up VM: $vm_name"
    
    if [[ ! -d "$vm_dir" ]]; then
        log_warn "VM directory not found: $vm_dir"
        return 0
    fi
    
    local cleaned_resources=()
    
    # Stop cleanup timer if running
    if [[ -f "$vm_dir/cleanup.pid" ]]; then
        local cleanup_pid
        cleanup_pid=$(cat "$vm_dir/cleanup.pid" 2>/dev/null || echo "")
        if [[ -n "$cleanup_pid" ]] && kill -0 "$cleanup_pid" 2>/dev/null; then
            log_info "Stopping cleanup timer (PID: $cleanup_pid)"
            kill -TERM "$cleanup_pid" 2>/dev/null || true
            cleaned_resources+=("cleanup-timer")
        fi
    fi
    
    # Stop QEMU process
    if [[ -f "$vm_dir/qemu.pid" ]]; then
        local qemu_pid
        qemu_pid=$(cat "$vm_dir/qemu.pid" 2>/dev/null || echo "")
        if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
            log_info "Terminating QEMU process (PID: $qemu_pid)"
            
            # Try graceful shutdown first
            if [[ -S "$vm_dir/monitor.sock" ]]; then
                echo "system_powerdown" | socat - "UNIX:$vm_dir/monitor.sock" 2>/dev/null || true
                sleep 5
            fi
            
            # Force kill if still running
            if kill -0 "$qemu_pid" 2>/dev/null; then
                kill -TERM "$qemu_pid" 2>/dev/null || true
                sleep 3
                if kill -0 "$qemu_pid" 2>/dev/null; then
                    kill -KILL "$qemu_pid" 2>/dev/null || true
                fi
            fi
            cleaned_resources+=("qemu-process")
        fi
    fi
    
    # Remove TAP interface
    if [[ -f "$vm_dir/vm-info.json" ]]; then
        local tap_interface
        tap_interface=$(jq -r '.tap_interface // empty' "$vm_dir/vm-info.json" 2>/dev/null || echo "")
        if [[ -n "$tap_interface" ]] && ip link show "$tap_interface" >/dev/null 2>&1; then
            log_info "Removing TAP interface: $tap_interface"
            ip link delete "$tap_interface" 2>/dev/null || true
            cleaned_resources+=("tap-interface")
        fi
    fi
    
    # Remove working directory
    log_info "Removing VM working directory: $vm_dir"
    rm -rf "$vm_dir"
    cleaned_resources+=("work-directory")
    
    log_info "✅ VM cleanup completed: $vm_name"
    log_info "Cleaned resources: ${cleaned_resources[*]}"
}

# Clean up old VMs
cleanup_old_vms() {
    log_info "🧹 Cleaning up VMs older than $MAX_AGE_HOURS hours"
    
    if [[ ! -d "$SANDBOX_DIR" ]]; then
        log_info "No sandbox directory found"
        return 0
    fi
    
    local cleanup_count=0
    local current_time
    current_time=$(date +%s)
    local max_age_seconds=$((MAX_AGE_HOURS * 3600))
    
    for vm_dir in "$SANDBOX_DIR"/*/; do
        if [[ ! -d "$vm_dir" ]]; then
            continue
        fi
        
        local vm_name
        vm_name=$(basename "$vm_dir")
        
        # Get creation time
        local created_time=""
        if [[ -f "$vm_dir/vm-info.json" ]]; then
            created_time=$(jq -r '.created_at // empty' "$vm_dir/vm-info.json" 2>/dev/null || echo "")
        fi
        
        # Fall back to directory modification time if no JSON info
        if [[ -z "$created_time" ]]; then
            created_time=$(stat -c %Y "$vm_dir" 2>/dev/null || echo "0")
        else
            created_time=$(date -d "$created_time" +%s 2>/dev/null || echo "0")
        fi
        
        # Check age
        local age_seconds=$((current_time - created_time))
        if [[ $age_seconds -gt $max_age_seconds ]]; then
            local age_hours=$((age_seconds / 3600))
            log_info "VM $vm_name is ${age_hours}h old, cleaning up..."
            cleanup_vm "$vm_name"
            cleanup_count=$((cleanup_count + 1))
        fi
    done
    
    log_info "✅ Cleaned up $cleanup_count old VMs"
}

# Clean up all VMs
cleanup_all_vms() {
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo "WARNING: This will clean up ALL sandbox VMs!"
        echo "This action cannot be undone."
        echo
        list_sandboxes
        echo
        read -p "Are you sure you want to continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            return 0
        fi
    fi
    
    log_info "🧹 Cleaning up ALL sandbox VMs"
    
    if [[ ! -d "$SANDBOX_DIR" ]]; then
        log_info "No sandbox directory found"
        return 0
    fi
    
    local cleanup_count=0
    
    for vm_dir in "$SANDBOX_DIR"/*/; do
        if [[ ! -d "$vm_dir" ]]; then
            continue
        fi
        
        local vm_name
        vm_name=$(basename "$vm_dir")
        
        log_info "Cleaning up VM: $vm_name"
        cleanup_vm "$vm_name"
        cleanup_count=$((cleanup_count + 1))
    done
    
    # Remove sandbox directory if empty
    if [[ $cleanup_count -gt 0 ]]; then
        rmdir "$SANDBOX_DIR" 2>/dev/null || true
    fi
    
    log_info "✅ Cleaned up $cleanup_count VMs"
}

# Check system resources and clean up if needed
check_resources() {
    log_info "🔍 Checking system resources..."
    
    # Check available disk space (warn if less than 2GB free)
    local available_space
    available_space=$(df "$SANDBOX_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local available_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_gb -lt 2 ]]; then
        log_warn "Low disk space: ${available_gb}GB available"
        log_warn "Consider running cleanup to free space"
    fi
    
    # Check number of running VMs
    local running_vms=0
    if [[ -d "$SANDBOX_DIR" ]]; then
        for vm_dir in "$SANDBOX_DIR"/*/; do
            if [[ ! -d "$vm_dir" ]]; then
                continue
            fi
            
            if [[ -f "$vm_dir/qemu.pid" ]]; then
                local qemu_pid
                qemu_pid=$(cat "$vm_dir/qemu.pid" 2>/dev/null || echo "")
                if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
                    running_vms=$((running_vms + 1))
                fi
            fi
        done
    fi
    
    log_info "System status:"
    log_info "  Available disk space: ${available_gb}GB"
    log_info "  Running sandbox VMs: $running_vms"
    
    if [[ $running_vms -gt 3 ]]; then
        log_warn "High number of running VMs: $running_vms"
        log_warn "Consider cleaning up old VMs to free resources"
    fi
}

# Emergency cleanup for resource issues
emergency_cleanup() {
    log_warn "🚨 Emergency cleanup triggered"
    
    # Force cleanup of VMs older than 30 minutes
    MAX_AGE_HOURS="0.5"
    FORCE_CLEANUP=true
    cleanup_old_vms
    
    # Clean up any orphaned processes
    log_info "Cleaning up orphaned QEMU processes..."
    pgrep -f "qemu.*sandbox" | while read -r pid; do
        log_info "Killing orphaned QEMU process: $pid"
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Clean up orphaned TAP interfaces
    log_info "Cleaning up orphaned TAP interfaces..."
    ip link show | grep -E "sandbox.*-tap" | cut -d: -f2 | tr -d ' ' | while read -r interface; do
        log_info "Removing orphaned TAP interface: $interface"
        ip link delete "$interface" 2>/dev/null || true
    done
    
    log_info "✅ Emergency cleanup completed"
}

# Main execution
main() {
    log_info "🧹 RAVE P6: Sandbox VM Cleanup Script"
    log_info "====================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Check if running with proper privileges for network operations
    if [[ $EUID -ne 0 ]] && [[ "$ACTION" == *"cleanup"* ]]; then
        log_warn "Running without root privileges - some network cleanup may fail"
    fi
    
    # Execute requested action
    case "$ACTION" in
        "list")
            list_sandboxes
            check_resources
            ;;
        "cleanup-vm")
            if [[ -z "${VM_NAME:-}" ]]; then
                log_error "VM name required for cleanup-vm action"
                exit 1
            fi
            cleanup_vm "$VM_NAME"
            ;;
        "cleanup-old")
            cleanup_old_vms
            check_resources
            ;;
        "cleanup-all")
            cleanup_all_vms
            check_resources
            ;;
        "emergency")
            emergency_cleanup
            ;;
        *)
            log_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    
    log_info "🎉 Cleanup operation completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi