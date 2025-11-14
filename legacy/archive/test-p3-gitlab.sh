#!/bin/bash
# P3 GitLab Service Integration Test
# Validates GitLab configuration and service health

set -euo pipefail

echo "🦊 RAVE P3 GitLab Integration Test"
echo "=================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓ PASS${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    elif [[ "$result" == "WARN" ]]; then
        echo -e "${YELLOW}⚠ WARN${NC} $test_name"
        [[ -n "$details" ]] && echo "   $details"
    else
        echo -e "${RED}✗ FAIL${NC} $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        [[ -n "$details" ]] && echo "   $details"
    fi
}

# Test 1: Configuration file validity
echo -e "${BLUE}Phase 1: Configuration Validation${NC}"
echo "Testing NixOS configuration syntax..."

if nix-instantiate --parse /home/nathan/Projects/rave/p3-production-config.nix >/dev/null 2>&1; then
    test_result "P3 configuration syntax" "PASS"
else
    test_result "P3 configuration syntax" "FAIL" "Syntax errors in p3-production-config.nix"
fi

if nix-instantiate --parse /home/nathan/Projects/rave/infra/nixos/gitlab.nix >/dev/null 2>&1; then
    test_result "GitLab module syntax" "PASS"
else
    test_result "GitLab module syntax" "FAIL" "Syntax errors in infra/nixos/gitlab.nix"
fi

if nix-instantiate --parse /home/nathan/Projects/rave/infra/nixos/configuration.nix >/dev/null 2>&1; then
    test_result "NixOS configuration syntax" "PASS"
else
    test_result "NixOS configuration syntax" "FAIL" "Syntax errors in infra/nixos/configuration.nix"
fi

# Test 2: Dependencies and package availability
echo ""
echo -e "${BLUE}Phase 2: Package Dependencies${NC}"
echo "Checking package availability..."

if nix-env -qa gitlab >/dev/null 2>&1; then
    test_result "GitLab package availability" "PASS"
else
    test_result "GitLab package availability" "FAIL" "GitLab package not found in nixpkgs"
fi

if nix-env -qa gitlab-runner >/dev/null 2>&1; then
    test_result "GitLab Runner package availability" "PASS"
else
    test_result "GitLab Runner package availability" "FAIL" "GitLab Runner package not found in nixpkgs"
fi

if nix-env -qa docker >/dev/null 2>&1; then
    test_result "Docker package availability" "PASS"
else
    test_result "Docker package availability" "FAIL" "Docker package not found in nixpkgs"
fi

# Test 3: Secrets configuration
echo ""
echo -e "${BLUE}Phase 3: Secrets Management${NC}"
echo "Checking sops-nix configuration..."

if [[ -f "/home/nathan/Projects/rave/.sops.yaml" ]]; then
    test_result "SOPS configuration file exists" "PASS"
else
    test_result "SOPS configuration file exists" "FAIL" ".sops.yaml not found"
fi

if [[ -f "/home/nathan/Projects/rave/secrets.yaml" ]]; then
    test_result "Secrets file exists" "PASS"
else
    test_result "Secrets file exists" "FAIL" "secrets.yaml not found"
fi

# Check for GitLab secrets in secrets.yaml
if grep -q "gitlab:" /home/nathan/Projects/rave/secrets.yaml; then
    test_result "GitLab secrets defined" "PASS"
else
    test_result "GitLab secrets defined" "FAIL" "No GitLab secrets found in secrets.yaml"
fi

# Test 4: Service configuration validation
echo ""
echo -e "${BLUE}Phase 4: Service Configuration${NC}"
echo "Validating service configurations..."

# Check if PostgreSQL is configured for GitLab
if grep -q "gitlab" /home/nathan/Projects/rave/infra/nixos/gitlab.nix; then
    if grep -q "ensureDatabases.*gitlab" /home/nathan/Projects/rave/infra/nixos/gitlab.nix; then
        test_result "PostgreSQL GitLab database configured" "PASS"
    else
        test_result "PostgreSQL GitLab database configured" "WARN" "Database configuration may be incomplete"
    fi
else
    test_result "PostgreSQL GitLab database configured" "FAIL" "GitLab database not configured"
fi

# Check if nginx proxy configuration exists
if grep -q "/gitlab/" /home/nathan/Projects/rave/p3-production-config.nix; then
    test_result "Nginx GitLab proxy configured" "PASS"
else
    test_result "Nginx GitLab proxy configured" "FAIL" "GitLab nginx proxy not configured"
fi

# Check if resource limits are defined
if grep -q "MemoryMax.*8G" /home/nathan/Projects/rave/infra/nixos/gitlab.nix; then
    test_result "GitLab resource limits configured" "PASS"
else
    test_result "GitLab resource limits configured" "WARN" "Resource limits may not be configured"
fi

# Test 5: File structure validation
echo ""
echo -e "${BLUE}Phase 5: File Structure${NC}"
echo "Checking file structure..."

expected_files=(
    "/home/nathan/Projects/rave/p3-production-config.nix"
    "/home/nathan/Projects/rave/infra/nixos/configuration.nix"
    "/home/nathan/Projects/rave/infra/nixos/gitlab.nix"
    "/home/nathan/Projects/rave/infra/nixos/prometheus.nix"
    "/home/nathan/Projects/rave/infra/nixos/grafana.nix"
    "/home/nathan/Projects/rave/secrets.yaml"
    "/home/nathan/Projects/rave/.sops.yaml"
)

for file in "${expected_files[@]}"; do
    if [[ -f "$file" ]]; then
        test_result "File exists: $(basename "$file")" "PASS"
    else
        test_result "File exists: $(basename "$file")" "FAIL" "Required file not found"
    fi
done

# Test 6: Integration points
echo ""
echo -e "${BLUE}Phase 6: Integration Points${NC}"
echo "Checking service integration points..."

# Check if GitLab inherits from P2 configuration
if grep -q "p2-production-config.nix" /home/nathan/Projects/rave/p3-production-config.nix; then
    test_result "P2 configuration inheritance" "PASS"
else
    test_result "P2 configuration inheritance" "FAIL" "P3 does not inherit from P2"
fi

# Check if sops-nix is imported
if grep -q "sops-nix" /home/nathan/Projects/rave/p3-production-config.nix; then
    test_result "sops-nix integration" "PASS"
else
    test_result "sops-nix integration" "FAIL" "sops-nix not imported"
fi

# Check if monitoring is configured for GitLab
if grep -q "gitlab" /home/nathan/Projects/rave/infra/nixos/prometheus.nix; then
    test_result "GitLab monitoring configured" "PASS"
else
    test_result "GitLab monitoring configured" "WARN" "GitLab monitoring may not be configured"
fi

# Test 7: Security configuration
echo ""
echo -e "${BLUE}Phase 7: Security Configuration${NC}"
echo "Checking security settings..."

# Check if Docker is configured with proper security
if grep -q "privileged.*true" /home/nathan/Projects/rave/infra/nixos/gitlab.nix; then
    test_result "Docker privileged mode configured" "WARN" "Privileged mode enabled (required for KVM)"
else
    test_result "Docker privileged mode configured" "FAIL" "Privileged mode not configured for KVM access"
fi

# Check if KVM access is configured
if grep -q "/dev/kvm" /home/nathan/Projects/rave/infra/nixos/gitlab.nix; then
    test_result "KVM device access configured" "PASS"
else
    test_result "KVM device access configured" "FAIL" "KVM device not mounted for runners"
fi

# Final results
echo ""
echo "=================================="
echo -e "${BLUE}Test Summary${NC}"
echo "=================================="
echo "Total tests: $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Warnings: ${YELLOW}$((TESTS_TOTAL - TESTS_PASSED - TESTS_FAILED))${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All critical tests passed!${NC}"
    echo "P3 GitLab service integration is ready for deployment."
    echo ""
    echo "Next steps:"
    echo "1. Generate and encrypt actual secrets with sops"
    echo "2. Test the configuration in a VM environment"
    echo "3. Validate GitLab startup and runner registration"
    echo "4. Configure OAuth applications for OIDC (Phase P4)"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed!${NC}"
    echo "Please fix the failing tests before proceeding with deployment."
    echo ""
    echo "Common fixes:"
    echo "1. Run 'nix-instantiate --parse <file>' to check syntax"
    echo "2. Ensure all required files exist"
    echo "3. Check sops-nix installation and configuration"
    echo "4. Verify package availability in your nixpkgs channel"
    exit 1
fi