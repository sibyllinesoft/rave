#!/bin/bash
# RAVE Master Service Runner
# Single entry point for managing key services, primarily GitLab.

set -euo pipefail

# --- Configuration ---
GITLAB_DIR="gitlab-complete"
DOCKER_COMPOSE_CMD="docker compose"

# --- Colors ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Helper Functions ---
log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

usage() {
    echo "RAVE Master Service Runner"
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  start      - Start the GitLab service stack."
    echo "  stop       - Stop the GitLab service stack."
    echo "  status     - Show the status of GitLab containers."
    echo "  logs       - Follow the logs from all GitLab services."
    echo "  restart    - Restart the GitLab services."
    echo "  validate   - Run health checks and redirect validation."
    echo "  penpot     - Manage Penpot design tool (use: run.sh penpot help)."
    echo "  help       - Show this help message."
    exit 1
}

# --- Command Functions ---
cmd_start() {
    log_info "Starting GitLab stack..."
    if [ ! -f "${GITLAB_DIR}/scripts/startup.sh" ]; then
        log_error "Startup script not found in ${GITLAB_DIR}/scripts/"
        exit 1
    fi
    (cd "${GITLAB_DIR}" && ./scripts/startup.sh)
    log_success "GitLab stack started."
}

cmd_stop() {
    log_info "Stopping GitLab stack..."
    (cd "${GITLAB_DIR}" && ${DOCKER_COMPOSE_CMD} down)
    log_success "GitLab stack stopped."
}

cmd_status() {
    log_info "GitLab stack status:"
    (cd "${GITLAB_DIR}" && ${DOCKER_COMPOSE_CMD} ps)
}

cmd_logs() {
    log_info "Following logs for GitLab stack... (Press Ctrl+C to exit)"
    (cd "${GITLAB_DIR}" && ${DOCKER_COMPOSE_CMD} logs -f)
}

cmd_restart() {
    log_info "Restarting GitLab stack..."
    cmd_stop
    sleep 2
    cmd_start
    log_success "GitLab stack restarted."
}

cmd_validate() {
    log_info "Running validation suite for GitLab..."
    (cd "${GITLAB_DIR}" && ./scripts/health-check.sh)
    (cd "${GITLAB_DIR}" && ./scripts/validate-redirect-fix.sh)
    log_success "Validation complete."
}

cmd_penpot() {
    log_info "Penpot Design Tool Management"
    shift # Remove 'penpot' from arguments
    if [ ! -f "${GITLAB_DIR}/scripts/penpot.sh" ]; then
        log_error "Penpot script not found in ${GITLAB_DIR}/scripts/"
        exit 1
    fi
    (cd "${GITLAB_DIR}" && ./scripts/penpot.sh "$@")
}

# --- Main Logic ---
if [ ! -d "$GITLAB_DIR" ]; then
    log_error "GitLab directory '${GITLAB_DIR}' not found. Cannot proceed."
    exit 1
fi

# Check for docker compose vs docker-compose
if ! docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
fi

COMMAND="${1:-}"
case "$COMMAND" in
    start|up) cmd_start ;;
    stop|down) cmd_stop ;;
    status|ps) cmd_status ;;
    logs) cmd_logs ;;
    restart) cmd_restart ;;
    validate|test|check) cmd_validate ;;
    penpot) cmd_penpot "$@" ;;
    help|--help|-h) usage ;;
    *)
        log_error "Unknown command: '$COMMAND'"
        usage
        ;;
esac

if [ -z "$COMMAND" ]; then
    usage
fi