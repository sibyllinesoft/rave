# RAVE Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide provides systematic approaches to diagnosing and resolving issues in RAVE (Reproducible AI Virtual Environment) production deployments. It includes common problem patterns, diagnostic procedures, and step-by-step resolution workflows.

## Troubleshooting Framework

### Systematic Diagnostic Approach

1. **Symptom Collection**: Gather observable symptoms and error messages
2. **Context Analysis**: Determine when the issue started and environmental factors
3. **Component Isolation**: Identify which system components are affected
4. **Root Cause Analysis**: Use diagnostic tools to identify underlying causes
5. **Resolution Implementation**: Apply targeted fixes with minimal disruption
6. **Verification**: Confirm resolution and prevent recurrence

### Diagnostic Tool Hierarchy

```bash
# Level 1: Basic System Health
systemctl status rave-production.service
curl -k https://localhost:3002/
journalctl -u rave-production.service --since "30 minutes ago"

# Level 2: Component Analysis
ssh agent@localhost systemctl status nginx grafana prometheus
curl -k https://localhost:3002/grafana/api/health
curl http://localhost:9090/-/ready

# Level 3: Deep Diagnostics
ssh agent@localhost 'ps aux | grep -E "(nginx|grafana|prometheus)"'
ssh agent@localhost 'netstat -tulpn | grep -E ":3002|:3030|:9090"'
ssh agent@localhost 'free -h && df -h'

# Level 4: VM-Level Diagnostics  
virsh list --all
qemu-img info /opt/rave/production/rave-production.qcow2
```

## Common Issues and Solutions

### 1. System Startup and Boot Issues

#### Issue: VM Fails to Boot
**Symptoms:**
- QEMU process exits immediately
- No response on expected ports (3002, 22)
- VM process not visible in `ps` output

**Diagnostic Steps:**
```bash
#!/bin/bash
# diagnose-boot-failure.sh

echo "=== VM Boot Failure Diagnosis ==="

# Check QEMU image integrity
echo "Checking VM image integrity..."
if qemu-img check /opt/rave/production/rave-production.qcow2; then
  echo "✅ VM image integrity OK"
else
  echo "❌ VM image corrupted - rebuild required"
  exit 1
fi

# Check available system resources
echo "Checking system resources..."
echo "Memory: $(free -h | awk 'NR==2{print $7" available"}')"
echo "Disk: $(df -h /opt/rave/production | awk 'NR==2{print $4" available"}')"

# Verify KVM support
if [ -r /dev/kvm ]; then
  echo "✅ KVM acceleration available"
else
  echo "❌ KVM acceleration not available - check virtualization support"
fi

# Check for conflicting processes
echo "Checking for conflicting QEMU processes..."
ps aux | grep qemu | grep -v grep

# Test boot with console output
echo "Attempting boot with console output..."
timeout 60 qemu-system-x86_64 \
  -m 2048 \
  -smp 2 \
  -enable-kvm \
  -hda /opt/rave/production/rave-production.qcow2 \
  -nographic \
  -serial mon:stdio &

sleep 10
echo "Boot test initiated - check console output above"
```

**Resolution Steps:**
```bash
#!/bin/bash
# resolve-boot-failure.sh

set -e

ISSUE_TYPE=${1:-image}

case $ISSUE_TYPE in
  image)
    echo "🔧 Rebuilding corrupted VM image..."
    
    # Backup current image
    sudo cp /opt/rave/production/rave-production.qcow2 \
           /opt/rave/production/rave-production.qcow2.corrupted-$(date +%Y%m%d-%H%M)
    
    # Rebuild fresh image
    nix build .#p2-production --refresh
    sudo cp $(nix build .#p2-production --print-out-paths) \
            /opt/rave/production/rave-production.qcow2
    
    # Restart service
    sudo systemctl restart rave-production.service
    ;;
    
  resources)
    echo "🔧 Resolving resource constraints..."
    
    # Enable SAFE mode if not already
    export SAFE=1
    
    # Restart with reduced resource allocation
    sudo systemctl stop rave-production.service
    sudo systemctl start rave-production.service
    ;;
    
  kvm)
    echo "🔧 Resolving KVM issues..."
    
    # Check KVM module
    sudo modprobe kvm
    sudo modprobe kvm_intel  # or kvm_amd
    
    # Set permissions
    sudo chmod 666 /dev/kvm
    
    # Restart service
    sudo systemctl restart rave-production.service
    ;;
esac

echo "✅ Boot issue resolution completed"
```

#### Issue: Service Fails to Start
**Symptoms:**
- systemd service shows "failed" status
- Service stops immediately after starting
- Error messages in system journal

**Diagnostic Commands:**
```bash
# Check service status and logs
systemctl status rave-production.service -l --no-pager
journalctl -u rave-production.service --since "1 hour ago" -n 50

# Check systemd service configuration
systemctl show rave-production.service | grep -E "(ExecStart|WorkingDirectory|User)"

# Validate service dependencies
systemctl list-dependencies rave-production.service
```

**Resolution Procedure:**
```bash
#!/bin/bash
# resolve-service-failure.sh

set -e

echo "=== Service Failure Resolution ==="

# Check for common systemd issues
echo "Checking systemd configuration..."

# Validate service file syntax
if systemd-analyze verify /etc/systemd/system/rave-production.service; then
  echo "✅ Service file syntax valid"
else
  echo "❌ Service file syntax error - manual correction required"
  exit 1
fi

# Check working directory
if [ -d "/opt/rave/production" ]; then
  echo "✅ Working directory exists"
else
  echo "❌ Working directory missing - creating..."
  sudo mkdir -p /opt/rave/production
fi

# Check VM image file
if [ -f "/opt/rave/production/rave-production.qcow2" ]; then
  echo "✅ VM image file exists"
else
  echo "❌ VM image missing - rebuilding..."
  nix build .#p2-production
  sudo cp $(nix build .#p2-production --print-out-paths) \
          /opt/rave/production/rave-production.qcow2
fi

# Reset service state
echo "Resetting service state..."
sudo systemctl daemon-reload
sudo systemctl reset-failed rave-production.service

# Restart service with verbose logging
echo "Restarting service..."
sudo systemctl start rave-production.service

# Verify startup
sleep 30
if systemctl is-active rave-production.service; then
  echo "✅ Service started successfully"
else
  echo "❌ Service still failing - check logs:"
  journalctl -u rave-production.service -n 20 --no-pager
  exit 1
fi
```

### 2. Network and Connectivity Issues

#### Issue: Cannot Access Web Interface
**Symptoms:**
- Connection timeout when accessing https://localhost:3002/
- "Connection refused" errors
- Browser shows "This site can't be reached"

**Diagnostic Workflow:**
```bash
#!/bin/bash
# diagnose-connectivity.sh

echo "=== Network Connectivity Diagnosis ==="

# Test port accessibility
echo "Testing port accessibility..."
PORTS=(22 3002)
for port in "${PORTS[@]}"; do
  if nc -z localhost $port; then
    echo "✅ Port $port is accessible"
  else
    echo "❌ Port $port is not accessible"
    ((failures++))
  fi
done

# Check QEMU network configuration
echo "Checking QEMU network configuration..."
ps aux | grep qemu | grep -E "hostfwd|netdev" | head -1

# Test VM internal network
echo "Testing VM internal connectivity..."
if ssh -o ConnectTimeout=5 agent@localhost 'curl -s http://localhost:3000' >/dev/null 2>&1; then
  echo "✅ Internal services responding"
else
  echo "❌ Internal services not responding"
  ((failures++))
fi

# Check firewall status
echo "Checking firewall configuration..."
ssh agent@localhost 'sudo iptables -L INPUT -n | grep -E ":22|:3002"'

# Test nginx status
echo "Checking nginx status..."
ssh agent@localhost 'systemctl is-active nginx && curl -s http://localhost:3002 >/dev/null'

failures=${failures:-0}
if [ $failures -eq 0 ]; then
  echo "✅ Network connectivity diagnosis completed - no issues found"
else
  echo "❌ Found $failures connectivity issues - see diagnostics above"
fi
```

**Resolution Steps:**
```bash
#!/bin/bash
# resolve-connectivity.sh

set -e

ISSUE_TYPE=${1:-network}

case $ISSUE_TYPE in
  network)
    echo "🔧 Resolving network configuration..."
    
    # Restart VM with correct network settings
    sudo systemctl stop rave-production.service
    
    # Verify service configuration includes correct port forwarding
    grep -q "hostfwd=tcp::3002-:3002" /etc/systemd/system/rave-production.service
    grep -q "hostfwd=tcp::22-:22" /etc/systemd/system/rave-production.service
    
    sudo systemctl start rave-production.service
    ;;
    
  firewall)
    echo "🔧 Resolving firewall issues..."
    
    # Reset VM firewall rules (inside VM)
    ssh agent@localhost 'sudo systemctl restart nixos-firewall'
    
    # Verify expected ports are open
    ssh agent@localhost 'sudo iptables -L INPUT -n | grep ACCEPT'
    ;;
    
  nginx)
    echo "🔧 Resolving nginx issues..."
    
    # Restart nginx service
    ssh agent@localhost 'sudo systemctl restart nginx'
    
    # Check nginx configuration
    ssh agent@localhost 'sudo nginx -t'
    
    # Verify nginx is listening on expected ports
    ssh agent@localhost 'netstat -tulpn | grep :3002'
    ;;
    
  ssl)
    echo "🔧 Resolving SSL/TLS issues..."
    
    # Check certificate status
    ssh agent@localhost 'sudo ls -la /run/secrets/tls-*'
    
    # Restart sops-nix for secret delivery
    ssh agent@localhost 'sudo systemctl restart sops-nix'
    
    # Restart nginx to reload certificates
    ssh agent@localhost 'sudo systemctl restart nginx'
    ;;
esac

# Validate resolution
echo "Validating connectivity resolution..."
sleep 20

if curl -k -s https://localhost:3002/ >/dev/null; then
  echo "✅ Web interface accessible"
else
  echo "❌ Web interface still not accessible"
  exit 1
fi
```

#### Issue: SSH Connection Failures
**Symptoms:**
- "Connection refused" when attempting SSH
- "Permission denied (publickey)" errors  
- SSH hangs without authentication prompt

**Diagnostic Process:**
```bash
#!/bin/bash
# diagnose-ssh-issues.sh

echo "=== SSH Connectivity Diagnosis ==="

# Test basic connectivity
echo "Testing SSH port connectivity..."
if nc -z localhost 22; then
  echo "✅ SSH port accessible"
else
  echo "❌ SSH port not accessible"
  exit 1
fi

# Check SSH client configuration
echo "Checking SSH client configuration..."
ssh -v agent@localhost exit 2>&1 | grep -E "(Connecting|Connected|Offering|Authentications)"

# Verify SSH keys
echo "Checking SSH key availability..."
ssh-add -l || echo "No keys in SSH agent"

# Check authorized keys on server
echo "Checking server-side SSH configuration..."
if ssh -o PasswordAuthentication=no -o PubkeyAuthentication=yes agent@localhost 'cat ~/.ssh/authorized_keys' 2>/dev/null; then
  echo "✅ SSH keys properly configured"
else
  echo "❌ SSH key authentication failing"
fi

# Test SSH service status
echo "Checking SSH service status..."
ssh agent@localhost 'systemctl is-active sshd' 2>/dev/null || echo "Cannot check SSH service - connection failed"
```

**Resolution Procedure:**
```bash
#!/bin/bash
# resolve-ssh-issues.sh

set -e

ISSUE_TYPE=${1:-keys}

case $ISSUE_TYPE in
  keys)
    echo "🔧 Resolving SSH key authentication..."
    
    # Check if SSH key exists locally
    if [ ! -f ~/.ssh/id_ed25519 ]; then
      echo "Generating new SSH key..."
      ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
    fi
    
    # Add key to SSH agent
    ssh-add ~/.ssh/id_ed25519
    
    # Update secrets with new public key
    echo "Update secrets.yaml with public key:"
    cat ~/.ssh/id_ed25519.pub
    echo "Add this key to secrets.yaml under ssh.authorized-keys"
    
    # Rebuild and redeploy with new keys
    read -p "Press Enter after updating secrets.yaml..."
    ./scripts/rave-service-management.sh update
    ;;
    
  service)
    echo "🔧 Resolving SSH service issues..."
    
    # Restart SSH service inside VM
    ssh agent@localhost 'sudo systemctl restart sshd' 2>/dev/null || {
      echo "Cannot restart SSH via SSH - using VM console"
      # Alternative: restart entire VM
      sudo systemctl restart rave-production.service
    }
    ;;
    
  configuration)
    echo "🔧 Resolving SSH configuration issues..."
    
    # Reset SSH client configuration
    ssh-keygen -R localhost
    ssh-keygen -R "[localhost]:22"
    
    # Test with verbose output
    ssh -v -o StrictHostKeyChecking=no agent@localhost exit
    ;;
esac

echo "✅ SSH issue resolution completed"
```

### 3. Service and Application Issues

#### Issue: Grafana Dashboard Not Loading
**Symptoms:**
- Grafana returns 502 Bad Gateway
- Dashboard shows "No data" or loading indefinitely
- Grafana API endpoints return errors

**Diagnostic Steps:**
```bash
#!/bin/bash
# diagnose-grafana-issues.sh

echo "=== Grafana Issues Diagnosis ==="

# Check Grafana service status
echo "Checking Grafana service status..."
ssh agent@localhost 'systemctl status grafana -l --no-pager'

# Test Grafana API directly
echo "Testing Grafana API..."
if ssh agent@localhost 'curl -s http://localhost:3030/api/health' | grep -q "ok"; then
  echo "✅ Grafana API responding"
else
  echo "❌ Grafana API not responding"
fi

# Check Grafana logs for errors
echo "Checking Grafana logs..."
ssh agent@localhost 'journalctl -u grafana --since "30 minutes ago" | grep -i error'

# Test database connectivity
echo "Testing database connectivity..."
ssh agent@localhost 'systemctl is-active postgresql'

# Check Prometheus connectivity
echo "Testing Prometheus connectivity..."
if ssh agent@localhost 'curl -s http://localhost:9090/-/ready' >/dev/null; then
  echo "✅ Prometheus responding"
else
  echo "❌ Prometheus not responding"
fi

# Verify Grafana configuration
echo "Checking Grafana configuration..."
ssh agent@localhost 'ls -la /etc/grafana/ | head -10'
```

**Resolution Process:**
```bash
#!/bin/bash
# resolve-grafana-issues.sh

set -e

ISSUE_TYPE=${1:-service}

case $ISSUE_TYPE in
  service)
    echo "🔧 Resolving Grafana service issues..."
    
    # Restart Grafana service
    ssh agent@localhost 'sudo systemctl restart grafana'
    
    # Wait for startup
    sleep 15
    
    # Verify service health
    if ssh agent@localhost 'curl -s http://localhost:3030/api/health' | grep -q "ok"; then
      echo "✅ Grafana service restored"
    else
      echo "❌ Grafana service still failing"
      ssh agent@localhost 'journalctl -u grafana -n 20'
      exit 1
    fi
    ;;
    
  database)
    echo "🔧 Resolving database connectivity..."
    
    # Restart PostgreSQL service
    ssh agent@localhost 'sudo systemctl restart postgresql'
    
    # Wait for PostgreSQL startup
    sleep 10
    
    # Restart Grafana to reconnect
    ssh agent@localhost 'sudo systemctl restart grafana'
    ;;
    
  prometheus)
    echo "🔧 Resolving Prometheus connectivity..."
    
    # Restart Prometheus service
    ssh agent@localhost 'sudo systemctl restart prometheus'
    
    # Wait for Prometheus startup
    sleep 20
    
    # Verify Prometheus is responding
    if ssh agent@localhost 'curl -s http://localhost:9090/-/ready' >/dev/null; then
      echo "✅ Prometheus restored"
    else
      echo "❌ Prometheus still failing"
      exit 1
    fi
    ;;
    
  configuration)
    echo "🔧 Resolving Grafana configuration..."
    
    # Reset Grafana configuration
    ssh agent@localhost 'sudo rm -rf /var/lib/grafana/grafana.db'
    
    # Restart Grafana to recreate database
    ssh agent@localhost 'sudo systemctl restart grafana'
    
    # Wait for initialization
    sleep 30
    
    echo "⚠️  Grafana database reset - dashboards need to be reconfigured"
    ;;
esac

echo "✅ Grafana issue resolution completed"
```

#### Issue: Webhook Processing Failures
**Symptoms:**
- Webhook requests return 500 Internal Server Error
- GitLab webhooks show failed delivery status
- No webhook events processed despite GitLab activity

**Diagnostic Workflow:**
```bash
#!/bin/bash
# diagnose-webhook-issues.sh

echo "=== Webhook Processing Diagnosis ==="

# Check webhook dispatcher service
echo "Checking webhook dispatcher status..."
ssh agent@localhost 'systemctl status webhook-dispatcher -l --no-pager'

# Test webhook endpoint directly
echo "Testing webhook endpoint..."
curl -X POST https://localhost:3002/webhook \
  -H "X-Gitlab-Token: test-token" \
  -H "Content-Type: application/json" \
  -d '{"test": true}' \
  -k -v

# Check webhook dispatcher logs
echo "Checking webhook dispatcher logs..."
ssh agent@localhost 'journalctl -u webhook-dispatcher --since "1 hour ago" | tail -20'

# Verify webhook secret configuration
echo "Checking webhook secret..."
ssh agent@localhost 'ls -la /run/secrets/webhook-*'

# Check nginx proxy configuration
echo "Checking nginx webhook routing..."
ssh agent@localhost 'curl -s http://localhost:3001/metrics' | grep webhook || echo "No webhook metrics"

# Test internal webhook processing
echo "Testing internal webhook processing..."
ssh agent@localhost 'curl -X POST http://localhost:3001/webhook \
  -H "X-Gitlab-Token: test" \
  -H "Content-Type: application/json" \
  -d "{\"test\": true}"'
```

**Resolution Steps:**
```bash
#!/bin/bash
# resolve-webhook-issues.sh

set -e

ISSUE_TYPE=${1:-service}

case $ISSUE_TYPE in
  service)
    echo "🔧 Resolving webhook service issues..."
    
    # Restart webhook dispatcher
    ssh agent@localhost 'sudo systemctl restart webhook-dispatcher'
    
    # Wait for startup
    sleep 10
    
    # Verify service is running
    if ssh agent@localhost 'systemctl is-active webhook-dispatcher'; then
      echo "✅ Webhook dispatcher restarted"
    else
      echo "❌ Webhook dispatcher still failing"
      ssh agent@localhost 'journalctl -u webhook-dispatcher -n 10'
      exit 1
    fi
    ;;
    
  secrets)
    echo "🔧 Resolving webhook secret issues..."
    
    # Restart sops-nix to refresh secrets
    ssh agent@localhost 'sudo systemctl restart sops-nix'
    
    # Wait for secret delivery
    sleep 5
    
    # Restart webhook dispatcher to pick up new secrets
    ssh agent@localhost 'sudo systemctl restart webhook-dispatcher'
    ;;
    
  nginx)
    echo "🔧 Resolving nginx proxy issues..."
    
    # Restart nginx
    ssh agent@localhost 'sudo systemctl restart nginx'
    
    # Test nginx configuration
    ssh agent@localhost 'sudo nginx -t'
    
    # Verify proxy routing
    curl -k -I https://localhost:3002/webhook
    ;;
    
  database)
    echo "🔧 Resolving webhook database issues..."
    
    # Check SQLite database
    ssh agent@localhost 'ls -la /home/agent/webhook-events.db'
    
    # Reset database if corrupted
    read -p "Reset webhook database? (y/n): " reset_confirm
    if [ "$reset_confirm" = "y" ]; then
      ssh agent@localhost 'rm -f /home/agent/webhook-events.db'
      ssh agent@localhost 'sudo systemctl restart webhook-dispatcher'
    fi
    ;;
esac

# Test webhook functionality
echo "Testing webhook functionality..."
response=$(curl -X POST https://localhost:3002/webhook \
  -H "X-Gitlab-Token: test-token" \
  -H "Content-Type: application/json" \
  -d '{"test": "resolution-verification"}' \
  -k -s -w "%{http_code}")

if [ "$response" = "200" ]; then
  echo "✅ Webhook processing restored"
else
  echo "❌ Webhook still not processing correctly (HTTP $response)"
  exit 1
fi
```

### 4. Performance and Resource Issues

#### Issue: High Memory Usage / OOM Kills
**Symptoms:**
- Services being killed by OOM killer
- System becomes unresponsive
- Memory usage consistently above 90%

**Memory Diagnosis Script:**
```bash
#!/bin/bash
# diagnose-memory-issues.sh

echo "=== Memory Usage Diagnosis ==="

# System memory overview
echo "System memory status:"
free -h
echo ""

# Process memory usage
echo "Top memory consumers:"
ps aux --sort=-%mem | head -20
echo ""

# Service memory usage via systemd
echo "Service memory usage (systemd):"
ssh agent@localhost 'systemd-cgtop --depth=2 -n 1 -b | head -10'
echo ""

# Check for memory leaks
echo "Checking for memory leaks..."
ssh agent@localhost 'cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Cached|Buffers)"'
echo ""

# Check OOM killer activity
echo "Recent OOM killer activity:"
dmesg | grep -i "killed process" | tail -10
journalctl --since "24 hours ago" | grep -i oom | tail -10
echo ""

# SAFE mode validation
if [ "$SAFE" = "1" ]; then
  echo "SAFE mode memory limits:"
  ssh agent@localhost 'systemctl show prometheus grafana webhook-dispatcher | grep -E "(MemoryMax|MemoryCurrent)"'
fi
```

**Memory Issue Resolution:**
```bash
#!/bin/bash
# resolve-memory-issues.sh

set -e

RESOLUTION_TYPE=${1:-safe-mode}

case $RESOLUTION_TYPE in
  safe-mode)
    echo "🔧 Enforcing SAFE mode memory limits..."
    
    # Enable SAFE mode globally
    export SAFE=1
    
    # Apply memory limits to services
    ssh agent@localhost 'sudo systemctl set-property prometheus.service MemoryMax=256M'
    ssh agent@localhost 'sudo systemctl set-property grafana.service MemoryMax=128M'
    ssh agent@localhost 'sudo systemctl set-property webhook-dispatcher.service MemoryMax=64M'
    
    # Restart services to apply limits
    ssh agent@localhost 'sudo systemctl daemon-reload'
    ssh agent@localhost 'sudo systemctl restart prometheus grafana webhook-dispatcher'
    ;;
    
  optimization)
    echo "🔧 Optimizing memory usage..."
    
    # Clear system caches
    ssh agent@localhost 'sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches'
    
    # Optimize Prometheus configuration
    ssh agent@localhost 'sudo systemctl edit prometheus --full' << 'EOF'
# Reduce Prometheus memory usage
--storage.tsdb.retention.time=3d
--storage.tsdb.retention.size=256MB
--query.max-concurrency=2
--query.max-samples=25000000
EOF
    
    # Restart with optimized settings
    ssh agent@localhost 'sudo systemctl restart prometheus'
    ;;
    
  emergency)
    echo "🚨 Emergency memory recovery..."
    
    # Stop non-essential services temporarily
    ssh agent@localhost 'sudo systemctl stop grafana'
    
    # Clear all caches
    ssh agent@localhost 'sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches'
    
    # Wait for memory recovery
    sleep 10
    
    # Restart with SAFE mode constraints
    ssh agent@localhost 'sudo systemctl set-property prometheus.service MemoryMax=128M'
    ssh agent@localhost 'sudo systemctl restart prometheus'
    
    # Gradually restart other services
    sleep 10
    ssh agent@localhost 'sudo systemctl set-property grafana.service MemoryMax=64M'
    ssh agent@localhost 'sudo systemctl start grafana'
    ;;
esac

# Monitor memory recovery
echo "Monitoring memory recovery..."
for i in {1..10}; do
  memory_percent=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
  echo "Memory usage: ${memory_percent}%"
  
  if (( $(echo "$memory_percent < 80" | bc -l) )); then
    echo "✅ Memory usage normalized"
    break
  fi
  
  sleep 5
done
```

#### Issue: High CPU Usage
**Symptoms:**
- System load average consistently high
- Applications become unresponsive
- CPU usage above 90% for extended periods

**CPU Diagnosis:**
```bash
#!/bin/bash
# diagnose-cpu-issues.sh

echo "=== CPU Usage Diagnosis ==="

# System load overview
echo "System load and CPU usage:"
uptime
top -bn1 | head -5
echo ""

# Top CPU consumers
echo "Top CPU consuming processes:"
ps aux --sort=-%cpu | head -15
echo ""

# Service CPU usage
echo "Service CPU usage:"
ssh agent@localhost 'systemd-cgtop --depth=2 -n 1 -b | grep -E "(prometheus|grafana|nginx|webhook)"'
echo ""

# CPU utilization per core
echo "CPU utilization per core:"
ssh agent@localhost 'grep "cpu " /proc/stat && mpstat -P ALL 1 1' 2>/dev/null || echo "mpstat not available"
echo ""

# Check for CPU-intensive tasks
echo "Checking for CPU-intensive background tasks..."
ssh agent@localhost 'ps aux | grep -E "(prometheus|grafana)" | grep -v grep'
```

**CPU Issue Resolution:**
```bash
#!/bin/bash
# resolve-cpu-issues.sh

set -e

RESOLUTION_TYPE=${1:-throttling}

case $RESOLUTION_TYPE in
  throttling)
    echo "🔧 Implementing CPU throttling..."
    
    # Apply CPU quotas to services
    ssh agent@localhost 'sudo systemctl set-property prometheus.service CPUQuota=50%'
    ssh agent@localhost 'sudo systemctl set-property grafana.service CPUQuota=25%'
    ssh agent@localhost 'sudo systemctl set-property webhook-dispatcher.service CPUQuota=25%'
    
    # Apply nice values for priority adjustment
    ssh agent@localhost 'sudo systemctl set-property nginx.service Nice=-5'  # Higher priority
    ssh agent@localhost 'sudo systemctl set-property prometheus.service Nice=10'  # Lower priority
    
    # Reload configuration
    ssh agent@localhost 'sudo systemctl daemon-reload'
    ;;
    
  optimization)
    echo "🔧 Optimizing CPU usage..."
    
    # Optimize Prometheus query execution
    ssh agent@localhost 'sudo systemctl edit prometheus --full' << 'EOF'
# Optimize CPU usage
--query.max-concurrency=2
--web.max-connections=256
--storage.tsdb.wal-compression
EOF
    
    # Restart services with optimizations
    ssh agent@localhost 'sudo systemctl restart prometheus'
    ;;
    
  emergency)
    echo "🚨 Emergency CPU load reduction..."
    
    # Temporarily stop high-CPU services
    ssh agent@localhost 'sudo systemctl stop prometheus'
    
    # Wait for load to decrease
    sleep 10
    
    # Restart with severe limitations
    ssh agent@localhost 'sudo systemctl set-property prometheus.service CPUQuota=25%'
    ssh agent@localhost 'sudo systemctl start prometheus'
    ;;
esac

# Monitor CPU recovery
echo "Monitoring CPU recovery..."
for i in {1..6}; do
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
  echo "CPU usage: ${cpu_usage}%"
  
  if (( $(echo "$cpu_usage < 70" | bc -l) )); then
    echo "✅ CPU usage normalized"
    break
  fi
  
  sleep 10
done
```

### 5. Security and Access Issues

#### Issue: Certificate Expiration / SSL Errors
**Symptoms:**
- Browser shows "Your connection is not private"
- SSL certificate warnings
- HTTPS connections failing

**Certificate Diagnosis:**
```bash
#!/bin/bash
# diagnose-certificate-issues.sh

echo "=== SSL/TLS Certificate Diagnosis ==="

# Check certificate validity
echo "Checking certificate validity..."
echo | openssl s_client -connect localhost:3002 -servername localhost 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null

# Check certificate details
echo "Certificate details:"
echo | openssl s_client -connect localhost:3002 -servername localhost 2>/dev/null | \
  openssl x509 -noout -subject -issuer 2>/dev/null

# Check server certificate files
echo "Checking server certificate files..."
ssh agent@localhost 'ls -la /run/secrets/tls-* 2>/dev/null || echo "Certificate files not found"'

# Verify certificate chain
echo "Verifying certificate chain..."
echo | openssl s_client -connect localhost:3002 -showcerts 2>/dev/null | \
  grep -E "(BEGIN|END) CERTIFICATE"

# Check nginx SSL configuration
echo "Checking nginx SSL configuration..."
ssh agent@localhost 'sudo nginx -T | grep -A5 -B5 ssl' 2>/dev/null || echo "Cannot check nginx config"
```

**Certificate Resolution:**
```bash
#!/bin/bash
# resolve-certificate-issues.sh

set -e

RESOLUTION_TYPE=${1:-refresh}

case $RESOLUTION_TYPE in
  refresh)
    echo "🔧 Refreshing SSL certificates..."
    
    # Restart sops-nix to refresh certificate delivery
    ssh agent@localhost 'sudo systemctl restart sops-nix'
    
    # Wait for secret delivery
    sleep 5
    
    # Restart nginx to reload certificates
    ssh agent@localhost 'sudo systemctl restart nginx'
    
    # Test certificate after refresh
    sleep 10
    if echo | openssl s_client -connect localhost:3002 2>/dev/null | grep -q "Verify return code: 0"; then
      echo "✅ Certificate refreshed successfully"
    else
      echo "⚠️  Certificate may still have issues"
    fi
    ;;
    
  regenerate)
    echo "🔧 Regenerating self-signed certificate..."
    
    # Generate new self-signed certificate
    openssl req -x509 -newkey rsa:4096 -keyout temp-key.pem -out temp-cert.pem -days 365 -nodes \
      -subj "/CN=localhost/O=RAVE Development/C=US"
    
    # Update secrets with new certificate
    echo "Update secrets.yaml with new certificate:"
    echo "tls.certificate:"
    cat temp-cert.pem | sed 's/^/    /'
    echo "tls.private-key:"  
    cat temp-key.pem | sed 's/^/    /'
    
    rm temp-cert.pem temp-key.pem
    
    echo "⚠️  Manual action required: Update secrets.yaml and redeploy"
    ;;
    
  disable-ssl)
    echo "🔧 Temporarily disabling SSL for debugging..."
    
    # Configure nginx for HTTP only (emergency mode)
    ssh agent@localhost 'sudo systemctl stop nginx'
    
    echo "⚠️  SSL disabled - system running in insecure mode"
    echo "⚠️  Manual nginx reconfiguration required for HTTP-only operation"
    ;;
esac
```

#### Issue: SSH Key Authentication Failures
**Symptoms:**
- "Permission denied (publickey)" errors
- Cannot authenticate with SSH keys
- SSH connection works but key auth fails

**SSH Key Diagnosis:**
```bash
#!/bin/bash
# diagnose-ssh-key-issues.sh

echo "=== SSH Key Authentication Diagnosis ==="

# Check local SSH keys
echo "Checking local SSH keys..."
ssh-add -l 2>/dev/null || echo "No keys in SSH agent"
ls -la ~/.ssh/id_* 2>/dev/null || echo "No SSH keys found in ~/.ssh/"

# Test SSH key authentication with verbose output
echo "Testing SSH authentication (verbose)..."
ssh -v -o PasswordAuthentication=no agent@localhost exit 2>&1 | \
  grep -E "(Offering|Authentications|Server accepts|Permission denied)"

# Check server-side authorized keys
echo "Checking server authorized keys..."
ssh -o PasswordAuthentication=yes agent@localhost 'cat ~/.ssh/authorized_keys' 2>/dev/null || \
  echo "Cannot access authorized_keys (password auth may be disabled)"

# Check SSH service configuration
echo "Checking SSH service configuration..."
ssh agent@localhost 'sudo sshd -T | grep -E "(PubkeyAuthentication|PasswordAuthentication|AuthorizedKeysFile)"' 2>/dev/null || \
  echo "Cannot check SSH config - connection failed"

# Check file permissions
echo "Checking SSH file permissions..."
ssh agent@localhost 'ls -la ~/.ssh/' 2>/dev/null || echo "Cannot check SSH directory"
```

**SSH Key Resolution:**
```bash
#!/bin/bash
# resolve-ssh-key-issues.sh

set -e

RESOLUTION_TYPE=${1:-keys}

case $RESOLUTION_TYPE in
  keys)
    echo "🔧 Resolving SSH key authentication..."
    
    # Generate new SSH key if needed
    if [ ! -f ~/.ssh/id_ed25519 ]; then
      echo "Generating new Ed25519 SSH key..."
      ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "rave-production-$(date +%Y%m%d)"
    fi
    
    # Add to SSH agent
    ssh-add ~/.ssh/id_ed25519
    
    # Display public key for manual addition
    echo "Add this public key to secrets.yaml:"
    echo "ssh:"
    echo "  authorized-keys:"
    echo "    - \"$(cat ~/.ssh/id_ed25519.pub)\""
    
    echo "⚠️  Update secrets.yaml and redeploy system"
    ;;
    
  permissions)
    echo "🔧 Fixing SSH file permissions..."
    
    # Fix local SSH permissions
    chmod 700 ~/.ssh/
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    
    # Fix remote SSH permissions (if accessible)
    ssh agent@localhost 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys' 2>/dev/null || \
      echo "Cannot fix remote permissions - manual intervention required"
    ;;
    
  service)
    echo "🔧 Restarting SSH service..."
    
    # Restart SSH service
    ssh agent@localhost 'sudo systemctl restart sshd' 2>/dev/null || {
      echo "Cannot restart SSH via SSH - using VM restart"
      sudo systemctl restart rave-production.service
      sleep 60
    }
    ;;
esac

# Test authentication after resolution
echo "Testing SSH authentication after resolution..."
if ssh -o ConnectTimeout=10 -o PasswordAuthentication=no agent@localhost exit 2>/dev/null; then
  echo "✅ SSH key authentication working"
else
  echo "❌ SSH key authentication still failing"
  exit 1
fi
```

## Advanced Troubleshooting Procedures

### System Recovery from Complete Failure

#### Emergency Recovery Script
```bash
#!/bin/bash
# emergency-system-recovery.sh

set -e

RECOVERY_TYPE=${1:-full}

echo "🚨 EMERGENCY SYSTEM RECOVERY"
echo "Recovery Type: $RECOVERY_TYPE"
echo "Timestamp: $(date -Iseconds)"

case $RECOVERY_TYPE in
  full)
    echo "Full system recovery initiated..."
    
    # 1. Stop all services
    sudo systemctl stop rave-production.service 2>/dev/null || true
    
    # 2. Create emergency backup
    if [ -f /opt/rave/production/rave-production.qcow2 ]; then
      sudo cp /opt/rave/production/rave-production.qcow2 \
             /opt/rave/production/rave-production.qcow2.emergency-$(date +%Y%m%d-%H%M)
    fi
    
    # 3. Rebuild system from scratch
    echo "Rebuilding system from configuration..."
    nix build .#p2-production --refresh --show-trace
    
    # 4. Deploy fresh image
    sudo cp $(nix build .#p2-production --print-out-paths) \
            /opt/rave/production/rave-production.qcow2
    
    # 5. Reset systemd state
    sudo systemctl daemon-reload
    sudo systemctl reset-failed rave-production.service
    
    # 6. Start system
    sudo systemctl start rave-production.service
    
    # 7. Wait and validate
    echo "Waiting for system recovery..."
    sleep 90
    ./scripts/validate-deployment-success.sh
    ;;
    
  partial)
    echo "Partial recovery - service restart..."
    
    # Restart all services in dependency order
    ssh agent@localhost 'sudo systemctl restart postgresql' || true
    sleep 10
    ssh agent@localhost 'sudo systemctl restart prometheus' || true
    sleep 15
    ssh agent@localhost 'sudo systemctl restart grafana' || true
    sleep 10
    ssh agent@localhost 'sudo systemctl restart webhook-dispatcher' || true
    ssh agent@localhost 'sudo systemctl restart nginx' || true
    ;;
    
  config-only)
    echo "Configuration-only recovery..."
    
    # Redeploy configuration without rebuilding
    ssh agent@localhost 'sudo systemctl restart sops-nix'
    sleep 5
    ssh agent@localhost 'sudo systemctl restart nginx grafana webhook-dispatcher'
    ;;
esac

echo "✅ Emergency recovery completed"
```

### Comprehensive System Diagnostics

#### Full System Health Check
```bash
#!/bin/bash
# comprehensive-system-diagnostics.sh

set -e

echo "=== COMPREHENSIVE RAVE SYSTEM DIAGNOSTICS ==="
echo "Timestamp: $(date -Iseconds)"
echo "Host: $(hostname)"
echo ""

# 1. System Information
echo "=== SYSTEM INFORMATION ==="
echo "Kernel: $(uname -a)"
echo "Uptime: $(uptime)"
echo "Load: $(cat /proc/loadavg)"
echo ""

# 2. Resource Usage
echo "=== RESOURCE USAGE ==="
echo "Memory:"
free -h
echo ""
echo "Disk:"
df -h /opt/rave/production/ 2>/dev/null || df -h /
echo ""
echo "CPU:"
grep "model name" /proc/cpuinfo | head -1
echo ""

# 3. Service Status
echo "=== SERVICE STATUS ==="
systemctl status rave-production.service --no-pager -l || echo "Main service not running"
echo ""

# VM internal services
echo "VM Internal Services:"
ssh agent@localhost 'systemctl status nginx grafana prometheus webhook-dispatcher postgresql --no-pager' 2>/dev/null || \
  echo "Cannot check internal services"
echo ""

# 4. Network Connectivity
echo "=== NETWORK CONNECTIVITY ==="
echo "Port accessibility:"
nc -z localhost 22 && echo "SSH: ✅" || echo "SSH: ❌"
nc -z localhost 3002 && echo "HTTPS: ✅" || echo "HTTPS: ❌"
echo ""

echo "Endpoint responses:"
curl -k -s -o /dev/null -w "Main UI: %{http_code}\n" https://localhost:3002/ 2>/dev/null || echo "Main UI: ❌"
curl -k -s -o /dev/null -w "Grafana: %{http_code}\n" https://localhost:3002/grafana/ 2>/dev/null || echo "Grafana: ❌"
echo ""

# 5. Security Status
echo "=== SECURITY STATUS ==="
echo "Certificate status:"
echo | openssl s_client -connect localhost:3002 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null || echo "Certificate check failed"
echo ""

echo "SSH configuration:"
ssh agent@localhost 'sudo sshd -T | grep -E "(PasswordAuthentication|PubkeyAuthentication)"' 2>/dev/null || \
  echo "Cannot check SSH config"
echo ""

# 6. Recent Errors
echo "=== RECENT ERRORS ==="
echo "System errors (last 10):"
journalctl --since "1 hour ago" -p err -n 10 --no-pager 2>/dev/null || echo "No recent errors"
echo ""

echo "Service errors:"
ssh agent@localhost 'journalctl --since "1 hour ago" -p err -n 5 --no-pager' 2>/dev/null || \
  echo "Cannot check service errors"
echo ""

# 7. Performance Metrics
echo "=== PERFORMANCE METRICS ==="
if ssh agent@localhost 'curl -s http://localhost:9090/api/v1/query?query=up' 2>/dev/null | grep -q "success"; then
  echo "✅ Monitoring system operational"
  
  # Get key metrics
  memory_usage=$(ssh agent@localhost 'curl -s "http://localhost:9090/api/v1/query?query=(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes))*100"' 2>/dev/null | \
    jq -r '.data.result[0].value[1] // "unknown"' 2>/dev/null || echo "unknown")
  echo "Memory usage: ${memory_usage}%"
  
  cpu_usage=$(ssh agent@localhost 'curl -s "http://localhost:9090/api/v1/query?query=100-(avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)"' 2>/dev/null | \
    jq -r '.data.result[0].value[1] // "unknown"' 2>/dev/null || echo "unknown")
  echo "CPU usage: ${cpu_usage}%"
else
  echo "❌ Monitoring system not operational"
fi
echo ""

echo "=== DIAGNOSTIC SUMMARY ==="
echo "Full diagnostics completed at $(date -Iseconds)"
echo "Review output above for specific issues requiring attention"
```

## Proactive Monitoring and Prevention

### Automated Issue Detection
```bash
#!/bin/bash
# proactive-monitoring.sh

set -e

echo "=== Proactive Issue Detection ==="

# Health thresholds
MEMORY_THRESHOLD=85
CPU_THRESHOLD=80
DISK_THRESHOLD=90

# Check memory usage
memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
if [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
  echo "⚠️  High memory usage: ${memory_usage}% (threshold: ${MEMORY_THRESHOLD}%)"
  ./scripts/resolve-memory-issues.sh optimization
fi

# Check disk usage
disk_usage=$(df /opt/rave/production/ | awk 'NR==2{printf "%.0f", $5}' | sed 's/%//')
if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
  echo "⚠️  High disk usage: ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
  # Clean up old backups
  find /opt/rave/backups/ -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true
fi

# Check service health
services=("nginx" "grafana" "prometheus" "webhook-dispatcher")
for service in "${services[@]}"; do
  if ! ssh agent@localhost "systemctl is-active $service" >/dev/null 2>&1; then
    echo "⚠️  Service $service is not active - attempting restart"
    ssh agent@localhost "sudo systemctl restart $service"
  fi
done

# Check certificate expiration
cert_days=$(echo | openssl s_client -connect localhost:3002 2>/dev/null | \
  openssl x509 -noout -dates 2>/dev/null | grep "notAfter" | \
  sed 's/notAfter=//' | xargs -I {} date -d "{}" +%s)
current_time=$(date +%s)
days_until_expiry=$(( (cert_days - current_time) / 86400 ))

if [ "$days_until_expiry" -lt 30 ]; then
  echo "⚠️  Certificate expires in $days_until_expiry days - renewal recommended"
fi

echo "✅ Proactive monitoring completed"
```

## Conclusion

This troubleshooting guide provides systematic approaches to diagnosing and resolving the most common issues in RAVE production deployments. For complex issues not covered here:

1. **Escalate to specialized documentation**: [RUNBOOK.md](RUNBOOK.md), [SECURITY.md](SECURITY.md)
2. **Enable debug mode**: Use debug deployment procedures for detailed analysis
3. **Contact support**: Follow escalation procedures in [RUNBOOK.md](RUNBOOK.md)
4. **Document new issues**: Add discovered issues and solutions to this guide

Regular use of the proactive monitoring scripts can prevent many common issues from becoming critical problems.

---

**Document Classification**: Internal Use  
**Last Updated**: 2025-01-23  
**Next Review**: 2025-04-23  
**Document Owner**: SRE Team