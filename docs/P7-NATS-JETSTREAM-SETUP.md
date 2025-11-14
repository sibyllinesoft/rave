# P7: NATS JetStream Native Integration

**Phase 7 Implementation**: Native NATS JetStream messaging service integrated directly into NixOS VM configuration.

## 📋 Overview

NATS JetStream is now baked directly into the RAVE NixOS VM as a native system service, providing high-performance streaming and messaging capabilities without Docker overhead.

### ✅ Implementation Status: COMPLETE

- ✅ **Native NixOS Service**: NATS runs as a native systemd service
- ✅ **JetStream Enabled**: Persistent streaming with configurable storage
- ✅ **Development Config**: HTTP-only, debug logging, no authentication
- ✅ **Production Config**: HTTPS, authentication, resource limits
- ✅ **Security Hardening**: Systemd security features, user isolation
- ✅ **Monitoring Integration**: Health checks, log rotation, nginx proxy
- ✅ **Firewall Configuration**: Ports 4222 (client) and 8222 (monitoring)

## 🏗️ Architecture

### Native NixOS Integration

```
┌─────────────────────────────────────────────────────────┐
│ NixOS VM                                                │
├─────────────────────────────────────────────────────────┤
│ SystemD Services:                                       │
│ ├── nats.service (Native NATS Server)                   │
│ ├── nats-health-check.service (Health monitoring)       │
│ └── nats-health-check.timer (Periodic checks)           │
├─────────────────────────────────────────────────────────┤
│ File System:                                            │
│ ├── /var/lib/nats/                   (Data directory)   │
│ │   ├── jetstream/                   (Stream storage)   │
│ │   └── nats-server.log              (Service logs)     │
│ └── /nix/store/.../nats-server.conf  (Configuration)    │
├─────────────────────────────────────────────────────────┤
│ Network:                                                │
│ ├── 4222:tcp  (NATS client connections)                 │
│ ├── 8222:tcp  (HTTP monitoring interface)               │
│ └── nginx:/nats/ → 127.0.0.1:8222   (Web monitoring)    │
└─────────────────────────────────────────────────────────┘
```

### JetStream Architecture

```
Client Applications
         ↓
    NATS Server :4222
         ↓
   JetStream Core
    ├── Memory Store (configurable limit)
    └── File Store (persistent, configurable limit)
         ↓
    Stream Storage
    ├── Subjects: "service.*", "build.*", "deploy.*"
    ├── Consumers: Durable message consumption
    └── Retention: Message age and count policies
```

## 🔧 Configuration

### Development Environment

```nix
services.rave.nats = {
  enable = true;
  serverName = "rave-dev-nats";
  debug = true;                    # Enhanced logging
  safeMode = false;               # More resources available
  jetstream = {
    maxMemory = "128MB";
    maxFileStore = "512MB";
  };
  auth = {
    enable = false;               # No authentication for development
  };
};
```

**Features:**
- **Debug Logging**: Full trace and debug information
- **No Authentication**: Simplified access for development
- **Generous Limits**: Higher memory and storage allocation
- **HTTP Only**: Accessible via http://rave.local/nats/

### Production Environment

```nix
services.rave.nats = {
  enable = true;
  serverName = "rave-prod-nats";
  debug = false;
  safeMode = true;                # Resource limits enforced
  jetstream = {
    maxMemory = "512MB";
    maxFileStore = "2GB";
  };
  limits = {
    maxConnections = 100000;
    maxPayload = 2097152;         # 2MB messages
  };
  auth = {
    enable = true;
    users = [
      {
        name = "gitlab";
        password = ""; # Set via secrets
        publish = ["gitlab.*" "build.*" "deploy.*"];
        subscribe = ["gitlab.*" "build.*" "deploy.*"];
      }
      {
        name = "matrix";
        password = ""; # Set via secrets  
        publish = ["matrix.*" "notifications.*"];
        subscribe = ["matrix.*" "notifications.*"];
      }
      {
        name = "monitoring";
        password = ""; # Set via secrets
        publish = ["metrics.*" "alerts.*"];
        subscribe = ["metrics.*" "alerts.*"];
      }
    ];
  };
};
```

**Features:**
- **Authentication**: Role-based user accounts with subject permissions
- **Resource Limits**: Memory and CPU quotas via systemd
- **High Throughput**: Up to 100,000 concurrent connections
- **Secure Access**: HTTPS only via https://rave.local/nats/

## 🛠️ Service Features

### Security & Isolation

```yaml
Systemd Security:
  - NoNewPrivileges: true
  - ProtectSystem: strict
  - ProtectHome: true
  - PrivateTmp: true
  - RestrictAddressFamilies: [AF_UNIX, AF_INET, AF_INET6]
  - LockPersonality: true
  - MemoryDenyWriteExecute: true
  - RestrictRealtime: true
  - RestrictSUIDSGID: true
  - RemoveIPC: true

User Isolation:
  - Dedicated 'nats' user and group
  - Home directory: /var/lib/nats
  - File permissions: 750 (owner + group only)
  - No shell access
```

### Resource Management

```yaml
SAFE Mode (Production):
  - Memory Limit: 512MB
  - CPU Quota: 50%
  - Task Limit: 1024
  - OOM Score: 200 (lower priority than critical services)

Development Mode:
  - No resource limits
  - More memory for debugging
  - Higher CPU allocation
```

### Monitoring & Health Checks

```yaml
Health Monitoring:
  - Service: nats-health-check.service
  - Timer: Every 5 minutes after boot
  - Endpoint: http://localhost:8222/healthz
  - Timeout: 30 seconds
  - Auto-restart: On failure

Log Management:
  - Service logs: journald
  - Application logs: /var/lib/nats/nats-server.log
  - Rotation: Daily (7 days in SAFE mode, 30 days otherwise)
  - Compression: Enabled

Web Interface:
  - URL: http(s)://rave.local/nats/
  - Monitoring: Server stats, connection info
  - JetStream: Stream and consumer metrics
```

## 📊 JetStream Usage

### Basic Stream Operations

```bash
# Connect to NATS server
export NATS_URL=nats://rave.local:4222

# Development (no auth)
nats server info

# Production (with auth)  
nats --user=monitoring --password=secret server info

# Create a stream
nats stream create \
  --subjects="deploy.*" \
  --storage=file \
  --max-msgs=10000 \
  --max-age=24h \
  deployment-stream

# Publish messages
echo "Deployment started" | nats pub deploy.start

# Create consumer
nats consumer create deployment-stream deployment-processor \
  --filter="deploy.*" \
  --replay=instant \
  --deliver=all

# Read messages
nats consumer next deployment-stream deployment-processor
```

### Integration Examples

#### GitLab CI/CD Integration

```yaml
# .gitlab-ci.yml
stages:
  - build
  - deploy

build:
  script:
    - echo "Build started" | nats pub gitlab.build.start
    - # Build application
    - echo "Build completed" | nats pub gitlab.build.complete
    
deploy:
  script:  
    - echo "Deploy started" | nats pub gitlab.deploy.start
    - # Deploy application
    - echo "Deploy completed" | nats pub gitlab.deploy.complete
```

#### Matrix Notifications

```javascript
// Matrix bot integration
const nats = require('nats');

const nc = await nats.connect({
  servers: 'nats://rave.local:4222',
  user: 'matrix',
  pass: process.env.NATS_MATRIX_PASSWORD
});

// Subscribe to deployment events
const sub = nc.subscribe('deploy.*');
for await (const msg of sub) {
  const event = msg.subject.split('.')[1];
  await sendMatrixMessage(`🚀 Deployment ${event}: ${msg.string()}`);
}
```

## 🧪 Testing & Validation

### Automated Testing

The configuration includes automated validation:

```bash
# Run configuration tests
./scripts/test-nats-config.sh

# Test JetStream functionality
./scripts/nats-jetstream-demo.sh
```

### Manual Testing

```bash
# Check service status
systemctl status nats

# Check JetStream status  
nats stream ls

# Monitor logs
journalctl -u nats -f

# Test health endpoint
curl http://rave.local/nats/healthz

# Performance test
nats bench pub --msgs=1000 --size=1024 test.performance
nats bench sub --msgs=1000 test.performance
```

## 🔄 Operational Procedures

### Starting/Stopping Service

```bash
# Start NATS service
sudo systemctl start nats

# Stop NATS service  
sudo systemctl stop nats

# Restart with new config
sudo systemctl reload nats

# Check service health
sudo systemctl status nats
```

### Configuration Updates

```bash
# 1. Update NixOS configuration
sudo nano /etc/infra/nixos/configuration.nix

# 2. Rebuild system
sudo nixos-rebuild switch

# 3. Verify service restart
sudo systemctl status nats
```

### Backup & Recovery

```bash
# Backup JetStream data
sudo tar -czf /backup/nats-$(date +%Y%m%d).tar.gz /var/lib/nats/jetstream/

# Restore JetStream data
sudo systemctl stop nats
sudo tar -xzf /backup/nats-20250827.tar.gz -C /
sudo chown -R nats:nats /var/lib/nats
sudo systemctl start nats
```

## 📈 Performance & Scaling

### Benchmarks

```yaml
Development Configuration:
  - Memory: 128MB JetStream, unlimited system
  - Storage: 512MB file store
  - Connections: 65,536 (default)
  - Expected Throughput: ~50K msgs/sec

Production Configuration:
  - Memory: 512MB JetStream, 512MB system limit
  - Storage: 2GB file store  
  - Connections: 100,000
  - Expected Throughput: ~100K msgs/sec
```

### Scaling Considerations

```yaml
Single Node Limits:
  - Memory: Up to 4GB JetStream store
  - Storage: Limited by disk space
  - Connections: Up to 1M with sufficient resources
  - Network: Limited by network bandwidth

Clustering (Future):
  - Multiple NATS servers with JetStream replication
  - Load balancing across nodes
  - Automatic failover
```

## 🚨 Troubleshooting

### Common Issues

#### Service Won't Start

```bash
# Check systemd status
sudo systemctl status nats

# Check configuration validity
nats-server -c /nix/store/.../nats-server.conf -t

# Check file permissions
ls -la /var/lib/nats/
```

#### JetStream Not Available

```bash
# Verify JetStream is enabled in config
grep -A5 "jetstream:" /nix/store/.../nats-server.conf

# Check available space
df -h /var/lib/nats/

# Verify nats user permissions
sudo -u nats ls -la /var/lib/nats/jetstream/
```

#### Connection Issues

```bash
# Test local connectivity
nats --server=localhost:4222 server info

# Check firewall
sudo ss -tlnp | grep :4222

# Test from client
telnet rave.local 4222
```

#### Performance Issues

```bash
# Check resource usage
systemctl show nats | grep Memory
systemctl show nats | grep CPU

# Monitor in real-time
htop -p $(pgrep nats-server)

# JetStream statistics
nats stream report
```

## 🔗 Integration Points

### With Existing Services

```yaml
GitLab Integration:
  - Build notifications: "gitlab.build.*"
  - Deployment events: "gitlab.deploy.*"  
  - Pipeline status: "gitlab.pipeline.*"

Matrix Integration:
  - Notifications: "matrix.notify.*"
  - Bot commands: "matrix.command.*"
  - System alerts: "matrix.alert.*"

Monitoring Integration:
  - Metrics collection: "metrics.collect.*"
  - Alert generation: "metrics.alert.*"
  - Health status: "health.check.*"
```

### External Access

```yaml
Network Access:
  - Client Port: rave.local:4222
  - Monitoring: http(s)://rave.local/nats/
  - Health Check: /nats/healthz
  - Metrics: /nats/metrics (Prometheus format)

Security:
  - Development: HTTP, no authentication
  - Production: HTTPS, user authentication required
  - Firewall: Ports 4222, 8222 open
```

## 📚 Further Reading

- [NATS JetStream Documentation](https://docs.nats.io/nats-concepts/jetstream)
- [NixOS Service Configuration](https://nixos.org/manual/infra/nixos/stable/#sec-writing-modules)
- [SystemD Security Features](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Security)

## 🎯 Success Criteria: ✅ ACHIEVED

- ✅ **Native Integration**: NATS runs as native NixOS service (not Docker)
- ✅ **JetStream Enabled**: Persistent streaming with configurable limits  
- ✅ **Development Ready**: HTTP access, debug logging, no auth complexity
- ✅ **Production Ready**: HTTPS, authentication, resource limits
- ✅ **Security Hardened**: SystemD security features, user isolation
- ✅ **Monitoring Integrated**: Health checks, log rotation, web interface
- ✅ **Performance Optimized**: Resource limits, connection scaling
- ✅ **Operations Ready**: Backup, recovery, troubleshooting procedures

**NATS JetStream is now fully integrated into RAVE's NixOS architecture as a native, high-performance messaging service.**