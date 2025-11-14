#!/bin/bash
# GitLab Health Check Script
# Comprehensive validation of GitLab service health and functionality

set -euo pipefail

# Configuration
GITLAB_BASE_URL="https://localhost:3002/gitlab"
TIMEOUT_SECONDS=30
MAX_RETRIES=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $*"; }
log_warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date +'%H:%M:%S')] SUCCESS:${NC} $*"; }

# Health check results
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_TOTAL=0

check_result() {
    local name="$1"
    local status="$2"
    local details="${3:-}"
    
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    
    if [[ "$status" == "PASS" ]]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        log_success "✅ $name"
    else
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        log_error "❌ $name"
    fi
    
    [[ -n "$details" ]] && echo "   └─ $details"
}

# Check if GitLab systemd service is active
check_gitlab_service() {
    log_info "Checking GitLab systemd service status..."
    
    if systemctl is-active gitlab >/dev/null 2>&1; then
        local status=$(systemctl status gitlab --no-pager -l 2>/dev/null | head -3 | tail -1)
        check_result "GitLab systemd service" "PASS" "Service is active: $status"
        return 0
    else
        local status=$(systemctl status gitlab --no-pager -l 2>/dev/null | head -3 | tail -1 || echo "Service not found")
        check_result "GitLab systemd service" "FAIL" "Service not active: $status"
        return 1
    fi
}

# Check GitLab configuration files
check_gitlab_config() {
    log_info "Checking GitLab configuration files..."
    
    local config_files=(
        "/etc/gitlab/gitlab.rb"
        "/var/opt/gitlab/gitlab-rails/etc/gitlab.yml"
    )
    
    local missing_configs=()
    for config in "${config_files[@]}"; do
        if [[ ! -f "$config" ]]; then
            missing_configs+=("$config")
        fi
    done
    
    if [[ ${#missing_configs[@]} -eq 0 ]]; then
        check_result "GitLab configuration files" "PASS" "All configuration files present"
        return 0
    else
        check_result "GitLab configuration files" "FAIL" "Missing: ${missing_configs[*]}"
        return 1
    fi
}

# Check GitLab process health
check_gitlab_processes() {
    log_info "Checking GitLab process health..."
    
    local required_processes=(
        "gitlab-runsvdir"
        "redis-server"
        "postgres"
        "traefik"
    )
    
    local missing_processes=()
    for process in "${required_processes[@]}"; do
        if ! pgrep -f "$process" >/dev/null 2>&1; then
            missing_processes+=("$process")
        fi
    done
    
    if [[ ${#missing_processes[@]} -eq 0 ]]; then
        local process_count=$(pgrep -f gitlab | wc -l)
        check_result "GitLab processes" "PASS" "$process_count GitLab-related processes running"
        return 0
    else
        check_result "GitLab processes" "FAIL" "Missing processes: ${missing_processes[*]}"
        return 1
    fi
}

# Check GitLab database connectivity
check_gitlab_database() {
    log_info "Checking GitLab database connectivity..."
    
    # Check if PostgreSQL is accessible for GitLab
    if sudo -u gitlab-psql psql -d gitlabhq_production -c "SELECT version();" >/dev/null 2>&1; then
        local version=$(sudo -u gitlab-psql psql -d gitlabhq_production -c "SELECT version();" 2>/dev/null | head -3 | tail -1 | cut -c2-50)
        check_result "GitLab database connectivity" "PASS" "Database accessible: $version"
        return 0
    elif sudo -u postgres psql -d gitlabhq_production -c "SELECT version();" >/dev/null 2>&1; then
        local version=$(sudo -u postgres psql -d gitlabhq_production -c "SELECT version();" 2>/dev/null | head -3 | tail -1 | cut -c2-50)
        check_result "GitLab database connectivity" "PASS" "Database accessible: $version"
        return 0
    else
        check_result "GitLab database connectivity" "FAIL" "Cannot connect to GitLab database"
        return 1
    fi
}

# Check GitLab HTTP endpoints
check_gitlab_http() {
    log_info "Checking GitLab HTTP endpoints..."
    
    local endpoints=(
        "/-/health"
        "/-/readiness"
        "/-/liveness"
        "/users/sign_in"
    )
    
    local failed_endpoints=()
    for endpoint in "${endpoints[@]}"; do
        local url="$GITLAB_BASE_URL$endpoint"
        if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$url" >/dev/null 2>&1; then
            log_info "✓ Endpoint accessible: $endpoint"
        else
            failed_endpoints+=("$endpoint")
            log_warn "✗ Endpoint failed: $endpoint"
        fi
    done
    
    if [[ ${#failed_endpoints[@]} -eq 0 ]]; then
        check_result "GitLab HTTP endpoints" "PASS" "All ${#endpoints[@]} endpoints accessible"
        return 0
    else
        check_result "GitLab HTTP endpoints" "FAIL" "Failed endpoints: ${failed_endpoints[*]}"
        return 1
    fi
}

# Check GitLab API functionality
check_gitlab_api() {
    log_info "Checking GitLab API functionality..."
    
    # Test version endpoint
    local api_url="$GITLAB_BASE_URL/api/v4/version"
    if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$api_url" >/dev/null 2>&1; then
        local version_info=$(timeout "$TIMEOUT_SECONDS" curl -s -k "$api_url" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
        check_result "GitLab API functionality" "PASS" "API accessible, version: $version_info"
        return 0
    else
        check_result "GitLab API functionality" "FAIL" "GitLab API not accessible"
        return 1
    fi
}

# Check GitLab Runner integration
check_gitlab_runner() {
    log_info "Checking GitLab Runner integration..."
    
    if systemctl is-active gitlab-runner >/dev/null 2>&1; then
        # Check runner registration status
        local runner_count=0
        if [[ -f "/etc/gitlab-runner/config.toml" ]]; then
            runner_count=$(grep -c "\[\[runners\]\]" /etc/gitlab-runner/config.toml 2>/dev/null || echo "0")
        fi
        
        check_result "GitLab Runner integration" "PASS" "Runner service active with $runner_count registered runners"
        return 0
    else
        check_result "GitLab Runner integration" "FAIL" "GitLab Runner service not active"
        return 1
    fi
}

# Check GitLab storage and permissions
check_gitlab_storage() {
    log_info "Checking GitLab storage and permissions..."
    
    local storage_paths=(
        "/var/opt/gitlab/git-data/repositories"
        "/var/opt/gitlab/gitlab-rails/uploads"
        "/var/opt/gitlab/gitlab-rails/shared"
    )
    
    local issues=()
    for path in "${storage_paths[@]}"; do
        if [[ ! -d "$path" ]]; then
            issues+=("Missing directory: $path")
        elif [[ ! -w "$path" ]]; then
            issues+=("Not writable: $path")
        fi
    done
    
    # Check disk space
    local git_data_usage=$(du -sh /var/opt/gitlab/git-data 2>/dev/null | awk '{print $1}' || echo "unknown")
    local available_space=$(df -h /var/opt/gitlab 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        check_result "GitLab storage and permissions" "PASS" "Git data: $git_data_usage, Available: $available_space"
        return 0
    else
        check_result "GitLab storage and permissions" "FAIL" "${issues[*]}"
        return 1
    fi
}

# Check OIDC configuration (P4 feature)
check_gitlab_oidc() {
    log_info "Checking GitLab OIDC configuration..."
    
    # Check if OIDC is configured in GitLab
    if sudo -u git gitlab-rails runner "puts ApplicationSetting.current.omniauth_enabled" 2>/dev/null | grep -q "true"; then
        local oidc_providers=$(sudo -u git gitlab-rails runner "puts ApplicationSetting.current.omniauth_providers.map(&:name)" 2>/dev/null || echo "[]")
        check_result "GitLab OIDC configuration" "PASS" "OmniAuth enabled with providers: $oidc_providers"
        return 0
    else
        check_result "GitLab OIDC configuration" "WARN" "OmniAuth not explicitly enabled (may be configured differently)"
        return 1
    fi
}

# Main health check execution
main() {
    echo "🦊 GitLab Health Check"
    echo "====================="
    echo ""
    
    local start_time=$(date +%s)
    
    # Execute all health checks
    check_gitlab_service
    check_gitlab_config
    check_gitlab_processes
    check_gitlab_database
    check_gitlab_http
    check_gitlab_api
    check_gitlab_runner
    check_gitlab_storage
    check_gitlab_oidc
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "Health Check Summary"
    echo "===================="
    echo "Total checks: $CHECKS_TOTAL"
    echo "Passed: $CHECKS_PASSED"
    echo "Failed: $CHECKS_FAILED"
    echo "Duration: ${duration}s"
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_success "🎉 All GitLab health checks passed!"
        exit 0
    else
        log_error "❌ $CHECKS_FAILED GitLab health checks failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
