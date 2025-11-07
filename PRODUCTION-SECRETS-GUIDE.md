# Production Secrets Management Guide

> **Heads-up:** Day-to-day provisioning now lives in `docs/how-to/provision-complete-vm.md`. This document remains for legacy context until we extract a dedicated \"Rotate Secrets\" guide.

## 🔐 SOPS + AGE Encryption for Production Deployment

This guide provides the complete process for securely deploying RAVE with encrypted secrets for production use.

## ✅ Current Implementation Status

**WORKING**: The RAVE VM now includes a production-ready SOPS implementation that:
- ✅ **Graceful Fallback**: Services start without blocking when SOPS secrets aren't available
- ✅ **Secure by Default**: All secrets are encrypted in version control using SOPS + AGE
- ✅ **Git-Safe**: Private keys and unencrypted files are automatically excluded from version control
- ✅ **Conditional Services**: GitLab and Mattermost services only require secrets when actually decrypted

## 🚀 Production Deployment Steps

### Step 1: Generate Production AGE Key (One-Time Setup)

```bash
# Install age if not already installed
sudo apt install age  # Ubuntu/Debian
# OR
brew install age      # macOS

# Generate a new AGE key pair for production
age-keygen -o production.agekey

# CRITICAL: Store the PUBLIC key (age1...) in your secrets.yaml
# CRITICAL: Store the PRIVATE key securely (DO NOT commit to git!)
```

**Example Output:**
```
# created: 2024-10-31T20:30:00Z
# public key: age1abcd1234...xyz789
AGE-SECRET-KEY-1ABC...XYZ789
```

### Step 2: Update SOPS Configuration

Edit your `config/secrets.yaml` to use your production AGE public key:

```yaml
sops:
    age:
        - recipient: age1abcd1234...xyz789  # Your production PUBLIC key
```

### Step 3: Re-encrypt All Secrets

```bash
# Re-encrypt the secrets file with your new key
sops updatekeys config/secrets.yaml

# Verify the encryption worked
sops -d config/secrets.yaml  # Should prompt for your private key
```

### Step 4: Deploy Private Key to Production VM

**Option A: VM Environment Variable (Recommended)**
```bash
# On your production host, set the private key
export SOPS_AGE_KEY="AGE-SECRET-KEY-1ABC...XYZ789"

# Start the VM - it will automatically use the key
qemu-system-x86_64 \
  -drive file=rave-production.qcow2,format=qcow2 \
  -m 12G -smp 4 \
  -netdev user,id=net0,hostfwd=tcp::443-:443,hostfwd=tcp::22-:22 \
  -device virtio-net-pci,netdev=net0
```

**Option B: VM Key File (Advanced)**
```bash
# Create the key file on the VM (via SSH after boot)
echo "AGE-SECRET-KEY-1ABC...XYZ789" | ssh root@vm-host "cat > /var/lib/sops-nix/key.txt"
ssh root@vm-host "chmod 600 /var/lib/sops-nix/key.txt"
ssh root@vm-host "systemctl restart sops-nix"
```

### Step 5: Verify Production Deployment

```bash
# Test that secrets are properly decrypted
ssh root@production-vm "systemctl status gitlab-config.service"
ssh root@production-vm "systemctl status gitlab.service" 
ssh root@production-vm "systemctl status mattermost.service"

# All services should be 'active' instead of 'inactive'
```

## 🔒 Security Best Practices

### Private Key Management

**✅ SECURE STORAGE:**
- Store AGE private keys in your organization's secret management system (HashiCorp Vault, AWS Secrets Manager, etc.)
- Use environment variables for key injection during deployment
- Never commit private keys to version control

**✅ ACCESS CONTROL:**
- Limit access to production AGE keys to essential personnel only
- Use separate keys for development/staging/production environments
- Rotate keys annually or after personnel changes

**✅ BACKUP STRATEGY:**
- Store encrypted backups of AGE private keys in multiple secure locations
- Document key recovery procedures for disaster scenarios
- Test key recovery procedures regularly

### Network Security

**✅ PRODUCTION CONFIGURATION:**
```bash
# Use proper firewall rules (example for UFW)
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 443/tcp  # HTTPS only
sudo ufw deny 80/tcp    # Block HTTP in production
sudo ufw enable

# Use strong SSH configuration
# In /etc/ssh/sshd_config on VM:
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
```

## 🛠 Development vs Production

### Development Mode (No Secrets Required)
```bash
# For development, VM boots without secrets
# Services use fallback configurations
nix build && cp result/nixos.qcov2 dev.qcov2
# Services start but GitLab/Mattermost have default configs
```

### Production Mode (Full Secrets)
```bash
# Production requires AGE key for full functionality
export SOPS_AGE_KEY="AGE-SECRET-KEY-1ABC...XYZ789"
# All services start with production credentials
```

## 🔍 Troubleshooting

### Services Not Starting
```bash
# Check if SOPS secrets are being decrypted
ssh root@vm "ls -la /run/secrets/"
ssh root@vm "journalctl -u sops-nix -f"

# Check gitlab-config service specifically  
ssh root@vm "systemctl status gitlab-config.service"
ssh root@vm "journalctl -u gitlab-config.service -f"
```

### Key Issues
```bash
# Verify key format
age-keygen -y production.agekey  # Should show public key

# Test decryption manually
SOPS_AGE_KEY_FILE=production.agekey sops -d config/secrets.yaml
```

### SOPS Re-encryption
```bash
# If you need to change recipients
sops updatekeys config/secrets.yaml

# Add new recipients without losing existing ones
sops --add-age age1newkey... config/secrets.yaml
```

## 📁 File Organization

### Version Control (Safe to Commit)
```
config/
├── secrets.yaml              # ✅ SOPS-encrypted, safe to commit
└── .gitignore updates        # ✅ Excludes private keys

.gitignore additions:          # ✅ Already configured
├── *.age                     # Private keys
├── *.agekey                  # Private key files  
├── keys/                     # Key directories
└── *_unencrypted.*           # Decrypted files
```

### Secure Storage (Never Commit)
```
production-keys/               # ❌ NEVER commit this directory
├── production.agekey         # ❌ Private key
└── backup-keys/              # ❌ Key backups
```

## 🎯 Production Checklist

Before deploying to production:

- [ ] Generated unique AGE key pair for production
- [ ] Updated `config/secrets.yaml` with production public key  
- [ ] Re-encrypted all secrets with `sops updatekeys`
- [ ] Verified AGE private key is securely stored (not in git)
- [ ] Tested VM boot with production key
- [ ] Confirmed all services start and are 'active'
- [ ] Verified GitLab and Mattermost are accessible
- [ ] Configured production firewall rules
- [ ] Disabled SSH password authentication
- [ ] Documented key recovery procedures
- [ ] Established key rotation schedule

## 🔄 Key Rotation Process

Annually or after security events:

1. Generate new AGE key pair
2. Add new public key to `config/secrets.yaml` recipients
3. Re-encrypt: `sops updatekeys config/secrets.yaml`
4. Deploy new private key to production
5. Verify services restart successfully
6. Remove old public key from recipients
7. Securely destroy old private key

---

**✅ PRODUCTION READY**: This implementation provides enterprise-grade security for your RAVE deployment while maintaining the ability to develop and test without requiring production secrets.
