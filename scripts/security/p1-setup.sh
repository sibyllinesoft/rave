#!/bin/bash
# P1 Security Hardening Setup Script
# Sets up P1 production environment with security hardening

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOPS_CONFIG="$PROJECT_ROOT/.sops.yaml"
SECRETS_FILE="$PROJECT_ROOT/secrets.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for P1 setup..."
    
    local missing_deps=()
    
    # Check for required tools
    command -v age >/dev/null 2>&1 || missing_deps+=("age")
    command -v sops >/dev/null 2>&1 || missing_deps+=("sops")
    command -v nix >/dev/null 2>&1 || missing_deps+=("nix")
    command -v git >/dev/null 2>&1 || missing_deps+=("git")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing tools and try again"
        return 1
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# Generate age key for secrets management
setup_age_keys() {
    log_info "Setting up age keys for secrets management..."
    
    local age_key_dir="$HOME/.config/sops/age"
    local age_key_file="$age_key_dir/keys.txt"
    
    # Create age key directory
    mkdir -p "$age_key_dir"
    
    if [ -f "$age_key_file" ]; then
        log_warning "Age key already exists at $age_key_file"
        log_info "Public key:"
        grep "# public key:" "$age_key_file" | cut -d: -f2 | tr -d ' '
    else
        log_info "Generating new age key..."
        age-keygen -o "$age_key_file"
        
        log_success "Age key generated at $age_key_file"
        log_info "Public key:"
        grep "# public key:" "$age_key_file" | cut -d: -f2 | tr -d ' '
        
        log_warning "IMPORTANT: Back up your age key securely!"
        log_warning "Without this key, you cannot decrypt secrets."
    fi
    
    # Set secure permissions
    chmod 600 "$age_key_file"
    chmod 700 "$age_key_dir"
}

# Initialize sops configuration
setup_sops_config() {
    log_info "Setting up sops configuration..."
    
    if [ ! -f "$SOPS_CONFIG" ]; then
        log_error "sops configuration not found at $SOPS_CONFIG"
        log_info "Please update .sops.yaml with your team's age public keys"
        return 1
    fi
    
    # Validate sops config
    if ! sops -d --extract '["keys"]' "$SOPS_CONFIG" >/dev/null 2>&1; then
        log_warning "Could not validate sops configuration"
        log_info "Make sure your age public key is added to .sops.yaml"
    fi
    
    log_success "sops configuration ready"
}

# Initialize secrets file
setup_secrets() {
    log_info "Setting up secrets file..."
    
    if [ ! -f "$SECRETS_FILE" ]; then
        log_error "Secrets template not found at $SECRETS_FILE"
        return 1
    fi
    
    # Check if secrets file is already encrypted
    if grep -q "sops" "$SECRETS_FILE" && grep -q "version" "$SECRETS_FILE"; then
        log_success "Secrets file is already encrypted"
        
        # Test decryption
        if sops -d "$SECRETS_FILE" >/dev/null 2>&1; then
            log_success "Can successfully decrypt secrets file"
        else
            log_error "Cannot decrypt secrets file - check your age key access"
            return 1
        fi
    else
        log_info "Encrypting secrets file with sops..."
        
        # Backup original
        cp "$SECRETS_FILE" "$SECRETS_FILE.backup"
        
        # Encrypt with sops
        if sops -e -i "$SECRETS_FILE"; then
            log_success "Secrets file encrypted successfully"
            rm -f "$SECRETS_FILE.backup"
        else
            log_error "Failed to encrypt secrets file"
            mv "$SECRETS_FILE.backup" "$SECRETS_FILE"
            return 1
        fi
    fi
    
    log_warning "Remember to replace PLACEHOLDER values with real secrets:"
    log_info "  sops $SECRETS_FILE"
}

# Generate SSH keys for production access
setup_ssh_keys() {
    log_info "Setting up SSH keys for production access..."
    
    local ssh_key_path="$HOME/.ssh/rave-p1-production"
    
    if [ -f "$ssh_key_path" ]; then
        log_warning "SSH key already exists at $ssh_key_path"
    else
        log_info "Generating SSH key for production access..."
        ssh-keygen -t ed25519 -f "$ssh_key_path" -C "rave-p1-production-$(whoami)@$(hostname)"
        
        log_success "SSH key generated at $ssh_key_path"
    fi
    
    log_info "Public key (add this to p1-production-config.nix):"
    cat "$ssh_key_path.pub"
    
    log_info "SSH connection command:"
    echo "  ssh -i $ssh_key_path agent@<production-server-ip>"
}

# Validate P1 configuration
validate_p1_config() {
    log_info "Validating P1 configuration..."
    
    local config_file="$PROJECT_ROOT/p1-production-config.nix"
    
    if [ ! -f "$config_file" ]; then
        log_error "P1 configuration not found at $config_file"
        return 1
    fi
    
    # Check for security hardening features
    local checks=(
        "PasswordAuthentication = false"
        "PermitRootLogin = \"no\""
        "sops-nix"
        "verifyWebhookSignature"
        "kernel.dmesg_restrict"
        "firewall"
    )
    
    local failed_checks=()
    
    for check in "${checks[@]}"; do
        if grep -q "$check" "$config_file"; then
            log_success "✓ $check"
        else
            log_error "✗ $check"
            failed_checks+=("$check")
        fi
    done
    
    if [ ${#failed_checks[@]} -eq 0 ]; then
        log_success "P1 configuration validation passed"
        return 0
    else
        log_error "P1 configuration validation failed"
        log_info "Missing security features: ${failed_checks[*]}"
        return 1
    fi
}

# Build P1 image
build_p1_image() {
    log_info "Building P1 production image..."
    
    cd "$PROJECT_ROOT"
    
    if nix build .#p1-production --show-trace; then
        log_success "P1 production image built successfully"
        log_info "Image available at: $(readlink -f result)"
    else
        log_error "Failed to build P1 production image"
        return 1
    fi
}

# Run security tests
run_security_tests() {
    log_info "Running security validation tests..."
    
    cd "$PROJECT_ROOT"
    
    # Test 1: Configuration validation
    log_info "Testing configuration validation..."
    if validate_p1_config; then
        log_success "✓ Configuration validation passed"
    else
        log_error "✗ Configuration validation failed"
        return 1
    fi
    
    # Test 2: Secrets decryption
    log_info "Testing secrets decryption..."
    if sops -d "$SECRETS_FILE" >/dev/null 2>&1; then
        log_success "✓ Secrets decryption passed"
    else
        log_error "✗ Secrets decryption failed"
        return 1
    fi
    
    # Test 3: NixOS configuration syntax
    log_info "Testing NixOS configuration syntax..."
    if nix-instantiate --eval --strict "$PROJECT_ROOT/p1-production-config.nix" >/dev/null 2>&1; then
        log_success "✓ NixOS configuration syntax passed"
    else
        log_error "✗ NixOS configuration syntax failed"
        return 1
    fi
    
    log_success "All security tests passed"
}

# Generate deployment guide
generate_deployment_guide() {
    log_info "Generating deployment guide..."
    
    local guide_file="$PROJECT_ROOT/docs/security/p1-deployment-guide.md"
    mkdir -p "$(dirname "$guide_file")"
    
    cat > "$guide_file" << 'EOF'
# P1 Security Hardening Deployment Guide

## Prerequisites
- [ ] Team age keys generated and distributed
- [ ] sops-nix installed on deployment server
- [ ] SSH access to production server configured
- [ ] GitLab OAuth application created
- [ ] Mattermost chat service deployed (if using)

## Deployment Steps

### 1. Secrets Management Setup
```bash
# On deployment server
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt

# Add production public key to .sops.yaml and re-encrypt
sops -r secrets.yaml
```

### 2. Update Production Secrets
```bash
# Edit secrets with real production values
sops secrets.yaml

# Replace all SOPS_ENCRYPTED_PLACEHOLDER values with:
# - Real TLS certificates from Let's Encrypt/CA
# - Actual OAuth client secrets from GitLab
# - Strong passwords for all services
# - Webhook secrets matching GitLab configuration
```

### 3. SSH Key Configuration
```bash
# Add team SSH public keys to p1-production-config.nix
# Replace the TODO comment with actual keys:
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3... team-member-1"
  "ssh-ed25519 AAAAC3... team-member-2"
];
```

### 4. Build and Deploy
```bash
# Build P1 image
nix build .#p1-production

# Deploy to production server
# (specific deployment method depends on infrastructure)
```

### 5. Post-Deployment Verification
- [ ] SSH access works with keys only
- [ ] HTTPS services accessible at https://rave.local:3002
- [ ] Webhook endpoint responds to GitLab webhooks
- [ ] Grafana OIDC authentication working
- [ ] Security scans pass in CI pipeline

## Security Checklist
- [ ] All secrets encrypted and rotated from defaults
- [ ] SSH password authentication disabled
- [ ] Firewall configured with minimal ports
- [ ] TLS certificates valid and trusted
- [ ] Webhook signature verification working
- [ ] Regular vulnerability scanning enabled
- [ ] Security monitoring and alerting configured

## Maintenance
- [ ] Rotate secrets quarterly
- [ ] Update vulnerability databases weekly
- [ ] Review security logs monthly
- [ ] Test backup and recovery procedures
- [ ] Update security documentation
EOF

    log_success "Deployment guide created at $guide_file"
}

# Main setup function
main() {
    log_info "Starting P1 Security Hardening Setup"
    log_info "===================================="
    
    # Check if running in project root
    if [ ! -f "$PROJECT_ROOT/flake.nix" ]; then
        log_error "Please run this script from the RAVE project root directory"
        exit 1
    fi
    
    # Run setup steps
    if check_prerequisites && \
       setup_age_keys && \
       setup_sops_config && \
       setup_secrets && \
       setup_ssh_keys && \
       validate_p1_config && \
       build_p1_image && \
       run_security_tests && \
       generate_deployment_guide; then
        
        log_success "P1 Security Hardening Setup Complete!"
        log_info ""
        log_info "Next Steps:"
        log_info "1. Update .sops.yaml with team member age public keys"
        log_info "2. Edit secrets.yaml with real production values: sops secrets.yaml"
        log_info "3. Add team SSH public keys to p1-production-config.nix"
        log_info "4. Deploy P1 image to production environment"
        log_info "5. Configure GitLab OAuth and webhook settings"
        log_info "6. Review deployment guide: docs/security/p1-deployment-guide.md"
        log_info ""
        log_warning "IMPORTANT: Backup your age keys securely!"
    else
        log_error "P1 Security Hardening Setup Failed!"
        log_info "Please review the errors above and try again"
        exit 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
