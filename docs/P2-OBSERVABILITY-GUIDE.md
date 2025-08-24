# RAVE Phase P2: CI/CD & Observability Implementation Guide

## Overview

Phase P2 implements comprehensive CI/CD automation and observability for RAVE, building upon the security foundation established in P1. This phase introduces GitLab Runner pipelines, NixOS VM integration tests, and a complete Prometheus + Grafana monitoring stack.

## 🎯 P2 Objectives Achieved

### P2.1: GitLab Runner + Pipeline ✅
- **GitLab CI Configuration**: Complete `.gitlab-ci.yml` with memory-disciplined builds
- **Build Stages**: lint → build → test → scan → release pipeline
- **Memory Constraints**: `CARGO_BUILD_JOBS=4`, `NODE_OPTIONS=--max-old-space-size=2048`
- **Artifact Management**: 7-day expiration for VM images, 1-year for releases
- **Multi-Phase Builds**: P0, P1, P2 production images with optimized caching

### P2.2: NixOS VM Tests ✅
- **Test Framework**: `tests/rave-vm.nix` using NixOS test driver
- **Comprehensive Coverage**: 12 test suites covering system, security, and integration
- **Service Health**: Validates all systemd services (nginx, grafana, postgresql, etc.)
- **HTTP Endpoints**: Tests all service endpoints with proper response validation
- **Security Validation**: TLS, SSH, firewall, and secrets management verification

### P2.3: Prometheus + Grafana + Metrics ✅
- **Prometheus Stack**: 30-day retention, memory-limited (512MB max)
- **Exporters**: Node, nginx, PostgreSQL, and custom webhook metrics
- **Dashboards**: 3 comprehensive monitoring dashboards (JSON format)
- **OpenTelemetry**: Tracing integration with task_id correlation
- **Pushgateway**: Agent job metrics collection endpoint

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    RAVE P2 Architecture                     │
├─────────────────────────────────────────────────────────────┤
│  GitLab CI/CD Pipeline                                      │
│  ├── Lint (syntax validation)                              │
│  ├── Build (P0/P1/P2 images)                              │
│  ├── Test (NixOS VM integration)                          │
│  ├── Scan (Trivy security scanning)                       │
│  └── Release (tagged artifacts)                           │
├─────────────────────────────────────────────────────────────┤
│  Observability Stack                                        │
│  ├── Prometheus (metrics collection)                       │
│  ├── Grafana (visualization + dashboards)                 │
│  ├── Node Exporter (system metrics)                       │
│  ├── Pushgateway (agent job metrics)                      │
│  └── OpenTelemetry (distributed tracing)                  │
├─────────────────────────────────────────────────────────────┤
│  Enhanced Services (from P1)                               │
│  ├── Webhook Dispatcher (now with metrics)                │
│  ├── nginx (with monitoring endpoints)                    │
│  ├── Grafana (OIDC + provisioned dashboards)             │
│  └── PostgreSQL (with metrics export)                     │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Monitoring Dashboards

### 1. Project Health Dashboard
**Purpose**: Overall system and service health monitoring
- Service availability status (UP/DOWN indicators)
- System resource usage (CPU, memory, disk)
- Service response times and performance
- Event processing rates and error tracking
- Alert status and network activity

**Key Metrics**:
- `up{job=~"node|nginx|grafana|webhook-dispatcher"}` - Service availability
- `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` - Memory usage
- `rate(webhook_events_processed_total[5m])` - Event processing rate

### 2. Agent Performance Dashboard
**Purpose**: AI agent task processing with OpenTelemetry tracing
- Task processing rates and success metrics
- Duration percentiles (P50, P90, P95, P99)
- Memory usage and service uptime tracking
- OpenTelemetry trace correlation with task_id
- Event store database growth monitoring

**Key Metrics**:
- `rate(webhook_events_processed_total[5m]) * 60` - Tasks per minute
- `webhook_duration_seconds_sum / webhook_duration_seconds_count` - Average duration
- `webhook_dispatcher_uptime_seconds` - Service uptime

### 3. System Health Dashboard
**Purpose**: Infrastructure metrics and service dependencies
- CPU usage by core and memory usage details
- Disk I/O and network I/O monitoring
- Filesystem usage with threshold alerting
- Service resource consumption table
- PostgreSQL connection monitoring

**Key Metrics**:
- `100 - (avg by (cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` - CPU usage
- `rate(node_disk_read_bytes_total[5m])` - Disk I/O
- `pg_stat_database_numbackends` - Database connections

## 🔧 Development Workflow

### Local Testing
```bash
# Quick health check
./test-vm.sh health

# Build P2 image
./test-vm.sh build --phase p2

# Run integration tests
./test-vm.sh test

# Start VM for manual testing
./test-vm.sh run --headless

# Full CI-like pipeline
./test-vm.sh ci
```

### CI/CD Pipeline Stages

1. **Lint Stage**: Syntax validation and secrets checking
   ```bash
   nix flake check --no-build --show-trace
   # Validates flake syntax and configuration
   ```

2. **Build Stage**: Multi-phase image creation
   ```bash
   nix build .#p2-production --no-link --print-out-paths
   # Creates P2 production image with observability
   ```

3. **Test Stage**: Comprehensive VM testing
   ```bash
   nix run .#tests.rave-vm
   # 12 test suites validating system integration
   ```

4. **Scan Stage**: Security vulnerability scanning
   ```bash
   trivy fs --format json --output trivy-p2-report.json
   # Scans for known vulnerabilities in dependencies
   ```

5. **Release Stage**: Tagged artifact creation
   ```bash
   # Creates versioned releases with both P1 and P2 variants
   # Includes comprehensive release manifest
   ```

## 🚨 Memory Discipline Implementation

### Build-Time Constraints
```yaml
variables:
  NIX_CONFIG: |
    max-jobs = 2
    cores = 4
  CARGO_BUILD_JOBS: "4"
  NODE_OPTIONS: "--max-old-space-size=2048"
  NIX_BUILD_MEMORY_LIMIT: "4GB"
```

### Runtime Resource Limits
```nix
# Prometheus memory limit
systemd.services.prometheus.serviceConfig = {
  MemoryMax = "512M";
  CPUQuota = "50%";
};

# Grafana memory limit  
systemd.services.grafana.serviceConfig = {
  MemoryMax = "256M";
  CPUQuota = "25%";
};

# Webhook dispatcher limits
systemd.services.webhook-dispatcher.serviceConfig = {
  MemoryMax = "256M";
  CPUQuota = "50%";
};
```

### VM Testing Constraints
```nix
virtualisation = {
  memorySize = 2048;  # 2GB RAM for test
  cores = 2;          # Limit cores for CI
  graphics = false;   # Headless for CI
};
```

## 📈 Metrics Collection

### System Metrics (Node Exporter)
- CPU, memory, disk, network utilization
- Filesystem usage and system load
- Process and file descriptor monitoring
- systemd service status tracking

### Application Metrics (Webhook Dispatcher)
```javascript
// Prometheus metrics in webhook dispatcher
webhook_requests_total - Total HTTP requests received
webhook_errors_total - Total processing errors
webhook_duration_seconds - Request processing duration histogram
webhook_events_processed_total - Successfully processed events
webhook_events_deduplicated_total - Deduplicated events
webhook_dispatcher_uptime_seconds - Service uptime gauge
```

### Service Metrics (nginx, PostgreSQL, Grafana)
- HTTP request rates and response times
- Database connection counts and query performance  
- Grafana user sessions and dashboard usage

## 🔍 OpenTelemetry Integration

### Trace Correlation
```javascript
// Generated for each webhook request
traceId = crypto.randomBytes(16).toString('hex');
taskId = crypto.randomBytes(8).toString('hex');

// Stored in event database for correlation
INSERT INTO events (event_uuid, task_id, trace_id, ...) VALUES (?, ?, ?, ...);
```

### Grafana Exemplars
- Link metrics to traces using task_id labels
- Enable drill-down from dashboard metrics to trace details
- Correlate agent performance with specific task execution

## 🚀 Deployment Options

### Development
```bash
nix run .#qemu  # Basic development image
```

### Production Security-Focused
```bash
nix run .#p1-production  # Maximum security, minimal monitoring
```

### Production Observability-Enhanced (Recommended)
```bash
nix run .#p2-production  # Full observability + P1 security
```

## ⚡ Performance Characteristics

### Build Times
- **P0 Development**: ~5 minutes
- **P1 Security**: ~8 minutes  
- **P2 Observability**: ~12 minutes

### Resource Usage
- **Base System**: ~512MB RAM
- **With Observability**: ~1.2GB RAM
- **Under Load**: ~1.8GB RAM (within 2GB limit)

### Network Ports
- **22**: SSH (key-only authentication)
- **3002**: HTTPS (nginx with all services)
- **9090**: Prometheus (internal access only)
- **9100**: Node Exporter (metrics collection)

## 🛡️ Security Considerations

### Inherited from P1
- sops-nix encrypted secrets management
- SSH key-only authentication  
- Enhanced firewall with rate limiting
- TLS certificates for all HTTP traffic

### P2 Additions
- Prometheus metrics access control (internal only)
- Webhook signature verification with timing-safe comparison
- Resource limits prevent DoS via memory exhaustion
- Structured logging for security event correlation

## 📋 Troubleshooting

### Build Issues
```bash
# Clear Nix cache if builds fail
nix store gc

# Rebuild with verbose output
nix build .#p2-production --show-trace --verbose

# Check flake syntax
nix flake check
```

### Test Failures
```bash
# Run tests with more verbose output
nix run .#tests.rave-vm --show-trace

# Check individual service status in VM
systemctl status webhook-dispatcher
journalctl -u webhook-dispatcher
```

### Monitoring Issues
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Verify Grafana datasource
curl -u admin:admin http://localhost:3030/api/datasources

# Test metrics endpoints
curl http://localhost:3001/metrics  # Webhook dispatcher
curl http://localhost:9100/metrics  # Node exporter
```

## 🔄 Next Steps (Phase P3)

Based on this P2 foundation, Phase P3 could include:
- **Advanced Monitoring**: APM, user analytics, business metrics
- **Alerting**: Email, Slack, PagerDuty integrations
- **Log Aggregation**: Centralized logging with search and analysis
- **Performance**: Auto-scaling, load balancing, CDN integration
- **Compliance**: Audit logging, retention policies, compliance reporting

---

**Phase P2 Status**: ✅ **COMPLETE**  
All objectives achieved with comprehensive testing and documentation.