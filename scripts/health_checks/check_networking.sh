#!/bin/bash
# Network Connectivity Health Check Script
# Comprehensive validation of network configuration and connectivity

set -euo pipefail

# Configuration
TIMEOUT_SECONDS=10
EXTERNAL_TEST_HOSTS=("8.8.8.8" "1.1.1.1")
INTERNAL_SERVICES=(
    "localhost:22"      # SSH
    "localhost:3002"    # HTTPS Traefik
    "localhost:5432"    # PostgreSQL
    "localhost:3030"    # Grafana
    "localhost:9090"    # Prometheus
    "localhost:8065"    # Mattermost
)

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

# Check network interfaces
check_network_interfaces() {
    log_info "Checking network interfaces..."
    
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ')
    local active_interfaces=()
    local interface_details=()
    
    while IFS= read -r interface; do
        if ip link show "$interface" | grep -q "state UP"; then
            active_interfaces+=("$interface")
            local ip_addr=$(ip addr show "$interface" | grep -E 'inet [0-9]' | awk '{print $2}' | head -1 || echo "no-ip")
            interface_details+=("$interface: $ip_addr")
        fi
    done <<< "$interfaces"
    
    if [[ ${#active_interfaces[@]} -gt 0 ]]; then
        check_result "Network interfaces" "PASS" "${#active_interfaces[@]} active: ${interface_details[*]}"
        return 0
    else
        check_result "Network interfaces" "FAIL" "No active network interfaces found"
        return 1
    fi
}

# Check DNS resolution
check_dns_resolution() {
    log_info "Checking DNS resolution..."
    
    local test_hosts=("localhost" "rave.local" "google.com")
    local failed_resolutions=()
    
    for host in "${test_hosts[@]}"; do
        if timeout "$TIMEOUT_SECONDS" nslookup "$host" >/dev/null 2>&1; then
            log_info "✓ DNS resolution successful: $host"
        else
            failed_resolutions+=("$host")
            log_warn "✗ DNS resolution failed: $host"
        fi
    done
    
    if [[ ${#failed_resolutions[@]} -eq 0 ]]; then
        check_result "DNS resolution" "PASS" "All test domains resolve successfully"
        return 0
    elif [[ ${#failed_resolutions[@]} -le 1 ]]; then
        check_result "DNS resolution" "PASS" "Most domains resolve (${#failed_resolutions[@]} failed)"
        return 0
    else
        check_result "DNS resolution" "FAIL" "Failed to resolve: ${failed_resolutions[*]}"
        return 1
    fi
}

# Check internal service connectivity
check_internal_services() {
    log_info "Checking internal service connectivity..."
    
    local failed_services=()
    local successful_services=()
    
    for service in "${INTERNAL_SERVICES[@]}"; do
        local host=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)
        
        if timeout "$TIMEOUT_SECONDS" nc -z "$host" "$port" 2>/dev/null; then
            successful_services+=("$service")
            log_info "✓ Service connectivity: $service"
        else
            failed_services+=("$service")
            log_warn "✗ Service connectivity failed: $service"
        fi
    done
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        check_result "Internal service connectivity" "PASS" "All ${#INTERNAL_SERVICES[@]} services accessible"
        return 0
    elif [[ ${#successful_services[@]} -ge $((${#INTERNAL_SERVICES[@]} / 2)) ]]; then
        check_result "Internal service connectivity" "PASS" "${#successful_services[@]}/${#INTERNAL_SERVICES[@]} services accessible"
        return 0
    else
        check_result "Internal service connectivity" "FAIL" "Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Check external connectivity
check_external_connectivity() {
    log_info "Checking external connectivity..."
    
    local failed_hosts=()
    local ping_results=()
    
    for host in "${EXTERNAL_TEST_HOSTS[@]}"; do
        if timeout "$TIMEOUT_SECONDS" ping -c 1 "$host" >/dev/null 2>&1; then
            local ping_time=$(timeout "$TIMEOUT_SECONDS" ping -c 1 "$host" 2>/dev/null | grep 'time=' | sed -E 's/.*time=([0-9.]+).*/\1/' || echo "unknown")
            ping_results+=("$host: ${ping_time}ms")
            log_info "✓ External connectivity: $host (${ping_time}ms)"
        else
            failed_hosts+=("$host")
            log_warn "✗ External connectivity failed: $host"
        fi
    done
    
    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        check_result "External connectivity" "PASS" "Ping times: ${ping_results[*]}"
        return 0
    elif [[ ${#failed_hosts[@]} -lt ${#EXTERNAL_TEST_HOSTS[@]} ]]; then
        check_result "External connectivity" "PASS" "Some external hosts reachable"
        return 0
    else
        check_result "External connectivity" "FAIL" "No external connectivity"
        return 1
    fi
}

# Check HTTPS/TLS connectivity
check_https_connectivity() {
    log_info "Checking HTTPS/TLS connectivity..."
    
    local https_endpoints=(
        "https://localhost:3002/"
        "https://localhost:3002/grafana/"
        "https://localhost:3002/gitlab/"
        "https://localhost:3002/element/"
    )
    
    local failed_endpoints=()
    local successful_endpoints=()
    
    for endpoint in "${https_endpoints[@]}"; do
        if timeout "$TIMEOUT_SECONDS" curl -k -f -s "$endpoint" >/dev/null 2>&1; then
            successful_endpoints+=("$endpoint")
            log_info "✓ HTTPS endpoint accessible: $endpoint"
        else
            failed_endpoints+=("$endpoint")
            log_warn "✗ HTTPS endpoint failed: $endpoint"
        fi
    done
    
    if [[ ${#failed_endpoints[@]} -eq 0 ]]; then
        check_result "HTTPS connectivity" "PASS" "All ${#https_endpoints[@]} endpoints accessible"
        return 0
    elif [[ ${#successful_endpoints[@]} -ge $((${#https_endpoints[@]} / 2)) ]]; then
        check_result "HTTPS connectivity" "PASS" "${#successful_endpoints[@]}/${#https_endpoints[@]} endpoints accessible"
        return 0
    else
        check_result "HTTPS connectivity" "FAIL" "Failed endpoints: ${failed_endpoints[*]}"
        return 1
    fi
}

# Check firewall configuration
check_firewall_configuration() {
    log_info "Checking firewall configuration..."
    
    # Check if firewall service is active
    local firewall_active=false
    local firewall_service=""
    
    if systemctl is-active ufw >/dev/null 2>&1; then
        firewall_active=true
        firewall_service="ufw"
    elif systemctl is-active iptables >/dev/null 2>&1; then
        firewall_active=true
        firewall_service="iptables"
    elif command -v iptables >/dev/null 2>&1; then
        # Check if iptables has rules
        local rule_count=$(iptables -L | wc -l 2>/dev/null || echo "0")
        if [[ $rule_count -gt 10 ]]; then
            firewall_active=true
            firewall_service="iptables (manual rules)"
        fi
    fi
    
    if [[ "$firewall_active" == "true" ]]; then
        # Check for allowed ports
        local allowed_ports=()
        if [[ "$firewall_service" == "ufw" ]]; then
            allowed_ports=($(ufw status numbered 2>/dev/null | grep -oE '[0-9]+/(tcp|udp)' | cut -d/ -f1 | sort -u || echo ""))
        elif command -v iptables >/dev/null 2>&1; then
            allowed_ports=($(iptables -L INPUT -n 2>/dev/null | grep -oE 'dpt:[0-9]+' | cut -d: -f2 | sort -u || echo ""))
        fi
        
        # Check for required ports (22, 3002)
        local required_ports=("22" "3002")
        local missing_ports=()
        
        for port in "${required_ports[@]}"; do
            if ! printf '%s\n' "${allowed_ports[@]}" | grep -qx "$port" 2>/dev/null; then
                missing_ports+=("$port")
            fi
        done
        
        if [[ ${#missing_ports[@]} -eq 0 ]]; then
            check_result "Firewall configuration" "PASS" "Active ($firewall_service), required ports allowed"
        else
            check_result "Firewall configuration" "WARN" "Active but missing ports: ${missing_ports[*]}"
        fi
        return 0
    else
        check_result "Firewall configuration" "WARN" "No active firewall detected (security risk)"
        return 1
    fi
}

# Check routing table
check_routing_table() {
    log_info "Checking routing table..."
    
    # Check default route
    if ip route | grep -q "default"; then
        local default_route=$(ip route | grep "default" | head -1)
        local gateway=$(echo "$default_route" | awk '{print $3}')
        local interface=$(echo "$default_route" | awk '{print $5}')
        
        check_result "Default route" "PASS" "Gateway: $gateway via $interface"
        
        # Test gateway reachability
        if timeout 5 ping -c 1 "$gateway" >/dev/null 2>&1; then
            check_result "Gateway reachability" "PASS" "Gateway $gateway is reachable"
        else
            check_result "Gateway reachability" "WARN" "Gateway $gateway not responding to ping"
        fi
        
        return 0
    else
        check_result "Default route" "FAIL" "No default route configured"
        return 1
    fi
}

# Check network performance
check_network_performance() {
    log_info "Checking network performance..."
    
    # Test localhost loopback performance
    local loopback_time=""
    if command -v curl >/dev/null 2>&1; then
        loopback_time=$(timeout 10 curl -w "%{time_total}" -s -o /dev/null "http://localhost" 2>/dev/null || echo "timeout")
    fi
    
    # Check network interface statistics
    local rx_errors=$(cat /sys/class/net/*/statistics/rx_errors 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    local tx_errors=$(cat /sys/class/net/*/statistics/tx_errors 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    
    # Check network load
    local network_load=$(cat /proc/net/dev | awk 'NR>2 {rx+=$2; tx+=$10} END {printf "RX: %.1fMB, TX: %.1fMB", rx/1024/1024, tx/1024/1024}')
    
    if [[ ${rx_errors:-0} -eq 0 ]] && [[ ${tx_errors:-0} -eq 0 ]]; then
        check_result "Network performance" "PASS" "$network_load, No errors"
        return 0
    else
        check_result "Network performance" "WARN" "$network_load, RX errors: $rx_errors, TX errors: $tx_errors"
        return 1
    fi
}

# Check sandbox networking (P6 feature)
check_sandbox_networking() {
    log_info "Checking sandbox networking configuration..."
    
    # Check for sandbox port ranges (2200-2299 for SSH, 3000-3099 for web)
    local sandbox_ssh_range="2200-2299"
    local sandbox_web_range="3000-3099"
    
    # Check if ports in sandbox ranges are available
    local used_sandbox_ports=()
    for port in {2200..2210} {3000..3010}; do  # Sample from ranges
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            used_sandbox_ports+=("$port")
        fi
    done
    
    # Check for bridge interfaces (used for VM networking)
    local bridge_interfaces=$(ip link show type bridge 2>/dev/null | grep -c "^[0-9]" || echo "0")
    
    # Check for TAP interfaces (used for VM networking)
    local tap_interfaces=$(ip link show | grep -c "tap" || echo "0")
    
    local sandbox_summary="Bridge interfaces: $bridge_interfaces, TAP interfaces: $tap_interfaces, Used sandbox ports: ${#used_sandbox_ports[@]}"
    
    if [[ $bridge_interfaces -gt 0 ]] || [[ $tap_interfaces -gt 0 ]]; then
        check_result "Sandbox networking" "PASS" "$sandbox_summary"
        return 0
    else
        check_result "Sandbox networking" "PASS" "Ready for sandbox VMs: $sandbox_summary"
        return 0
    fi
}

# Main health check execution
main() {
    echo "🌐 Network Connectivity Health Check"
    echo "==================================="
    echo ""
    
    local start_time=$(date +%s)
    
    # Execute all health checks
    check_network_interfaces
    check_dns_resolution
    check_internal_services
    check_external_connectivity
    check_https_connectivity
    check_firewall_configuration
    check_routing_table
    check_network_performance
    check_sandbox_networking
    
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
        log_success "🎉 All network health checks passed!"
        exit 0
    else
        log_error "❌ $CHECKS_FAILED network health checks failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
