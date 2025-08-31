# RAVE Hermetic Spin-up and Smoke Test System

## Overview

The RAVE Hermetic Spin-up and Smoke Test System provides comprehensive validation of the complete RAVE Autonomous Dev Agency infrastructure. This system performs end-to-end validation from clean checkout to full functional agency, generating a signed boot transcript proving system readiness.

## System Components

### 1. Main Validation Script

**File**: `scripts/spinup_smoke.sh`

The primary hermetic validation script that orchestrates all testing phases:

- **Phase 1**: Configuration Validation (Nix flake, P6 config, secrets management)
- **Phase 2**: VM Build Validation (P6 production image build and integrity)
- **Phase 3**: VM Boot Validation (NixOS VM integration tests)
- **Phase 4**: Service Health Validation (PostgreSQL, GitLab, Matrix, Grafana)
- **Phase 5**: OIDC Authentication Validation (GitLab ↔ Matrix ↔ Grafana)
- **Phase 6**: Agent Control Validation (Matrix bridge functionality)
- **Phase 7**: Sandbox Provisioning Validation (VM provisioning workflow)
- **Phase 8**: End-to-End Workflow Validation (Hello World project flow)
- **Phase 9**: Performance and Resource Validation (SAFE mode constraints)
- **Security Validation**: Comprehensive security posture assessment

### 2. Health Check Scripts

**Location**: `scripts/health_checks/`

Individual service health validation scripts:

#### `check_gitlab.sh`
- GitLab systemd service status
- Configuration file validation
- Process health monitoring
- Database connectivity
- HTTP endpoint validation
- API functionality testing
- Runner integration checks
- Storage and permissions
- OIDC configuration validation

#### `check_matrix.sh`
- Matrix Synapse service status
- Configuration file validation
- Database connectivity
- HTTP endpoint validation
- Client API functionality
- Element web client validation
- Matrix bridge configuration
- Federation security (should be disabled)
- Media repository health
- OIDC integration validation

#### `check_database.sh`
- PostgreSQL service status
- Version and configuration validation
- Process and resource monitoring
- RAVE-specific database checks (GitLab, Synapse, Grafana)
- User permissions validation
- Performance metrics monitoring
- Maintenance configuration
- Storage and disk space validation

#### `check_networking.sh`
- Network interface validation
- DNS resolution testing
- Internal service connectivity
- External connectivity validation
- HTTPS/TLS endpoint testing
- Firewall configuration validation
- Routing table verification
- Network performance monitoring
- Sandbox networking readiness

### 3. Test Scenario Scripts

**Location**: `scripts/test_scenarios/`

End-to-end workflow validation scripts:

#### `hello_world_flow.sh`
Complete autonomous development workflow simulation:
1. Matrix command processing (`!rave create project hello-world`)
2. GitLab project creation
3. Code structure generation
4. Git repository operations
5. Merge request creation
6. CI/CD pipeline trigger
7. Sandbox VM provisioning
8. Matrix room notification
9. User sandbox testing
10. Merge approval and cleanup

#### `agent_control_test.sh`
Matrix bridge and agent functionality testing:
- Matrix bridge code validation
- Command parsing logic testing
- Agent response generation
- Bridge configuration validation
- Security and permissions testing
- PM agent integration
- Matrix room management
- Error handling and recovery

### 4. Boot Transcript System

**Output**: `artifacts/boot_transcript_YYYYMMDD-HHMMSS.json`

Comprehensive signed validation report including:

- **System Information**: Hardware specs, OS details, Nix version
- **Test Results**: All validation phases with pass/fail/warn status
- **Service Health**: Detailed health status for all services
- **Authentication Tests**: OIDC flow validation results
- **Agent Control Tests**: Matrix bridge functionality validation
- **Sandbox Tests**: VM provisioning workflow validation
- **Performance Metrics**: Resource usage and timing data
- **Security Validation**: Comprehensive security posture assessment
- **Image Digest**: SHA256 hash of VM image for integrity
- **Signature**: Cryptographic signature for transcript integrity

## Usage

### Quick Start

```bash
# Run complete hermetic validation
./scripts/spinup_smoke.sh

# View detailed help
./scripts/spinup_smoke.sh --help
```

### Environment Variables

```bash
# SAFE mode configuration (default: 1)
export SAFE_MODE=1          # Memory-disciplined mode
export SAFE_MODE=0          # Full performance mode

# Debug output
export DEBUG=1              # Enable debug logging

# Custom timeout (default: 1800s)
export VALIDATION_TIMEOUT=2400
```

### Individual Component Testing

```bash
# Run individual health checks
./scripts/health_checks/check_gitlab.sh
./scripts/health_checks/check_matrix.sh
./scripts/health_checks/check_database.sh
./scripts/health_checks/check_networking.sh

# Run specific workflow tests
./scripts/test_scenarios/hello_world_flow.sh simulate
./scripts/test_scenarios/agent_control_test.sh test-mode
```

## Validation Criteria

### Success Criteria
- ✅ All services healthy within 10 minutes of boot
- ✅ OIDC authentication working end-to-end
- ✅ Matrix commands successfully control agent services
- ✅ Sandbox VM provisioning completes within 20 minutes
- ✅ Boot transcript properly signed and validated
- ✅ Zero critical security or functionality issues

### Performance Targets (SAFE Mode)
- **Build Time**: P6 image build completes within 15 minutes
- **Memory Usage**: Total system memory < 8GB
- **Boot Time**: All services ready within 10 minutes
- **Response Time**: Health checks complete within 5 minutes

### Security Validation
- SSH password authentication disabled
- Firewall configured (ports 22, 3002 only)
- Secrets management via sops-nix
- No hardcoded secrets detected
- TLS certificates properly configured

## Boot Transcript Format

```json
{
  "test_session_id": "spinup-20250124-143052",
  "rave_version": "P6-production",
  "start_time": "2025-01-24T14:30:52Z",
  "completion_time": "2025-01-24T14:45:18Z",
  "duration_seconds": 866,
  "overall_status": "SUCCESS",
  "system_info": {
    "hostname": "rave-host",
    "kernel": "6.1.0-17-amd64",
    "arch": "x86_64",
    "cpu_cores": "8",
    "memory_gb": "16"
  },
  "test_summary": {
    "total_tests": 45,
    "passed": 43,
    "failed": 0,
    "warned": 2
  },
  "validation_results": [...],
  "service_health": {...},
  "authentication_tests": {...},
  "agent_control_tests": {...},
  "sandbox_tests": {...},
  "performance_metrics": {...},
  "security_validation": {...},
  "image_digest": "sha256:abc123def456...",
  "signature": "def789abc123..."
}
```

## Integration with CI/CD

### GitLab CI Integration

```yaml
# Add to .gitlab-ci.yml
test:hermetic-validation:
  stage: test
  script:
    - ./scripts/spinup_smoke.sh
  artifacts:
    reports:
      junit: artifacts/boot_transcript_*.json
    paths:
      - artifacts/
  only:
    - main
    - merge_requests
```

### Manual Validation Workflow

1. **Pre-deployment Validation**
   ```bash
   # Full system validation
   ./scripts/spinup_smoke.sh
   
   # Check transcript
   cat artifacts/boot_transcript_*.json | jq '.overall_status'
   ```

2. **Component-specific Testing**
   ```bash
   # Test specific service
   ./scripts/health_checks/check_gitlab.sh
   
   # Test workflow
   ./scripts/test_scenarios/hello_world_flow.sh simulate
   ```

3. **Performance Profiling**
   ```bash
   # SAFE mode validation
   SAFE_MODE=1 ./scripts/spinup_smoke.sh
   
   # Full performance mode
   SAFE_MODE=0 ./scripts/spinup_smoke.sh
   ```

## Troubleshooting

### Common Issues

**Build Failures**
```bash
# Check Nix configuration
nix flake check --show-trace

# Verify available disk space
df -h

# Check memory constraints in SAFE mode
free -m
```

**Service Health Failures**
```bash
# Check systemd services
systemctl status postgresql gitlab matrix-synapse

# Verify network connectivity
./scripts/health_checks/check_networking.sh

# Check logs
journalctl -u service-name -f
```

**Sandbox Provisioning Issues**
```bash
# Check KVM availability
ls -la /dev/kvm

# Verify libvirt setup
systemctl status libvirtd

# Test sandbox script manually
./scripts/launch_sandbox.sh --help
```

### Debug Mode

```bash
# Enable comprehensive debugging
DEBUG=1 ./scripts/spinup_smoke.sh

# Check individual components
DEBUG=1 ./scripts/health_checks/check_gitlab.sh
```

## Architecture Integration

### P6 Production Configuration
The validation system is specifically designed for the P6 production configuration, which includes:

- GitLab CE with PostgreSQL backend
- Matrix Synapse homeserver with Element client
- GitLab OIDC authentication integration
- Automated sandbox VM provisioning
- Grafana monitoring and observability
- Security hardening and secrets management

### Resource Management
- **SAFE Mode**: Memory-disciplined operation (6-8GB total)
- **FULL_PIPE Mode**: Performance-optimized operation (8-16GB total)
- Resource constraints enforced through systemd limits
- Sandbox VMs limited to 4GB RAM, 2 CPU cores each

### Security Model
- Defense-in-depth architecture validation
- Cryptographic secrets management verification
- Network security posture assessment
- Access control validation
- Vulnerability scanning integration

## Future Enhancements

### Phase P7+ Features
- Advanced agent orchestration testing
- Multi-tenant sandbox environments
- Enhanced performance profiling
- Extended observability validation
- Chaos engineering integration

### Continuous Improvement
- Automated test case generation
- Performance regression detection
- Security posture monitoring
- User experience optimization
- Reliability engineering metrics

## Conclusion

The RAVE Hermetic Spin-up and Smoke Test System provides comprehensive validation of the complete autonomous development agency infrastructure. It ensures that all components work together seamlessly and that the system is ready for production autonomous development workflows.

The system generates cryptographically signed boot transcripts that serve as proof of system integrity and readiness, enabling confident deployment of the RAVE infrastructure in enterprise environments.