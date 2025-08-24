#!/bin/bash
# PostgreSQL Database Health Check Script
# Comprehensive validation of database health for RAVE services

set -euo pipefail

# Configuration
TIMEOUT_SECONDS=30
POSTGRES_VERSION_MIN="12"

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

# Check PostgreSQL service status
check_postgresql_service() {
    log_info "Checking PostgreSQL service status..."
    
    if systemctl is-active postgresql >/dev/null 2>&1; then
        local status=$(systemctl status postgresql --no-pager -l 2>/dev/null | head -3 | tail -1)
        check_result "PostgreSQL systemd service" "PASS" "Service is active: $status"
        return 0
    else
        local status=$(systemctl status postgresql --no-pager -l 2>/dev/null | head -3 | tail -1 || echo "Service not found")
        check_result "PostgreSQL systemd service" "FAIL" "Service not active: $status"
        return 1
    fi
}

# Check PostgreSQL version and configuration
check_postgresql_version() {
    log_info "Checking PostgreSQL version..."
    
    if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
        local version_info=$(sudo -u postgres psql -c "SELECT version();" 2>/dev/null | sed -n '3p' | cut -c 2-80)
        local version_number=$(echo "$version_info" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        
        if [[ $(echo "$version_number >= $POSTGRES_VERSION_MIN" | bc -l 2>/dev/null || echo "0") == "1" ]]; then
            check_result "PostgreSQL version" "PASS" "$version_info"
        else
            check_result "PostgreSQL version" "WARN" "Version $version_number may be outdated (min recommended: $POSTGRES_VERSION_MIN)"
        fi
        return 0
    else
        check_result "PostgreSQL version" "FAIL" "Cannot connect to PostgreSQL to check version"
        return 1
    fi
}

# Check PostgreSQL configuration files
check_postgresql_config() {
    log_info "Checking PostgreSQL configuration files..."
    
    local pg_version=$(sudo -u postgres psql -c "SHOW server_version_num;" 2>/dev/null | sed -n '3p' | xargs 2>/dev/null || echo "0")
    local pg_major_version=$((pg_version / 10000))
    
    local config_dir="/etc/postgresql/${pg_major_version}/main"
    local config_files=(
        "$config_dir/postgresql.conf"
        "$config_dir/pg_hba.conf"
    )
    
    local missing_configs=()
    for config in "${config_files[@]}"; do
        if [[ ! -f "$config" ]]; then
            missing_configs+=("$config")
        fi
    done
    
    if [[ ${#missing_configs[@]} -eq 0 ]]; then
        check_result "PostgreSQL configuration files" "PASS" "All configuration files present for version $pg_major_version"
        return 0
    else
        # Try alternative locations
        local alt_configs=("/var/lib/postgresql/data/postgresql.conf" "/usr/local/pgsql/data/postgresql.conf")
        local found_alt=false
        for alt_config in "${alt_configs[@]}"; do
            if [[ -f "$alt_config" ]]; then
                found_alt=true
                break
            fi
        done
        
        if [[ "$found_alt" == "true" ]]; then
            check_result "PostgreSQL configuration files" "PASS" "Configuration files found in alternative location"
        else
            check_result "PostgreSQL configuration files" "FAIL" "Missing: ${missing_configs[*]}"
        fi
        return 1
    fi
}

# Check PostgreSQL process and memory usage
check_postgresql_processes() {
    log_info "Checking PostgreSQL processes and resource usage..."
    
    local postgres_procs=$(pgrep -f postgres | wc -l)
    if [[ $postgres_procs -gt 0 ]]; then
        local memory_usage=$(ps aux | grep -E 'postgres.*:' | awk '{sum += $6} END {printf "%.1f", sum/1024}' || echo "unknown")
        local cpu_usage=$(ps aux | grep -E 'postgres.*:' | awk '{sum += $3} END {printf "%.1f", sum}' || echo "unknown")
        
        check_result "PostgreSQL processes" "PASS" "$postgres_procs processes, Memory: ${memory_usage}MB, CPU: ${cpu_usage}%"
        return 0
    else
        check_result "PostgreSQL processes" "FAIL" "No PostgreSQL processes found"
        return 1
    fi
}

# Check RAVE databases
check_rave_databases() {
    log_info "Checking RAVE-specific databases..."
    
    local required_databases=(
        "gitlabhq_production"
        "synapse"
        "grafana"
    )
    
    local missing_databases=()
    local database_stats=()
    
    for db in "${required_databases[@]}"; do
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db" 2>/dev/null; then
            # Get database size
            local db_size=$(sudo -u postgres psql -d "$db" -c "SELECT pg_size_pretty(pg_database_size('$db'));" 2>/dev/null | sed -n '3p' | xargs || echo "unknown")
            database_stats+=("$db: $db_size")
        else
            missing_databases+=("$db")
        fi
    done
    
    if [[ ${#missing_databases[@]} -eq 0 ]]; then
        check_result "RAVE databases" "PASS" "${database_stats[*]}"
        return 0
    else
        check_result "RAVE databases" "FAIL" "Missing databases: ${missing_databases[*]}"
        return 1
    fi
}

# Check database connectivity and permissions
check_database_permissions() {
    log_info "Checking database user permissions..."
    
    local database_users=(
        "gitlab"
        "synapse"
        "grafana"
    )
    
    local user_issues=()
    
    for user in "${database_users[@]}"; do
        if sudo -u postgres psql -c "\du" 2>/dev/null | grep -qw "$user"; then
            log_info "✓ Database user exists: $user"
        else
            user_issues+=("Missing user: $user")
        fi
    done
    
    if [[ ${#user_issues[@]} -eq 0 ]]; then
        check_result "Database user permissions" "PASS" "All required users present"
        return 0
    else
        check_result "Database user permissions" "FAIL" "${user_issues[*]}"
        return 1
    fi
}

# Check database performance and health
check_database_performance() {
    log_info "Checking database performance metrics..."
    
    # Check connection count
    local conn_count=$(sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | sed -n '3p' | xargs || echo "0")
    
    # Check longest running query
    local longest_query=$(sudo -u postgres psql -c "SELECT EXTRACT(EPOCH FROM (now() - query_start)) as seconds FROM pg_stat_activity WHERE state = 'active' ORDER BY query_start LIMIT 1;" 2>/dev/null | sed -n '3p' | xargs 2>/dev/null || echo "0")
    longest_query=${longest_query%.*}  # Remove decimal part
    
    # Check database sizes
    local total_db_size=$(sudo -u postgres psql -c "SELECT pg_size_pretty(sum(pg_database_size(datname))) FROM pg_database;" 2>/dev/null | sed -n '3p' | xargs || echo "unknown")
    
    # Check for locks
    local lock_count=$(sudo -u postgres psql -c "SELECT count(*) FROM pg_locks;" 2>/dev/null | sed -n '3p' | xargs || echo "0")
    
    local performance_summary="Connections: $conn_count, Total size: $total_db_size, Locks: $lock_count"
    
    if [[ $conn_count -lt 100 ]] && [[ ${longest_query:-0} -lt 300 ]]; then
        check_result "Database performance" "PASS" "$performance_summary"
        return 0
    else
        check_result "Database performance" "WARN" "$performance_summary (high load detected)"
        return 1
    fi
}

# Check backup and maintenance
check_database_maintenance() {
    log_info "Checking database maintenance configuration..."
    
    # Check for WAL files (Write-Ahead Logging)
    local pg_version=$(sudo -u postgres psql -c "SHOW data_directory;" 2>/dev/null | sed -n '3p' | xargs 2>/dev/null || echo "/var/lib/postgresql/data")
    local wal_files=$(find "$pg_version/pg_wal" -name "00000*" 2>/dev/null | wc -l || echo "0")
    
    # Check last vacuum/analyze operations
    local last_vacuum=$(sudo -u postgres psql -c "SELECT schemaname, tablename, last_vacuum, last_autovacuum FROM pg_stat_user_tables ORDER BY last_vacuum DESC NULLS LAST, last_autovacuum DESC NULLS LAST LIMIT 1;" 2>/dev/null | sed -n '3p' | awk '{print $3, $4}' || echo "unknown")
    
    check_result "Database maintenance" "PASS" "WAL files: $wal_files, Recent vacuum: $last_vacuum"
    return 0
}

# Check disk space and storage
check_database_storage() {
    log_info "Checking database storage and disk space..."
    
    # Get PostgreSQL data directory
    local data_dir=$(sudo -u postgres psql -c "SHOW data_directory;" 2>/dev/null | sed -n '3p' | xargs 2>/dev/null || echo "/var/lib/postgresql")
    
    # Check disk usage
    local disk_usage=$(df -h "$data_dir" 2>/dev/null | tail -1 | awk '{print "Used: " $3 ", Available: " $4 ", Usage: " $5}' || echo "unknown")
    local usage_percent=$(df "$data_dir" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    
    if [[ ${usage_percent:-0} -lt 80 ]]; then
        check_result "Database storage" "PASS" "$disk_usage"
        return 0
    elif [[ ${usage_percent:-0} -lt 90 ]]; then
        check_result "Database storage" "WARN" "$disk_usage (approaching capacity)"
        return 1
    else
        check_result "Database storage" "FAIL" "$disk_usage (critically low space)"
        return 1
    fi
}

# Main health check execution
main() {
    echo "🗄️  PostgreSQL Database Health Check"
    echo "==================================="
    echo ""
    
    local start_time=$(date +%s)
    
    # Execute all health checks
    check_postgresql_service
    check_postgresql_version
    check_postgresql_config
    check_postgresql_processes
    check_rave_databases
    check_database_permissions
    check_database_performance
    check_database_maintenance
    check_database_storage
    
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
        log_success "🎉 All PostgreSQL health checks passed!"
        exit 0
    else
        log_error "❌ $CHECKS_FAILED PostgreSQL health checks failed"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi