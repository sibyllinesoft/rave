# ADR-004: Phase P2 Observability Implementation

## Status
**ACCEPTED** - Implementation Complete

## Context

Phase P2 extends the RAVE security foundation (P1) with comprehensive CI/CD automation and observability infrastructure. This phase implements production-grade monitoring, automated testing, and resource-disciplined operations to ensure sustainable long-term operation.

## Decision

Implement Phase P2 with three core components:

### P2.1: Complete CI/CD Pipeline
- **GitLab Runner Integration**: Full automation pipeline with 5 stages
- **Memory-Disciplined Builds**: SAFE mode constraints with 3GB RAM limits
- **Multi-Phase Artifacts**: P0, P1, P2 image variants with proper retention
- **Security Scanning**: Trivy vulnerability scanning with SAFE/FULL_PIPE thresholds

### P2.2: NixOS VM Integration Tests  
- **Comprehensive Test Coverage**: 21 test cases across 4 test suites
- **Service Health Validation**: All systemd services and HTTP endpoints
- **Security Verification**: TLS, SSH, firewall, secrets management
- **Resource Monitoring**: Memory, CPU, disk usage validation

### P2.3: Prometheus + Grafana Observability
- **Metrics Collection**: System and application metrics with configurable retention
- **SAFE Mode Constraints**: 3-day retention, 30s scrape intervals, reduced memory limits  
- **Monitoring Dashboards**: 3 comprehensive Grafana dashboards
- **OpenTelemetry Integration**: Distributed tracing with task correlation

## Implementation Details

### SAFE Mode Resource Management
```nix
# Dynamic configuration based on SAFE environment variable
safeMode = builtins.getEnv "SAFE" != "0";
retentionTime = if safeMode then "3d" else "7d";
scrapeInterval = if safeMode then "30s" else "15s"; 
prometheusMemory = if safeMode then "256M" else "512M";
grafanaMemory = if safeMode then "128M" else "256M";
```

### CI/CD Pipeline Architecture
```yaml
stages: [lint, build, test, scan, release]
memory_constraints:
  QEMU_RAM_MB: 3072
  QEMU_CPUS: 2
  NIX_BUILD_CORES: 2
  NIX_MAX_JOBS: 1
```

### Observability Stack
- **Prometheus**: Metrics collection with configurable retention and resource limits
- **Grafana**: Visualization with provisioned dashboards and OIDC integration
- **Node Exporter**: System metrics (CPU, memory, disk, network)
- **Custom Metrics**: Webhook dispatcher with OpenTelemetry tracing
- **Pushgateway**: Agent job metrics collection endpoint

### Integration Testing
- **Service Validation**: All systemd services (nginx, grafana, postgresql, vibe-kanban, ccr, webhook-dispatcher, prometheus)
- **HTTP Health Checks**: All endpoints with proper response validation
- **Security Verification**: TLS certificates, SSH configuration, firewall rules, secrets management
- **Observability Validation**: Prometheus targets, Grafana datasources, metrics endpoints, resource constraints

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    RAVE P2 Architecture                     │
├─────────────────────────────────────────────────────────────┤
│  GitLab CI/CD Pipeline                                      │
│  ├── lint (syntax + secrets validation)                    │
│  ├── build (P0/P1/P2 images with memory constraints)      │
│  ├── test (comprehensive NixOS VM integration)            │
│  ├── scan (Trivy security + npm audit)                    │
│  └── release (tagged artifacts + manifest)                │
├─────────────────────────────────────────────────────────────┤
│  Observability Stack                                        │
│  ├── Prometheus (configurable retention + scrape)         │
│  ├── Grafana (3 dashboards + OIDC integration)           │
│  ├── Node Exporter (comprehensive system metrics)         │
│  ├── Pushgateway (agent job metrics collection)           │
│  └── OpenTelemetry (distributed tracing + correlation)    │
├─────────────────────────────────────────────────────────────┤
│  Enhanced Services (from P1)                               │
│  ├── Webhook Dispatcher (metrics + tracing)               │
│  ├── nginx (monitoring endpoints + rate limiting)         │
│  ├── Grafana (provisioned dashboards + datasources)      │
│  └── PostgreSQL (metrics export + connection monitoring)  │
└─────────────────────────────────────────────────────────────┘
```

## Consequences

### Positive
- **Production Readiness**: Complete automation and monitoring for sustainable operations
- **Resource Discipline**: SAFE mode ensures reliable operation within memory constraints
- **Comprehensive Testing**: 21 test cases provide confidence in system reliability
- **Observability**: Full visibility into system performance and health
- **Security Maintained**: All P1 security features preserved and enhanced

### Negative  
- **Complexity**: Additional moving parts require more operational knowledge
- **Resource Usage**: Observability stack adds ~700MB memory overhead
- **Build Time**: P2 images take ~12 minutes vs ~5 minutes for P0

### Risks Mitigated
- **Production Issues**: Comprehensive monitoring enables proactive issue detection
- **Resource Exhaustion**: Memory limits prevent cascading failures
- **Security Regressions**: Automated security scanning in CI pipeline
- **Integration Failures**: Extensive integration testing catches deployment issues

## Monitoring and Alerting

### Key Metrics
- **System Health**: Memory usage >85%, CPU usage >80%, disk usage >85%
- **Service Availability**: Any service down for >2 minutes
- **Application Performance**: Webhook processing errors >10 in 5 minutes
- **Resource Limits**: Services approaching memory limits

### Dashboards
1. **Project Health**: Service availability, resource usage, performance metrics
2. **Agent Performance**: Task processing rates, duration percentiles, OpenTelemetry traces
3. **System Health**: Infrastructure metrics, service dependencies, PostgreSQL connections

### Alerting Rules
- High memory/CPU/disk usage warnings
- Service availability critical alerts  
- Webhook dispatcher error rate monitoring
- Resource constraint violations

## Testing Strategy

### Unit Tests
- Configuration validation for both SAFE and FULL_PIPE modes
- Memory constraint calculation logic
- Metrics collection and export functions

### Integration Tests  
- Complete service stack deployment and health verification
- HTTP endpoint responses and security headers
- Prometheus target discovery and scraping
- Grafana datasource connectivity and query execution
- Resource limit enforcement and OOM handling

### End-to-End Tests
- Full CI/CD pipeline execution with artifacts
- VM deployment with resource constraints
- Monitoring stack functionality under load
- Alert firing and resolution workflows

## Performance Characteristics

### Build Performance
- **P0 Development**: ~5 minutes (basic services)
- **P1 Security**: ~8 minutes (+ security hardening)  
- **P2 Observability**: ~12 minutes (+ monitoring stack)

### Runtime Performance
- **Base System**: ~512MB RAM (core services)
- **With Observability**: ~1.2GB RAM (+ monitoring)
- **Under Load**: ~1.8GB RAM (within 2GB VM limit)

### Network Utilization
- **SSH**: Port 22 (key-only authentication)
- **HTTPS**: Port 3002 (all web services)
- **Internal Monitoring**: Ports 9090, 9100, 3030 (localhost only)

## Deployment Options

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

## Validation

Complete validation implemented via `test-p2-validation.sh`:

- **Prerequisites Check**: System resources and dependencies
- **Flake Validation**: Configuration syntax and target definitions  
- **Build Validation**: P2 image creation with memory constraints
- **Integration Testing**: 21 comprehensive test cases
- **CI Pipeline Validation**: GitLab CI configuration completeness
- **SAFE Mode Testing**: Resource constraint behavior verification

## Future Considerations (Phase P3)

Potential extensions beyond P2:
- **Advanced APM**: Application performance monitoring with user analytics
- **External Alerting**: Email, Slack, PagerDuty integrations
- **Log Aggregation**: Centralized logging with search and analysis
- **Performance Optimization**: Auto-scaling, load balancing, CDN integration  
- **Compliance**: Audit logging, retention policies, compliance reporting

## References

- [P0 Production Readiness Foundation](002-p0-production-readiness-foundation.md)
- [P1 Security Hardening](003-p1-security-hardening.md)  
- [P2 Observability Guide](../P2-OBSERVABILITY-GUIDE.md)
- [GitLab CI Configuration](.gitlab-ci.yml)
- [P2 Configuration](p2-production-config.nix)
- [VM Integration Tests](tests/rave-vm.nix)

---

**Date**: 2024-12-28  
**Author**: RAVE Development Team  
**Status**: ✅ **IMPLEMENTATION COMPLETE**