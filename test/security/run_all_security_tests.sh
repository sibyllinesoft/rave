#!/bin/bash
# Master Security Test Runner
# Executes all security validation tests and generates comprehensive report

set -euo pipefail

# Configuration
VM_HOST="${1:-localhost}"
VM_PORT="${2:-2223}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="${REPORT_DIR}/security_report_${TIMESTAMP}.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create reports directory
mkdir -p "$REPORT_DIR"

# Test results
declare -A test_results
declare -A test_outputs

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$REPORT_FILE"
}

run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local description="$3"
    
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Running: $test_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    local output_file="${REPORT_DIR}/${test_name}_${TIMESTAMP}.log"
    
    if bash "$test_script" "$VM_HOST" "$VM_PORT" > "$output_file" 2>&1; then
        test_results["$test_name"]="PASS"
        echo -e "${GREEN}✓ $test_name PASSED${NC}"
    else
        test_results["$test_name"]="FAIL"
        echo -e "${RED}✗ $test_name FAILED${NC}"
    fi
    
    test_outputs["$test_name"]="$output_file"
    
    # Add results to main report
    {
        echo
        echo "## $test_name - $description"
        echo
        echo "**Status:** ${test_results["$test_name"]}"
        echo
        echo "**Output:**"
        echo '```'
        tail -n 20 "$output_file"
        echo '```'
        echo
        echo "**Full Log:** [${test_name}_${TIMESTAMP}.log](${test_name}_${TIMESTAMP}.log)"
        echo
    } >> "$REPORT_FILE"
}

generate_summary_report() {
    local total_tests=${#test_results[@]}
    local passed_tests=0
    local failed_tests=0
    
    for result in "${test_results[@]}"; do
        if [ "$result" = "PASS" ]; then
            ((passed_tests++))
        else
            ((failed_tests++))
        fi
    done
    
    # Create comprehensive markdown report
    cat > "$REPORT_FILE" << EOF
# AI Agent Sandbox VM - Security Validation Report

**Generated:** $(date)  
**Target:** $VM_HOST:$VM_PORT  
**Test Suite Version:** 1.0  

## Executive Summary

This report provides a comprehensive security assessment of the AI Agent Sandbox VM configuration.

### Test Results Overview

- **Total Test Suites:** $total_tests
- **Passed:** $passed_tests
- **Failed:** $failed_tests
- **Success Rate:** $((passed_tests * 100 / total_tests))%

### Security Status

EOF

    if [ $failed_tests -eq 0 ]; then
        cat >> "$REPORT_FILE" << EOF
🎉 **EXCELLENT**: All security tests passed. The system demonstrates strong security controls and is ready for production deployment with proper operational procedures.

**Recommendation:** APPROVED for production deployment.
EOF
    elif [ $passed_tests -gt $failed_tests ]; then
        cat >> "$REPORT_FILE" << EOF
⚠️ **GOOD**: Most security tests passed, but some issues were identified. Review failed tests and implement fixes before production deployment.

**Recommendation:** CONDITIONAL APPROVAL - Fix identified issues.
EOF
    else
        cat >> "$REPORT_FILE" << EOF
❌ **POOR**: Significant security issues identified. Do not deploy to production until all issues are resolved.

**Recommendation:** REJECTED for production - Major security remediation required.
EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Test Suite Results

EOF
    
    # Add individual test results (will be appended by run_test_suite)
    
    # Add recommendations section
    cat >> "$REPORT_FILE" << EOF

## Security Recommendations

### Immediate Actions Required

EOF
    
    if [ $failed_tests -gt 0 ]; then
        cat >> "$REPORT_FILE" << EOF
1. **Review Failed Tests**: Address all failing security controls before production deployment
2. **Implement Missing Controls**: Deploy any missing security measures identified in the tests
3. **Validate Fixes**: Re-run security tests after implementing fixes
EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF

### Best Practices for Production

1. **Regular Security Audits**: Run these tests monthly or after any configuration changes
2. **Automated Monitoring**: Implement security monitoring and alerting for key metrics
3. **Incident Response**: Establish incident response procedures and emergency contacts
4. **Key Rotation**: Implement regular SSH key rotation procedures
5. **Backup Security**: Ensure backups are encrypted and securely stored
6. **Network Segmentation**: Consider network segmentation for production deployments
7. **Vulnerability Management**: Implement regular vulnerability scanning and patching
8. **Documentation**: Keep security documentation current and accessible

### Additional Security Measures

1. **Multi-Factor Authentication**: Consider implementing MFA for enhanced security
2. **Centralized Logging**: Implement centralized log collection and analysis
3. **File Integrity Monitoring**: Deploy file integrity monitoring for critical files
4. **Intrusion Detection**: Consider network-based intrusion detection systems
5. **Security Training**: Ensure operators receive security awareness training

## Compliance Alignment

This security assessment aligns with the following standards and frameworks:

- **CIS Benchmarks**: SSH hardening, firewall configuration, and service security
- **NIST Cybersecurity Framework**: Identify, Protect, Detect, Respond, Recover controls
- **OWASP Security Guidelines**: Secure configuration and authentication controls

## Test Environment Details

- **Target System:** $VM_HOST:$VM_PORT
- **Test Date:** $(date)
- **Test Duration:** N/A
- **Tester:** Automated Security Test Suite
- **Test Framework Version:** 1.0

## Contact Information

For questions about this security assessment or to report security issues:

- **Security Team:** security@organization.com
- **Operations Team:** ops@organization.com
- **Documentation:** [Security Model Documentation](../docs/security/SECURITY_MODEL.md)

---

**Classification:** Internal Use  
**Retention:** 1 Year  
**Distribution:** Security Team, Operations Team, Project Stakeholders
EOF
}

main() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    AI Agent Sandbox Security Validation   ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
    echo "Target: $VM_HOST:$VM_PORT"
    echo "Report: $REPORT_FILE"
    echo
    
    # Initialize report with header
    generate_summary_report
    
    # Run all security test suites
    run_test_suite "ssh_security" \
                  "${SCRIPT_DIR}/ssh_security_test.sh" \
                  "SSH Service Security Configuration"
    
    run_test_suite "security_compliance" \
                  "${SCRIPT_DIR}/security_compliance_test.sh" \
                  "Overall Security Compliance Assessment"
    
    # Generate final summary
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}           FINAL RESULTS                ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    local total_tests=${#test_results[@]}
    local passed_tests=0
    local failed_tests=0
    
    echo
    echo "Test Suite Results:"
    for test_name in "${!test_results[@]}"; do
        if [ "${test_results[$test_name]}" = "PASS" ]; then
            echo -e "  ${GREEN}✓${NC} $test_name"
            ((passed_tests++))
        else
            echo -e "  ${RED}✗${NC} $test_name"
            ((failed_tests++))
        fi
    done
    
    echo
    echo "Summary: $passed_tests/$total_tests tests passed"
    echo "Comprehensive report: $REPORT_FILE"
    
    if [ $failed_tests -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All security tests passed! System is ready for production deployment.${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some security tests failed. Review the report and address issues before production.${NC}"
        exit 1
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [VM_HOST] [VM_PORT]"
    echo
    echo "Master Security Test Runner"
    echo "Executes all security validation tests and generates a comprehensive report."
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
    echo "Output:"
    echo "  - Individual test logs in test/security/reports/"
    echo "  - Comprehensive markdown report with recommendations"
    echo "  - Exit code 0 if all tests pass, 1 if any fail"
}

# Check for help flag
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    usage
    exit 0
fi

# Verify test scripts exist
if [ ! -f "${SCRIPT_DIR}/ssh_security_test.sh" ]; then
    echo "Error: ssh_security_test.sh not found"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/security_compliance_test.sh" ]; then
    echo "Error: security_compliance_test.sh not found"
    exit 1
fi

# Run main function
main "$@"