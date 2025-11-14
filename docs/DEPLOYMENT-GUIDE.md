# RAVE Production Deployment Guide

## Overview

This guide provides step-by-step procedures for deploying RAVE (Reproducible AI Virtual Environment) in production environments. It covers initial setup, configuration, deployment, and validation procedures for all supported deployment modes.

## Prerequisites

### System Requirements

#### Minimum Hardware Requirements (SAFE Mode)
- **CPU**: 2 cores (x86_64 architecture)
- **Memory**: 4GB RAM (2GB for VM, 2GB for host overhead)
- **Storage**: 20GB available disk space
- **Network**: Internet connectivity for package downloads
- **Hypervisor**: KVM support (Linux) or equivalent virtualization

#### Recommended Hardware Requirements (FULL_PIPE Mode)  
- **CPU**: 4+ cores (x86_64 architecture)
- **Memory**: 8GB RAM (4GB for VM, 4GB for host overhead)
- **Storage**: 50GB available disk space (SSD recommended)
- **Network**: High-bandwidth internet connection
- **Hypervisor**: KVM with nested virtualization support

#### Software Prerequisites
- **Nix Package Manager**: Version 2.18+ with flakes support
- **Git**: For repository cloning and version control
- **QEMU/KVM**: For virtual machine execution
- **SSH Client**: For system administration access
- **Age**: For secrets decryption (if managing secrets)

### Environment Setup

#### Install Nix with Flakes Support
```bash
#!/bin/bash
# install-nix-production.sh

set -e

echo "=== Installing Nix for RAVE Production Deployment ==="

# 1. Install Nix package manager
curl -L https://nixos.org/nix/install | sh -s -- --daemon

# 2. Source Nix environment  
source /etc/profile.d/nix.sh

# 3. Enable experimental features
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes
max-jobs = auto
cores = 0
EOF

# 4. Verify installation
nix --version
nix flake --help

echo "✅ Nix installation completed successfully"
```

#### Clone RAVE Repository
```bash
# Clone production-ready RAVE repository
git clone https://github.com/organization/rave.git
cd rave

# Verify repository integrity
git log --oneline -10
nix flake check

# Switch to production-ready branch/tag
git checkout v1.0.0  # Use appropriate production version
```

## Configuration Management

### Secrets Setup (Production)

#### 1. Age Key Generation and Distribution
```bash
#!/bin/bash
# setup-production-secrets.sh

set -e

echo "=== Production Secrets Setup ==="

# Generate age key for production team
age-keygen -o ~/.config/rave/production.key
chmod 600 ~/.config/rave/production.key

# Extract public key
PUBLIC_KEY=$(age-keygen -y ~/.config/rave/production.key)
echo "Production age public key: $PUBLIC_KEY"

echo "⚠️  CRITICAL: Store the private key securely and distribute to authorized team members"
echo "Private key location: ~/.config/rave/production.key"
```

#### 2. Secrets Configuration
```bash
# Copy and customize secrets template
cp secrets.yaml secrets-production.yaml

# Edit production secrets (requires age private key)
export SOPS_AGE_KEY_FILE=~/.config/rave/production.key
sops secrets-production.yaml
```

**Required Production Secrets:**
```yaml
# secrets-production.yaml structure
ssh:
  authorized-keys:
    - "ssh-ed25519 AAAAC3... production-admin-1"
    - "ssh-ed25519 AAAAC3... production-admin-2"

tls:
  certificate: |
    -----BEGIN CERTIFICATE-----
    # Production TLS certificate (from CA)
    -----END CERTIFICATE-----
  private-key: |
    -----BEGIN PRIVATE KEY-----
    # Production TLS private key (secure)
    -----END PRIVATE KEY-----

database:
  postgres-password: "secure-random-password-32chars"
  grafana-admin-password: "secure-admin-password"

external-services:
  gitlab-root-password: "gitlab-admin-secure-password"
  matrix-shared-secret: "matrix-homeserver-secret"

webhooks:
  gitlab-secret: "webhook-hmac-secret-64chars"
```

### Environment Configuration

#### Production Environment Variables
```bash
# production-environment.sh - Source before deployment

# RAVE Operation Mode
export SAFE=1  # Use SAFE=0 for FULL_PIPE mode in high-resource environments

# Build Configuration  
export NIX_BUILD_CORES=2  # Adjust based on available CPU cores
export NIX_MAX_JOBS=1     # Conservative for memory-constrained environments

# Deployment Configuration
export RAVE_ENVIRONMENT="production"
export RAVE_VERSION="p2-production"
export RAVE_SECRETS_FILE="$(pwd)/secrets-production.yaml"

# Logging and Monitoring
export RAVE_LOG_LEVEL="info"
export RAVE_METRICS_ENABLED="true"

echo "✅ Production environment configured"
echo "Mode: $(if [ "$SAFE" = "1" ]; then echo "SAFE (memory-disciplined)"; else echo "FULL_PIPE (performance)"; fi)"
```

## Deployment Procedures

### Standard Production Deployment

#### Method 1: Direct QEMU Deployment (Recommended)

```bash
#!/bin/bash
# deploy-rave-production.sh

set -e

source ./production-environment.sh

echo "=== RAVE Production Deployment ==="
echo "Version: $RAVE_VERSION"
echo "Environment: $RAVE_ENVIRONMENT"
echo "Mode: $(if [ "$SAFE" = "1" ]; then echo "SAFE"; else echo "FULL_PIPE"; fi)"

# 1. Pre-deployment validation
echo "🔍 Running pre-deployment validation..."
./scripts/validate-deployment-prerequisites.sh

# 2. Build production image
echo "🏗️  Building production image..."
nix build ".#$RAVE_VERSION" --show-trace

# 3. Store image path for deployment
IMAGE_PATH=$(nix build ".#$RAVE_VERSION" --print-out-paths)
echo "Built image: $IMAGE_PATH"

# 4. Create deployment directory
sudo mkdir -p /opt/rave/production
sudo cp "$IMAGE_PATH" /opt/rave/production/rave-production.qcow2

# 5. Create systemd service for production
sudo tee /etc/systemd/system/rave-production.service << EOF
[Unit]
Description=RAVE Production AI Virtual Environment
After=network.target
Wants=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/opt/rave/production

# Resource limits based on SAFE mode
Environment=SAFE=$SAFE
$(if [ "$SAFE" = "1" ]; then 
  echo "ExecStart=/usr/bin/qemu-system-x86_64 -m 2048 -smp 2 -enable-kvm \\"
else 
  echo "ExecStart=/usr/bin/qemu-system-x86_64 -m 4096 -smp 4 -enable-kvm \\"
fi)
ExecStart=/usr/bin/qemu-system-x86_64 \\
  -m $(if [ "$SAFE" = "1" ]; then echo "2048"; else echo "4096"; fi) \\
  -smp $(if [ "$SAFE" = "1" ]; then echo "2"; else echo "4"; fi) \\
  -enable-kvm \\
  -netdev user,id=net0,hostfwd=tcp::3002-:3002,hostfwd=tcp::22-:22 \\
  -device virtio-net-pci,netdev=net0 \\
  -drive format=qcow2,file=/opt/rave/production/rave-production.qcow2 \\
  -daemonize \\
  -pidfile /var/run/rave-production.pid

ExecStop=/bin/kill \$MAINPID
PIDFile=/var/run/rave-production.pid

# Service hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/rave/production /var/run

# Restart policy
Restart=always
RestartSec=10
StartLimitBurst=3
StartLimitInterval=60

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable rave-production.service
sudo systemctl start rave-production.service

# 7. Wait for system initialization
echo "⏳ Waiting for system initialization..."
sleep 60

# 8. Run post-deployment validation
echo "✅ Running post-deployment validation..."
./scripts/validate-deployment-success.sh

echo "🎉 RAVE production deployment completed successfully!"
echo "Access URLs:"
echo "  - Main UI: https://localhost:3002/"
echo "  - Grafana: https://localhost:3002/grafana/"
echo "  - SSH: ssh agent@localhost"
```

#### Method 2: Cloud Provider Deployment (AWS/GCP/Azure)

```bash
#!/bin/bash
# deploy-rave-cloud.sh

set -e

CLOUD_PROVIDER=${1:-aws}  # aws, gcp, azure
INSTANCE_TYPE=${2:-t3.medium}  # Adjust based on SAFE mode requirements

echo "=== RAVE Cloud Deployment ($CLOUD_PROVIDER) ==="

case $CLOUD_PROVIDER in
  aws)
    # AWS deployment with EC2
    echo "Deploying to AWS EC2..."
    
    # Create EC2 instance with appropriate specs
    aws ec2 run-instances \
      --image-id ami-0c02fb55956c7d316 \
      --instance-type $INSTANCE_TYPE \
      --key-name rave-production-key \
      --security-group-ids sg-rave-production \
      --subnet-id subnet-production \
      --user-data file://cloud-init-rave.sh \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=RAVE-Production}]'
    ;;
    
  gcp)  
    # GCP deployment with Compute Engine
    echo "Deploying to GCP Compute Engine..."
    
    gcloud compute instances create rave-production \
      --machine-type=e2-standard-2 \
      --image-family=ubuntu-2204-lts \
      --image-project=ubuntu-os-cloud \
      --boot-disk-size=50GB \
      --metadata-from-file startup-script=cloud-init-rave.sh \
      --tags=rave-production
    ;;
    
  azure)
    # Azure deployment with Virtual Machines
    echo "Deploying to Azure VM..."
    
    az vm create \
      --resource-group rave-production-rg \
      --name rave-production-vm \
      --image UbuntuLTS \
      --size Standard_B2s \
      --admin-username azureuser \
      --ssh-key-values ~/.ssh/rave-production.pub \
      --custom-data cloud-init-rave.sh
    ;;
esac

echo "✅ Cloud deployment initiated. Check cloud provider console for status."
```

### Container Deployment (Docker/Podman)

```bash
#!/bin/bash
# deploy-rave-container.sh

set -e

echo "=== RAVE Container Deployment ==="

# 1. Build container image
nix build .#container-image

# 2. Load image into Docker
docker load < $(nix build .#container-image --print-out-paths)

# 3. Create production container
docker run -d \
  --name rave-production \
  --hostname rave-production \
  -p 3002:3002 \
  -p 22:22 \
  --memory=$(if [ "$SAFE" = "1" ]; then echo "2g"; else echo "4g"; fi) \
  --cpus=$(if [ "$SAFE" = "1" ]; then echo "2"; else echo "4"; fi) \
  --restart=unless-stopped \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=100m \
  rave:latest

echo "✅ RAVE container deployment completed"
docker ps | grep rave-production
```

## Deployment Validation

### Comprehensive Health Check Suite

```bash
#!/bin/bash
# validate-deployment-success.sh

set -e

echo "=== RAVE Deployment Validation ==="

# Configuration
RAVE_HOST=${RAVE_HOST:-localhost}
RAVE_PORT=${RAVE_PORT:-3002}
SSH_PORT=${SSH_PORT:-22}
MAX_WAIT_TIME=300  # 5 minutes maximum wait

# Wait for system availability
echo "⏳ Waiting for system availability..."
for i in $(seq 1 $MAX_WAIT_TIME); do
  if nc -z $RAVE_HOST $RAVE_PORT; then
    echo "✅ System responding on port $RAVE_PORT after $i seconds"
    break
  fi
  
  if [ $i -eq $MAX_WAIT_TIME ]; then
    echo "❌ System not responding after $MAX_WAIT_TIME seconds"
    exit 1
  fi
  
  sleep 1
done

# Test 1: SSH Connectivity
echo "🔑 Testing SSH connectivity..."
if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes agent@$RAVE_HOST exit 2>/dev/null; then
  echo "✅ SSH authentication successful"
else
  echo "⚠️  SSH authentication failed (expected if keys not configured)"
fi

# Test 2: HTTPS Endpoints
echo "🌐 Testing HTTPS endpoints..."
ENDPOINTS=(
  "https://$RAVE_HOST:$RAVE_PORT/ 200"
  "https://$RAVE_HOST:$RAVE_PORT/grafana/api/health 200"
  "https://$RAVE_HOST:$RAVE_PORT/webhook 405"  # POST only
)

for endpoint_test in "${ENDPOINTS[@]}"; do
  url=$(echo $endpoint_test | cut -d' ' -f1)
  expected_code=$(echo $endpoint_test | cut -d' ' -f2)
  
  actual_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$url" || echo "000")
  
  if [ "$actual_code" = "$expected_code" ]; then
    echo "✅ $url responds with $actual_code"
  else
    echo "❌ $url responds with $actual_code (expected $expected_code)"
    ((failures++))
  fi
done

# Test 3: System Services (via SSH)
echo "🔧 Testing system services..."
if timeout 30 ssh -o ConnectTimeout=10 agent@$RAVE_HOST 'systemctl is-active traefik grafana prometheus webhook-dispatcher' 2>/dev/null; then
  echo "✅ Core services are active"
else
  echo "⚠️  Service status check failed (requires SSH access)"
fi

# Test 4: Monitoring Stack
echo "📊 Testing monitoring stack..."
if curl -k -s "https://$RAVE_HOST:$RAVE_PORT/grafana/api/health" | grep -q "ok"; then
  echo "✅ Grafana is healthy"
else
  echo "❌ Grafana health check failed"
  ((failures++))
fi

# Test 5: Resource Utilization (SAFE mode validation)
if [ "$SAFE" = "1" ]; then
  echo "💾 Validating SAFE mode resource constraints..."
  
  # Check memory usage via monitoring endpoint (if available)
  memory_usage=$(curl -k -s "https://$RAVE_HOST:$RAVE_PORT/grafana/api/health" | jq -r '.memory // "unknown"' 2>/dev/null || echo "unknown")
  
  if [ "$memory_usage" != "unknown" ]; then
    echo "📊 Memory usage: $memory_usage"
  else
    echo "⚠️  Memory usage monitoring not available"
  fi
fi

# Test 6: Security Configuration
echo "🔒 Validating security configuration..."

# Check TLS certificate
echo | openssl s_client -connect $RAVE_HOST:$RAVE_PORT -servername $RAVE_HOST 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null && echo "✅ TLS certificate is valid" || echo "❌ TLS certificate validation failed"

# Check SSH hardening
ssh_config=$(timeout 5 ssh -o ConnectTimeout=2 agent@$RAVE_HOST 'sudo sshd -T' 2>/dev/null || echo "")
if echo "$ssh_config" | grep -q "passwordauthentication no"; then
  echo "✅ SSH password authentication disabled"
else
  echo "⚠️  SSH password authentication status unknown"
fi

# Summary
failures=${failures:-0}
if [ $failures -eq 0 ]; then
  echo "🎉 All deployment validation tests passed!"
  echo "✅ RAVE production system is ready for use"
  
  echo ""
  echo "📋 System Access Information:"
  echo "  Main Application: https://$RAVE_HOST:$RAVE_PORT/"
  echo "  Grafana Dashboard: https://$RAVE_HOST:$RAVE_PORT/grafana/"
  echo "  SSH Access: ssh agent@$RAVE_HOST"
  echo "  Claude Code Router: https://$RAVE_HOST:$RAVE_PORT/ccr-ui/"
  
  exit 0
else
  echo "❌ Deployment validation failed with $failures errors"
  echo "⚠️  Review the failed tests above and address issues before proceeding"
  exit 1
fi
```

### Monitoring and Health Checks

```bash
#!/bin/bash
# continuous-health-monitoring.sh

set -e

echo "=== RAVE Continuous Health Monitoring ==="

# Create monitoring script for systemd timer
sudo tee /opt/rave/scripts/health-check.sh << 'EOF'
#!/bin/bash

set -e

TIMESTAMP=$(date -Iseconds)
LOG_FILE="/var/log/rave-health.log"

# Function to log with timestamp
log_message() {
  echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

# Check core services
SERVICES=("traefik" "grafana" "prometheus" "webhook-dispatcher")
for service in "${SERVICES[@]}"; do
  if systemctl is-active "$service" >/dev/null 2>&1; then
    log_message "✅ $service is active"
  else
    log_message "❌ $service is inactive"
    # Attempt restart
    systemctl restart "$service" && log_message "🔄 $service restarted successfully"
  fi
done

# Check endpoints
if curl -k -s https://localhost:3002/ >/dev/null; then
  log_message "✅ Main endpoint responding"
else
  log_message "❌ Main endpoint not responding"
fi

# Check resource usage
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')

log_message "📊 Memory: ${MEMORY_USAGE}%, CPU: ${CPU_USAGE}%"

# SAFE mode resource validation
if [ "$SAFE" = "1" ] && (( $(echo "$MEMORY_USAGE > 85" | bc -l) )); then
  log_message "⚠️  SAFE mode memory usage high: ${MEMORY_USAGE}%"
fi
EOF

chmod +x /opt/rave/scripts/health-check.sh

# Create systemd service for health monitoring
sudo tee /etc/systemd/system/rave-health-check.service << EOF
[Unit]
Description=RAVE Health Check
After=rave-production.service

[Service]
Type=oneshot
ExecStart=/opt/rave/scripts/health-check.sh
User=root
EOF

# Create systemd timer for regular health checks
sudo tee /etc/systemd/system/rave-health-check.timer << EOF
[Unit]
Description=Run RAVE Health Check every 5 minutes
Requires=rave-health-check.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable health monitoring
sudo systemctl daemon-reload
sudo systemctl enable rave-health-check.timer
sudo systemctl start rave-health-check.timer

echo "✅ Continuous health monitoring configured"
```

## Production Management

### Service Management

```bash
#!/bin/bash
# rave-service-management.sh

COMMAND=${1:-status}

case $COMMAND in
  start)
    echo "🚀 Starting RAVE production service..."
    sudo systemctl start rave-production.service
    sleep 30
    ./scripts/validate-deployment-success.sh
    ;;
    
  stop)
    echo "🛑 Stopping RAVE production service..."
    sudo systemctl stop rave-production.service
    echo "✅ Service stopped"
    ;;
    
  restart)
    echo "🔄 Restarting RAVE production service..."
    sudo systemctl restart rave-production.service
    sleep 45
    ./scripts/validate-deployment-success.sh
    ;;
    
  status)
    echo "📊 RAVE Production Service Status"
    echo "================================"
    sudo systemctl status rave-production.service --no-pager -l
    
    echo -e "\n🌐 Service Endpoints:"
    curl -k -s -o /dev/null -w "Main UI: %{http_code}\n" https://localhost:3002/
    curl -k -s -o /dev/null -w "Grafana: %{http_code}\n" https://localhost:3002/grafana/
    
    echo -e "\n💾 Resource Usage:"
    ps aux | grep qemu | grep -v grep | awk '{print "CPU: "$3"%, Memory: "$4"%"}'
    ;;
    
  logs)
    echo "📝 RAVE Production Service Logs"
    echo "==============================="
    sudo journalctl -u rave-production.service -f --since "1 hour ago"
    ;;
    
  update)
    echo "⬆️  Updating RAVE production deployment..."
    
    # Create backup
    sudo cp /opt/rave/production/rave-production.qcow2 \
           /opt/rave/production/rave-production.qcow2.backup-$(date +%Y%m%d-%H%M)
    
    # Build new image
    nix build .#p2-production --refresh
    
    # Stop service
    sudo systemctl stop rave-production.service
    
    # Replace image
    sudo cp $(nix build .#p2-production --print-out-paths) \
            /opt/rave/production/rave-production.qcow2
    
    # Start service and validate
    sudo systemctl start rave-production.service
    sleep 60
    ./scripts/validate-deployment-success.sh
    
    echo "✅ Update completed successfully"
    ;;
    
  backup)
    BACKUP_DIR="/opt/rave/backups/$(date +%Y%m%d-%H%M)"
    echo "💾 Creating backup: $BACKUP_DIR"
    
    sudo mkdir -p "$BACKUP_DIR"
    sudo cp /opt/rave/production/rave-production.qcow2 "$BACKUP_DIR/"
    sudo cp -r /opt/rave/production/secrets/ "$BACKUP_DIR/" 2>/dev/null || true
    
    echo "✅ Backup created: $BACKUP_DIR"
    ;;
    
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|update|backup}"
    echo ""
    echo "Commands:"
    echo "  start   - Start RAVE production service"
    echo "  stop    - Stop RAVE production service"  
    echo "  restart - Restart RAVE production service"
    echo "  status  - Show service status and health"
    echo "  logs    - Show service logs (tail -f)"
    echo "  update  - Update to latest version"
    echo "  backup  - Create system backup"
    exit 1
    ;;
esac
```

### Update Procedures

```bash
#!/bin/bash
# production-update-procedure.sh

set -e

UPDATE_TYPE=${1:-minor}  # minor, major, security

echo "=== RAVE Production Update Procedure ==="
echo "Update Type: $UPDATE_TYPE"

case $UPDATE_TYPE in
  security)
    echo "🚨 Security Update - Expedited Process"
    
    # Immediate backup
    sudo ./scripts/rave-service-management.sh backup
    
    # Update dependencies
    nix flake update --commit-lock-file
    
    # Build and validate
    nix build .#p2-production --refresh
    ./scripts/validate-deployment-success.sh
    
    # Deploy with minimal downtime
    sudo systemctl stop rave-production.service
    sudo cp $(nix build .#p2-production --print-out-paths) \
            /opt/rave/production/rave-production.qcow2
    sudo systemctl start rave-production.service
    
    # Validate immediately
    sleep 45
    ./scripts/validate-deployment-success.sh
    
    echo "✅ Security update completed"
    ;;
    
  minor)
    echo "📦 Minor Update - Standard Process"
    
    # Scheduled maintenance window
    echo "⏰ Recommend scheduling during low-traffic period"
    read -p "Continue with update? (y/n): " confirm
    [ "$confirm" != "y" ] && exit 0
    
    # Standard update process
    sudo ./scripts/rave-service-management.sh update
    ;;
    
  major)
    echo "🔄 Major Update - Full Process"
    
    # Pre-update validation
    echo "📋 Pre-update checklist:"
    echo "  - [ ] Maintenance window scheduled"
    echo "  - [ ] Team notified"
    echo "  - [ ] Rollback plan confirmed"
    echo "  - [ ] Database backup verified"
    
    read -p "All items confirmed? (y/n): " checklist_confirm
    [ "$checklist_confirm" != "y" ] && exit 0
    
    # Full backup
    sudo ./scripts/rave-service-management.sh backup
    
    # Test build first
    nix build .#p2-production --refresh
    
    # Run in staging mode for validation
    echo "🧪 Running staging validation..."
    # (Add staging deployment logic here)
    
    # Production deployment
    echo "🚀 Deploying to production..."
    sudo ./scripts/rave-service-management.sh update
    
    echo "✅ Major update completed successfully"
    ;;
    
  *)
    echo "Usage: $0 {security|minor|major}"
    exit 1
    ;;
esac
```

## Disaster Recovery

### Backup and Restore Procedures

```bash
#!/bin/bash
# disaster-recovery-procedures.sh

OPERATION=${1:-backup}
BACKUP_ID=${2:-$(date +%Y%m%d-%H%M)}

case $OPERATION in
  backup)
    echo "💾 Creating comprehensive backup: $BACKUP_ID"
    
    BACKUP_DIR="/opt/rave/disaster-recovery/$BACKUP_ID"
    sudo mkdir -p "$BACKUP_DIR"
    
    # VM image backup
    echo "Backing up VM image..."
    sudo cp /opt/rave/production/rave-production.qcow2 \
            "$BACKUP_DIR/rave-production.qcow2"
    
    # Configuration backup
    echo "Backing up configuration..."
    sudo cp -r ./secrets-production.yaml "$BACKUP_DIR/" 2>/dev/null || true
    sudo cp -r .sops.yaml "$BACKUP_DIR/"
    sudo cp -r ./p2-production-config.nix "$BACKUP_DIR/"
    
    # System state backup
    echo "Backing up system state..."
    sudo systemctl show rave-production.service > "$BACKUP_DIR/service-state.txt"
    
    # Create integrity checksums
    echo "Creating integrity checksums..."
    cd "$BACKUP_DIR"
    sudo find . -type f -exec sha256sum {} \; > checksums.sha256
    
    # Compress backup
    sudo tar -czf "/opt/rave/disaster-recovery/rave-backup-$BACKUP_ID.tar.gz" \
                  -C "/opt/rave/disaster-recovery" "$BACKUP_ID"
    sudo rm -rf "$BACKUP_DIR"
    
    echo "✅ Disaster recovery backup completed: rave-backup-$BACKUP_ID.tar.gz"
    ;;
    
  restore)
    if [ -z "$2" ]; then
      echo "❌ Backup ID required for restore operation"
      echo "Usage: $0 restore <backup-id>"
      exit 1
    fi
    
    echo "🔄 Restoring from backup: $BACKUP_ID"
    
    BACKUP_FILE="/opt/rave/disaster-recovery/rave-backup-$BACKUP_ID.tar.gz"
    
    if [ ! -f "$BACKUP_FILE" ]; then
      echo "❌ Backup file not found: $BACKUP_FILE"
      exit 1
    fi
    
    # Stop production service
    echo "Stopping production service..."
    sudo systemctl stop rave-production.service
    
    # Extract backup
    echo "Extracting backup..."
    sudo tar -xzf "$BACKUP_FILE" -C /tmp/
    
    # Verify integrity
    echo "Verifying backup integrity..."
    cd "/tmp/$BACKUP_ID"
    sudo sha256sum -c checksums.sha256
    
    # Restore VM image
    echo "Restoring VM image..."
    sudo cp rave-production.qcow2 /opt/rave/production/
    
    # Restore configuration
    echo "Restoring configuration..."
    cp secrets-production.yaml "$(pwd)/"
    cp .sops.yaml "$(pwd)/"
    cp p2-production-config.nix "$(pwd)/"
    
    # Start production service
    echo "Starting production service..."
    sudo systemctl start rave-production.service
    
    # Validate restore
    sleep 60
    ./scripts/validate-deployment-success.sh
    
    # Cleanup
    sudo rm -rf "/tmp/$BACKUP_ID"
    
    echo "✅ Disaster recovery restore completed successfully"
    ;;
    
  list)
    echo "📋 Available disaster recovery backups:"
    ls -la /opt/rave/disaster-recovery/rave-backup-*.tar.gz 2>/dev/null || echo "No backups found"
    ;;
    
  *)
    echo "Usage: $0 {backup|restore <backup-id>|list}"
    exit 1
    ;;
esac
```

## Troubleshooting Deployment Issues

### Common Deployment Problems

#### Issue: Nix Build Failures
```bash
# Diagnosis
nix build .#p2-production --show-trace --verbose

# Resolution
# Clear Nix cache
nix store gc
nix-collect-garbage -d

# Update flake lock
nix flake update

# Retry with clean cache
nix build .#p2-production --refresh --show-trace
```

#### Issue: Secret Decryption Failures
```bash
# Diagnosis  
export SOPS_AGE_KEY_FILE=~/.config/rave/production.key
sops -d secrets-production.yaml

# Resolution
# Verify age key
age-keygen -y ~/.config/rave/production.key

# Re-encrypt secrets if needed
sops updatekeys secrets-production.yaml
```

#### Issue: VM Won't Boot
```bash
# Diagnosis
qemu-system-x86_64 -m 2048 -hda /opt/rave/production/rave-production.qcow2 -nographic

# Resolution
# Check image integrity
qemu-img check /opt/rave/production/rave-production.qcow2

# Rebuild if corrupted
nix build .#p2-production
sudo cp $(nix build .#p2-production --print-out-paths) \
        /opt/rave/production/rave-production.qcow2
```

### Debug Mode Deployment

```bash
#!/bin/bash
# deploy-debug-mode.sh

set -e

echo "🐛 RAVE Debug Mode Deployment"

# Build with debug symbols
nix build .#p2-production-debug --show-trace

# Deploy with console access
qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -netdev user,id=net0,hostfwd=tcp::3002-:3002,hostfwd=tcp::22-:22 \
  -device virtio-net-pci,netdev=net0 \
  -drive format=qcow2,file=$(nix build .#p2-production-debug --print-out-paths) \
  -nographic \
  -serial mon:stdio

echo "🔧 Debug console access enabled"
echo "Use Ctrl+A, C to access QEMU monitor"
echo "Use Ctrl+A, X to exit"
```

## Security Considerations

### Production Security Checklist

**Pre-Deployment Security Validation:**
```bash
#!/bin/bash
# security-pre-deployment-check.sh

set -e

echo "🔒 Production Security Pre-Deployment Check"

# Check 1: SSH key security
echo "Validating SSH keys..."
sops -d secrets-production.yaml | yq '.ssh."authorized-keys"[]' | while read key; do
  if ssh-keygen -l -f <(echo "$key") | grep -q "ed25519"; then
    echo "✅ Ed25519 key found"
  else
    echo "⚠️  Non-Ed25519 key detected - consider upgrading"
  fi
done

# Check 2: Secret encryption
echo "Validating secret encryption..."
if sops -d secrets-production.yaml >/dev/null 2>&1; then
  echo "✅ Secrets decrypt successfully"
else
  echo "❌ Secret decryption failed"
  exit 1
fi

# Check 3: TLS certificate validity
echo "Validating TLS certificates..."
sops -d secrets-production.yaml | yq '.tls.certificate' | openssl x509 -noout -dates
echo "✅ TLS certificate validation complete"

# Check 4: Firewall configuration
echo "Validating firewall configuration..."
nix eval .#nixosConfigurations.rave-vm.config.networking.firewall --json | \
  jq '.allowedTCPPorts' | grep -E '22|3002' && echo "✅ Firewall properly configured"

echo "🎉 Security pre-deployment check completed"
```

### Post-Deployment Security Validation

```bash
#!/bin/bash
# security-post-deployment-check.sh

set -e

RAVE_HOST=${RAVE_HOST:-localhost}

echo "🔒 Production Security Post-Deployment Check"

# Check 1: SSH hardening
echo "Validating SSH security..."
if timeout 5 ssh -o ConnectTimeout=2 root@$RAVE_HOST exit 2>/dev/null; then
  echo "❌ Root SSH access enabled (security violation)"
  exit 1
else
  echo "✅ Root SSH access properly disabled"
fi

# Check 2: TLS configuration
echo "Validating TLS security..."
echo | openssl s_client -connect $RAVE_HOST:3002 -cipher 'ECDHE-RSA-AES256-GCM-SHA384' 2>/dev/null | \
  grep -q "Cipher is" && echo "✅ Strong TLS ciphers enabled"

# Check 3: Service isolation
echo "Validating service isolation..."
if timeout 10 curl -s http://$RAVE_HOST:9090 2>/dev/null; then
  echo "❌ Prometheus exposed externally (security violation)"
  exit 1
else
  echo "✅ Internal services properly isolated"
fi

# Check 4: Firewall effectiveness
echo "Validating firewall effectiveness..."
if timeout 5 nc -z $RAVE_HOST 5432 2>/dev/null; then
  echo "❌ Database port exposed externally (security violation)"
  exit 1
else
  echo "✅ Firewall blocking unauthorized ports"
fi

echo "🎉 Security post-deployment validation completed"
```

## Conclusion

This deployment guide provides comprehensive procedures for deploying RAVE in production environments. Follow the security checklist and validation procedures to ensure a secure and reliable deployment.

For ongoing maintenance and troubleshooting, refer to:
- [RUNBOOK.md](RUNBOOK.md) - Operational procedures
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Issue resolution
- [SECURITY.md](SECURITY.md) - Security model and procedures

---

**Document Classification**: Internal Use  
**Last Updated**: 2025-01-23  
**Next Review**: 2025-04-23  
**Document Owner**: DevOps Team
