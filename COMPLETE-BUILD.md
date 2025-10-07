# RAVE Complete Production Build

This document describes the **complete, consolidated NixOS VM configuration** that includes ALL services properly configured and working from the start.

## 🚀 Quick Start

**Build the complete VM:**
```bash
nix build .#complete
```

**Start the VM:**
```bash
# Copy with proper permissions
cp result/nixos.qcow2 rave-complete.qcow2 && chmod 644 rave-complete.qcow2

# Start with port forwarding
qemu-system-x86_64 \
  -drive file=rave-complete.qcow2,format=qcow2 \
  -m 8G \
  -smp 4 \
  -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::8443-:443,hostfwd=tcp::2224-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

**Access services immediately:**
- **Dashboard**: https://localhost:8443/
- **GitLab**: https://localhost:8443/gitlab/ (root:admin123456)
- **Grafana**: https://localhost:8443/grafana/ (admin:admin123)
- **Mattermost**: https://localhost:8443/mattermost/
- **Prometheus**: https://localhost:8443/prometheus/
- **NATS**: https://localhost:8443/nats/

## 🎯 What Makes This Different

### ❌ Previous Issues (Fixed)
1. **Grafana domain mismatch**: Was using `rave.local`, now uses `localhost`
2. **GitLab setup delays**: Database was not pre-configured, now all databases are ready
3. **Penpot Docker issues**: Removed Docker complexity for core services
4. **Scattered configurations**: Multiple files with inconsistent settings
5. **Manual interventions**: Required post-boot setup steps

### ✅ Complete Solution
1. **All services start immediately** - No setup delays or manual steps
2. **Localhost-first configuration** - Works perfectly with port forwarding
3. **Pre-configured databases** - PostgreSQL with all users and permissions ready
4. **Consolidated single file** - One configuration to rule them all
5. **Proper SSL certificates** - Self-signed certs generated automatically

## 🏗️ Architecture

### Core Infrastructure
- **nginx**: Reverse proxy with SSL termination
- **PostgreSQL 15**: All databases pre-created (gitlab, grafana, penpot, mattermost)
- **Redis**: Multiple instances (GitLab:6379, Penpot:6380)
- **NATS**: JetStream messaging with monitoring on port 8222

### Application Services
- **GitLab**: Full CI/CD with container registry
- **Grafana**: Monitoring dashboards with PostgreSQL + Prometheus datasources
- **Mattermost**: Secure team chat and agent control (auto-provisions `/rave` slash command)
- **Prometheus**: Metrics collection with exporters

### Service Dependencies
```
nginx (443) → All services
├── GitLab (8080) → PostgreSQL + Redis
├── Grafana (3000) → PostgreSQL + Prometheus
├── Mattermost (8065) → PostgreSQL
├── Prometheus (9090) → Node/Nginx/Postgres exporters
└── NATS (4222) → JetStream storage
```

## 🔧 Configuration Details

### Database Pre-configuration
All PostgreSQL databases and users are created during build:

```sql
-- Pre-configured databases
gitlab (owner: gitlab, password: gitlab-production-password)
grafana (owner: grafana, password: grafana-production-password)  
penpot (owner: penpot, password: penpot-production-password)
mattermost (owner: mattermost, password: mattermost-production-password)
```

### SSL Certificates
- **Domain**: localhost (with SAN for rave.local)
- **Location**: `/var/lib/acme/rave.local/`
- **Type**: Self-signed with proper CA chain
- **Permissions**: nginx-readable (640 for key.pem)

### Service Ports
```
External (via nginx):
- 80/tcp  → HTTPS redirect
- 443/tcp → Main HTTPS endpoint

Internal services:
- 8080/tcp → GitLab
- 3000/tcp → Grafana  
- 8065/tcp → Mattermost
- 9090/tcp → Prometheus
- 4222/tcp → NATS
- 8222/tcp → NATS monitoring
- 6379/tcp → Redis (GitLab)
- 6380/tcp → Redis (Penpot) 
- 5432/tcp → PostgreSQL
```

## 🎛️ Service Management

### Check Service Status
```bash
# SSH into VM
sshpass -p 'debug123' ssh root@localhost -p 2224

# Check all services
systemctl status postgresql redis-gitlab redis-penpot nats prometheus grafana gitlab mattermost rave-chat-bridge nginx

# View logs
journalctl -u SERVICE_NAME -f
```

### Default Credentials
- **System**: root:debug123
- **GitLab**: root:admin123456
- **Grafana**: admin:admin123

## 🔍 Troubleshooting

### Build Issues
```bash
# Clean build
nix build .#complete --rebuild

# Check build logs
nix build .#complete --print-build-logs
```

### Runtime Issues
```bash
# Check certificate generation
ssh root@localhost -p 2224 "systemctl status generate-localhost-certs"

# Fix certificate permissions if needed
ssh root@localhost -p 2224 "chmod 640 /var/lib/acme/rave.local/key.pem && systemctl restart nginx"

# Verify database connectivity
ssh root@localhost -p 2224 "sudo -u postgres psql -l"
```

### Service Dependencies
If a service fails to start:
```bash
# Check dependency status
systemctl list-dependencies SERVICE_NAME

# Restart in dependency order
systemctl restart postgresql redis-gitlab redis-penpot
systemctl restart gitlab grafana mattermost  
systemctl restart nginx
```

## 📊 Performance Tuning

### VM Resources
**Recommended minimum:**
- **Memory**: 8GB (services are memory-optimized)
- **CPU**: 4 cores (2 cores minimum)
- **Disk**: 20GB (10GB minimum)

### Service Resource Limits
- **GitLab**: 8GB memory, 50% CPU
- **Grafana**: Default (PostgreSQL backend)
- **Mattermost**: Default configuration with webhook integration
- **PostgreSQL**: 512MB shared_buffers, 200 max_connections
- **Redis instances**: 256-512MB per instance

## 🔧 Customization

### Change Domain
To use a different domain than localhost:

1. Edit `complete-production.nix`
2. Change all `localhost` references to your domain
3. Update SSL certificate generation
4. Rebuild: `nix build .#complete --rebuild`

### Add Services
The configuration is modular - add new services by:

1. Adding service configuration to `complete-production.nix`
2. Adding nginx reverse proxy location
3. Adding to dashboard HTML
4. Adding required database/Redis instances

### Environment Variables
All services use production-ready defaults. For development:
- Database passwords are hardcoded
- SSL uses self-signed certificates
- Services are configured for localhost access

## 📈 Monitoring & Observability

### Built-in Monitoring
- **Prometheus**: Collects metrics from all services
- **Grafana**: Pre-configured dashboards
- **Exporters**: Node, nginx, PostgreSQL, Redis

### Health Checks
```bash
# Service health
curl -k https://localhost:8443/gitlab/health
curl -k https://localhost:8443/grafana/api/health
curl -k https://localhost:8443/prometheus/-/healthy

# Database connectivity
curl -k https://localhost:8443/grafana/api/datasources/proxy/1/api/v1/query?query=up
```

## 🚦 Next Steps

1. **Customize credentials**: Change default passwords before production use
2. **Add your SSH key**: Replace placeholder in user configuration  
3. **Configure secrets**: Use sops-nix for production secret management
4. **Scale resources**: Adjust memory/CPU limits based on usage
5. **Add monitoring**: Extend Prometheus scrape configs for your services

---

This complete configuration eliminates all the previous pain points and provides a fully working RAVE environment from first boot. No more partial deployments, configuration drift, or manual setup steps!
