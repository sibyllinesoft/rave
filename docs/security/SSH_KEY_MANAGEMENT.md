# SSH Key Management for AI Agent Sandbox VM

## Overview

This document outlines the SSH key management processes for the AI Agent Sandbox VM, including key generation, distribution, rotation, and emergency access procedures.

## Key Management Architecture

### Key Sources Priority

The VM SSH key setup service checks for SSH keys in the following order:

1. **Environment Variable** (`SSH_PUBLIC_KEY`)
2. **File System** (`/etc/ssh-public-key`)  
3. **Cloud Metadata Services** (AWS EC2, GCP)
4. **Manual Injection** (post-deployment)

### Supported Key Types

**Recommended:**
- **Ed25519**: Preferred for new deployments (modern, secure, fast)
- **ECDSA**: Acceptable alternative (P-256, P-384, P-521 curves)

**Supported but Deprecated:**
- **RSA**: Minimum 3072 bits (4096 bits recommended)
- **DSA**: Not recommended (weak security)

## Key Generation Best Practices

### Ed25519 Key Generation (Recommended)

```bash
# Generate new Ed25519 key pair
ssh-keygen -t ed25519 -f ~/.ssh/ai-sandbox-key -C "ai-sandbox-vm-$(date +%Y%m%d)"

# Generate with specific comment for identification
ssh-keygen -t ed25519 -f ~/.ssh/ai-sandbox-key -C "user@company-ai-sandbox"

# Secure file permissions
chmod 600 ~/.ssh/ai-sandbox-key
chmod 644 ~/.ssh/ai-sandbox-key.pub
```

### RSA Key Generation (Legacy)

```bash
# Generate RSA key (minimum 3072 bits)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ai-sandbox-rsa-key -C "ai-sandbox-vm-rsa"

# Secure permissions
chmod 600 ~/.ssh/ai-sandbox-rsa-key  
chmod 644 ~/.ssh/ai-sandbox-rsa-key.pub
```

### Key Security Requirements

**Key Protection:**
- Private keys must be stored with 600 permissions
- Use strong passphrase protection for private keys
- Store keys in secure key management systems for production
- Never embed private keys in configuration or code

**Key Identification:**
- Use meaningful comments for key identification
- Include deployment date and purpose in key name
- Maintain key inventory with owner and expiration tracking

## Deployment Methods

### Method 1: Environment Variable

**Best for**: Automated deployments, CI/CD pipelines

```bash
# Set environment variable before VM startup
export SSH_PUBLIC_KEY="ssh-ed25519 AAAAB3... user@host"

# Deploy VM with key
nix build .#qemu
./run-vm.sh
```

**Docker/Container Deployment:**
```bash
docker run -e SSH_PUBLIC_KEY="$(cat ~/.ssh/ai-sandbox-key.pub)" vm-image
```

### Method 2: File System Injection

**Best for**: Manual deployments, testing

```bash
# Create key file before VM startup
cat ~/.ssh/ai-sandbox-key.pub > /etc/ssh-public-key

# Or inject into VM after creation
qemu-img create -f qcow2 key-disk.qcow2 1M
# Mount and copy key to /etc/ssh-public-key
```

### Method 3: Cloud Metadata

**AWS EC2:**
```bash
# AWS CLI key injection
aws ec2 run-instances \
  --image-id ami-12345678 \
  --key-name ai-sandbox-keypair \
  --security-groups ai-sandbox-sg
```

**Google Cloud:**
```bash  
# GCP key injection
gcloud compute instances create ai-sandbox \
  --image-family ai-sandbox \
  --metadata ssh-keys="agent:$(cat ~/.ssh/ai-sandbox-key.pub)"
```

**Azure:**
```bash
# Azure key injection
az vm create \
  --name ai-sandbox \
  --image ai-sandbox-image \
  --admin-username agent \
  --ssh-key-values ~/.ssh/ai-sandbox-key.pub
```

### Method 4: Manual Post-Deployment

**Emergency Access Setup:**

```bash
# Access VM via console or alternative method
# Create SSH directory (if not exists)
sudo mkdir -p /home/agent/.ssh
sudo chmod 700 /home/agent/.ssh

# Add public key manually  
sudo echo "ssh-ed25519 AAAAB3... user@host" >> /home/agent/.ssh/authorized_keys
sudo chmod 600 /home/agent/.ssh/authorized_keys
sudo chown agent:users /home/agent/.ssh/authorized_keys

# Restart SSH service
sudo systemctl restart sshd
```

## Key Rotation Procedures

### Regular Key Rotation

**Recommended Schedule:**
- **Production**: Every 90 days
- **Development**: Every 180 days
- **Testing**: Every 365 days or as needed

**Rotation Process:**

1. **Generate New Key Pair:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/ai-sandbox-new-key -C "ai-sandbox-rotation-$(date +%Y%m%d)"
```

2. **Add New Key (Dual Key Period):**
```bash
# Add new key alongside existing key
cat ~/.ssh/ai-sandbox-new-key.pub >> authorized_keys_temp
scp authorized_keys_temp agent@vm:/home/agent/.ssh/authorized_keys
```

3. **Test New Key:**
```bash
# Test SSH access with new key
ssh -i ~/.ssh/ai-sandbox-new-key agent@vm-hostname "whoami"
```

4. **Remove Old Key:**
```bash
# Remove old key from authorized_keys
ssh -i ~/.ssh/ai-sandbox-new-key agent@vm-hostname \
  "grep -v 'old-key-comment' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys_new && mv ~/.ssh/authorized_keys_new ~/.ssh/authorized_keys"
```

5. **Update Deployment Configuration:**
```bash
# Update environment variables, files, or cloud metadata
export SSH_PUBLIC_KEY="$(cat ~/.ssh/ai-sandbox-new-key.pub)"
```

### Emergency Key Rotation

**Compromise Response:**

1. **Immediate Actions:**
   - Generate new emergency key pair immediately
   - Deploy new key via alternative access method (console, cloud metadata)
   - Remove compromised key from all systems

2. **Emergency Key Deployment:**
```bash
# Via cloud metadata (example for AWS)
aws ec2 modify-instance-attribute \
  --instance-id i-1234567890abcdef0 \
  --attribute userData \
  --value "$(base64 -w 0 emergency-key-script.sh)"
```

3. **Forensic Analysis:**
   - Preserve logs before key rotation
   - Analyze SSH logs for unauthorized access
   - Document timeline and impact assessment

## Multi-Key Management

### Multiple Authorized Keys

**Team Access Setup:**
```bash
# Add multiple team member keys
cat team-member-1.pub >> /home/agent/.ssh/authorized_keys
cat team-member-2.pub >> /home/agent/.ssh/authorized_keys
cat emergency-access.pub >> /home/agent/.ssh/authorized_keys

# Ensure proper permissions
chmod 600 /home/agent/.ssh/authorized_keys
```

**Key Management Script:**
```bash
#!/bin/bash
# add-ssh-key.sh - Add new SSH key to VM

KEY_FILE="$1"
KEY_COMMENT="${2:-added-$(date +%Y%m%d)}"

if [ ! -f "$KEY_FILE" ]; then
    echo "Error: Key file not found"
    exit 1
fi

# Add key with comment
echo "# $KEY_COMMENT" >> /home/agent/.ssh/authorized_keys
cat "$KEY_FILE" >> /home/agent/.ssh/authorized_keys
echo "Key added successfully"
```

### Key Inventory Management

**Maintain Key Registry:**
```bash
# Create key inventory file
cat > ssh-key-inventory.md << 'EOF'
# SSH Key Inventory - AI Sandbox VMs

| Key ID | Owner | Type | Created | Expires | Status | VMs |
|--------|-------|------|---------|---------|--------|-----|
| ai-sb-001 | admin@company.com | ed25519 | 2024-12-19 | 2025-03-19 | Active | prod-vm-01 |
| ai-sb-002 | dev1@company.com | ed25519 | 2024-12-19 | 2025-06-19 | Active | dev-vm-01,dev-vm-02 |
| ai-sb-emergency | security@company.com | ed25519 | 2024-12-19 | 2025-12-19 | Active | all |
EOF
```

## Integration with Cloud Providers

### AWS Integration

**CloudFormation Template:**
```yaml
Resources:
  AIAgentInstance:
    Type: AWS::EC2::Instance
    Properties:
      ImageId: ami-12345678
      KeyName: !Ref SSHKeyPair
      SecurityGroupIds: 
        - !Ref AIAgentSecurityGroup
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          echo "${SSHPublicKey}" > /etc/ssh-public-key
          systemctl restart setup-ssh-keys
```

**Terraform Configuration:**
```hcl
resource "aws_instance" "ai_agent_sandbox" {
  ami           = var.ai_sandbox_ami
  instance_type = "t3.medium"
  key_name      = aws_key_pair.ai_sandbox.key_name
  
  user_data = base64encode(templatefile("user-data.sh", {
    ssh_public_key = file("~/.ssh/ai-sandbox-key.pub")
  }))
  
  tags = {
    Name = "ai-agent-sandbox"
  }
}
```

### Google Cloud Integration

**gcloud Deployment Script:**
```bash
#!/bin/bash
# deploy-gcp.sh - Deploy AI Sandbox to GCP

PROJECT_ID="your-project"
ZONE="us-central1-a"
MACHINE_TYPE="e2-standard-2"
SSH_KEY="$(cat ~/.ssh/ai-sandbox-key.pub)"

gcloud compute instances create ai-sandbox-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family="ai-sandbox" \
  --metadata="ssh-keys=agent:$SSH_KEY" \
  --tags="ai-sandbox"
```

### Azure Integration

**ARM Template:**
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "sshPublicKey": {
      "type": "string",
      "metadata": {
        "description": "SSH public key for agent user"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2021-03-01",
      "name": "ai-sandbox-vm",
      "properties": {
        "osProfile": {
          "computerName": "ai-sandbox",
          "adminUsername": "agent",
          "linuxConfiguration": {
            "disablePasswordAuthentication": true,
            "ssh": {
              "publicKeys": [
                {
                  "path": "/home/agent/.ssh/authorized_keys",
                  "keyData": "[parameters('sshPublicKey')]"
                }
              ]
            }
          }
        }
      }
    }
  ]
}
```

## Security Best Practices

### Key Storage Security

**Local Development:**
- Use SSH agent for key management
- Enable key passphrase protection
- Store keys in encrypted file systems
- Use hardware security modules when available

**Production Systems:**
- Use cloud key management services (AWS KMS, Azure Key Vault, GCP KMS)
- Implement automated key rotation
- Monitor key usage and access patterns
- Maintain key backup and recovery procedures

### Access Control

**Principle of Least Privilege:**
- Grant SSH access only to necessary personnel
- Use separate keys for different environments
- Implement time-limited access for temporary users
- Regular access review and cleanup

**Monitoring and Auditing:**
- Log all SSH key additions and removals
- Monitor SSH authentication attempts and failures
- Regular key inventory audits
- Automated alerting for unauthorized key additions

## Troubleshooting

### Common SSH Key Issues

**Key Not Working:**
1. Verify key permissions (600 for private, 644 for public)
2. Check authorized_keys file permissions (600)
3. Verify key format and integrity
4. Check SSH client configuration
5. Review SSH server logs

**Permission Denied:**
1. Verify public key is in authorized_keys
2. Check file ownership (should be agent:users)
3. Verify SSH service is running
4. Check fail2ban status (may be blocking IP)
5. Verify private key matches public key

**Key Injection Failures:**
1. Check cloud metadata service availability
2. Verify environment variables are set correctly
3. Check file system permissions for key files
4. Review setup-ssh-keys service logs

### Diagnostic Commands

**SSH Connection Testing:**
```bash
# Test SSH connection with verbose output
ssh -vvv -i ~/.ssh/ai-sandbox-key agent@vm-hostname

# Test key authentication specifically  
ssh -o PreferredAuthentications=publickey -i ~/.ssh/ai-sandbox-key agent@vm-hostname

# Check SSH server configuration
sudo sshd -T | grep -i pubkey
```

**Key Verification:**
```bash
# Verify key fingerprint
ssh-keygen -lf ~/.ssh/ai-sandbox-key.pub
ssh-keygen -lf /home/agent/.ssh/authorized_keys

# Check key format
ssh-keygen -e -f ~/.ssh/ai-sandbox-key.pub
```

**Service Status:**
```bash
# Check SSH service status
sudo systemctl status sshd

# Check key setup service
sudo systemctl status setup-ssh-keys

# View SSH logs
sudo journalctl -u sshd -f
```

## Emergency Access Procedures

### Lost Key Recovery

1. **Console Access**: Use cloud provider console access
2. **Alternative Authentication**: Use cloud metadata or serial console
3. **VM Snapshot**: Create snapshot before recovery attempts
4. **Key Replacement**: Deploy new key via emergency method
5. **Access Verification**: Test new key before removing old access

### Lockout Recovery

1. **fail2ban Unban**: Clear IP bans via console access
2. **SSH Service Restart**: Restart SSH service to clear temporary issues  
3. **Configuration Rollback**: Revert SSH configuration changes if needed
4. **Network Connectivity**: Verify firewall and network settings

---

**Classification**: Internal Use  
**Last Updated**: 2024-12-19  
**Next Review**: 2025-03-19