#!/bin/bash
# RAVE Phase P6: Sandbox VM Launch Script
# Launches isolated sandbox VMs for merge request testing

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SANDBOX_DIR="/tmp/rave-sandboxes"
DEFAULT_MEMORY="4G"
DEFAULT_CPUS="2"
DEFAULT_TIMEOUT="1200"  # 20 minutes
DEFAULT_SSH_PORT="2200"

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

Launch a sandbox VM for testing agent-generated code changes.

OPTIONS:
    --vm-image PATH         Path to VM image (required)
    --vm-name NAME          Name for sandbox VM (required)
    --ssh-port PORT         SSH port for VM access (default: $DEFAULT_SSH_PORT)
    --memory SIZE           Memory allocation (default: $DEFAULT_MEMORY)
    --cpus COUNT            CPU count (default: $DEFAULT_CPUS)
    --timeout SECONDS       VM timeout in seconds (default: $DEFAULT_TIMEOUT)
    --commit SHA            Git commit SHA (optional)
    --branch NAME           Git branch name (optional)
    --mr-iid IID            Merge request IID (optional)
    --help                  Show this help message

EXAMPLES:
    $0 --vm-image ./vm.qcow2 --vm-name sandbox-mr-123 --ssh-port 2223
    $0 --vm-image ./vm.qcow2 --vm-name sandbox-test --memory 8G --cpus 4

ENVIRONMENT VARIABLES:
    SANDBOX_DIR             Directory for sandbox VMs (default: $SANDBOX_DIR)
    
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vm-image)
                VM_IMAGE="$2"
                shift 2
                ;;
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --cpus)
                CPUS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --commit)
                COMMIT_SHA="$2"
                shift 2
                ;;
            --branch)
                BRANCH_NAME="$2"
                shift 2
                ;;
            --mr-iid)
                MR_IID="$2"
                shift 2
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
    
    # Set defaults
    MEMORY=${MEMORY:-$DEFAULT_MEMORY}
    CPUS=${CPUS:-$DEFAULT_CPUS}
    TIMEOUT=${TIMEOUT:-$DEFAULT_TIMEOUT}
    SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}
    COMMIT_SHA=${COMMIT_SHA:-}
    BRANCH_NAME=${BRANCH_NAME:-}
    MR_IID=${MR_IID:-}
    
    # Validate required arguments
    if [[ -z "${VM_IMAGE:-}" ]]; then
        log_error "VM image path is required (--vm-image)"
        usage
        exit 1
    fi
    
    if [[ -z "${VM_NAME:-}" ]]; then
        log_error "VM name is required (--vm-name)"
        usage
        exit 1
    fi
    
    if [[ ! -f "$VM_IMAGE" ]]; then
        log_error "VM image file not found: $VM_IMAGE"
        exit 1
    fi
}

# Setup sandbox environment
setup_sandbox() {
    log_info "Setting up sandbox environment..."
    
    # Create sandbox directory structure
    mkdir -p "$SANDBOX_DIR"
    VM_WORK_DIR="$SANDBOX_DIR/$VM_NAME"
    
    # Clean up any existing VM with same name
    if [[ -d "$VM_WORK_DIR" ]]; then
        log_warn "Existing sandbox found, cleaning up..."
        cleanup_vm "$VM_NAME" || true
    fi
    
    mkdir -p "$VM_WORK_DIR"
    cd "$VM_WORK_DIR"
    
    log_info "Sandbox working directory: $VM_WORK_DIR"
}

# Create VM copy and setup
create_vm_copy() {
    log_info "Creating VM copy from $VM_IMAGE..."
    
    # Create a copy of the base image for this sandbox
    VM_DISK="$VM_WORK_DIR/${VM_NAME}.qcow2"
    cp "$VM_IMAGE" "$VM_DISK"
    
    # Resize disk if needed (expand to 20GB for testing)
    qemu-img resize "$VM_DISK" 20G
    
    log_info "VM disk created: $VM_DISK"
}

# Setup networking
setup_networking() {
    log_info "Setting up VM networking..."
    
    # Create tap interface for VM
    TAP_INTERFACE="${VM_NAME}-tap0"
    
    # Check if interface already exists
    if ip link show "$TAP_INTERFACE" >/dev/null 2>&1; then
        log_warn "TAP interface $TAP_INTERFACE already exists, reusing"
    else
        # Create TAP interface
        if command -v tunctl >/dev/null 2>&1; then
            tunctl -t "$TAP_INTERFACE" -u "$(whoami)" 2>/dev/null || {
                log_warn "Failed to create TAP interface, using default networking"
                TAP_INTERFACE=""
            }
        else
            log_warn "tunctl not available, using default QEMU networking"
            TAP_INTERFACE=""
        fi
    fi
    
    if [[ -n "$TAP_INTERFACE" ]]; then
        ip link set "$TAP_INTERFACE" up 2>/dev/null || {
            log_warn "Failed to bring up TAP interface, using default networking"
            TAP_INTERFACE=""
        }
    fi
}

# Launch VM
launch_vm() {
    log_info "Launching VM: $VM_NAME"
    log_info "  Memory: $MEMORY"
    log_info "  CPUs: $CPUS"
    log_info "  SSH Port: $SSH_PORT"
    log_info "  Timeout: ${TIMEOUT}s"
    
    # Generate SSH host key for this VM
    SSH_HOST_KEY="$VM_WORK_DIR/ssh_host_key"
    if [[ ! -f "$SSH_HOST_KEY" ]]; then
        ssh-keygen -t ed25519 -f "$SSH_HOST_KEY" -N "" -C "sandbox-$VM_NAME"
    fi
    
    # Create QEMU command
    QEMU_ARGS=(
        -name "$VM_NAME"
        -m "$MEMORY"
        -smp "$CPUS"
        -hda "$VM_DISK"
        -enable-kvm
        -cpu host
        -display none
        -serial stdio
        -daemonize
        
        # Network configuration
        -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::$((SSH_PORT + 800))-:3002"
        -device "virtio-net-pci,netdev=net0"
        
        # Random number generator
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        
        # Monitor socket for management
        -monitor "unix:$VM_WORK_DIR/monitor.sock,server,nowait"
        
        # PID file
        -pidfile "$VM_WORK_DIR/qemu.pid"
    )
    
    # Add TAP networking if available
    if [[ -n "$TAP_INTERFACE" ]]; then
        QEMU_ARGS+=(
            -netdev "tap,id=tap0,ifname=$TAP_INTERFACE,script=no,downscript=no"
            -device "virtio-net-pci,netdev=tap0,mac=52:54:00:12:34:$(printf '%02x' $((SSH_PORT % 256)))"
        )
    fi
    
    log_info "Starting QEMU with command: qemu-system-x86_64 ${QEMU_ARGS[*]}"
    
    # Launch QEMU
    if ! qemu-system-x86_64 "${QEMU_ARGS[@]}" > "$VM_WORK_DIR/qemu.log" 2>&1; then
        log_error "Failed to launch QEMU VM"
        cat "$VM_WORK_DIR/qemu.log"
        exit 1
    fi
    
    # Store VM information
    cat > "$VM_WORK_DIR/vm-info.json" << EOF
{
    "vm_name": "$VM_NAME",
    "ssh_port": $SSH_PORT,
    "web_port": $((SSH_PORT + 800)),
    "memory": "$MEMORY",
    "cpus": "$CPUS",
    "timeout": $TIMEOUT,
    "commit_sha": "$COMMIT_SHA",
    "branch_name": "$BRANCH_NAME",
    "mr_iid": "$MR_IID",
    "created_at": "$(date -Iseconds)",
    "expires_at": "$(date -d "+${TIMEOUT} seconds" -Iseconds)",
    "pid_file": "$VM_WORK_DIR/qemu.pid",
    "monitor_socket": "$VM_WORK_DIR/monitor.sock",
    "tap_interface": "$TAP_INTERFACE"
}
EOF
    
    log_info "VM information stored in: $VM_WORK_DIR/vm-info.json"
}

# Wait for VM to be ready
wait_for_vm() {
    log_info "Waiting for VM to boot and be accessible..."
    
    local max_attempts=60
    local attempt=0
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    
    while [[ $attempt -lt $max_attempts ]]; do
        attempt=$((attempt + 1))
        
        log_info "Boot check attempt $attempt/$max_attempts..."
        
        # Check if QEMU process is still running
        if [[ -f "$VM_WORK_DIR/qemu.pid" ]]; then
            local qemu_pid
            qemu_pid=$(cat "$VM_WORK_DIR/qemu.pid")
            if ! kill -0 "$qemu_pid" 2>/dev/null; then
                log_error "QEMU process has died unexpectedly"
                cat "$VM_WORK_DIR/qemu.log" || true
                exit 1
            fi
        else
            log_error "QEMU PID file not found"
            exit 1
        fi
        
        # Try SSH connection
        if timeout 10 ssh -o ConnectTimeout=5 \
                          -o StrictHostKeyChecking=no \
                          -o UserKnownHostsFile=/dev/null \
                          -o LogLevel=ERROR \
                          -p "$SSH_PORT" \
                          "agent@$host_ip" \
                          "echo 'SSH connection successful'" 2>/dev/null; then
            log_info "✅ VM is accessible via SSH!"
            return 0
        fi
        
        sleep 10
    done
    
    log_error "VM failed to become accessible within $((max_attempts * 10)) seconds"
    return 1
}

# Setup automatic cleanup
setup_cleanup() {
    log_info "Setting up automatic cleanup in ${TIMEOUT} seconds..."
    
    cat > "$VM_WORK_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
VM_NAME="$1"
TIMEOUT="$2"

sleep "$TIMEOUT"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Automatic cleanup triggered for VM: $VM_NAME"
/home/nathan/Projects/rave/scripts/sandbox_cleanup.sh --vm-name "$VM_NAME"
EOF
    
    chmod +x "$VM_WORK_DIR/cleanup.sh"
    
    # Start cleanup timer in background
    nohup "$VM_WORK_DIR/cleanup.sh" "$VM_NAME" "$TIMEOUT" > "$VM_WORK_DIR/cleanup.log" 2>&1 &
    echo $! > "$VM_WORK_DIR/cleanup.pid"
    
    log_info "Cleanup timer started (PID: $(cat "$VM_WORK_DIR/cleanup.pid"))"
}

# Cleanup function for errors
cleanup_vm() {
    local vm_name="$1"
    local vm_dir="$SANDBOX_DIR/$vm_name"
    
    if [[ -d "$vm_dir" ]]; then
        # Kill QEMU process
        if [[ -f "$vm_dir/qemu.pid" ]]; then
            local qemu_pid
            qemu_pid=$(cat "$vm_dir/qemu.pid")
            if kill -0 "$qemu_pid" 2>/dev/null; then
                log_info "Terminating QEMU process: $qemu_pid"
                kill -TERM "$qemu_pid" 2>/dev/null || true
                sleep 5
                kill -KILL "$qemu_pid" 2>/dev/null || true
            fi
        fi
        
        # Remove TAP interface
        local tap_interface
        if [[ -f "$vm_dir/vm-info.json" ]]; then
            tap_interface=$(jq -r '.tap_interface // empty' "$vm_dir/vm-info.json" 2>/dev/null || true)
            if [[ -n "$tap_interface" ]] && ip link show "$tap_interface" >/dev/null 2>&1; then
                log_info "Removing TAP interface: $tap_interface"
                ip link delete "$tap_interface" 2>/dev/null || true
            fi
        fi
        
        # Remove working directory
        rm -rf "$vm_dir"
    fi
}

# Main execution
main() {
    log_info "🚀 RAVE P6: Sandbox VM Launch Script"
    log_info "=================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Setup signal handlers for cleanup
    trap 'log_error "Script interrupted"; cleanup_vm "$VM_NAME"; exit 1' INT TERM
    
    # Execute launch sequence
    setup_sandbox
    create_vm_copy
    setup_networking
    launch_vm
    
    if wait_for_vm; then
        setup_cleanup
        
        log_info "🎉 Sandbox VM successfully launched!"
        log_info "VM Name: $VM_NAME"
        log_info "SSH Access: ssh -p $SSH_PORT agent@$(hostname -I | awk '{print $1}')"
        log_info "Web Access: https://$(hostname -I | awk '{print $1}'):$((SSH_PORT + 800))/"
        log_info "Working Directory: $VM_WORK_DIR"
        log_info "Automatic cleanup in: ${TIMEOUT} seconds"
        
        # Output access information for CI/CD
        echo "VM_NAME=$VM_NAME"
        echo "SSH_HOST=$(hostname -I | awk '{print $1}')"
        echo "SSH_PORT=$SSH_PORT"
        echo "WEB_PORT=$((SSH_PORT + 800))"
        echo "WORK_DIR=$VM_WORK_DIR"
        
    else
        log_error "❌ Failed to launch sandbox VM"
        cleanup_vm "$VM_NAME"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi