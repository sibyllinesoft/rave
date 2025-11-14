# P1 Security Hardening - Production Setup Guide

## Overview

Phase P1 security hardening has been fully implemented with comprehensive security controls. This guide covers the final steps needed to deploy P1 in a production environment.

## 🔒 Security Architecture

### Implemented Security Controls

- **P1.1**: SSH hardening, firewall restrictions, user security
- **P1.2**: sops-nix encrypted secrets management 
- **P1.3**: Webhook dispatcher with signature verification and event deduplication
- **P1.4**: Automated vulnerability scanning with SAFE thresholds

### Security Layers

1. **Network Layer**: Firewall restricts to ports 22 (SSH) and 3002 (HTTPS) only
2. **Transport Layer**: TLS 1.3 with strong ciphers, security headers
3. **Application Layer**: Webhook signature verification, input validation
4. **System Layer**: Kernel hardening, service isolation, resource limits
5. **Secrets Layer**: Age-encrypted secrets with team-based access control

## 🚀 Production Setup Steps

### Step 1: Generate SSH Keys for Team Access

Generate SSH key pairs for each team member who needs access:

```bash
# For each team member, generate Ed25519 keys
ssh-keygen -t ed25519 -C "security-lead@company.com" -f ~/.ssh/id_rave_security_lead
ssh-keygen -t ed25519 -C "devops-admin@company.com" -f ~/.ssh/id_rave_devops
ssh-keygen -t ed25519 -C "sre-team@company.com" -f ~/.ssh/id_rave_sre

# Extract public keys
cat ~/.ssh/id_rave_security_lead.pub
cat ~/.ssh/id_rave_devops.pub  
cat ~/.ssh/id_rave_sre.pub
```

Update `p1-production-config.nix` with actual public keys:

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... security-lead@company.com"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... devops-admin@company.com"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... sre-team@company.com"
];
```

### Step 2: Set Up sops-nix Encryption

Generate age keys for team members:

```bash
# Each team member generates their age key
age-keygen -o ~/.config/sops/age/keys.txt

# Share public keys securely (via secure channel)
grep "public key:" ~/.config/sops/age/keys.txt
```

Update `.sops.yaml` with actual team public keys:

```yaml
keys:
  - &security_lead age1abc123... # Replace with actual public key
  - &devops_admin age1def456... # Replace with actual public key  
  - &sre_team age1ghi789... # Replace with actual public key
  - &prod_key age1jkl012... # Generated on production server
```

Generate production secrets:

```bash
# Generate strong random secrets
openssl rand -base64 32  # For webhook secrets
openssl rand -base64 64  # For encryption keys
openssl genrsa -out tls-private-key.pem 2048  # For TLS if not using Let's Encrypt

# Encrypt the secrets file
sops -e -i secrets.yaml

# Edit secrets with real values
sops secrets.yaml
```

### Step 3: Configure External Integrations

#### GitLab OAuth Application

1. In GitLab, go to Admin Area → Applications
2. Create new application:
   - Name: `RAVE Grafana OIDC`
   - Redirect URI: `https://your-domain.com:3002/grafana/login/generic_oauth`
   - Scopes: `openid`, `profile`, `email`
3. Note the Application ID and Secret
4. Update secrets.yaml with the OAuth secret

#### GitLab Webhook Configuration

1. In your GitLab project, go to Settings → Webhooks
2. Create webhook:
   - URL: `https://your-domain.com:3002/webhook`
   - Secret Token: (generate with `openssl rand -base64 32`)
   - Trigger: Issues events, Merge request events, Pipeline events
3. Update secrets.yaml with the webhook secret

### Step 4: TLS Certificate Setup

Choose one option:

#### Option A: Let's Encrypt (Recommended)

```bash
# Install certbot on production server
certbot certonly --standalone -d your-domain.com

# Add certificates to secrets.yaml
sops secrets.yaml
# Add the certificate and key content
```

#### Option B: Internal CA Certificate

```bash
# Generate certificate with your internal CA
# Add certificate and key to secrets.yaml
```

### Step 5: Deploy and Verify

Deploy the P1 configuration:

```bash
# Build P1 production image
nix build .#p1-production

# Deploy to production server
qemu-system-x86_64 -m 4096 -smp 2 -enable-kvm \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3002-:3002 \
  -device virtio-net-pci,netdev=net0 \
  -hda result/nixos.qcow2

# SSH into the system (should only work with keys)
ssh -i ~/.ssh/id_rave_security_lead -p 2222 agent@localhost
```

Run security verification:

```bash
# Inside the VM or via SSH
./scripts/security/p1-security-verification.sh
./scripts/security/p1-status-summary.sh
```

### Step 6: Security Testing

Perform security validation:

```bash
# Test SSH access (should fail without keys)
ssh -p 2222 agent@localhost  # Should fail

# Test webhook signature verification
curl -X POST https://your-domain.com:3002/webhook \
  -H "Content-Type: application/json" \
  -H "X-Gitlab-Token: invalid-signature" \
  -d '{"test": "event"}'
# Should return 401 Unauthorized

# Test firewall (should timeout on blocked ports)
nmap -p 80,443,8080 your-domain.com  # Should show closed/filtered
nmap -p 22,3002 your-domain.com      # Should show open
```

## 🔍 Security Monitoring

### Log Monitoring

Monitor these security events:

```bash
# SSH authentication attempts
journalctl -u sshd -f | grep "authentication failure\|Invalid user"

# Webhook dispatcher security events
journalctl -u webhook-dispatcher -f | grep "signature\|unauthorized"

# Firewall blocked connections
journalctl -u firewall -f | grep "DROP\|REJECT"

# Service security violations
journalctl | grep "audit\|security\|violation"
```

### Security Metrics

Track these security metrics:

- SSH authentication failure rate
- Webhook signature verification failures  
- Vulnerability scan results trend
- Secret access audit logs
- Service resource usage vs limits

## 🚨 Incident Response

### Emergency Procedures

#### Compromised SSH Key
```bash
# Remove compromised key from authorized_keys
# Redeploy P1 configuration
# Rotate all affected secrets
```

#### Webhook Signature Compromise
```bash
# Rotate webhook secret in GitLab and secrets.yaml
# Redeploy P1 configuration
# Monitor for unauthorized webhook attempts
```

#### Secret Compromise
```bash
# Rotate affected secrets immediately
# Re-encrypt secrets.yaml with sops
# Redeploy and verify secret access
# Audit access logs for breach timeline
```

## ✅ Production Readiness Checklist

- [ ] Team SSH public keys added to p1-production-config.nix
- [ ] Age keys generated and distributed to team members
- [ ] secrets.yaml encrypted with production values
- [ ] GitLab OAuth application configured
- [ ] GitLab webhook configured with secret
- [ ] TLS certificates configured (Let's Encrypt or internal CA)
- [ ] Production domain/hostname configured
- [ ] Security verification tests passed
- [ ] Monitoring and alerting configured
- [ ] Incident response procedures documented
- [ ] Team trained on sops-nix usage
- [ ] Backup and recovery procedures tested

## 📚 Additional Resources

- [sops-nix Documentation](https://github.com/Mic92/sops-nix)
- [Age Encryption Specification](https://age-encryption.org/)
- [OWASP Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/)
- [NixOS Security Hardening Guide](https://nixos.org/manual/infra/nixos/stable/index.html#sec-hardening)

## 🔄 Maintenance Schedule

### Daily
- Review security logs for anomalies
- Verify vulnerability scan results
- Monitor service health and resource usage

### Weekly  
- Review SSH access logs
- Update Trivy vulnerability database
- Verify backup integrity

### Monthly
- Rotate non-critical secrets
- Review and update security documentation
- Conduct security configuration audit

### Quarterly
- Rotate critical secrets (TLS certificates, etc.)
- Conduct penetration testing
- Review and update incident response procedures
- Team security training refresh