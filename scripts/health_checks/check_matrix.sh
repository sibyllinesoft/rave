#!/bin/bash
# Matrix Synapse Health Check Script
# Comprehensive validation of Matrix homeserver and bridge functionality

set -euo pipefail

# Configuration
MATRIX_BASE_URL="https://localhost:3002/matrix"
ELEMENT_BASE_URL="https://localhost:3002/element"
BRIDGE_CONFIG_PATH="/home/nathan/Projects/rave/services/matrix-bridge"
TIMEOUT_SECONDS=30

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

# Check Matrix Synapse service
check_matrix_service() {
    log_info "Checking Matrix Synapse service status..."
    
    if systemctl is-active matrix-synapse >/dev/null 2>&1; then
        local status=$(systemctl status matrix-synapse --no-pager -l 2>/dev/null | head -3 | tail -1)
        check_result "Matrix Synapse service" "PASS" "Service is active: $status"
        return 0
    else
        local status=$(systemctl status matrix-synapse --no-pager -l 2>/dev/null | head -3 | tail -1 || echo "Service not found")
        check_result "Matrix Synapse service" "FAIL" "Service not active: $status"
        return 1
    fi
}

# Check Matrix configuration files
check_matrix_config() {
    log_info "Checking Matrix configuration files..."
    
    local config_files=(
        "/etc/matrix-synapse/homeserver.yaml"
        "/etc/matrix-synapse/log.yaml"
    )
    
    local missing_configs=()
    for config in "${config_files[@]}"; do
        if [[ ! -f "$config" ]]; then
            missing_configs+=("$config")
        fi
    done
    
    if [[ ${#missing_configs[@]} -eq 0 ]]; then
        check_result "Matrix configuration files" "PASS" "All configuration files present"
        
        # Check for OIDC configuration
        if grep -q "oidc_providers" /etc/matrix-synapse/homeserver.yaml 2>/dev/null; then
            log_info "   └─ OIDC providers configured"
        fi
        
        return 0
    else
        check_result "Matrix configuration files" "FAIL" "Missing: ${missing_configs[*]}"
        return 1
    fi
}

# Check Matrix database connectivity
check_matrix_database() {
    log_info "Checking Matrix database connectivity..."
    
    # Check if Matrix database exists and is accessible
    if sudo -u postgres psql -d synapse -c "SELECT COUNT(*) FROM users;" >/dev/null 2>&1; then
        local user_count=$(sudo -u postgres psql -d synapse -c "SELECT COUNT(*) FROM users;" 2>/dev/null | sed -n '3p' | xargs)
        check_result "Matrix database connectivity" "PASS" "Database accessible with $user_count users"
        return 0
    elif sudo -u matrix-synapse psql -d synapse -c "SELECT COUNT(*) FROM users;" >/dev/null 2>&1; then
        local user_count=$(sudo -u matrix-synapse psql -d synapse -c "SELECT COUNT(*) FROM users;" 2>/dev/null | sed -n '3p' | xargs)
        check_result "Matrix database connectivity" "PASS" "Database accessible with $user_count users"
        return 0
    else
        check_result "Matrix database connectivity" "FAIL" "Cannot connect to Matrix database"
        return 1
    fi
}

# Check Matrix HTTP endpoints
check_matrix_http() {
    log_info "Checking Matrix HTTP endpoints..."
    
    local endpoints=(
        "/_matrix/client/versions"
        "/_matrix/federation/v1/version"
        "/_synapse/health"
        "/_matrix/client/r0/login"
    )
    
    local failed_endpoints=()
    for endpoint in "${endpoints[@]}"; do
        local url="$MATRIX_BASE_URL$endpoint"
        if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$url" >/dev/null 2>&1; then
            log_info "✓ Endpoint accessible: $endpoint"
        else
            failed_endpoints+=("$endpoint")
            log_warn "✗ Endpoint failed: $endpoint"
        fi
    done
    
    if [[ ${#failed_endpoints[@]} -eq 0 ]]; then
        check_result "Matrix HTTP endpoints" "PASS" "All ${#endpoints[@]} endpoints accessible"
        return 0
    elif [[ ${#failed_endpoints[@]} -le 1 ]]; then
        check_result "Matrix HTTP endpoints" "PASS" "Most endpoints accessible (${#failed_endpoints[@]} failed)"
        return 0
    else
        check_result "Matrix HTTP endpoints" "FAIL" "Failed endpoints: ${failed_endpoints[*]}"
        return 1
    fi
}

# Check Matrix client API
check_matrix_client_api() {
    log_info "Checking Matrix client API functionality..."
    
    # Test client versions endpoint
    local versions_url="$MATRIX_BASE_URL/_matrix/client/versions"
    if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$versions_url" >/dev/null 2>&1; then
        local versions_info=$(timeout "$TIMEOUT_SECONDS" curl -s -k "$versions_url" 2>/dev/null | jq -r '.versions[0] // "unknown"' 2>/dev/null || echo "unknown")
        check_result "Matrix client API" "PASS" "Client API accessible, latest version: $versions_info"
        return 0
    else
        check_result "Matrix client API" "FAIL" "Matrix client API not accessible"
        return 1
    fi
}

# Check Element web client
check_element_client() {
    log_info "Checking Element web client..."
    
    # Test Element web interface
    local element_url="$ELEMENT_BASE_URL/"
    if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$element_url" >/dev/null 2>&1; then
        # Check if it's actually serving Element content
        local content=$(timeout "$TIMEOUT_SECONDS" curl -s -k "$element_url" 2>/dev/null)
        if echo "$content" | grep -qi "element\|riot\|matrix"; then
            check_result "Element web client" "PASS" "Element web interface accessible"
        else
            check_result "Element web client" "FAIL" "Element endpoint accessible but not serving Matrix client"
        fi
        return 0
    else
        check_result "Element web client" "FAIL" "Element web interface not accessible"
        return 1
    fi
}

# Check Matrix bridge configuration
check_matrix_bridge() {
    log_info "Checking Matrix bridge configuration..."
    
    if [[ -d "$BRIDGE_CONFIG_PATH" ]]; then
        local bridge_files=(
            "$BRIDGE_CONFIG_PATH/src/main.py"
            "$BRIDGE_CONFIG_PATH/bridge_config.yaml"
            "$BRIDGE_CONFIG_PATH/registration.yaml"
        )
        
        local missing_files=()
        for file in "${bridge_files[@]}"; do
            if [[ ! -f "$file" ]]; then
                missing_files+=("$(basename "$file")")
            fi
        done
        
        if [[ ${#missing_files[@]} -eq 0 ]]; then
            check_result "Matrix bridge configuration" "PASS" "All bridge files present"
            
            # Check if bridge is running
            if pgrep -f "matrix.*bridge\|bridge.*matrix" >/dev/null 2>&1; then
                log_info "   └─ Bridge process detected running"
            else
                log_warn "   └─ Bridge process not detected (may be managed differently)"
            fi
            
            return 0
        else
            check_result "Matrix bridge configuration" "FAIL" "Missing bridge files: ${missing_files[*]}"
            return 1
        fi
    else
        check_result "Matrix bridge configuration" "FAIL" "Bridge directory not found: $BRIDGE_CONFIG_PATH"
        return 1
    fi
}

# Check Matrix federation status
check_matrix_federation() {
    log_info "Checking Matrix federation status..."
    
    # Federation should be disabled for security in RAVE setup
    local federation_url="$MATRIX_BASE_URL/_matrix/federation/v1/version"
    if timeout "$TIMEOUT_SECONDS" curl -f -s -k "$federation_url" >/dev/null 2>&1; then
        log_warn "Federation endpoint accessible (should be disabled for security)"
        check_result "Matrix federation security" "WARN" "Federation may be enabled (security concern)"
        return 1
    else
        check_result "Matrix federation security" "PASS" "Federation properly disabled"
        return 0
    fi
}

# Check Matrix media repository
check_matrix_media() {
    log_info "Checking Matrix media repository..."
    
    local media_path="/var/lib/matrix-synapse/media"
    if [[ -d "$media_path" ]]; then
        local media_size=$(du -sh "$media_path" 2>/dev/null | awk '{print $1}' || echo "unknown")
        local available_space=$(df -h "$media_path" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        check_result "Matrix media repository" "PASS" "Media store: $media_size, Available: $available_space"
        return 0
    else
        check_result "Matrix media repository" "FAIL" "Media repository directory not found"
        return 1
    fi
}

# Check Matrix OIDC integration
check_matrix_oidc() {
    log_info "Checking Matrix OIDC integration..."
    
    # Check homeserver.yaml for OIDC configuration
    if [[ -f "/etc/matrix-synapse/homeserver.yaml" ]]; then
        if grep -q "oidc_providers:" /etc/matrix-synapse/homeserver.yaml; then
            local provider_count=$(grep -A 20 "oidc_providers:" /etc/matrix-synapse/homeserver.yaml | grep -c "idp_id:" || echo "0")
            if [[ "$provider_count" -gt 0 ]]; then
                check_result "Matrix OIDC integration" "PASS" "$provider_count OIDC provider(s) configured"
            else
                check_result "Matrix OIDC integration" "WARN" "OIDC section present but no providers configured"
            fi
        else
            check_result "Matrix OIDC integration" "WARN" "OIDC not configured in homeserver.yaml"
        fi
    else
        check_result "Matrix OIDC integration" "FAIL" "Homeserver configuration not accessible"
    fi
}

# Main health check execution
main() {
    echo "💬 Matrix Health Check"
    echo "====================="
    echo ""
    
    local start_time=$(date +%s)
    
    # Execute all health checks
    check_matrix_service
    check_matrix_config
    check_matrix_database
    check_matrix_http
    check_matrix_client_api
    check_element_client
    check_matrix_bridge
    check_matrix_federation
    check_matrix_media
    check_matrix_oidc
    
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
        log_success "🎉 All Matrix health checks passed!"
        exit 0
    else
        log_error "❌ $CHECKS_FAILED Matrix health checks failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi