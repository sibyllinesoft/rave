# P3 GitLab Service Integration Deployment Guide

This guide walks through deploying the GitLab service integration for the RAVE Autonomous Dev Agency platform.

## Overview

Phase P3 adds GitLab CE as the central code repository and CI/CD hub for the autonomous development workflow. Key components include:

- **GitLab CE**: Complete DevOps platform with git repositories, issue tracking, CI/CD
- **GitLab Runner**: Docker-based CI/CD executor with KVM support for VM provisioning  
- **sops-nix**: Secure secrets management for all GitLab credentials
- **Integrated Monitoring**: Prometheus/Grafana dashboards for GitLab health

## Prerequisites

1. **P2 System**: Successfully deployed P2 observability configuration
2. **sops-nix**: Age keys generated and .sops.yaml configured
3. **Secrets**: All GitLab secrets defined and encrypted in secrets.yaml
4. **Resources**: Minimum 12GB RAM, 50GB storage for GitLab + repositories

## File Structure

```
rave/
├── p3-production-config.nix     # P3 main configuration (inherits P2)
├── infra/nixos/
│   ├── configuration.nix        # NixOS system entry point
│   ├── gitlab.nix              # GitLab service configuration  
│   ├── prometheus.nix          # Monitoring (extracted from P2)
│   └── grafana.nix             # Dashboards (extracted from P2)
├── secrets.yaml                # Encrypted secrets (sops-nix)
├── .sops.yaml                  # sops encryption configuration
└── test-p3-gitlab.sh          # Integration test script
```

## Secrets Configuration

### 1. Generate Age Keys (if not done)

```bash
# Generate age key for sops-nix
age-keygen -o ~/.config/sops/age/keys.txt

# Add public key to .sops.yaml
echo "Your public key: $(age-keygen -y ~/.config/sops/age/keys.txt)"
```

### 2. Configure Production Secrets

Edit secrets.yaml with real values:

```bash
# Decrypt and edit secrets
sops secrets.yaml
```

Required GitLab secrets:
- `gitlab.root-password`: Strong password for GitLab root user (16+ chars)
- `gitlab.secret-key-base`: 64-character random string for session encryption
- `gitlab.db-password`: PostgreSQL password for GitLab database user  
- `gitlab.runner-token`: Generated during GitLab setup for runner registration
- `gitlab.admin-token`: API token for GitLab administration (optional)

### 3. Generate Strong Secrets

```bash
# Generate random passwords and keys
openssl rand -hex 32  # For secret-key-base (64 chars)
openssl rand -base64 24  # For passwords (32 chars)
```

## Deployment Steps

### 1. Validate Configuration

```bash
# Run integration tests
./test-p3-gitlab.sh

# Check configuration syntax
nix-instantiate --parse p3-production-config.nix
nix-instantiate --parse infra/nixos/gitlab.nix
```

### 2. Build VM Image

```bash
# Build P3 configuration
nix-build -A config.system.build.vm p3-production-config.nix

# Or build using the RAVE CLI
rave vm build-image
```

### 3. Deploy to VM

```bash
# Start VM with P3 configuration
rave vm launch-local --image artifacts/legacy-qcow/rave-complete-localhost.qcow2

```

### 4. Initial GitLab Setup

Once the system boots:

1. **Access GitLab Web Interface**:
   ```
   https://rave.local:3002/gitlab/
   ```

2. **Initial Login**:
   - Username: `root`  
   - Password: From `secrets.yaml` → `gitlab.root-password`

3. **Complete Setup Wizard**:
   - Configure GitLab URL: `https://rave.local:3002/gitlab`
   - Set up admin email (or skip for local development)
   - Configure sign-up restrictions
   - Create first project

### 5. Register GitLab Runner

The runner should auto-register on startup. Verify with:

```bash
# Check runner status
systemctl status gitlab-runner

# View runner logs  
journalctl -u gitlab-runner -f

# List registered runners in GitLab
# Go to Admin → CI/CD → Runners
```

If manual registration is needed:

```bash
# Get registration token from GitLab Admin → CI/CD → Runners
sudo gitlab-runner register \
  --url https://rave.local:3002/gitlab \
  --registration-token YOUR_REGISTRATION_TOKEN \
  --executor docker \
  --docker-image alpine:latest \
  --docker-privileged
```

## Service Verification

### 1. Health Checks

```bash
# Check all services
systemctl status gitlab gitlab-runner docker postgresql nginx

# Check GitLab health
curl -k https://rave.local:3002/gitlab/-/health

# Check GitLab metrics
curl -k https://rave.local:3002/gitlab/-/metrics
```

### 2. Resource Usage

```bash
# Monitor resource consumption
htop
systemctl status gitlab  # Check memory usage

# GitLab resource limits
systemctl show gitlab | grep Memory
systemctl show gitlab-runner | grep Memory
```

### 3. CI/CD Pipeline Test

Create a test project with `.gitlab-ci.yml`:

```yaml
test:
  script:
    - echo "Hello from GitLab CI"
    - docker --version
    - ls /dev/kvm  # Verify KVM access
  tags:
    - docker
    - kvm
```

## Monitoring Integration

### 1. Prometheus Scraping

GitLab metrics are automatically scraped at:
- `https://rave.local:3002/gitlab/-/metrics` (GitLab)
- `http://localhost:9252/metrics` (GitLab Runner)

### 2. Grafana Dashboards

Pre-configured dashboards:
- **System Overview**: CPU, memory, service status
- **GitLab Overview**: Service health, runner status, memory usage

Access: `https://rave.local:3002/grafana/`

### 3. Alerting Rules

Configured alerts:
- `GitLabDown`: GitLab service unavailable >5min  
- `GitLabRunnerDown`: Runner unavailable >5min
- `GitLabHighMemoryUsage`: Memory usage >6GB for >10min
- `GitLabDatabaseConnectionsHigh`: High DB connection usage

## Troubleshooting

### Common Issues

1. **GitLab won't start**:
   ```bash
   # Check logs
   journalctl -u gitlab -f
   
   # Common issues:
   # - Database connection failed (check PostgreSQL)
   # - Secret files not accessible (check sops-nix)
   # - Insufficient memory (check resource limits)
   ```

2. **Runner registration failed**:
   ```bash
   # Check runner logs
   journalctl -u gitlab-runner -f
   
   # Manual registration
   sudo gitlab-runner register --url https://rave.local:3002/gitlab --registration-token TOKEN
   ```

3. **Docker executor issues**:
   ```bash
   # Check Docker daemon
   systemctl status docker
   
   # Test Docker access
   sudo -u gitlab-runner docker ps
   
   # Check KVM access
   ls -la /dev/kvm
   groups gitlab-runner  # Should include: docker, kvm, libvirtd
   ```

4. **Resource exhaustion**:
   ```bash
   # Check memory usage
   free -h
   systemctl show gitlab | grep Memory
   
   # Adjust limits in infra/nixos/gitlab.nix if needed
   # Then rebuild and redeploy
   ```

### Performance Tuning

1. **GitLab Memory Limits**:
   - Default: 8GB max memory
   - Adjust in `infra/nixos/gitlab.nix` → `systemd.services.gitlab.serviceConfig.MemoryMax`

2. **PostgreSQL Optimization**:
   - Shared buffers, work memory configured for GitLab workload
   - Connection limit: 200 concurrent connections

3. **Storage Management**:
   - Artifact retention: 7 days by default
   - Repository storage: `/var/lib/gitlab/repositories`
   - Backup location: `/var/lib/gitlab/backups`

## Security Considerations

### 1. Network Security

- GitLab accessible only via nginx reverse proxy
- Internal services bound to localhost
- Docker bridge network properly firewalled

### 2. Secrets Management  

- All secrets encrypted with sops-nix
- Service-specific secret file permissions
- No secrets in configuration files

### 3. Container Security

- Docker privileged mode required for KVM (unavoidable)
- Resource limits enforced via systemd
- Container capabilities restricted where possible

### 4. Access Control

- Initial setup requires root login
- OIDC integration planned for Phase P4
- Runner access restricted to Docker group

## Backup and Recovery

### 1. Automated Backups

Daily GitLab backups configured:
```bash
# Backup service runs daily
systemctl status gitlab-backup.timer

# Manual backup
sudo -u gitlab gitlab-backup create
```

### 2. Critical Data Locations

- **Repositories**: `/var/lib/gitlab/repositories`
- **Database**: PostgreSQL cluster
- **Configuration**: `/var/lib/gitlab/config`
- **Secrets**: `secrets.yaml` (encrypted)

### 3. Recovery Process

1. Fresh system deployment with same secrets
2. Restore GitLab backup:
   ```bash
   sudo -u gitlab gitlab-backup restore TIMESTAMP=backup_timestamp
   ```
3. Reconfigure and restart services

## Next Steps (Phase P4)

1. **Matrix/Element Integration**: Team chat with GitLab OIDC auth
2. **Advanced CI/CD**: Multi-stage pipelines with review apps
3. **External Runners**: Scale with additional runner nodes
4. **Backup Automation**: External backup storage integration

## Support

For issues with P3 GitLab integration:

1. Run `./test-p3-gitlab.sh` for diagnostic information
2. Check service logs: `journalctl -u gitlab -u gitlab-runner -f`
3. Verify resource usage and adjust limits if needed
4. Validate secrets decryption: `sops -d secrets.yaml`

The P3 configuration provides a solid foundation for autonomous development workflows while maintaining security and observability standards established in P1 and P2.
