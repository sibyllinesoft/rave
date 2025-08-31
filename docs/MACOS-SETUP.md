# macOS Setup Guide for RAVE CLI

This guide explains how to set up the RAVE CLI on macOS for building and managing development VMs.

## Prerequisites

### 1. Install Nix Package Manager

```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh

# Enable Nix flakes (required for RAVE)
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**Restart your terminal** after installing Nix.

### 2. Install QEMU for Virtualization

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install QEMU
brew install qemu
```

### 3. Apple Silicon Specific Setup

If you're on Apple Silicon (M1/M2/M3), install Rosetta 2 for x86_64 VM support:

```bash
# Install Rosetta 2
softwareupdate --install-rosetta
```

## Installation

1. **Clone RAVE repository:**
```bash
git clone https://github.com/your-org/rave.git
cd rave
```

2. **Enter Nix development shell:**
```bash
nix develop
```

3. **Check prerequisites:**
```bash
./cli/rave prerequisites
```

This will verify all required tools are available and show any warnings or missing components.

## Platform-Specific Considerations

### Intel Macs
- **Virtualization**: Uses Hypervisor Framework (HVF) for hardware acceleration
- **Performance**: Near-native performance for x86_64 VMs
- **Compatibility**: Full compatibility with all RAVE features

### Apple Silicon (M1/M2/M3)
- **Emulation**: x86_64 VMs run under emulation (slower but functional)
- **Performance**: ~50-70% of native speed, still usable for development
- **Memory**: Requires more RAM due to emulation overhead (recommend 16GB+)
- **Rosetta 2**: Required for Nix builds

## Usage

### Basic VM Operations

```bash
# Check system compatibility
./cli/rave prerequisites

# Create SSH keypair (if needed)
ssh-keygen -t ed25519 -f ~/.ssh/rave-key

# Create company development VM  
./cli/rave vm create my-company --keypair ~/.ssh/rave-key

# Start the VM
./cli/rave vm start my-company

# Check VM status
./cli/rave vm status my-company

# SSH into the VM
./cli/rave vm ssh my-company

# Stop the VM
./cli/rave vm stop my-company
```

### Port Forwarding

Each VM gets its own port range to avoid conflicts:
- **First VM**: 8100 (HTTP), 8110 (HTTPS), 8102 (SSH), 8103 (Test)
- **Second VM**: 8110 (HTTP), 8120 (HTTPS), 8112 (SSH), 8113 (Test)
- **Pattern**: Base port + (VM index × 10)

Access your VM services:
- **GitLab**: `https://localhost:8110/gitlab/`
- **Penpot**: `https://localhost:8110/penpot/`
- **NATS**: `https://localhost:8110/nats/`

## Troubleshooting

### Common Issues

**1. "nix: command not found"**
- Solution: Restart terminal after installing Nix
- Or source: `source ~/.nix-profile/etc/profile.d/nix.sh`

**2. "experimental-features not enabled"**
- Solution: Add to `~/.config/nix/nix.conf`:
  ```
  experimental-features = nix-command flakes
  ```

**3. "qemu-system-x86_64: command not found"**
- Solution: Install QEMU via Homebrew: `brew install qemu`

**4. VM runs slowly on Apple Silicon**
- Expected: x86_64 emulation is inherently slower
- Solutions:
  - Increase VM memory: Edit VM config to use 6-8GB
  - Use fewer concurrent services
  - Consider ARM64 VM image (future feature)

**5. "Permission denied" accessing VM**
- Solution: Check SSH key permissions:
  ```bash
  chmod 600 ~/.ssh/rave-key
  chmod 644 ~/.ssh/rave-key.pub
  ```

**6. Port conflicts**
- Solution: RAVE automatically assigns unique ports per VM
- Check: `./cli/rave vm status --all` to see port assignments

### Performance Optimization

**For Intel Macs:**
- Ensure HVF is enabled (automatic)
- Allocate 4-8GB RAM to VMs
- Use SSD storage for VM images

**For Apple Silicon:**
- Allocate more RAM (6-8GB) due to emulation
- Be patient with GitLab initialization (can take 20-30 minutes)
- Close other applications to free up resources

## Development Workflow

1. **Create VM per company/project**
2. **Use SSH keys for passwordless access**
3. **Access services via port forwarding**
4. **VM state is persistent** - stops/starts preserve data
5. **Reset VM** when needed: `./cli/rave vm reset company-name`

## Security Notes

- VMs use self-signed certificates for development
- Each VM generates unique cryptographic secrets
- SSH key authentication is strongly recommended
- Services are only accessible on localhost by default

## Getting Help

- Check prerequisites: `./cli/rave prerequisites`
- View VM logs: `./cli/rave vm logs company-name`
- GitHub Issues: [Report problems here]

---

**Next Steps:** Once setup is complete, your macOS system can build and run RAVE development VMs just like Linux systems, with automatic platform detection and optimization.