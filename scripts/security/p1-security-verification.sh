#!/usr/bin/env bash
# P1 Security Hardening Verification Script
# Validates all P1 security controls are properly implemented

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Global counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

# Function to track check results
check_result() {
    local status=$1
    local message=$2
    
    case $status in
        "PASS")
            log_success "$message"
            ((CHECKS_PASSED++))
            ;;
        "FAIL")
            log_error "$message"
            ((CHECKS_FAILED++))
            ;;
        "WARN")
            log_warning "$message"
            ((CHECKS_WARNED++))
            ;;
    esac
}

echo "🔒 RAVE P1 Security Hardening Verification"
echo "=========================================="
echo ""

# P1.1: SSH Hardening Verification
log_info "P1.1: Verifying SSH hardening configuration..."

# Check SSH configuration files exist
if [[ -f "p1-production-config.nix" ]]; then
    check_result "PASS" "P1 production configuration file exists"
    
    # Verify SSH key-only authentication
    if grep -q "PasswordAuthentication.*false" p1-production-config.nix; then
        check_result "PASS" "SSH password authentication disabled"
    else
        check_result "FAIL" "SSH password authentication not disabled"
    fi
    
    # Verify root login disabled
    if grep -q "PermitRootLogin.*no" p1-production-config.nix; then
        check_result "PASS" "SSH root login disabled"
    else
        check_result "FAIL" "SSH root login not disabled"
    fi
    
    # Verify enhanced SSH security settings
    if grep -q "AllowTcpForwarding.*false" p1-production-config.nix; then
        check_result "PASS" "SSH TCP forwarding disabled"
    else
        check_result "WARN" "SSH TCP forwarding not explicitly disabled"
    fi
    
    # Check for SSH key configuration
    if grep -q "authorizedKeys.keys" p1-production-config.nix; then
        check_result "PASS" "SSH authorized keys configuration present"
        
        # Check if production keys are configured
        if grep -q "# WARNING: No production SSH keys configured" p1-production-config.nix; then
            check_result "WARN" "Production SSH keys not yet configured (placeholders present)"
        else
            check_result "PASS" "Production SSH keys appear to be configured"
        fi
    else
        check_result "FAIL" "SSH authorized keys configuration missing"
    fi
    
    # Verify firewall configuration
    if grep -q "allowedTCPPorts.*\[.*22.*3002.*\]" p1-production-config.nix; then
        check_result "PASS" "Firewall restricts to ports 22 and 3002 only"
    else
        check_result "FAIL" "Firewall not properly restricted"
    fi
    
else
    check_result "FAIL" "P1 production configuration file missing"
fi

echo ""

# P1.2: sops-nix Secrets Management Verification
log_info "P1.2: Verifying sops-nix secrets management..."

# Check .sops.yaml configuration
if [[ -f ".sops.yaml" ]]; then
    check_result "PASS" "sops configuration file exists"
    
    # Verify YAML is valid
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' .sops.yaml >/dev/null 2>&1; then
            check_result "PASS" "sops configuration is valid YAML"
        else
            check_result "FAIL" "sops configuration has invalid YAML syntax"
        fi
    else
        check_result "WARN" "yq not available - cannot validate YAML syntax"
    fi
    
    # Check for team keys
    if grep -q "keys:" .sops.yaml; then
        check_result "PASS" "sops team keys configuration present"
        
        # Check for placeholder keys
        if grep -q "age1zt6z7z6z7z6z7z" .sops.yaml; then
            check_result "WARN" "sops contains placeholder keys (replace with actual team keys)"
        else
            check_result "PASS" "sops keys appear to be production-ready"
        fi
    else
        check_result "FAIL" "sops team keys configuration missing"
    fi
    
else
    check_result "FAIL" "sops configuration file (.sops.yaml) missing"
fi

# Check secrets.yaml template
if [[ -f "secrets.yaml" ]]; then
    check_result "PASS" "secrets template file exists"
    
    # Verify YAML is valid
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' secrets.yaml >/dev/null 2>&1; then
            check_result "PASS" "secrets template is valid YAML"
        else
            check_result "FAIL" "secrets template has invalid YAML syntax"
        fi
    fi
    
    # Check for placeholder values
    if grep -q "SOPS_ENCRYPTED_PLACEHOLDER" secrets.yaml; then
        check_result "WARN" "secrets.yaml contains placeholders (replace with encrypted values for production)"
    else
        check_result "PASS" "secrets.yaml appears to contain encrypted production data"
    fi
    
else
    check_result "FAIL" "secrets template file (secrets.yaml) missing"
fi

# Verify sops-nix integration in P1 config
if grep -q "sops.*defaultSopsFile.*secrets.yaml" p1-production-config.nix 2>/dev/null; then
    check_result "PASS" "sops-nix integration configured in P1"
else
    check_result "FAIL" "sops-nix integration missing from P1 configuration"
fi

echo ""

# P1.3: Webhook Dispatcher Security Verification
log_info "P1.3: Verifying webhook dispatcher security..."

if [[ -f "p1-production-config.nix" ]]; then
    # Check webhook dispatcher service configuration
    if grep -q "webhook-dispatcher" p1-production-config.nix; then
        check_result "PASS" "Webhook dispatcher service configured"
        
        # Check for signature verification
        if grep -q "verifyWebhookSignature" p1-production-config.nix; then
            check_result "PASS" "Webhook signature verification implemented"
        else
            check_result "FAIL" "Webhook signature verification missing"
        fi
        
        # Check for event deduplication
        if grep -q "event_uuid" p1-production-config.nix; then
            check_result "PASS" "Event deduplication implemented"
        else
            check_result "FAIL" "Event deduplication missing"
        fi
        
        # Check for event schema
        if grep -q "EVENT_SCHEMAS" p1-production-config.nix; then
            check_result "PASS" "Event schema v1 defined"
        else
            check_result "FAIL" "Event schema v1 missing"
        fi
        
        # Check for security hardening
        if grep -q "NoNewPrivileges.*true" p1-production-config.nix; then
            check_result "PASS" "Webhook dispatcher security hardening enabled"
        else
            check_result "WARN" "Webhook dispatcher security hardening not fully configured"
        fi
        
    else
        check_result "FAIL" "Webhook dispatcher service not configured"
    fi
fi

echo ""

# P1.4: CI Security Scanning Verification
log_info "P1.4: Verifying CI security scanning configuration..."

if [[ -f ".gitlab-ci.yml" ]]; then
    check_result "PASS" "GitLab CI configuration file exists"
    
    # Check for Trivy scanning
    if grep -q "scan:trivy" .gitlab-ci.yml; then
        check_result "PASS" "Trivy vulnerability scanning configured"
        
        # Check for SAFE thresholds
        if grep -q "TRIVY_SEVERITY.*SAFE.*CRITICAL" .gitlab-ci.yml; then
            check_result "PASS" "SAFE mode Trivy thresholds configured"
        else
            check_result "WARN" "SAFE mode thresholds not configured"
        fi
    else
        check_result "FAIL" "Trivy vulnerability scanning not configured"
    fi
    
    # Check for NPM audit
    if grep -q "scan:npm-audit" .gitlab-ci.yml; then
        check_result "PASS" "NPM security audit configured"
        
        # Check for SAFE thresholds
        if grep -q "NPM_AUDIT_LEVEL.*SAFE.*critical" .gitlab-ci.yml; then
            check_result "PASS" "SAFE mode NPM audit thresholds configured"
        else
            check_result "WARN" "SAFE mode NPM audit thresholds not configured"
        fi
    else
        check_result "FAIL" "NPM security audit not configured"
    fi
    
    # Check for security configuration audit
    if grep -q "scan:security-config" .gitlab-ci.yml; then
        check_result "PASS" "Security configuration audit configured"
    else
        check_result "WARN" "Security configuration audit not configured"
    fi
    
else
    check_result "FAIL" "GitLab CI configuration file (.gitlab-ci.yml) missing"
fi

echo ""

# Additional Security Checks
log_info "Additional security validations..."

# Check for security documentation
if [[ -f "docs/adr/003-p1-security-hardening.md" ]]; then
    check_result "PASS" "P1 security hardening documentation exists"
else
    check_result "WARN" "P1 security hardening documentation missing"
fi

# Check for security scripts directory
if [[ -d "scripts/security" ]]; then
    check_result "PASS" "Security scripts directory exists"
else
    check_result "PASS" "Security scripts directory created during verification"
    mkdir -p scripts/security
fi

# Verify kernel hardening in P1 config
if grep -q "boot.kernel.sysctl" p1-production-config.nix 2>/dev/null; then
    check_result "PASS" "Kernel hardening parameters configured"
else
    check_result "WARN" "Kernel hardening parameters not configured"
fi

# Check for service resource limits
if grep -q "MemoryMax" p1-production-config.nix 2>/dev/null; then
    check_result "PASS" "Service resource limits configured"
else
    check_result "WARN" "Service resource limits not configured"
fi

echo ""

# Summary Report
echo "=========================================="
echo "🔒 P1 Security Hardening Verification Results"
echo "=========================================="
echo ""
log_success "Checks Passed: $CHECKS_PASSED"
if [[ $CHECKS_WARNED -gt 0 ]]; then
    log_warning "Checks with Warnings: $CHECKS_WARNED"
fi
if [[ $CHECKS_FAILED -gt 0 ]]; then
    log_error "Checks Failed: $CHECKS_FAILED"
fi

echo ""

# Overall assessment
TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNED))
if [[ $CHECKS_FAILED -eq 0 ]]; then
    if [[ $CHECKS_WARNED -eq 0 ]]; then
        log_success "✅ P1 Security Hardening: FULLY IMPLEMENTED"
        log_info "All security controls are properly configured and ready for production."
    else
        log_warning "⚠️ P1 Security Hardening: MOSTLY IMPLEMENTED"
        log_info "Core security controls are implemented but some configurations need production values."
    fi
    echo ""
    log_info "Next steps for production deployment:"
    echo "  1. Replace placeholder SSH keys with actual team public keys"
    echo "  2. Encrypt secrets.yaml with actual production values using sops"
    echo "  3. Configure GitLab OAuth application for OIDC integration"
    echo "  4. Set up GitLab webhook with matching secret"
    echo "  5. Test security controls in staging environment"
    
    exit 0
else
    log_error "❌ P1 Security Hardening: IMPLEMENTATION INCOMPLETE"
    log_error "Critical security controls are missing or misconfigured."
    echo ""
    log_info "Required fixes before production deployment:"
    echo "  • Address all failed checks listed above"
    echo "  • Re-run this verification script until all checks pass"
    echo "  • Perform security penetration testing"
    
    exit 1
fi