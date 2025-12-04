#!/bin/bash
# SSH helpers for interacting with the RAVE VM.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/rave.env"

# Load shared configuration if present
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

vm_exec() {
    sshpass -p "${VM_PASS}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -p "${VM_SSH_PORT}" \
        "${VM_USER}@${VM_HOST}" "$@"
}

check_ssh_ready() {
    vm_exec "true" 2>/dev/null
}
