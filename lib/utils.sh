#!/bin/bash
# Common logging and retry helpers for RAVE shell tooling.

# Color palette
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# wait_for <description> <command> [max_retries]
# Repeatedly executes the command until it succeeds or times out.
wait_for() {
    local desc="$1"
    local cmd="$2"
    local max_retries="${3:-${MAX_RETRIES:-20}}"
    local sleep_interval="${SLEEP_INTERVAL:-15}"

    log_info "Waiting for: ${desc}"
    local count=0
    while [ "$count" -lt "$max_retries" ]; do
        if eval "$cmd"; then
            return 0
        fi
        count=$((count + 1))
        echo -n "."
        sleep "$sleep_interval"
    done

    log_warn "Timeout waiting for ${desc} after ${max_retries} attempts"
    return 1
}
