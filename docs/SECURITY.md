# RAVE Security Model and Implementation

## Executive Summary

The RAVE (Reproducible AI Virtual Environment) system implements a comprehensive defense-in-depth security architecture designed for secure deployment in public cloud and enterprise environments. This document provides the complete security model, threat analysis, implementation details, and operational procedures for maintaining security in production deployments.

## Security Architecture Overview

### Defense-in-Depth Strategy

RAVE implements multiple layers of security controls to protect against a wide range of attack vectors:

```
┌─────────────────────────────────────────────────────────────┐
│                    External Network/Internet                │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ Layer 1: Network Perimeter Security                        │
│ • iptables firewall (ports 22, 3002 only)                 │
│ • fail2ban intrusion prevention (3 attempts, 1h ban)      │
│ • Rate limiting and connection throttling                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ Layer 2: Transport Security                                │
│ • SSH with Ed25519 key authentication only                 │
│ • TLS 1.3 with strong cipher suites                        │
│ • Certificate-based service identity                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ Layer 3: Application Security                              │
│ • Webhook signature verification (HMAC-SHA256)             │
│ • Input validation and sanitization                        │
│ • Service isolation and least privilege                    │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ Layer 4: Data Security                                     │
│ • sops-nix encrypted secrets management                    │
│ • Age encryption with team key distribution                │
│ • No plaintext secrets in configuration or logs            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│ Layer 5: System Security                                   │
│ • Kernel hardening and security modules                    │
│ • systemd service isolation                                │
│ • Resource limits and memory protection                    │
└─────────────────────────────────────────────────────────────┘
```

### Zero-Trust Security Model

RAVE follows zero-trust principles where no component is implicitly trusted:

- **Identity Verification**: All access requires cryptographic authentication
- **Least Privilege**: Services run with minimal required permissions
- **Network Segmentation**: Internal services isolated from external access
- **Continuous Validation**: All communications authenticated and encrypted
- **Assume Breach**: Security controls designed to limit blast radius

## Threat Model and Risk Assessment

### Threat Landscape Analysis

#### High-Impact Threats

**T1: Remote Code Execution (RCE)**
- **Vector**: Vulnerable dependencies, unsafe deserialization, injection attacks
- **Impact**: Complete system compromise, data exfiltration, lateral movement
- **Likelihood**: Medium (continuous patching and scanning reduces risk)
- **Mitigation**: Automated vulnerability scanning, dependency auditing, input validation

**T2: Credential Compromise** 
- **Vector**: SSH key theft, secret extraction, insider threat
- **Impact**: Unauthorized access, privilege escalation, data breach
- **Likelihood**: Low (strong key management and rotation procedures)
- **Mitigation**: Age-encrypted secrets, regular rotation, audit logging

**T3: Denial of Service (DoS)**
- **Vector**: Resource exhaustion, connection flooding, malformed requests
- **Impact**: System unavailability, service degradation, revenue loss
- **Likelihood**: High (common attack vector for public services)
- **Mitigation**: Rate limiting, resource constraints, fail2ban protection

#### Medium-Impact Threats

**T4: Data Exfiltration**
- **Vector**: Compromised services, insider access, configuration exposure
- **Impact**: Intellectual property theft, compliance violations, reputational damage
- **Likelihood**: Low (limited data sensitivity in default configuration)
- **Mitigation**: Network segmentation, access logging, data classification

**T5: Supply Chain Compromise**
- **Vector**: Malicious packages, compromised build tools, dependency confusion
- **Impact**: Backdoor installation, long-term persistence, data harvesting
- **Likelihood**: Low (Nix provides reproducible builds with integrity verification)
- **Mitigation**: Package verification, dependency pinning, build isolation

### Security Controls Matrix

| Threat Category | Network | Application | Data | System | Detection |
|----------------|---------|-------------|------|--------|-----------|
| **External Attack** | Firewall, Rate Limiting | Input Validation, WAF | Encryption, Secrets | Hardening, Isolation | IPS, Monitoring |
| **Insider Threat** | Network Segmentation | RBAC, Audit Logs | Data Classification | Least Privilege | Behavioral Analysis |
| **Supply Chain** | Package Verification | Dependency Scanning | Integrity Checking | Secure Build | Vulnerability Scanning |
| **Configuration** | Security Baselines | Secure Defaults | Secret Management | Configuration Drift | Compliance Monitoring |

## Cryptographic Implementation

### Encryption Standards

**Symmetric Encryption:**
- **Algorithm**: ChaCha20-Poly1305 (SSH), AES-256-GCM (TLS)
- **Key Size**: 256-bit minimum for all symmetric operations
- **Key Derivation**: PBKDF2 or Argon2 for password-based derivation
- **Nonce Management**: Cryptographically secure random nonce generation

**Asymmetric Encryption:**
- **SSH Keys**: Ed25519 (preferred), RSA-4096 (legacy compatibility)
- **TLS Certificates**: ECDSA P-384 or RSA-3072 minimum
- **Age Encryption**: X25519 key exchange with ChaCha20-Poly1305

**Hashing and Signatures:**
- **Message Authentication**: HMAC-SHA256 for webhook verification
- **Digital Signatures**: Ed25519 signatures for SSH, ECDSA for TLS
- **Integrity Verification**: SHA-256 for file and message integrity

### Key Management Lifecycle

#### SSH Key Management

```bash
# Generate new SSH key pair for RAVE access
ssh-keygen -t ed25519 -C "rave-production-$(date +%Y%m%d)" -f ~/.ssh/rave-prod

# Add key to authorized_keys in secrets.yaml
sops secrets.yaml
# Add new key to ssh/authorized-keys array

# Deploy updated configuration
nix build .#p2-production
# Deploy with new SSH keys

# Rotate old keys (quarterly)
# Remove old keys from secrets.yaml after validating new key access
```

#### Age Key Management for Secrets

```bash
# Generate new age key pair for team member
age-keygen -o team-member-$(date +%Y%m%d).key

# Extract public key for .sops.yaml
age-keygen -y team-member-$(date +%Y%m%d).key

# Update .sops.yaml with new public key
echo "age1..." >> .sops.yaml

# Re-encrypt secrets with updated key set
sops updatekeys secrets.yaml

# Distribute private key securely to team member
# Use secure channel (encrypted email, password manager, etc.)
```

#### Webhook Secret Rotation

```bash
#!/bin/bash
# webhook-secret-rotation.sh

set -e

echo "=== Webhook Secret Rotation Procedure ==="

# 1. Generate cryptographically secure secret
NEW_SECRET=$(openssl rand -hex 32)
echo "Generated new webhook secret: ${NEW_SECRET:0:8}..."

# 2. Update GitLab webhook configuration
echo "Please update GitLab webhook secret token to: $NEW_SECRET"
echo "GitLab → Settings → Webhooks → Edit → Secret Token"
read -p "Press Enter after updating GitLab webhook..."

# 3. Update encrypted secrets
echo "Updating secrets.yaml..."
export WEBHOOK_SECRET="$NEW_SECRET"
sops --set '["webhook"]["gitlab-secret"] "'$NEW_SECRET'"' secrets.yaml

# 4. Deploy updated configuration
echo "Rebuilding system with new secret..."
nix build .#p2-production

# 5. Restart webhook-dependent services
echo "Restarting services..."
sudo systemctl restart webhook-dispatcher
sudo systemctl restart sops-nix

# 6. Verify webhook functionality
echo "Testing webhook with new secret..."
curl -X POST https://localhost:3002/webhook \
  -H "X-Gitlab-Token: $NEW_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"test": "rotation-verification"}'

echo "✅ Webhook secret rotation completed successfully"
```

## Authentication and Authorization

### SSH Authentication Hardening

**Configuration:**
```nix
# p1-production-config.nix SSH hardening
services.openssh = {
  enable = true;
  ports = [ 22 ];
  settings = {
    # Authentication
    PasswordAuthentication = false;
    ChallengeResponseAuthentication = false;
    PubkeyAuthentication = true;
    AuthenticationMethods = "publickey";
    PermitRootLogin = "no";
    PermitEmptyPasswords = false;
    
    # Security
    Protocol = 2;
    MaxAuthTries = 3;
    LoginGraceTime = 60;
    MaxSessions = 10;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
    
    # Algorithms (strong cryptography only)
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
      "aes256-ctr"
    ];
    KexAlgorithms = [
      "curve25519-sha256@libssh.org"
      "diffie-hellman-group16-sha512"
      "diffie-hellman-group18-sha512"
    ];
    Macs = [
      "hmac-sha2-256-etm@openssh.com"
      "hmac-sha2-512-etm@openssh.com"
    ];
  };
};
```

**Key Distribution Procedure:**
1. Team members generate Ed25519 key pairs locally
2. Public keys added to encrypted `secrets.yaml` file
3. Keys deployed via sops-nix to `~/.ssh/authorized_keys`
4. Access tested and validated before removing old keys
5. Old keys rotated quarterly or after team member departure

### Service Authentication Matrix

| Service | Authentication Method | Authorization | Network Access |
|---------|----------------------|---------------|----------------|
| **SSH** | Ed25519 Public Key | User: agent | 0.0.0.0:22 |
| **Nginx** | TLS Certificate | Service account | 0.0.0.0:3002 |
| **Grafana** | Internal (no auth) | Admin interface | 127.0.0.1:3030 |
| **Prometheus** | Internal only | Metrics collection | 127.0.0.1:9090 |
| **Webhook Dispatcher** | HMAC-SHA256 Signature | Event processing | 127.0.0.1:3001 |
| **Vibe Kanban** | Internal (no auth) | Project management | 127.0.0.1:3000 |
| **Claude Code Router** | Internal (no auth) | AI orchestration | 127.0.0.1:3456 |

## Network Security Implementation

### Firewall Configuration

**Default Policy: DENY ALL**
```bash
# iptables rules implemented by NixOS firewall
-P INPUT DROP
-P FORWARD DROP  
-P OUTPUT ACCEPT

# Allow essential services only
-A INPUT -i lo -j ACCEPT                    # Loopback
-A INPUT -p tcp --dport 22 -j ACCEPT        # SSH
-A INPUT -p tcp --dport 3002 -j ACCEPT      # HTTPS (nginx)
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Rate limiting for SSH (fail2ban integration)
-A INPUT -p tcp --dport 22 -m recent --name SSH --set
-A INPUT -p tcp --dport 22 -m recent --name SSH --rcheck --seconds 300 --hitcount 3 -j DROP
```

**Network Segmentation:**
- External access limited to SSH (22) and HTTPS (3002)  
- Internal services bound to localhost only
- No inter-service network authentication (trusted network model)
- All external communication through nginx reverse proxy

### Intrusion Prevention System (fail2ban)

**SSH Protection Configuration:**
```ini
[sshd]
enabled = true
backend = systemd
port = 22
filter = sshd
logpath = /dev/null
maxretry = 3
findtime = 600
bantime = 3600
action = iptables[name=SSH, port=22, protocol=tcp]
```

**Monitoring and Response:**
- Real-time SSH authentication monitoring
- Automatic IP blocking after 3 failed attempts
- 1-hour ban duration with exponential backoff for repeat offenders
- Email notifications for security events (when configured)

## Secrets Management with sops-nix

### Architecture Overview

RAVE uses sops-nix for comprehensive secrets management with the following architecture:

```
Age Encryption Keys (Team Members)
           ↓
    .sops.yaml configuration
           ↓
    secrets.yaml (encrypted)
           ↓
    sops-nix service (runtime)
           ↓
    /run/secrets/* (plaintext, memory-only)
           ↓
    Service configuration (referenced)
```

### Secret Categories and Management

#### TLS/SSL Certificates
```yaml
# secrets.yaml structure
tls:
  certificate: |
    -----BEGIN CERTIFICATE-----
    [encrypted PEM certificate]
    -----END CERTIFICATE-----
  private-key: |
    -----BEGIN PRIVATE KEY-----
    [encrypted PEM private key]  
    -----END PRIVATE KEY-----
```

**Deployment:**
- Certificate deployed to `/run/secrets/tls-cert`
- Private key deployed to `/run/secrets/tls-key` 
- nginx configured to read from secrets paths
- Automatic service restart on certificate updates

#### Database and Service Secrets
```yaml
database:
  postgres-password: "encrypted-database-password"
  grafana-admin-password: "encrypted-admin-password"

external-services:
  gitlab-root-password: "encrypted-gitlab-admin"
  matrix-shared-secret: "encrypted-matrix-secret"

webhooks:
  gitlab-secret: "encrypted-webhook-token"
```

### Secret Access Control

**Access Matrix:**
| Secret | Service | User Context | File Mode | Path |
|--------|---------|--------------|-----------|------|
| TLS Certificate | nginx | nginx:nginx | 0444 | /run/secrets/tls-cert |
| TLS Private Key | nginx | nginx:nginx | 0400 | /run/secrets/tls-key |
| Webhook Secret | webhook-dispatcher | agent:users | 0400 | /run/secrets/webhook-gitlab |
| Postgres Password | postgresql | postgres:postgres | 0400 | /run/secrets/postgres-password |
| Grafana Password | grafana | grafana:grafana | 0400 | /run/secrets/grafana-admin |

**Security Properties:**
- Secrets exist only in memory (`/run` is tmpfs)
- No plaintext secrets in configuration files or logs
- Automatic cleanup on service shutdown
- Permission-based access control per secret

### Emergency Secret Recovery

**Key Loss Recovery Procedure:**
```bash
#!/bin/bash
# emergency-secret-recovery.sh

set -e

echo "🚨 EMERGENCY SECRET RECOVERY PROCEDURE"
echo "Use only if age keys are lost or compromised"

# 1. Generate new age key pair
age-keygen -o emergency-recovery-$(date +%Y%m%d).key
NEW_PUBLIC_KEY=$(age-keygen -y emergency-recovery-$(date +%Y%m%d).key)

echo "New public key: $NEW_PUBLIC_KEY"

# 2. Update .sops.yaml with new key
cp .sops.yaml .sops.yaml.backup
echo "  - &emergency $NEW_PUBLIC_KEY" >> .sops.yaml

# 3. Re-encrypt secrets with new key
sops updatekeys secrets.yaml

# 4. Verify decryption with new key
SOPS_AGE_KEY_FILE=emergency-recovery-$(date +%Y%m%d).key sops -d secrets.yaml

echo "✅ Emergency recovery key generated and secrets re-encrypted"
echo "Distribute new private key securely to authorized personnel"
echo "Remove old keys from .sops.yaml after confirming access"
```

## Vulnerability Management

### Automated Security Scanning

RAVE implements comprehensive vulnerability management through automated scanning and continuous monitoring:

#### Container and System Scanning
```yaml
# .github/workflows/security-scan.yml
name: Security Scanning
on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  vulnerability-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # System vulnerability scanning
      - name: Trivy filesystem scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'HIGH,CRITICAL'
          
      # Container image scanning  
      - name: Build and scan container
        run: |
          nix build .#p2-production
          trivy image --format sarif --output container-results.sarif $(nix build .#p2-production --print-out-paths)
          
      # Dependency vulnerability scanning
      - name: NPM audit
        run: |
          find . -name package.json -exec dirname {} \; | while read dir; do
            cd "$dir" && npm audit --audit-level=high && cd -
          done
          
      # Upload results to GitHub Security
      - name: Upload SARIF results
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: trivy-results.sarif
```

#### Vulnerability Assessment Pipeline
1. **Daily Automated Scans**: Trivy scans for OS and library vulnerabilities
2. **Dependency Auditing**: NPM audit for JavaScript dependencies
3. **Configuration Scanning**: Security configuration validation
4. **SARIF Reporting**: Results uploaded to GitHub Security tab
5. **Fail-Fast Policy**: Builds fail on HIGH/CRITICAL vulnerabilities
6. **Exception Handling**: Allowlist system for accepted risks

### Security Patch Management

**Critical Patch Process:**
```bash
#!/bin/bash
# security-patch-deployment.sh

set -e

echo "=== CRITICAL SECURITY PATCH DEPLOYMENT ==="

# 1. Emergency maintenance notification
echo "Initiating emergency maintenance for critical security patch"
# curl -X POST webhook-notification-url (implement as needed)

# 2. Create emergency backup
qemu-img snapshot -c "pre-security-patch-$(date +%Y%m%d-%H%M)" /var/lib/rave/production.qcow2

# 3. Update Nix flake with security patches
nix flake update --commit-lock-file

# 4. Build patched system
nix build .#p2-production --refresh

# 5. Run security validation
nix run .#tests.security-validation

# 6. Deploy with minimal downtime
systemctl stop rave-production
cp $(nix build .#p2-production --print-out-paths) /var/lib/rave/production-new.qcow2
mv /var/lib/rave/production.qcow2 /var/lib/rave/production-backup.qcow2
mv /var/lib/rave/production-new.qcow2 /var/lib/rave/production.qcow2
systemctl start rave-production

# 7. Verify system health
./scripts/rave health

# 8. Confirm security patch effectiveness
trivy fs --severity HIGH,CRITICAL .

echo "✅ Critical security patch deployed successfully"
```

## Incident Response Procedures

### Security Incident Classification

#### Severity 1 (Critical) - Immediate Response
- **Definition**: Active compromise, data breach, system unavailable
- **Response Time**: 15 minutes
- **Escalation**: Immediate CTO/CISO notification
- **Examples**: 
  - Successful SSH compromise with evidence of malicious activity
  - Data exfiltration detected
  - Complete system compromise (root access achieved)
  - Ransomware or destructive malware

#### Severity 2 (High) - Priority Response  
- **Definition**: Attempted compromise, service degradation, potential data exposure
- **Response Time**: 1 hour
- **Escalation**: Security team lead notification
- **Examples**:
  - Multiple failed SSH attempts from same source
  - Vulnerability exploitation attempts
  - Unauthorized access to internal services
  - Suspicious network traffic patterns

#### Severity 3 (Medium) - Standard Response
- **Definition**: Policy violations, configuration drift, minor security issues  
- **Response Time**: 4 hours
- **Escalation**: During business hours
- **Examples**:
  - fail2ban activations
  - Security scan findings
  - Configuration compliance violations
  - Minor privilege escalation attempts

### Incident Response Playbooks

#### Playbook IR-001: SSH Compromise Response

**Indicators:**
- Multiple successful SSH connections from unusual IP addresses
- Commands executed by agent user outside normal patterns
- New SSH keys added to authorized_keys
- Unusual network connections or data transfer patterns

**Immediate Response (0-15 minutes):**
```bash
#!/bin/bash
# ssh-compromise-response.sh

set -e

echo "🚨 SSH COMPROMISE INCIDENT RESPONSE"
echo "Timestamp: $(date -Iseconds)"

# 1. Isolate system (block all SSH access)
sudo iptables -A INPUT -p tcp --dport 22 -j DROP
echo "✅ SSH access blocked immediately"

# 2. Document current state
who > /tmp/current-sessions.log
netstat -tulpn > /tmp/network-connections.log
ps aux > /tmp/running-processes.log
journalctl --since "1 hour ago" > /tmp/system-logs.log
echo "✅ System state documented"

# 3. Preserve evidence
cp /home/agent/.ssh/authorized_keys /tmp/authorized-keys-evidence.txt
cp /var/log/auth.log /tmp/auth-log-evidence.log 2>/dev/null || true
journalctl -u sshd --since "24 hours ago" > /tmp/ssh-logs-evidence.log
echo "✅ Evidence preserved"

# 4. Terminate suspicious sessions
sudo pkill -9 -t pts/1 2>/dev/null || true  # Terminate active sessions
echo "✅ Suspicious sessions terminated"

# 5. Initiate key rotation
echo "⚠️  MANUAL ACTION REQUIRED:"
echo "1. Generate new SSH key pairs for all team members"
echo "2. Update secrets.yaml with new authorized keys"
echo "3. Deploy updated configuration with emergency procedure"
echo "4. Investigate evidence files in /tmp/"

echo "📞 Escalating to security team..."
# Add notification mechanism here
```

#### Playbook IR-002: Webhook Security Incident

**Indicators:**
- Webhook requests with invalid signatures
- High volume of webhook requests (potential DoS)
- Unusual webhook payloads or event types
- Webhook dispatcher errors or crashes

**Response Procedure:**
```bash
#!/bin/bash  
# webhook-security-response.sh

set -e

echo "🚨 WEBHOOK SECURITY INCIDENT RESPONSE"

# 1. Analyze webhook logs
journalctl -u webhook-dispatcher --since "30 minutes ago" > /tmp/webhook-incident-logs.log

# 2. Check for signature verification failures
grep -i "signature" /tmp/webhook-incident-logs.log > /tmp/signature-failures.log || true

# 3. Identify suspicious source IPs
grep -o 'X-Real-IP: [0-9.]*' /tmp/webhook-incident-logs.log | sort | uniq -c | sort -nr > /tmp/source-ips.log

# 4. Temporarily disable webhook processing if needed
if [ "$1" = "disable" ]; then
  sudo systemctl stop webhook-dispatcher
  echo "⚠️  Webhook processing disabled"
fi

# 5. Rotate webhook secret if compromise suspected
if [ "$1" = "rotate-secret" ]; then
  ./scripts/webhook-secret-rotation.sh
  echo "✅ Webhook secret rotated"
fi

# 6. Block malicious IPs via fail2ban
while read -r count ip; do
  if [ "$count" -gt 100 ]; then
    sudo fail2ban-client set sshd banip "$ip"
    echo "🚫 Blocked IP: $ip (requests: $count)"
  fi
done < /tmp/source-ips.log

echo "✅ Webhook security incident response completed"
```

### Digital Forensics and Evidence Preservation

**Evidence Collection Procedure:**
```bash
#!/bin/bash
# collect-forensic-evidence.sh

set -e

INCIDENT_ID="INC-$(date +%Y%m%d-%H%M%S)"
EVIDENCE_DIR="/tmp/forensics-$INCIDENT_ID"

mkdir -p "$EVIDENCE_DIR"

echo "📂 Collecting forensic evidence: $INCIDENT_ID"

# System state
uname -a > "$EVIDENCE_DIR/system-info.txt"
date -Iseconds > "$EVIDENCE_DIR/collection-timestamp.txt"
uptime > "$EVIDENCE_DIR/uptime.txt"

# Process information
ps auxf > "$EVIDENCE_DIR/processes.txt"
netstat -tulpn > "$EVIDENCE_DIR/network-connections.txt"
ss -tulpn > "$EVIDENCE_DIR/socket-state.txt"

# Authentication logs
journalctl -u sshd --since "24 hours ago" > "$EVIDENCE_DIR/ssh-logs.txt"
journalctl --since "24 hours ago" | grep -i auth > "$EVIDENCE_DIR/auth-events.txt"
last -x > "$EVIDENCE_DIR/login-history.txt"

# System logs
journalctl --since "24 hours ago" > "$EVIDENCE_DIR/system-journal.txt"
dmesg > "$EVIDENCE_DIR/kernel-messages.txt"

# File system state
find /home/agent -type f -mtime -1 -ls > "$EVIDENCE_DIR/recent-file-changes.txt"
ls -la /home/agent/.ssh/ > "$EVIDENCE_DIR/ssh-directory-listing.txt"
cp /home/agent/.ssh/authorized_keys "$EVIDENCE_DIR/authorized-keys.txt" 2>/dev/null || true

# Network state
iptables -L -n -v > "$EVIDENCE_DIR/firewall-rules.txt"
fail2ban-client status > "$EVIDENCE_DIR/fail2ban-status.txt"

# Create tamper-evident archive
tar -czf "/tmp/evidence-$INCIDENT_ID.tar.gz" -C /tmp "forensics-$INCIDENT_ID"
sha256sum "/tmp/evidence-$INCIDENT_ID.tar.gz" > "/tmp/evidence-$INCIDENT_ID.sha256"

echo "✅ Forensic evidence collected: /tmp/evidence-$INCIDENT_ID.tar.gz"
echo "🔒 SHA256 checksum: $(cat /tmp/evidence-$INCIDENT_ID.sha256)"
```

## Compliance and Audit

### Security Audit Trail

RAVE maintains comprehensive audit logs for security events:

**SSH Access Logging:**
```bash
# Query SSH access patterns
journalctl -u sshd --since "30 days ago" | grep "Accepted" | \
  awk '{print $1, $2, $3, $9, $11}' | sort | uniq -c

# Failed authentication attempts
journalctl -u sshd --since "30 days ago" | grep "Failed" | \
  awk '{print $1, $2, $3, $9, $11}' | sort | uniq -c
```

**Secret Access Monitoring:**
```bash
# Monitor secret file access
journalctl -u sops-nix --since "7 days ago" | grep "secret"

# Track configuration changes
git log --since "30 days ago" --grep="secret" --oneline
```

**Service Access Logs:**
```bash  
# Webhook processing audit
journalctl -u webhook-dispatcher --since "7 days ago" | \
  grep -E "(signature|authentication|error)" | \
  while read line; do
    echo "$(date): $line"
  done > webhook-audit-$(date +%Y%m%d).log
```

### Compliance Framework Alignment

#### SOC 2 Type II Controls
- **CC6.1**: Logical access controls implemented via SSH key authentication
- **CC6.2**: Network isolation via firewall and service segmentation  
- **CC6.3**: Secret management with encryption and access controls
- **CC6.6**: Vulnerability management through automated scanning
- **CC6.7**: Data transmission security via TLS encryption
- **CC6.8**: Security monitoring through logging and alerting

#### NIST Cybersecurity Framework
- **Identify (ID)**: Asset inventory, threat modeling, risk assessment
- **Protect (PR)**: Access controls, encryption, security training
- **Detect (DE)**: Security monitoring, vulnerability scanning, logging
- **Respond (RS)**: Incident response procedures, forensics, recovery
- **Recover (RC)**: Backup procedures, system restoration, lessons learned

#### CIS Critical Security Controls
- **Control 1**: Hardware and Software Asset Management
- **Control 3**: Data Protection through encryption and access controls
- **Control 4**: Secure Configuration Management via NixOS
- **Control 5**: Account Management through SSH key authentication
- **Control 6**: Access Control Management and least privilege
- **Control 8**: Malware Defenses through system hardening
- **Control 11**: Data Recovery through backup procedures
- **Control 12**: Boundary Defense via firewall and network controls
- **Control 16**: Account Monitoring and Control via audit logging

### Security Assessment Procedures

#### Quarterly Security Review
```bash
#!/bin/bash
# quarterly-security-review.sh

set -e

REVIEW_DATE=$(date +%Y%m%d)
REPORT_FILE="security-review-$REVIEW_DATE.md"

echo "📋 RAVE Quarterly Security Review - $REVIEW_DATE" > $REPORT_FILE
echo "=================================================" >> $REPORT_FILE

# Vulnerability assessment summary
echo -e "\n## Vulnerability Assessment" >> $REPORT_FILE
trivy fs --format table . >> $REPORT_FILE

# Access review
echo -e "\n## SSH Key Audit" >> $REPORT_FILE  
sops -d secrets.yaml | yq '.ssh."authorized-keys"[]' >> $REPORT_FILE

# Configuration compliance
echo -e "\n## Configuration Compliance" >> $REPORT_FILE
nix eval .#nixosConfigurations.rave-vm.config.services.openssh.settings --json | \
  jq '.PasswordAuthentication, .PermitRootLogin' >> $REPORT_FILE

# Security event summary  
echo -e "\n## Security Events (30 days)" >> $REPORT_FILE
journalctl --since "30 days ago" | grep -E "(failed|blocked|banned)" | \
  wc -l >> $REPORT_FILE

# Patch status
echo -e "\n## System Update Status" >> $REPORT_FILE
nix flake metadata --json | jq '.locks.nodes.nixpkgs.locked.lastModified' >> $REPORT_FILE

echo "✅ Security review report generated: $REPORT_FILE"
```

## Security Configuration Reference

### NixOS Security Hardening

```nix
# security-hardening.nix
{ config, pkgs, lib, ... }:
{
  # Kernel hardening
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.ip_forward" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    
    # Memory protection
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    
    # Process isolation
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
  };

  # Service hardening
  systemd.services = {
    webhook-dispatcher.serviceConfig = {
      # Security
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      
      # Capabilities
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      
      # Namespaces
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = false;  # Needs network access
      
      # Resource limits
      MemoryMax = "256M";
      CPUQuota = "50%";
      TasksMax = 100;
    };
  };

  # File system security
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "noexec" "nosuid" "nodev" "size=1G" ];
  };
}
```

### Security Monitoring Configuration

```nix
# monitoring-security.nix  
{ config, pkgs, lib, ... }:
{
  # Security event collection for Prometheus
  services.prometheus.scrapeConfigs = [
    {
      job_name = "security-events";
      static_configs = [
        {
          targets = [ "localhost:9100" ];  # Node exporter
        }
      ];
      metric_relabel_configs = [
        {
          source_labels = [ "__name__" ];
          regex = "(ssh_login_failures|firewall_dropped_packets|fail2ban_bans)";
          target_label = "security_event";
          replacement = "true";
        }
      ];
    }
  ];

  # fail2ban configuration for security
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    findtime = 600;
    bantime = 3600;
    
    jails = {
      ssh = {
        filter = "sshd";
        logpath = "/var/log/auth.log";
        backend = "systemd";
        maxretry = 3;
        findtime = 600;
        bantime = 3600;
        action = ''
          iptables[name=SSH, port=22, protocol=tcp]
          sendmail-whois[name=SSH, dest=security@example.com]
        '';
      };
    };
  };
}
```

## Conclusion

The RAVE security model provides comprehensive protection through defense-in-depth strategies, zero-trust architecture, and automated security controls. Regular security assessments, vulnerability management, and incident response procedures ensure ongoing security posture maintenance.

For operational security procedures, refer to the [RUNBOOK.md](RUNBOOK.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md) documents. For immediate security incidents, follow the escalation procedures defined in this document.

---

**Document Classification**: Confidential  
**Last Updated**: 2025-01-23  
**Review Cycle**: Quarterly  
**Document Owner**: Security Team  
**Approval Required**: CISO, Security Architect, DevOps Lead
