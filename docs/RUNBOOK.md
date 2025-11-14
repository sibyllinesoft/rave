# RAVE Production Runbook

## Overview

This runbook provides operational procedures for deploying, monitoring, and maintaining the RAVE (Reproducible AI Virtual Environment) system in production. All procedures are designed for both SAFE mode (resource-constrained) and FULL_PIPE mode (performance-optimized) operations.

## Emergency Contacts & Escalation

### Primary On-Call Rotation
- **Platform Team**: platform-oncall@organization.com  
- **Security Team**: security-incident@organization.com
- **SRE Team**: sre-oncall@organization.com

### Escalation Matrix
1. **Level 1 (0-15 min)**: Automated monitoring alerts
2. **Level 2 (15-30 min)**: On-call engineer notification
3. **Level 3 (30-60 min)**: Team lead escalation
4. **Level 4 (60+ min)**: Management escalation

## Quick Reference

### Service URLs
- **Main Application**: https://rave.local:3002/
- **Grafana Dashboards**: https://rave.local:3002/grafana/
- **Prometheus Metrics**: http://localhost:9090 (internal only)
- **Webhook Endpoint**: https://rave.local:3002/webhook

### Critical Service Ports
- **22**: SSH (key authentication only)
- **3002**: HTTPS (Traefik unified proxy)
- **9090**: Prometheus (localhost only)
- **3030**: Grafana (internal)
- **3001**: Webhook dispatcher

### System Resource Limits (SAFE Mode)
- **Memory**: 2GB total system limit
- **Prometheus**: 256MB limit
- **Grafana**: 128MB limit
- **CPU**: 2 cores maximum

## Deployment Procedures

### Production Deployment (Standard)

#### Prerequisites Verification
```bash
# 1. Verify system resources
free -h
df -h
nproc

# 2. Check network connectivity
ping -c 3 cache.nixos.org
curl -I https://nix-community.cachix.org

# 3. Validate SSH key access
ssh-add -l
```

#### P2 Production Deployment (Recommended)
```bash
#!/bin/bash
set -e

echo "=== RAVE P2 Production Deployment ==="

# 1. Set environment variables
export SAFE=1  # Enable memory discipline by default
export NIX_BUILD_CORES=2
export NIX_MAX_JOBS=1

# 2. Build P2 production image
echo "Building P2 production image..."
nix build .#p2-production --no-link --print-out-paths > p2-image-path.txt
IMAGE_PATH=$(cat p2-image-path.txt)
echo "Built image: $IMAGE_PATH"

# 3. Validate image integrity
echo "Validating image integrity..."
ls -lh "$IMAGE_PATH"
qemu-img check "$IMAGE_PATH"

# 4. Deploy with resource constraints
echo "Starting VM with SAFE mode constraints..."
qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -netdev user,id=net0,hostfwd=tcp::3002-:3002,hostfwd=tcp::22-:22 \
  -device virtio-net-pci,netdev=net0 \
  -drive format=qcow2,file="$IMAGE_PATH" \
  -daemonize

echo "Deployment initiated. Monitoring startup..."
```

#### Health Check Validation
```bash
#!/bin/bash
# health-check-deployment.sh

set -e

echo "=== Post-Deployment Health Checks ==="

# Wait for system boot
echo "Waiting for system availability..."
for i in {1..30}; do
  if nc -z localhost 3002; then
    echo "System responding on port 3002"
    break
  fi
  echo "Waiting for system startup... ($i/30)"
  sleep 10
done

# Check critical services
SERVICES=(
  "traefik"
  "postgresql" 
  "grafana"
  "prometheus"
  "webhook-dispatcher"
)

echo "Checking systemd services..."
for service in "${SERVICES[@]}"; do
  if systemctl is-active "$service" >/dev/null 2>&1; then
    echo "✅ $service is running"
  else
    echo "❌ $service is not running"
    systemctl status "$service"
    exit 1
  fi
done

# Validate HTTP endpoints
ENDPOINTS=(
  "https://localhost:3002/ 200"
  "https://localhost:3002/grafana/ 200"
  "https://localhost:3002/webhook 405"  # POST only
  "http://localhost:9090/-/healthy 200"
)

echo "Checking HTTP endpoints..."
for endpoint in "${ENDPOINTS[@]}"; do
  url=$(echo $endpoint | cut -d' ' -f1)
  expected_code=$(echo $endpoint | cut -d' ' -f2)
  
  actual_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
  
  if [ "$actual_code" = "$expected_code" ]; then
    echo "✅ $url responds with $actual_code"
  else
    echo "❌ $url responds with $actual_code (expected $expected_code)"
    exit 1
  fi
done

echo "🎉 All health checks passed!"
echo "System is ready for production traffic"
```

### Emergency Deployment Rollback

#### Rapid Rollback Procedure (< 5 minutes)
```bash
#!/bin/bash
# emergency-rollback.sh

set -e

echo "🚨 EMERGENCY ROLLBACK INITIATED"
echo "Timestamp: $(date -Iseconds)"

# 1. Stop current VM
echo "Stopping current VM..."
pkill -f qemu-system-x86_64 || true

# 2. Identify last known good image
LAST_GOOD_IMAGE="/path/to/last-known-good.qcow2"
if [ ! -f "$LAST_GOOD_IMAGE" ]; then
  echo "❌ Last known good image not found!"
  exit 1
fi

# 3. Start last known good version
echo "Starting last known good image..."
qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -netdev user,id=net0,hostfwd=tcp::3002-:3002,hostfwd=tcp::22-:22 \
  -device virtio-net-pci,netdev=net0 \
  -drive format=qcow2,file="$LAST_GOOD_IMAGE" \
  -daemonize

# 4. Verify rollback success
echo "Verifying rollback..."
sleep 30
if nc -z localhost 3002; then
  echo "✅ Rollback successful - system responding"
else
  echo "❌ Rollback failed - manual intervention required"
  exit 1
fi

echo "📧 Notifying incident response team..."
# Add notification logic here

echo "🎯 Rollback completed successfully"
```

## Monitoring & Alerting

### Key Performance Indicators (KPIs)

#### System Health Dashboard
```bash
# View real-time system metrics
curl -s http://localhost:9090/api/v1/query?query=up | jq .

# Check memory utilization
curl -s http://localhost:9090/api/v1/query?query='(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes))*100' | jq .

# Check CPU utilization  
curl -s http://localhost:9090/api/v1/query?query='100-(avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100)' | jq .
```

#### Service Level Objectives (SLOs)
- **API Availability**: 99.9% (< 45 minutes downtime/month)
- **Response Time**: p99 < 200ms for all HTTP endpoints  
- **Error Rate**: < 0.1% of all requests
- **Memory Usage**: < 85% of allocated resources
- **CPU Usage**: < 80% average utilization

### Alert Response Procedures

#### Critical Alert: System Down
```
Alert: rave_system_down
Severity: Critical
Threshold: Service unavailable for > 2 minutes
```

**Response Procedure:**
1. **Acknowledge** alert within 5 minutes
2. **Assess** scope via service health checks
3. **Triage** root cause using monitoring dashboards
4. **Restore** service using appropriate recovery procedure
5. **Verify** system health and alert resolution
6. **Document** incident in post-mortem template

#### High Memory Usage Alert
```
Alert: rave_high_memory_usage
Severity: Warning  
Threshold: Memory usage > 85% for 5 minutes
```

**Response Procedure:**
```bash
# 1. Check current memory usage
free -h
ps aux --sort=-%mem | head -20

# 2. Identify memory-heavy processes
systemd-cgtop --depth=3

# 3. Check service memory limits
systemctl show prometheus.service | grep Memory
systemctl show grafana.service | grep Memory

# 4. Restart services if necessary (in order)
sudo systemctl restart prometheus
sudo systemctl restart grafana
sudo systemctl restart traefik

# 5. Verify memory reduction
watch -n 5 free -h
```

#### Webhook Processing Errors
```
Alert: rave_webhook_errors
Severity: Warning
Threshold: > 10 errors in 5 minutes
```

**Response Procedure:**
```bash
# 1. Check webhook dispatcher logs
journalctl -u webhook-dispatcher -f --since "5 minutes ago"

# 2. Verify webhook secret configuration
sudo cat /run/secrets/webhook-gitlab-secret

# 3. Test webhook endpoint
curl -X POST https://localhost:3002/webhook \
  -H "X-Gitlab-Token: test-token" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'

# 4. Restart webhook dispatcher if needed
sudo systemctl restart webhook-dispatcher

# 5. Monitor recovery
watch -n 10 "curl -s http://localhost:3001/metrics | grep webhook_errors_total"
```

### Grafana Dashboard Navigation

#### 1. Project Health Dashboard
- **URL**: https://rave.local:3002/grafana/d/project-health
- **Purpose**: Overall system and service health monitoring
- **Key Panels**:
  - Service availability matrix
  - Resource utilization trends
  - Error rate by service
  - Response time percentiles

#### 2. Agent Performance Dashboard  
- **URL**: https://rave.local:3002/grafana/d/agent-performance
- **Purpose**: AI agent task processing and performance
- **Key Panels**:
  - Task completion rates
  - Processing duration distributions
  - OpenTelemetry trace correlation
  - Agent resource consumption

#### 3. System Health Dashboard
- **URL**: https://rave.local:3002/grafana/d/system-health  
- **Purpose**: Infrastructure metrics and dependencies
- **Key Panels**:
  - CPU, memory, disk utilization
  - Network traffic and connections
  - PostgreSQL connection status
  - Systemd service status

## Incident Response Procedures

### Incident Classification

#### Severity 1 (Critical)
- **Definition**: Complete system outage, data loss, security breach
- **Response Time**: 15 minutes
- **Escalation**: Immediate management notification

#### Severity 2 (High)
- **Definition**: Significant service degradation, partial outage
- **Response Time**: 30 minutes  
- **Escalation**: Team lead notification

#### Severity 3 (Medium)
- **Definition**: Minor service issues, performance degradation
- **Response Time**: 2 hours
- **Escalation**: During business hours

#### Severity 4 (Low)
- **Definition**: Cosmetic issues, documentation errors
- **Response Time**: Next business day
- **Escalation**: Backlog prioritization

### Common Incident Scenarios

#### Scenario 1: Memory Exhaustion (OOM)
**Symptoms:**
- Services failing to start
- High memory utilization alerts
- Slow response times

**Diagnosis:**
```bash
# Check memory usage
free -h
cat /proc/meminfo

# Check OOM killer activity
dmesg | grep -i "killed process"
journalctl --since "1 hour ago" | grep -i oom

# Identify memory-heavy processes
ps aux --sort=-%mem | head -20
```

**Resolution:**
```bash
# 1. Enable SAFE mode if not already active
export SAFE=1

# 2. Restart services in priority order
sudo systemctl restart prometheus
sudo systemctl restart grafana
sudo systemctl restart webhook-dispatcher
sudo systemctl restart traefik

# 3. Monitor memory recovery
watch -n 5 free -h

# 4. Adjust memory limits if needed
sudo systemctl edit prometheus.service
# Add: [Service]
#      MemoryMax=256M

# 5. Verify system stability
curl -k https://localhost:3002/
```

#### Scenario 2: SSL Certificate Expiration
**Symptoms:**
- HTTPS connection failures
- Browser certificate warnings
- SSL/TLS handshake errors

**Diagnosis:**
```bash
# Check certificate expiration
openssl x509 -in /run/secrets/tls-cert -text -noout | grep -A2 Validity

# Test SSL connectivity
openssl s_client -connect localhost:3002 -servername rave.local

# Check certificate file permissions
ls -la /run/secrets/tls-*
```

**Resolution:**
```bash
# 1. Update certificate in secrets.yaml
# Edit secrets.yaml with new certificate
sops secrets.yaml

# 2. Restart sops-nix secret delivery
sudo systemctl restart sops-nix

# 3. Restart Traefik to reload certificates
sudo systemctl restart traefik

# 4. Verify certificate renewal
curl -k -I https://localhost:3002/

# 5. Test SSL grade
nmap --script ssl-cert localhost -p 3002
```

#### Scenario 3: Database Connection Failures
**Symptoms:**
- Grafana unable to connect to PostgreSQL
- Database connection errors in logs
- Missing data in dashboards

**Diagnosis:**
```bash
# Check PostgreSQL service status
sudo systemctl status postgresql

# Test database connectivity
sudo -u postgres psql -c "SELECT version();"

# Check database logs
journalctl -u postgresql -f --since "30 minutes ago"

# Verify connection limits
sudo -u postgres psql -c "SHOW max_connections;"
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"
```

**Resolution:**
```bash
# 1. Restart PostgreSQL service
sudo systemctl restart postgresql

# 2. Verify database is responding
sudo -u postgres psql -c "SELECT NOW();"

# 3. Restart dependent services
sudo systemctl restart grafana

# 4. Check connection recovery
curl -k https://localhost:3002/grafana/api/health

# 5. Verify data consistency
# Check Grafana datasource connectivity via UI
```

## Maintenance Procedures

### Regular Maintenance Tasks

#### Daily Maintenance (Automated)
- **Log Rotation**: Automatic cleanup of logs > 7 days old
- **Metric Retention**: Prometheus data cleanup per retention policy
- **Security Updates**: Automated scanning for critical vulnerabilities
- **Health Checks**: Continuous monitoring via health check endpoints

#### Weekly Maintenance (Manual)
- **Resource Review**: Analyze resource utilization trends
- **Security Audit**: Review access logs and authentication events
- **Backup Verification**: Test backup restoration procedures
- **Configuration Drift**: Validate system configuration consistency

#### Monthly Maintenance (Scheduled)
- **Dependency Updates**: Update non-critical packages
- **Secret Rotation**: Rotate webhook secrets and certificates  
- **Performance Review**: Analyze performance trends and bottlenecks
- **Documentation Updates**: Update runbook and procedures

### System Updates

#### Minor Updates (Low Risk)
```bash
#!/bin/bash
# minor-update.sh

set -e

echo "=== RAVE Minor Update Procedure ==="

# 1. Create system snapshot
qemu-img snapshot -c "pre-update-$(date +%Y%m%d)" system.qcow2

# 2. Update system packages
nix flake update --commit-lock-file

# 3. Build updated image
nix build .#p2-production

# 4. Test updated image in staging
# (staging deployment procedure)

# 5. Deploy to production during maintenance window
# (standard deployment procedure)

echo "Minor update completed successfully"
```

#### Major Updates (High Risk)
```bash
#!/bin/bash
# major-update.sh

set -e

echo "=== RAVE Major Update Procedure ==="

# 1. Schedule maintenance window
echo "Maintenance window: $(date)"

# 2. Notify users of planned downtime
# (notification procedure)

# 3. Create full system backup
qemu-img snapshot -c "pre-major-update-$(date +%Y%m%d)" system.qcow2

# 4. Update and test in isolated environment
# (comprehensive testing procedure)

# 5. Deploy with rollback plan ready
# (deployment with rollback procedure)

# 6. Validate post-update functionality
# (full health check procedure)

echo "Major update completed successfully"
```

### Secret Rotation Procedures

#### Webhook Secret Rotation
```bash
#!/bin/bash
# rotate-webhook-secret.sh

set -e

echo "=== Webhook Secret Rotation ==="

# 1. Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# 2. Update GitLab webhook configuration
# (GitLab admin procedure)

# 3. Update secrets.yaml
sops -e --in-place secrets.yaml <<EOF
webhook:
  gitlab-secret: "$NEW_SECRET"
EOF

# 4. Restart secret-dependent services
sudo systemctl restart sops-nix
sudo systemctl restart webhook-dispatcher

# 5. Verify rotation success
curl -X POST https://localhost:3002/webhook \
  -H "X-Gitlab-Token: $NEW_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"test": "rotation"}'

echo "Webhook secret rotation completed"
```

#### SSL Certificate Renewal
```bash
#!/bin/bash  
# renew-ssl-certificate.sh

set -e

echo "=== SSL Certificate Renewal ==="

# 1. Generate new certificate request
# (Certificate authority procedure)

# 2. Receive new certificate and private key
# (Secure certificate delivery)

# 3. Update secrets.yaml
sops secrets.yaml
# Update tls/certificate and tls/private-key

# 4. Test certificate validity
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt newcert.pem

# 5. Deploy new certificate
sudo systemctl restart sops-nix
sudo systemctl restart traefik

# 6. Verify HTTPS functionality
curl -k -I https://localhost:3002/

echo "SSL certificate renewal completed"
```

## Performance Tuning

### SAFE Mode Optimization

#### Memory Optimization
```bash
# Configure system for memory-constrained operation
echo "=== SAFE Mode Memory Optimization ==="

# 1. Set memory limits for services
sudo systemctl set-property prometheus.service MemoryMax=256M
sudo systemctl set-property grafana.service MemoryMax=128M
sudo systemctl set-property postgresql.service MemoryMax=256M

# 2. Configure kernel memory management
echo 3 > /proc/sys/vm/drop_caches  # Clear caches
echo 1 > /proc/sys/vm/swappiness    # Minimize swap usage

# 3. Optimize Prometheus configuration
cat >> /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s
rule_files: []
scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:9090']
EOF

# 4. Restart services with new configuration
sudo systemctl daemon-reload
sudo systemctl restart prometheus
sudo systemctl restart grafana
```

#### CPU Optimization  
```bash
# Optimize CPU usage for 2-core systems
echo "=== SAFE Mode CPU Optimization ==="

# 1. Set CPU quotas for services
sudo systemctl set-property prometheus.service CPUQuota=50%
sudo systemctl set-property grafana.service CPUQuota=25%

# 2. Configure process priorities
sudo systemctl set-property traefik.service Nice=-5      # Higher priority
sudo systemctl set-property prometheus.service Nice=5  # Lower priority

# 3. Optimize Nix build settings
export NIX_BUILD_CORES=2
export NIX_MAX_JOBS=1

# 4. Verify CPU optimization
systemd-cgtop --depth=2
```

### Performance Monitoring

#### Real-time Performance Dashboard
```bash
#!/bin/bash
# performance-dashboard.sh

while true; do
  clear
  echo "=== RAVE Performance Dashboard ==="
  echo "Timestamp: $(date)"
  echo ""
  
  echo "=== Memory Usage ==="
  free -h
  echo ""
  
  echo "=== CPU Usage ==="
  top -b -n1 | head -5
  echo ""
  
  echo "=== Service Status ==="
  systemctl status traefik grafana prometheus postgresql --no-pager -l
  echo ""
  
  echo "=== Network Connections ==="
  netstat -tulpn | grep -E ':3002|:3030|:9090|:5432'
  echo ""
  
  echo "Press Ctrl+C to exit"
  sleep 10
done
```

## Troubleshooting Guide

### Common Issues & Solutions

#### Issue: High CPU Usage
**Symptoms:** System slowness, high load average
**Diagnosis:**
```bash
top -c
htop
iotop
```
**Solution:**
```bash
# Identify CPU-intensive processes
ps aux --sort=-%cpu | head -20

# Check for runaway processes
systemd-cgtop

# Restart services consuming excessive CPU
sudo systemctl restart <service-name>
```

#### Issue: Disk Space Full
**Symptoms:** Write errors, service failures
**Diagnosis:**
```bash
df -h
du -sh /var/log/*
du -sh /nix/store/*
```
**Solution:**
```bash
# Clean up logs
sudo journalctl --vacuum-time=7d

# Clean Nix store
sudo nix-collect-garbage -d

# Clean up temporary files
sudo rm -rf /tmp/*
```

#### Issue: Network Connectivity Problems
**Symptoms:** External API failures, package download failures
**Diagnosis:**
```bash
ping 8.8.8.8
dig cache.nixos.org
traceroute nix-community.cachix.org
```
**Solution:**
```bash
# Check firewall rules
sudo iptables -L -n

# Restart networking
sudo systemctl restart systemd-networkd

# Verify DNS resolution
cat /etc/resolv.conf
```

### Diagnostic Commands Reference

```bash
# System Information
uname -a                    # System information
lscpu                      # CPU information  
lsmem                      # Memory information
lsblk                      # Block devices
ip addr show               # Network interfaces

# Service Management
systemctl status <service> # Service status
journalctl -u <service>    # Service logs
systemctl list-failed     # Failed services
systemd-analyze           # Boot performance

# Resource Monitoring
free -h                    # Memory usage
df -h                      # Disk usage
iostat 1 5                # I/O statistics
netstat -tulpn            # Network connections
ss -tulpn                 # Socket statistics

# Process Analysis
ps aux                     # Process list
htop                      # Interactive process viewer
pstree                    # Process tree
lsof                      # Open files

# Network Diagnostics  
ping <host>               # Connectivity test
traceroute <host>         # Route tracing
nmap <host>               # Port scanning
tcpdump -i eth0           # Packet capture
```

---

**Document Classification**: Internal Use  
**Last Updated**: 2024-12-28  
**On-Call Rotation**: https://oncall.organization.com/rave  
**Incident Tracking**: https://incidents.organization.com/rave
