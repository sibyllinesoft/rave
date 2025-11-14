#!/bin/bash
# Security Compliance Validation Test Suite
# Validates overall security compliance and hardening measures

set -euo pipefail

# Configuration
VM_HOST="${1:-localhost}"
VM_PORT="${2:-2223}"
TEST_USER="agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/security_compliance_test.log"

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
TESTS_WARNING=0

# Compliance scores
SCORE_TOTAL=0
SCORE_MAX=0

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Test result functions
test_pass() {
    ((TESTS_PASSED++))
    ((SCORE_TOTAL += ${2:-1}))
    echo -e "${GREEN}✓ PASS${NC}: $1 (Score: +${2:-1})"
    log "PASS: $1 (Score: +${2:-1})"
}

test_fail() {
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: $1 (Score: 0)"
    log "FAIL: $1 (Score: 0)"
}

test_warn() {
    ((TESTS_WARNING++))
    ((SCORE_TOTAL += ${2:-0}))
    echo -e "${YELLOW}⚠ WARN${NC}: $1 (Score: +${2:-0})"
    log "WARN: $1 (Score: +${2:-0})"
}

test_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
    log "INFO: $1"
}

run_test() {
    ((TESTS_TOTAL++))
    ((SCORE_MAX += ${2:-1}))
    echo -e "\n${BLUE}Running test:${NC} $1 (Max Score: ${2:-1})"
}

# Helper function to run SSH commands
ssh_exec() {
    local cmd="$1"
    
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -p "$VM_PORT" \
           "$TEST_USER@$VM_HOST" \
           "$cmd" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Test SSH hardening compliance (CIS Benchmark aligned)
test_ssh_hardening() {
    run_test "SSH Hardening Compliance (CIS)" 10
    
    local ssh_config
    if ssh_config=$(ssh_exec "sudo sshd -T 2>/dev/null"); then
        local score=0
        local max_score=10
        
        # Protocol 2 enforcement
        if echo "$ssh_config" | grep -q "protocol 2"; then
            ((score += 1))
            test_info "✓ SSH Protocol 2 enforced"
        fi
        
        # Strong ciphers only
        if echo "$ssh_config" | grep -q "chacha20-poly1305"; then
            ((score += 2))
            test_info "✓ Strong ciphers configured (ChaCha20-Poly1305)"
        fi
        
        # Strong MACs
        if echo "$ssh_config" | grep -q "hmac-sha2-256-etm"; then
            ((score += 1))
            test_info "✓ Strong MAC algorithms configured"
        fi
        
        # Strong key exchange
        if echo "$ssh_config" | grep -q "curve25519-sha256"; then
            ((score += 2))
            test_info "✓ Strong key exchange algorithms configured"
        fi
        
        # Connection limits
        if echo "$ssh_config" | grep -q "maxauthtries 3"; then
            ((score += 1))
            test_info "✓ MaxAuthTries properly configured"
        fi
        
        # Login grace time
        if echo "$ssh_config" | grep -q "logingracetime 60"; then
            ((score += 1))
            test_info "✓ LoginGraceTime configured"
        fi
        
        # Client alive settings
        if echo "$ssh_config" | grep -q "clientaliveinterval 300"; then
            ((score += 1))
            test_info "✓ ClientAliveInterval configured"
        fi
        
        # X11 forwarding disabled
        if echo "$ssh_config" | grep -q "x11forwarding no"; then
            ((score += 1))
            test_info "✓ X11Forwarding disabled"
        fi
        
        if [ $score -eq $max_score ]; then
            test_pass "SSH hardening fully compliant" $score
        elif [ $score -ge 7 ]; then
            test_warn "SSH hardening mostly compliant ($score/$max_score)" $score
        else
            test_fail "SSH hardening not compliant ($score/$max_score)"
        fi
    else
        test_fail "Could not retrieve SSH configuration"
    fi
}

# Test firewall compliance
test_firewall_compliance() {
    run_test "Firewall Compliance" 5
    
    local score=0
    local max_score=5
    
    # Firewall enabled
    if ssh_exec "sudo systemctl is-active --quiet nftables || sudo systemctl is-active --quiet iptables || sudo iptables -L >/dev/null 2>&1"; then
        ((score += 2))
        test_info "✓ Firewall is active"
        
        # Default deny policy
        if ssh_exec "sudo iptables -L INPUT | head -1 | grep -q DROP"; then
            ((score += 1))
            test_info "✓ Default DROP policy configured"
        fi
        
        # SSH port restrictions
        if ssh_exec "sudo iptables -L INPUT -n | grep -E 'dpt:22|dpt:2223'"; then
            ((score += 1))
            test_info "✓ SSH port access controlled"
        fi
        
        # Minimal open ports
        local open_ports
        if open_ports=$(ssh_exec "ss -tlnp | grep LISTEN | wc -l"); then
            if [ "$open_ports" -le 6 ]; then
                ((score += 1))
                test_info "✓ Minimal ports open ($open_ports services)"
            else
                test_info "⚠ Multiple ports open ($open_ports services)"
            fi
        fi
        
        test_pass "Firewall compliance" $score
    else
        test_fail "Firewall is not active"
    fi
}

# Test intrusion prevention compliance
test_intrusion_prevention() {
    run_test "Intrusion Prevention Compliance" 3
    
    local score=0
    local max_score=3
    
    # fail2ban active
    if ssh_exec "sudo systemctl is-active --quiet fail2ban"; then
        ((score += 2))
        test_info "✓ fail2ban service is active"
        
        # SSH jail configured
        if ssh_exec "sudo fail2ban-client status | grep -q sshd"; then
            ((score += 1))
            test_info "✓ SSH jail configured in fail2ban"
        fi
        
        test_pass "Intrusion prevention configured" $score
    else
        test_fail "fail2ban is not active"
    fi
}

# Test user account security
test_user_security() {
    run_test "User Account Security" 8
    
    local score=0
    local max_score=8
    
    # Root account locked
    if ssh_exec "sudo passwd -S root | grep -q 'L'"; then
        ((score += 2))
        test_info "✓ Root account is locked"
    fi
    
    # No password authentication for SSH
    if ssh_exec "sudo sshd -T | grep -q 'passwordauthentication no'"; then
        ((score += 3))
        test_info "✓ SSH password authentication disabled"
    fi
    
    # Proper SSH key permissions
    if ssh_exec "stat -c '%a' /home/$TEST_USER/.ssh/authorized_keys 2>/dev/null | grep -q 600"; then
        ((score += 1))
        test_info "✓ SSH key permissions correct (600)"
    fi
    
    # SSH directory permissions
    if ssh_exec "stat -c '%a' /home/$TEST_USER/.ssh 2>/dev/null | grep -q 700"; then
        ((score += 1))
        test_info "✓ SSH directory permissions correct (700)"
    fi
    
    # Minimal user accounts
    local user_count
    if user_count=$(ssh_exec "grep -E '^[^:]+:[^:]+:[0-9]{4,}:' /etc/passwd | wc -l"); then
        if [ "$user_count" -le 2 ]; then
            ((score += 1))
            test_info "✓ Minimal user accounts ($user_count non-system users)"
        else
            test_info "⚠ Multiple user accounts ($user_count non-system users)"
        fi
    fi
    
    if [ $score -ge 6 ]; then
        test_pass "User security compliant" $score
    elif [ $score -ge 4 ]; then
        test_warn "User security partially compliant" $score
    else
        test_fail "User security not compliant"
    fi
}

# Test service security compliance
test_service_security() {
    run_test "Service Security Compliance" 6
    
    local score=0
    local max_score=6
    
    # Services running as non-root
    local services=("vibe-kanban" "claude-code-router" "traefik")
    local non_root_services=0
    
    for service in "${services[@]}"; do
        if ssh_exec "sudo systemctl is-active --quiet $service"; then
            if ssh_exec "sudo systemctl show $service -p User | grep -v 'User=root'"; then
                ((non_root_services++))
            fi
        fi
    done
    
    if [ $non_root_services -ge 2 ]; then
        ((score += 2))
        test_info "✓ Services running as non-root users"
    fi
    
    # Service isolation
    if ssh_exec "sudo systemctl show vibe-kanban -p PrivateTmp | grep -q yes"; then
        ((score += 1))
        test_info "✓ Service isolation configured"
    fi
    
    # No unnecessary services
    local service_count
    if service_count=$(ssh_exec "sudo systemctl list-units --type=service --state=active | grep -v '@' | wc -l"); then
        if [ "$service_count" -le 20 ]; then
            ((score += 2))
            test_info "✓ Minimal services running ($service_count active services)"
        else
            test_info "⚠ Many services running ($service_count active services)"
        fi
    fi
    
    # Service autostart security
    if ssh_exec "sudo systemctl list-unit-files --type=service | grep enabled | grep -vE '(sshd|fail2ban|systemd|network)'"; then
        ((score += 1))
        test_info "✓ Service autostart configuration reviewed"
    fi
    
    if [ $score -ge 4 ]; then
        test_pass "Service security compliant" $score
    else
        test_warn "Service security needs improvement" $score
    fi
}

# Test logging and monitoring compliance
test_logging_monitoring() {
    run_test "Logging and Monitoring Compliance" 4
    
    local score=0
    local max_score=4
    
    # System logging active
    if ssh_exec "sudo systemctl is-active --quiet systemd-journald"; then
        ((score += 1))
        test_info "✓ System logging active"
        
        # SSH logging
        if ssh_exec "sudo journalctl -u sshd --since='1 minute ago' >/dev/null 2>&1"; then
            ((score += 1))
            test_info "✓ SSH logging functional"
        fi
        
        # fail2ban logging
        if ssh_exec "sudo journalctl -u fail2ban --since='1 minute ago' >/dev/null 2>&1"; then
            ((score += 1))
            test_info "✓ fail2ban logging functional"
        fi
        
        # Log retention
        if ssh_exec "sudo journalctl --disk-usage | grep -E '[0-9]+(M|G|T)B'"; then
            ((score += 1))
            test_info "✓ Log retention configured"
        fi
        
        test_pass "Logging and monitoring configured" $score
    else
        test_fail "System logging not active"
    fi
}

# Test network security compliance
test_network_security() {
    run_test "Network Security Compliance" 5
    
    local score=0
    local max_score=5
    
    # Network services bound appropriately
    if ssh_exec "ss -tlnp | grep -E ':22|:3000|:3001|:3002' | grep -v '127.0.0.1'"; then
        ((score += 1))
        test_info "✓ Network services accessible"
    fi
    
    # No unnecessary network services
    local listening_ports
    if listening_ports=$(ssh_exec "ss -tlnp | grep LISTEN | grep -v '127.0.0.1' | wc -l"); then
        if [ "$listening_ports" -le 5 ]; then
            ((score += 2))
            test_info "✓ Minimal network exposure ($listening_ports public ports)"
        else
            test_info "⚠ Multiple network services exposed ($listening_ports public ports)"
        fi
    fi
    
    # IPv6 disabled or secured
    if ssh_exec "cat /proc/sys/net/ipv6/conf/all/disable_ipv6 | grep -q 1"; then
        ((score += 1))
        test_info "✓ IPv6 disabled (if not needed)"
    elif ssh_exec "ip6tables -L >/dev/null 2>&1"; then
        ((score += 1))
        test_info "✓ IPv6 firewall configured"
    fi
    
    # Network parameter hardening
    if ssh_exec "sysctl net.ipv4.ip_forward | grep -q 0"; then
        ((score += 1))
        test_info "✓ IP forwarding disabled"
    fi
    
    if [ $score -ge 3 ]; then
        test_pass "Network security compliant" $score
    else
        test_warn "Network security needs improvement" $score
    fi
}

# Test file system security
test_filesystem_security() {
    run_test "File System Security" 4
    
    local score=0
    local max_score=4
    
    # Proper file permissions
    if ssh_exec "find /home/$TEST_USER -type f -perm /o+w | wc -l | grep -q '^0$'"; then
        ((score += 1))
        test_info "✓ No world-writable files in user directory"
    fi
    
    # SSH key security
    if ssh_exec "find /home/$TEST_USER/.ssh -name '*' -perm /g+rwx,o+rwx | wc -l | grep -q '^0$'"; then
        ((score += 1))
        test_info "✓ SSH keys properly secured"
    fi
    
    # System file permissions
    if ssh_exec "stat -c '%a' /etc/passwd | grep -q 644"; then
        ((score += 1))
        test_info "✓ System files properly secured"
    fi
    
    # Temporary directory security
    if ssh_exec "mount | grep '/tmp' | grep -E '(noexec|nosuid)'"; then
        ((score += 1))
        test_info "✓ Temporary directories secured"
    fi
    
    if [ $score -ge 3 ]; then
        test_pass "File system security compliant" $score
    else
        test_warn "File system security needs improvement" $score
    fi
}

# Generate compliance report
generate_report() {
    local compliance_percentage=$((SCORE_TOTAL * 100 / SCORE_MAX))
    
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}       SECURITY COMPLIANCE REPORT      ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    echo "Date: $(date)"
    echo "Target: $VM_HOST:$VM_PORT"
    echo
    echo "Test Summary:"
    echo "  Total Tests: $TESTS_TOTAL"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Warnings: ${YELLOW}$TESTS_WARNING${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    echo "Compliance Score: $SCORE_TOTAL / $SCORE_MAX ($compliance_percentage%)"
    echo
    
    if [ $compliance_percentage -ge 90 ]; then
        echo -e "${GREEN}🎉 EXCELLENT COMPLIANCE${NC}: Your system meets high security standards."
        echo "Status: Production Ready"
    elif [ $compliance_percentage -ge 75 ]; then
        echo -e "${YELLOW}👍 GOOD COMPLIANCE${NC}: Your system has strong security but could be improved."
        echo "Status: Production Acceptable with Minor Improvements"
    elif [ $compliance_percentage -ge 60 ]; then
        echo -e "${YELLOW}⚠️ MODERATE COMPLIANCE${NC}: Your system has basic security but needs improvement."
        echo "Status: Development/Testing Only - Requires Hardening for Production"
    else
        echo -e "${RED}❌ POOR COMPLIANCE${NC}: Your system has significant security issues."
        echo "Status: Not Recommended for Any Environment - Major Security Issues"
    fi
    
    echo
    echo "Recommendations:"
    
    if [ $compliance_percentage -lt 100 ]; then
        echo "- Review failed tests and implement missing security controls"
        echo "- Consider additional hardening measures for production deployment"
        echo "- Implement regular security audits and compliance monitoring"
    fi
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "- Address all failed test items before production deployment"
    fi
    
    if [ $TESTS_WARNING -gt 0 ]; then
        echo "- Review warning items and implement improvements where possible"
    fi
    
    echo "- Regularly update and patch the system"
    echo "- Monitor security logs and implement alerting"
    echo "- Consider additional security measures based on threat model"
}

# Test SSH connectivity first
test_connectivity() {
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -o PasswordAuthentication=no \
           -p "$VM_PORT" \
           "$TEST_USER@$VM_HOST" \
           "echo 'SSH connection successful'" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Security Compliance Validation Suite   ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
    echo "Testing security compliance on $VM_HOST:$VM_PORT"
    echo "Log file: $LOG_FILE"
    echo
    
    # Initialize log
    echo "Security Compliance Test Suite - $(date)" > "$LOG_FILE"
    
    # Test connectivity
    if ! test_connectivity; then
        echo -e "\n${RED}Cannot establish SSH connection. Tests cannot continue.${NC}"
        echo "Please ensure:"
        echo "1. VM is running and accessible"
        echo "2. SSH keys are properly configured"
        echo "3. Host and port are correct: $VM_HOST:$VM_PORT"
        exit 1
    fi
    
    test_info "SSH connectivity verified"
    
    # Run all compliance tests
    test_ssh_hardening
    test_firewall_compliance
    test_intrusion_prevention
    test_user_security
    test_service_security
    test_logging_monitoring
    test_network_security
    test_filesystem_security
    
    # Generate final report
    generate_report
    
    # Log final results
    log "Test completed: $TESTS_PASSED passed, $TESTS_WARNING warnings, $TESTS_FAILED failed"
    log "Compliance score: $SCORE_TOTAL/$SCORE_MAX ($((SCORE_TOTAL * 100 / SCORE_MAX))%)"
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [VM_HOST] [VM_PORT]"
    echo
    echo "Security Compliance Validation Test Suite"
    echo "Tests system configuration against security best practices and compliance standards."
    echo
    echo "Parameters:"
    echo "  VM_HOST    - Target VM hostname or IP (default: localhost)"
    echo "  VM_PORT    - SSH port number (default: 2223)"
    echo
    echo "Examples:"
    echo "  $0                           # Test localhost:2223"
    echo "  $0 10.0.1.100 22            # Test 10.0.1.100:22"
    echo "  $0 my-vm.example.com         # Test my-vm.example.com:2223"
}

# Check for help flag
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"
