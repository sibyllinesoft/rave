# CLAUDE.md - RAVE Development VM Instructions

## Overview
This repository contains a **consolidated NixOS VM** for the RAVE project. There is ONE primary build configuration that includes ALL services pre-configured and ready to use.

**CRITICAL ARCHITECTURE DECISIONS:**
- **Consolidated Build Strategy**: Single `complete-production.nix` configuration eliminates confusion from scattered builds
- **Services run INSIDE VM**: Never install Docker/GitLab directly on the host system
- **Default Build**: `nix build` always uses the complete configuration
- **Localhost-Optimized**: All services configured for localhost:8443 (no domain issues)

## 🚨 FOR CLAUDE: CRITICAL CONTEXT TO AVOID CONFUSION

**Current Repository State (August 2025):**
1. **Primary Configuration**: `nixos/configs/complete-production.nix` - USE THIS
2. **Default Build Command**: `nix build` (not .#development or other variants)
3. **All Other Configs**: Legacy/specialized use only
4. **Services Status**: 
   - ✅ GitLab, Grafana, Prometheus, NATS, PostgreSQL, Redis, nginx
   - 🔄 Penpot (Docker images download on first boot) 
   - ❌ Matrix/Element (temporarily disabled due to NixOS 24.11 conflicts)
5. **Build Issues Resolved**: SSH conflicts, Redis format, npm packages, domain configs

**❌ STRICTLY FORBIDDEN FOR CLAUDE:**
- Use old .#development or .#production build targets
- Try to fix "scattered build" issues (already consolidated)
- Attempt to re-enable Matrix without checking NixOS 24.11 compatibility
- Modify SSH/Redis configs without lib.mkForce overrides
- **NEVER bypass the RAVE CLI for VM management**
- **NEVER suggest manual `qemu-system-x86_64` commands**

## VM Architecture (Consolidated Complete Configuration)
```
Host System (Ubuntu)
├── Port 8081 → VM:80 (HTTP → HTTPS redirect)
├── Port 8443 → VM:443 (HTTPS dashboard + all services)
├── Port 8889 → VM:8080 (VM status page)  
├── Port 2224 → VM:22 (SSH access: root/debug123)
└── QEMU/KVM VM (NixOS 24.11) - COMPLETE BUILD
    ├── nginx (reverse proxy with SSL, localhost certs)
    ├── GitLab (CI/CD platform, /gitlab/ path)
    ├── Grafana (monitoring, /grafana/ path)
    ├── Prometheus (metrics collection, /prometheus/ path)
    ├── NATS Server (messaging, /nats/ monitoring)
    ├── PostgreSQL (pre-configured databases)
    ├── Redis (3 instances: gitlab, penpot, matrix)
    ├── Dashboard (elegant service overview)
    └── Penpot (design platform, Docker-based)
```

**🔥 IMPORTANT - Complete Service URLs:**
- **Dashboard**: https://localhost:8443/ (service overview)
- **GitLab**: https://localhost:8443/gitlab/ (root/admin123456)
- **Grafana**: https://localhost:8443/grafana/ (admin/admin123)
- **Prometheus**: https://localhost:8443/prometheus/ (metrics)
- **NATS**: https://localhost:8443/nats/ (monitoring)

## 🚨 RAVE CLI - **MANDATORY** MANAGEMENT METHOD

**IMPORTANT**: The RAVE CLI is the **ONLY SUPPORTED METHOD** for VM management. All other approaches are deprecated and **MUST NOT** be used.

**❌ FORBIDDEN METHODS:**
- ❌ Manual `qemu-system-x86_64` commands - **STRICTLY PROHIBITED**
- ❌ Any direct QEMU launching - **FORBIDDEN**

### Prerequisites Check (**MANDATORY FIRST STEP**)
```bash
# Check system requirements first - MUST RUN BEFORE ANYTHING
./cli/rave prerequisites
```

### VM Management (**REQUIRED WORKFLOW**)
```bash
# Create a company development environment
./cli/rave vm create my-company --keypair ~/.ssh/id_rsa

# Start VM
./cli/rave vm start my-company

# Check VM status
./cli/rave vm status my-company
./cli/rave vm status --all  # Show all VMs

# SSH into VM
./cli/rave vm ssh my-company

# View service logs  
./cli/rave vm logs my-company nginx
./cli/rave vm logs my-company --follow
./cli/rave vm logs my-company --all

# Stop VM
./cli/rave vm stop my-company

# Reset VM to clean state
./cli/rave vm reset my-company
```

### User Management
```bash
# Add user via GitLab OAuth
./cli/rave user add user@company.com --oauth-id 12345 --access developer --company my-company

# List users
./cli/rave user list
./cli/rave user list --company my-company

# Show user details
./cli/rave user show user@company.com

# Configure user access level
./cli/rave user config user@company.com --access admin

# Remove user
./cli/rave user remove user@company.com

# Bulk add users from CSV/JSON
./cli/rave user bulk-add users.csv --company my-company

# Export users
./cli/rave user export users.csv --format csv --company my-company

# Sync with GitLab
./cli/rave user sync

# View user activity and permissions
./cli/rave user activity user@company.com
./cli/rave user permissions user@company.com
```

### OAuth Configuration
```bash
# Configure OAuth for services
./cli/rave oauth config penpot --provider gitlab --client-id CLIENT_ID --client-secret CLIENT_SECRET
./cli/rave oauth config element --provider gitlab --client-id CLIENT_ID --client-secret CLIENT_SECRET

# Check OAuth status
./cli/rave oauth status
./cli/rave oauth status penpot
```

## 🔧 ENVIRONMENT CONFIGURATION

### SOPS Configuration (REQUIRED)
**CRITICAL**: The VM requires SOPS_AGE_KEY environment variable to decrypt secrets. This was the root cause of previous SOPS initialization failures.

```bash
# Set your AGE key for SOPS secret decryption
export SOPS_AGE_KEY=$(grep '^AGE-SECRET-KEY' ~/.config/sops/age/keys.txt)

# Verify your AGE key is available
echo $SOPS_AGE_KEY | head -c 50
# Should output: AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**Environment Files:**
- `.env` - Contains your actual configuration including SOPS_AGE_KEY
- `.env.example` - Template with placeholder values for all required variables

**Key Environment Variables:**
```bash
# SOPS Configuration - REQUIRED for VM secret management
SOPS_AGE_KEY=$(grep '^AGE-SECRET-KEY' ~/.config/sops/age/keys.txt)

# OAuth Configuration
GOOGLE_OAUTH_CLIENT_ID=your-google-oauth-client-id
GOOGLE_OAUTH_CLIENT_SECRET=your-google-oauth-client-secret
GITHUB_OAUTH_CLIENT_ID=your-github-oauth-client-id
GITHUB_OAUTH_CLIENT_SECRET=your-github-oauth-client-secret
```

**⚠️ Important Notes:**
- Without SOPS_AGE_KEY, the VM will fail with "FAILED Failed to start Initialize SOPS secrets"
- The AGE key must match your `~/.config/sops/age/keys.txt` file
- This variable must be set when starting VMs either via CLI or manual commands

## 🚀 CONSOLIDATED BUILD COMMANDS (Current - August 2025)

### Primary Build Process (ALWAYS USE THIS)
```bash
# Build complete VM (default configuration)
nix build

# Copy and prepare for launch
cp result/nixos.qcow2 rave-complete.qcow2 && chmod 644 rave-complete.qcow2

# Launch complete VM with all services
qemu-system-x86_64 \
  -drive file=rave-complete.qcow2,format=qcow2 \
  -m 8G \
  -smp 4 \
  -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::8889-:8080,hostfwd=tcp::2224-:22,hostfwd=tcp::8443-:443 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
```

### Alternative Build Options (When Needed)
```bash
# Minimal build (basic services only)
nix build .#minimal

# Monitoring-only build (Grafana + Prometheus)  
nix build .#monitoring
```

### 🚨 DEPRECATED BUILD COMMANDS (DO NOT USE)
❌ `nix build .#development` - Old scattered configuration
❌ `nix build .#production` - Legacy configuration  
❌ Multiple VM variants - Consolidation eliminated these

### Passwordless SSH Access
The VM root password is: `debug123`

**SSH Commands:**
```bash
# Using sshpass (recommended)
sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224

# If SSH key changes after VM rebuild:
ssh-keygen -f '/home/nathan/.ssh/known_hosts' -R '[localhost]:2224'
```

### Testing VM Services
```bash
# Test HTTP (should redirect to HTTPS)
curl -I http://localhost:8081/

# Test HTTPS with SSL
curl -k https://localhost:8443/

# Test VM status page
curl http://localhost:8889/

# Test NATS monitoring (through nginx proxy)
curl -k https://localhost:8443/nats/

# Test SSH connectivity
sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224 "echo 'VM accessible'"
```

## Service Management

### Inside the VM (via SSH):
```bash
# Check all services
systemctl status nginx redis postgresql nats generate-dev-certs

# Check nginx logs
journalctl -u nginx.service -f

# Check certificate generation
systemctl status generate-dev-certs.service
ls -la /var/lib/acme/rave.local/

# Restart nginx if needed
systemctl restart nginx.service
```

### Expected Service Status (Complete Configuration):
- ✅ **nginx**: `active (running)` with SSL certificates (localhost domain)
- ✅ **GitLab**: `active (running)` with pre-configured database
- ✅ **Grafana**: `active (running)` on localhost:3000, proxied via /grafana/
- ✅ **Prometheus**: `active (running)` with exporters and scraping configured
- ✅ **NATS**: `active (running)` on internal port 4222 with JetStream
- ✅ **PostgreSQL**: `active (running)` with gitlab, grafana, penpot databases
- ✅ **Redis instances**: gitlab (6379), penpot (6380), matrix (6381)  
- 🔄 **Penpot**: Docker containers downloading/starting (may take 5-10min)
- ❌ **Matrix/Element**: Disabled (NixOS 24.11 compatibility issues)

## SSL Certificates (Consolidated Configuration)

The complete VM uses self-signed certificates for localhost development:
- **Domain**: `localhost` (fixed from old rave.local issues)
- **Location**: `/var/lib/acme/localhost/` 
- **Files**: `cert.pem`, `key.pem`, `ca.pem`
- **Auto-Generated**: certificates created on first boot
- **No Manual Setup**: all permissions and generation handled automatically

### Certificate Troubleshooting:
If nginx fails with SSL permission errors:
```bash
# Check certificate permissions
ls -la /var/lib/acme/rave.local/

# Fix permissions if needed
chmod 640 /var/lib/acme/rave.local/key.pem
chgrp nginx /var/lib/acme/rave.local/{cert.pem,key.pem}

# Restart nginx
systemctl restart nginx.service
```

## ⚙️ CURRENT CONFIGURATION STRUCTURE (Post-Consolidation)

### 🔥 PRIMARY FILES (Current):
- **`nixos/configs/complete-production.nix`** - **MAIN CONFIGURATION** (Use This!)
- **`flake.nix`** - Streamlined build targets (default = complete)
- **`nixos/modules/`** - Supporting modules (certificates, security, services)

### Key Configuration Features:
```nix
# Complete configuration includes:
- SSH: root password "debug123" with lib.mkForce overrides  
- SSL: localhost certificates (no rave.local conflicts)
- Services: All pre-configured with proper database setup
- Redis: Fixed list format for save settings  
- Package: nodePackages.npm (not bare "npm")
- Matrix: Temporarily disabled (NixOS 24.11 compatibility)
```

### 🚨 LEGACY FILES (Do Not Modify):
- ❌ `nixos/configs/development.nix` - Old development config
- ❌ `nixos/configs/production.nix` - Old production config  
- ❌ Multiple other configs - Replaced by complete-production.nix

## Troubleshooting

### VM Won't Start:
1. Check if old VM processes are running: `pkill -f qemu-system`
2. Ensure image permissions: `chmod 644 rave-dev.qcow2`
3. Check available memory (VM needs 4GB)

### nginx SSL Errors:
```bash
# Common error: "Permission denied" accessing key.pem
# Solution: Fix key permissions
sshpass -p 'debug123' ssh root@localhost -p 2224 \
  "chmod 640 /var/lib/acme/rave.local/key.pem && systemctl restart nginx"
```

### SSH Connection Issues:
```bash
# Remove old host key and try again
ssh-keygen -f '/home/nathan/.ssh/known_hosts' -R '[localhost]:2224'
sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224
```

### Service Not Running:
```bash
# Check service status and logs
sshpass -p 'debug123' ssh root@localhost -p 2224 \
  "systemctl status SERVICE_NAME && journalctl -u SERVICE_NAME -n 20"
```

## 🔄 DEVELOPMENT WORKFLOW (**RAVE CLI ONLY**)

### **MANDATORY WORKFLOW** - Use RAVE CLI:
```bash
# 1. Check prerequisites (REQUIRED FIRST)
./cli/rave prerequisites

# 2. Create development environment (REQUIRED)
./cli/rave vm create my-project --keypair ~/.ssh/your-key

# 3. Start VM (REQUIRED)
./cli/rave vm start my-project

# 4. Check status (RECOMMENDED)
./cli/rave vm status my-project

# 5. Access services at https://localhost:8443/
```

### **⚠️ LEGACY BUILD WORKFLOW** (Only for VM image creation):
```bash
# ⚠️ WARNING: This is ONLY for creating VM images, NOT for running VMs
# Use RAVE CLI for all VM operations instead!

# Build complete VM image (for RAVE CLI to use)
nix build

# The RAVE CLI will automatically use this image
# DO NOT manually launch qemu-system-x86_64 commands!
```

### **IMPORTANT WORKFLOW RULES:**
1. **MUST use RAVE CLI**: Never bypass the CLI for VM operations
2. **Build for CLI**: `nix build` creates images that RAVE CLI uses automatically
3. **No manual QEMU**: Direct QEMU launching is forbidden and unsupported
4. **Wait for services**: VM boot takes 2-3 minutes for all services to start
5. **Use CLI for SSH**: `./cli/rave vm ssh my-project` instead of manual SSH

### When to Rebuild:
- Configuration changes in `nixos/configs/complete-production.nix`
- Flake updates or dependency changes
- Adding/removing services from the complete build

## Port Reference
- `8081` - HTTP (redirects to HTTPS)
- `8443` - HTTPS with SSL certificates  
- `8889` - VM test page (direct HTTP)
- `2224` - SSH access (root:debug123)

## Security Notes
- VM uses self-signed certificates (not for production)
- Root password is hardcoded for development ease
- SSH accepts password authentication
- All services run with development-friendly settings

## GitLab Integration

### GitLab Access
- **URL**: https://localhost:8443/gitlab/
- **Boot time**: 3-5 minutes after VM start
- **Routing**: Fixed subdirectory routing with proper `/gitlab/` prefix
- **Status check**: GitLab shows "Waiting for GitLab to boot" page during startup

### GitLab Configuration
GitLab is configured with:
- Subdirectory deployment at `/gitlab/` path
- PostgreSQL database backend
- Redis for caching and sessions
- Proper nginx reverse proxy configuration
- OAuth integration ready for Matrix/Element

### Service Status Commands
```bash
# Check GitLab service status via SSH
sshpass -p 'debug123' ssh root@localhost -p 2224 "systemctl status gitlab"

# Start GitLab if not running
sshpass -p 'debug123' ssh root@localhost -p 2224 "systemctl start gitlab"

# View GitLab logs
sshpass -p 'debug123' ssh root@localhost -p 2224 "journalctl -u gitlab -f"
```

## Dashboard Interface

The VM includes an elegant dashboard at the root HTTPS URL:
- **URL**: https://localhost:8443/
- **Features**: Service status indicators, Lucide icons, modern design
- **Services**: GitLab, Matrix/Element (planned), Penpot (planned)
- **Style**: Michroma font with blue gradient header

## CLI Configuration

The RAVE CLI is located at `./cli/rave` and provides comprehensive management:
- **VM Management**: Multi-company VM lifecycle management
- **User Management**: GitLab OAuth integration with bulk operations
- **OAuth Configuration**: Service-specific OAuth setup
- **Prerequisites**: System dependency checking
- **Logging**: Service-specific log viewing with follow mode

### CLI Dependencies
The CLI requires these Python packages (see `cli/requirements.txt`):
- `click` - Command line interface framework
- Platform-specific utilities for VM management
- OAuth integration libraries

## 🚀 CURRENT STATUS & NEXT STEPS (August 2025)

### ✅ COMPLETED CONSOLIDATION:
- **Unified Build**: Single `nix build` command for complete VM
- **All Services**: GitLab, Grafana, Prometheus, NATS, PostgreSQL, Redis, nginx
- **Fixed Issues**: SSH conflicts, Redis format, domain configurations, build errors
- **Localhost Optimized**: No more rave.local domain issues
- **Auto-Configuration**: Databases, users, certificates all pre-configured

### 🔄 IN PROGRESS:
- **Penpot Integration**: Docker images download on first boot (5-10min)
- **RAVE CLI**: Management interface for multi-VM operations
- **Performance Tuning**: VM resource allocation optimized for all services

### 🔮 FUTURE ENHANCEMENTS:
- **Matrix/Element**: Re-enable once NixOS 24.11 compatibility resolved
- **OAuth Integration**: Complete GitLab OAuth for all services  
- **Multi-Company**: RAVE CLI multi-tenant VM management
- **Monitoring**: Enhanced Grafana dashboards and alerting

### 🚨 **MANDATORY** RULES FOR FUTURE CLAUDE SESSIONS:
- **MUST ALWAYS USE**: RAVE CLI (`./cli/rave vm`) for ALL VM operations
- **FORBIDDEN**: Manual QEMU commands
- **Build system**: `nix build` (complete configuration) - for VM image creation only
- **Primary file**: `nixos/configs/complete-production.nix`
- **VM access**: Use `./cli/rave vm ssh project-name` instead of manual SSH
- **Service URLs**: https://localhost:8443/ (dashboard shows all services)
- **No scattered builds**: Consolidation phase is COMPLETE
- **CLI FIRST**: Always check `./cli/rave vm status --all` before any operations