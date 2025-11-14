#!/bin/bash
# SSH Security Validation Test Suite
# Tests SSH configuration compliance with security hardening standards

set -euo pipefail

# Configuration
VM_HOST="${1:-localhost}"
VM_PORT="${2:-2223}"
TEST_USER="agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/ssh_security_test.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Test result functions
test_pass() {
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
    log "PASS: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: $1"
    log "FAIL: $1"
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    log "WARN: $1"
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
    log "INFO: $1"
}

run_test() {
    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}Running test:${NC} $1"
}

# Helper function to run SSH commands
ssh_exec() {
    local cmd="$1"
    local expected_exit="${2:-0}"
    
    # Try SSH connection with strict host key checking disabled for testing
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -p "$VM_PORT" \
           "$TEST_USER@$VM_HOST" \
           "$cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Test SSH connectivity (requires key-based auth to be working)
test_ssh_connectivity() {
    run_test "SSH Connectivity"
    
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -o PasswordAuthentication=no \
           -p "$VM_PORT" \
           "$TEST_USER@$VM_HOST" \
           "echo 'SSH connection successful'" >/dev/null 2>&1; then
        test_pass "SSH key-based authentication working"
    else
        test_fail "SSH key-based authentication not working"
        test_info "Ensure SSH keys are properly configured before running tests"
        return 1
    fi
}

# Test SSH password authentication is disabled
test_password_auth_disabled() {
    run_test "SSH Password Authentication Disabled"
    
    # Attempt password authentication (should fail)
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 \
           -o PasswordAuthentication=yes \
           -o PubkeyAuthentication=no \
           -o PreferredAuthentications=password \
           -p "$VM_PORT" \
           "$TEST_USER@$VM_HOST" \
           "echo 'password auth succeeded'" >/dev/null 2>&1; then
        test_fail "Password authentication is enabled (should be disabled)"
    else
        test_pass "Password authentication is properly disabled"
    fi
}

# Test SSH root login is disabled
test_root_login_disabled() {
    run_test "SSH Root Login Disabled"
    
    # Try to connect as root (should fail regardless of authentication method)
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 \
           -p "$VM_PORT" \
           "root@$VM_HOST" \
           "echo 'root login succeeded'" >/dev/null 2>&1; then
        test_fail "Root login is enabled (should be disabled)"
    else
        test_pass "Root login is properly disabled"
    fi
}

# Test SSH configuration parameters
test_ssh_configuration() {
    run_test "SSH Configuration Parameters"
    
    # Get SSH configuration from server
    local ssh_config
    if ssh_config=$(ssh -o StrictHostKeyChecking=no \
                        -o UserKnownHostsFile=/dev/null \
                        -p "$VM_PORT" \
                        "$TEST_USER@$VM_HOST" \
                        "sudo sshd -T 2>/dev/null"); then
        
        # Test MaxAuthTries
        if echo "$ssh_config" | grep -q "maxauthtries 3"; then
            test_pass "MaxAuthTries is set to 3"
        else
            test_fail "MaxAuthTries is not set to 3"
        fi
        
        # Test PermitRootLogin
        if echo "$ssh_config" | grep -q "permitrootlogin no"; then
            test_pass "PermitRootLogin is disabled"
        else
            test_fail "PermitRootLogin is not disabled"
        fi
        
        # Test PasswordAuthentication
        if echo "$ssh_config" | grep -q "passwordauthentication no"; then
            test_pass "PasswordAuthentication is disabled"
        else
            test_fail "PasswordAuthentication is not disabled"
        fi
        
        # Test PubkeyAuthentication
        if echo "$ssh_config" | grep -q "pubkeyauthentication yes"; then
            test_pass "PubkeyAuthentication is enabled"
        else
            test_fail "PubkeyAuthentication is not enabled"
        fi
        
        # Test X11Forwarding
        if echo "$ssh_config" | grep -q "x11forwarding no"; then
            test_pass "X11Forwarding is disabled"
        else
            test_warn "X11Forwarding is not disabled (potential security risk)"
        fi
        
        # Test Protocol version
        if echo "$ssh_config" | grep -q "protocol 2"; then
            test_pass "SSH Protocol 2 is enforced"
        else
            test_warn "SSH Protocol 2 may not be enforced"
        fi
        
    else
        test_fail "Could not retrieve SSH configuration"
    fi
}

# Test firewall status
test_firewall_status() {
    run_test "Firewall Status"
    
    if ssh_exec "sudo systemctl is-active --quiet nftables || sudo systemctl is-active --quiet iptables"; then
        test_pass "Firewall service is active"
        
        # Check if SSH port is allowed
        if ssh_exec "sudo iptables -L INPUT -n | grep -E ':22|:2223' || sudo nft list ruleset | grep -E ':22|:2223'"; then
            test_pass "SSH port is allowed through firewall"
        else
            test_warn "SSH port may not be explicitly allowed in firewall rules"
        fi
        
    else
        test_fail "Firewall service is not active"
    fi
}

# Test fail2ban status
test_fail2ban_status() {
    run_test "fail2ban Status"
    
    if ssh_exec "sudo systemctl is-active --quiet fail2ban"; then
        test_pass "fail2ban service is active"
        
        # Check SSH jail status
        if ssh_exec "sudo fail2ban-client status sshd"; then
            test_pass "SSH jail is configured in fail2ban"
        else
            test_warn "SSH jail may not be configured in fail2ban"
        fi
        
    else
        test_fail "fail2ban service is not active"
    fi
}

# Test SSH key setup
test_ssh_key_setup() {
    run_test "SSH Key Setup"
    
    # Check if authorized_keys file exists and has correct permissions
    if ssh_exec "test -f /home/$TEST_USER/.ssh/authorized_keys"; then
        test_pass "SSH authorized_keys file exists"
        
        # Check permissions
        if ssh_exec "stat -c '%a' /home/$TEST_USER/.ssh/authorized_keys | grep -q 600"; then
            test_pass "authorized_keys has correct permissions (600)"
        else
            test_fail "authorized_keys does not have correct permissions (should be 600)"
        fi
        
        # Check ownership
        if ssh_exec "stat -c '%U:%G' /home/$TEST_USER/.ssh/authorized_keys | grep -q '$TEST_USER:users'"; then
            test_pass "authorized_keys has correct ownership"
        else
            test_fail "authorized_keys does not have correct ownership"
        fi
        
    else
        test_fail "SSH authorized_keys file does not exist"
    fi
    
    # Check SSH directory permissions
    if ssh_exec "stat -c '%a' /home/$TEST_USER/.ssh | grep -q 700"; then
        test_pass "SSH directory has correct permissions (700)"
    else
        test_fail "SSH directory does not have correct permissions (should be 700)"
    fi
}

# Test service security
test_service_security() {
    run_test "Service Security Configuration"
    
    # Check if services are running as non-root user
    local services=("vibe-kanban" "claude-code-router" "traefik")
    
    for service in "${services[@]}"; do
        if ssh_exec "sudo systemctl is-active --quiet $service"; then
            # Check service user
            if ssh_exec "sudo systemctl show $service -p User | grep -v root"; then
                test_pass "$service is not running as root"
            else
                test_warn "$service may be running as root"
            fi
        else
            test_info "$service is not active (may be expected)"
        fi
    done
    
    # Check for any services running as root that shouldn't be
    if ssh_exec "sudo ps aux | grep -E '(vibe-kanban|claude-code-router)' | grep -v root"; then
        test_pass "AI services are not running as root"
    else
        test_warn "Some AI services may be running as root"
    fi
}

# Test network security
test_network_security() {
    run_test "Network Security"
    
    # Check open ports
    local expected_ports=(22 3000 3001 3002)
    
    if ssh_exec "command -v ss >/dev/null"; then
        for port in "${expected_ports[@]}"; do
            if ssh_exec "ss -tlnp | grep :$port"; then
                test_pass "Port $port is listening as expected"
            else
                test_warn "Port $port is not listening (service may be down)"
            fi
        done
        
        # Check for unexpected listening ports
        if ssh_exec "ss -tlnp | grep -vE ':(22|3000|3001|3002|53)' | grep LISTEN"; then
            test_warn "Unexpected ports may be listening"
        else
            test_pass "No unexpected ports are listening"
        fi
        
    else
        test_info "ss command not available, skipping port checks"
    fi
}

# Test system security basics
test_system_security() {
    run_test "System Security Basics"
    
    # Check if automatic security updates are enabled
    if ssh_exec "sudo systemctl is-enabled --quiet nixos-upgrade || test -f /etc/infra/nixos/configuration.nix"; then
        test_pass "System uses NixOS declarative configuration"
    else
        test_warn "System configuration management unclear"
    fi
    
    # Check system users
    if ssh_exec "grep -E '^(root|agent):' /etc/passwd | wc -l | grep -q '^2$'"; then
        test_pass "Only expected system users (root, agent) are present"
    else
        test_warn "Additional system users detected (may be expected)"
    fi
    
    # Check sudo configuration
    if ssh_exec "sudo -n true"; then
        test_warn "Passwordless sudo is enabled (security risk in production)"
    else
        test_info "Passwordless sudo test failed (may require password)"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  SSH Security Validation Test Suite   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo "Testing SSH security configuration on $VM_HOST:$VM_PORT"
    echo "Log file: $LOG_FILE"
    echo
    
    # Initialize log
    echo "SSH Security Test Suite - $(date)" > "$LOG_FILE"
    
    # Run all tests
    test_ssh_connectivity || {
        echo -e "\n${RED}Cannot establish SSH connection. Tests cannot continue.${NC}"
        echo "Please ensure:"
        echo "1. VM is running and accessible"
        echo "2. SSH keys are properly configured"
        echo "3. Host and port are correct: $VM_HOST:$VM_PORT"
        exit 1
    }
    
    test_password_auth_disabled
    test_root_login_disabled
    test_ssh_configuration
    test_firewall_status
    test_fail2ban_status
    test_ssh_key_setup
    test_service_security
    test_network_security
    test_system_security
    
    # Summary
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}           TEST SUMMARY                 ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! SSH security configuration looks good.${NC}"
        log "All tests passed successfully"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please review the security configuration.${NC}"
        log "$TESTS_FAILED tests failed"
        exit 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [VM_HOST] [VM_PORT]"
    echo
    echo "Parameters:"
    echo "  VM_HOST    - Target VM hostname or IP (default: localhost)"
    echo "  VM_PORT    - SSH port number (default: 2223)"
    echo
    echo "Examples:"
    echo "  $0                           # Test localhost:2223"
    echo "  $0 10.0.1.100 22            # Test 10.0.1.100:22"
    echo "  $0 my-vm.example.com         # Test my-vm.example.com:2223"
    echo
    echo "Prerequisites:"
    echo "  - SSH key-based authentication must be working"
    echo "  - Target VM must be running and accessible"
    echo "  - Agent user must have sudo privileges"
}

# Check for help flag
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"
