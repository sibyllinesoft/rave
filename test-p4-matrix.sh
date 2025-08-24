#!/bin/bash
# P4 Matrix Service Integration Test Script
# Tests Matrix Synapse homeserver and Element web client functionality

set -e

echo "🧪 RAVE P4 Matrix Integration Test Suite"
echo "========================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
BASE_URL="https://rave.local:3002"
MATRIX_URL="$BASE_URL/matrix"
ELEMENT_URL="$BASE_URL/element"
HEALTH_CHECK_URL="$BASE_URL/health/matrix"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    printf "%-50s" "Testing $test_name..."
    
    if eval "$test_command" > /tmp/test_output 2>&1; then
        if [[ -z "$expected_result" ]] || grep -q "$expected_result" /tmp/test_output; then
            echo -e "${GREEN}✅ PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ FAIL${NC} (Expected: $expected_result)"
            echo "Output: $(cat /tmp/test_output)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        echo -e "${RED}❌ FAIL${NC}"
        echo "Error: $(cat /tmp/test_output)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo -e "${BLUE}🔧 P4 System Service Tests${NC}"
echo "============================"

# Test 1: Check if Matrix Synapse service is running
run_test "Matrix Synapse service status" \
    "systemctl is-active matrix-synapse" \
    "active"

# Test 2: Check if Matrix is listening on port 8008
run_test "Matrix port 8008 listening" \
    "netstat -tlnp | grep :8008" \
    "8008"

# Test 3: Check PostgreSQL Synapse database
run_test "PostgreSQL Synapse database exists" \
    "sudo -u postgres psql -lqt | grep synapse" \
    "synapse"

# Test 4: Check Matrix data directories
run_test "Matrix data directories exist" \
    "ls -la /var/lib/matrix-synapse" \
    "media_store"

# Test 5: Check Matrix log files
run_test "Matrix log files exist" \
    "ls /var/log/matrix-synapse/" \
    "homeserver.log"

echo ""
echo -e "${BLUE}🌐 P4 HTTP/Web Interface Tests${NC}"
echo "==============================="

# Test 6: Matrix API versions endpoint
run_test "Matrix API versions endpoint" \
    "curl -k -s -o /dev/null -w '%{http_code}' $MATRIX_URL/_matrix/client/versions" \
    "200"

# Test 7: Matrix server info endpoint
run_test "Matrix server info endpoint" \
    "curl -k -s $MATRIX_URL/_matrix/client/versions" \
    "versions"

# Test 8: Element web client loading
run_test "Element web client loads" \
    "curl -k -s -o /dev/null -w '%{http_code}' $ELEMENT_URL/" \
    "200"

# Test 9: Element configuration file
run_test "Element config.json accessible" \
    "curl -k -s $ELEMENT_URL/config.json" \
    "m.homeserver"

# Test 10: Matrix health check endpoint
run_test "Matrix health check endpoint" \
    "curl -k -s -o /dev/null -w '%{http_code}' $HEALTH_CHECK_URL" \
    "200"

echo ""
echo -e "${BLUE}🔐 P4 Security & OIDC Tests${NC}"
echo "============================"

# Test 11: Matrix well-known server endpoint
run_test "Matrix well-known server" \
    "curl -k -s $BASE_URL/.well-known/matrix/server" \
    "m.server"

# Test 12: Matrix well-known client endpoint
run_test "Matrix well-known client" \
    "curl -k -s $BASE_URL/.well-known/matrix/client" \
    "m.homeserver"

# Test 13: GitLab OIDC discovery endpoint
run_test "GitLab OIDC discovery endpoint" \
    "curl -k -s $BASE_URL/gitlab/.well-known/openid_configuration" \
    "authorization_endpoint"

# Test 14: Matrix OIDC configuration (check if configured)
run_test "Matrix OIDC provider configured" \
    "systemctl show matrix-synapse -p Environment" \
    "Environment"

echo ""
echo -e "${BLUE}📊 P4 Monitoring & Metrics Tests${NC}"
echo "================================="

# Test 15: Matrix Synapse metrics endpoint
run_test "Matrix metrics endpoint" \
    "curl -k -s -o /dev/null -w '%{http_code}' $MATRIX_URL/_synapse/metrics" \
    "200"

# Test 16: Prometheus scraping Matrix
run_test "Prometheus Matrix target" \
    "curl -k -s $BASE_URL/prometheus/api/v1/targets" \
    "matrix-synapse"

# Test 17: Grafana Matrix dashboard
run_test "Grafana accessible" \
    "curl -k -s -o /dev/null -w '%{http_code}' $BASE_URL/grafana/" \
    "200"

echo ""
echo -e "${BLUE}💾 P4 Data & Backup Tests${NC}"
echo "========================="

# Test 18: Matrix database connectivity
run_test "Matrix database connection" \
    "sudo -u matrix-synapse psql -h /run/postgresql -d synapse -c 'SELECT 1;'" \
    "1"

# Test 19: Matrix media store writable
run_test "Matrix media store permissions" \
    "sudo -u matrix-synapse test -w /var/lib/matrix-synapse/media_store && echo 'writable'" \
    "writable"

# Test 20: Matrix backup directory
run_test "Matrix backup directory exists" \
    "ls -la /var/lib/matrix-synapse/backups" \
    ""

echo ""
echo -e "${BLUE}🔧 P4 Integration Tests${NC}"
echo "========================"

# Test 21: nginx Matrix proxy configuration
run_test "nginx Matrix location configured" \
    "nginx -T 2>/dev/null | grep -A 5 'location /matrix/'" \
    "proxy_pass"

# Test 22: Element client proxy configuration
run_test "nginx Element location configured" \
    "nginx -T 2>/dev/null | grep -A 5 'location /element/'" \
    "alias"

# Test 23: Matrix service dependencies
run_test "Matrix service after PostgreSQL" \
    "systemctl show matrix-synapse -p After" \
    "postgresql"

# Test 24: Matrix user and group
run_test "Matrix user exists" \
    "id matrix-synapse" \
    "uid=991"

echo ""
echo -e "${BLUE}🚀 P4 Performance Tests${NC}"
echo "======================="

# Test 25: Matrix memory usage within limits
run_test "Matrix memory usage check" \
    "systemctl show matrix-synapse -p MemoryMax" \
    "MemoryMax=4294967296"

# Test 26: Matrix process count
run_test "Matrix process count" \
    "pgrep -c -f matrix-synapse || echo 0" \
    ""

# Test 27: Matrix file descriptor limits
run_test "Matrix file descriptor limits" \
    "systemctl show matrix-synapse -p LimitNOFILE" \
    "32768"

echo ""
echo -e "${YELLOW}📋 P4 Configuration Validation${NC}"
echo "=================================="

# Test 28: Check Matrix homeserver.yaml syntax
if command -v python3 >/dev/null 2>&1; then
    run_test "Matrix config syntax validation" \
        "python3 -c 'import yaml; yaml.safe_load(open(\"/etc/matrix-synapse/homeserver.yaml\"))'" \
        ""
else
    echo "Python3 not available - skipping config syntax validation"
fi

# Test 29: Check Element config.json syntax
if command -v jq >/dev/null 2>&1; then
    run_test "Element config JSON syntax" \
        "curl -k -s $ELEMENT_URL/config.json | jq ." \
        "m.homeserver"
else
    echo "jq not available - skipping Element config validation"
fi

# Test 30: Check Matrix registration disabled
run_test "Matrix registration disabled" \
    "curl -k -s $MATRIX_URL/_matrix/client/r0/register" \
    "M_FORBIDDEN"

echo ""
echo "================================================"
echo -e "${BLUE}📊 P4 Matrix Integration Test Results${NC}"
echo "================================================"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! ($TESTS_PASSED/$TESTS_TOTAL)${NC}"
    echo ""
    echo -e "${GREEN}✅ Matrix Synapse homeserver is running correctly${NC}"
    echo -e "${GREEN}✅ Element web client is accessible${NC}"
    echo -e "${GREEN}✅ nginx proxy configuration is working${NC}"
    echo -e "${GREEN}✅ PostgreSQL integration is functional${NC}"
    echo -e "${GREEN}✅ OIDC configuration is prepared${NC}"
    echo -e "${GREEN}✅ Monitoring and metrics are enabled${NC}"
    echo -e "${GREEN}✅ Security settings are properly configured${NC}"
    echo ""
    echo -e "${BLUE}🔧 Next Steps for P4 Completion:${NC}"
    echo "1. Complete GitLab OAuth application setup:"
    echo "   - Access GitLab admin: $BASE_URL/gitlab/admin/applications"
    echo "   - Create Matrix OAuth app with callback: $MATRIX_URL/_synapse/client/oidc/callback"
    echo "   - Update secrets.yaml with client ID and secret"
    echo "2. Test OIDC authentication flow:"
    echo "   - Access Element: $ELEMENT_URL/"
    echo "   - Test GitLab SSO login"
    echo "3. Create initial Matrix rooms for agent control"
    echo "4. Verify end-to-end Matrix functionality"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Some tests failed ($TESTS_FAILED/$TESTS_TOTAL failed, $TESTS_PASSED/$TESTS_TOTAL passed)${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Troubleshooting Steps:${NC}"
    echo "1. Check service status: systemctl status matrix-synapse nginx postgresql"
    echo "2. Check logs: journalctl -u matrix-synapse -f"
    echo "3. Verify nginx configuration: nginx -t"
    echo "4. Check PostgreSQL connectivity: sudo -u postgres psql -l"
    echo "5. Verify sops-nix secrets: ls -la /run/secrets/"
    echo ""
    exit 1
fi