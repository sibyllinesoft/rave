# RAVE - Reproducible AI Virtual Environment

Build deterministic, reproducible AI agent sandbox VMs using **NixOS Flakes** with integrated Claude Code ecosystem tools.

## Architecture

- **NixOS Flakes**: Declarative, reproducible system configuration
- **nixos-generators**: Multi-format VM image generation (qcow2, VirtualBox, VMware, ISO, raw)
- **Systemd Services**: Automatic service orchestration for AI tools
- **Nginx Proxy**: Unified access routing for web interfaces
- **Binary Compatibility**: Steam-run FHS environment for non-NixOS binaries

## Quick Start

```bash
# Check Nix installation
nix --version

# Build QEMU VM image (default)
nix build .#qemu

# Run the VM
./result/bin/run-vm.sh
```

Your VM will auto-login to Xfce as user `agent` with:
- **Vibe Kanban**: http://localhost:3000 (Project Management)
- **Claude Code Router**: http://localhost:3001 (AI Router UI)  
- **Unified Access**: http://localhost:3002 (Nginx proxy routing)

## Prerequisites

### Nix Package Manager
Install Nix with flakes support:

```bash
# Install Nix (multi-user recommended)
curl -L https://nixos.org/nix/install | sh -s -- --daemon

# Enable flakes (if not already enabled)
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Virtualization Support
**Linux (KVM):**
```bash
# Verify KVM support
kvm-ok

# Install QEMU/KVM if needed (Ubuntu/Debian)
sudo apt install qemu-kvm libvirt-daemon-system
sudo usermod -aG kvm,libvirt $USER
```

**macOS (QEMU):**
```bash
# Install via Homebrew
brew install qemu
```

## Build System

### Available Formats

The flake supports multiple output formats via nixos-generators:

```bash
# QEMU/KVM (qcow2) - Linux virtualization
nix build .#qemu

# VirtualBox (OVA) - Cross-platform
nix build .#virtualbox

# VMware (VMDK) - Enterprise virtualization  
nix build .#vmware

# Raw disk image - Physical deployment
nix build .#raw

# ISO installer - Custom installations
nix build .#iso
```

### Build Configuration

Two main configurations are available:

- **simple-ai-config.nix**: Minimal AI sandbox with core tools
- **ai-sandbox-config.nix**: Full-featured environment with comprehensive services

Modify `flake.nix` to switch configurations:
```nix
modules = [ ./simple-ai-config.nix ];  # or ./ai-sandbox-config.nix
```

## VM Configuration

### Core System Configuration

Edit `simple-ai-config.nix` to customize:

```nix
{
  # User configuration
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    password = "agent";  # Change for production
  };

  # Package selection
  environment.systemPackages = with pkgs; [
    chromium nodejs_20 python3 rustc cargo
    # Add your packages here
  ];

  # Service configuration
  systemd.services.your-service = {
    description = "Your Custom Service";
    serviceConfig = {
      ExecStart = "${pkgs.your-package}/bin/your-binary";
      User = "agent";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
```

### Pre-installed Software

**Desktop Environment:**
- Xfce4 with auto-login
- Chromium browser (default)
- NetworkManager for connectivity

**Development Tools:**
- Node.js 20 + npm/pnpm/yarn
- Python 3 + pip + virtualenv  
- Rust toolchain (rustc, cargo)
- Git, curl, wget, vim

**AI Ecosystem:**
- Claude Code CLI (`claude-code`)
- Claude Code Router (`ccr`)
- Vibe Kanban (project management)
- Steam-run (binary compatibility)

### Service Architecture

Services start automatically via systemd:

```bash
# Check service status in VM
sudo systemctl status vibe-kanban claude-code-router nginx

# View service logs
journalctl -u vibe-kanban -f
```

**Service Dependencies:**
```
install-claude-tools.service → setup-agent-environment.service → vibe-kanban.service
                                                              → claude-code-router.service
                                                              → nginx.service
```

## VM Management

### Running VMs

**Direct QEMU:**
```bash
# Build and get result path
nix build .#qemu
RESULT=$(readlink -f result)

# Run with KVM acceleration
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 2 \
  -drive file=$RESULT/nixos.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::3000-:3000,hostfwd=tcp::3001-:3001,hostfwd=tcp::3002-:3002 \
  -device virtio-net,netdev=net0 \
  -display gtk
```

**Using build scripts:**
```bash
# Build VM
./build-vm.sh

# Run with forwarded ports
./run-vm.sh

# Run headless
./run-vm-headless.sh
```

### Port Forwarding

Default port mappings for VM services:

| Service | VM Port | Host Port | Description |
|---------|---------|-----------|-------------|
| Vibe Kanban | 3000 | 3000 | Project Management UI |
| Claude Code Router | 3456 | 3001 | AI Router API/UI |
| Nginx Proxy | 3002 | 3002 | Unified Access Point |
| SSH | 22 | 2223 | Remote access |

### VM Access

**SSH Access:**
```bash
# SSH into running VM
ssh -p 2223 agent@localhost
# Password: agent (change for production)
```

**Web Interfaces:**
- **Vibe Kanban**: http://localhost:3000
- **Claude Code Router**: http://localhost:3001  
- **Unified Interface**: http://localhost:3002 (routes to both)

## Development Workflow

### Iterative Development

```bash
# Make configuration changes
vim simple-ai-config.nix

# Rebuild VM
nix build .#qemu

# Test changes
./run-vm.sh
```

### Multi-format Testing

```bash
# Test different virtualization platforms
nix build .#virtualbox
nix build .#vmware

# Test ISO installer
nix build .#iso
# Boot ISO in virtual machine or burn to USB
```

### Configuration Validation

```bash
# Validate flake syntax and dependencies
nix flake check

# Show package dependencies
nix show-derivation .#qemu

# Build with verbose output
nix build .#qemu --print-build-logs
```

## Customization

### Adding Packages

Edit the `environment.systemPackages` list in your config:

```nix
environment.systemPackages = with pkgs; [
  # Existing packages...
  
  # Add development tools
  docker docker-compose
  terraform ansible
  
  # Add languages
  go gopls
  ruby ruby.gems
  
  # Add editors
  vscode emacs
];
```

### Adding Services

Define custom systemd services:

```nix
systemd.services.my-app = {
  description = "My Custom Application";
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  serviceConfig = {
    Type = "simple";
    User = "agent";
    ExecStart = "${pkgs.my-package}/bin/my-app";
    Restart = "always";
    RestartSec = 10;
  };
  wantedBy = [ "multi-user.target" ];
};
```

### Environment Variables

Set system-wide environment variables:

```nix
environment.sessionVariables = {
  EDITOR = "vim";
  BROWSER = "chromium";
  # Add your variables
};
```

## Troubleshooting

### Build Issues

**Flake evaluation errors:**
```bash
# Check flake syntax
nix flake check

# Update flake inputs
nix flake update

# Clear build cache
nix-collect-garbage -d
```

**Package conflicts:**
```bash
# Check for conflicting packages
nix-env --query --installed

# Rebuild with dependencies
nix build .#qemu --rebuild
```

### VM Runtime Issues

**Services not starting:**
```bash
# Check service status
systemctl status vibe-kanban claude-code-router

# View service logs  
journalctl -u service-name -n 50

# Restart services
sudo systemctl restart service-name
```

**Network connectivity:**
```bash
# Check VM network
ip addr show
ping 8.8.8.8

# Check port forwarding (from host)
netstat -tlnp | grep :3000
```

**Binary compatibility issues:**
```bash
# Use steam-run for non-NixOS binaries
steam-run ./your-binary

# Check FHS environment
steam-run bash
env
```

### Performance Issues

**Slow builds:**
```bash
# Use substituters for binary cache
nix build .#qemu --substituters "https://cache.nixos.org"

# Parallel builds
nix build .#qemu --max-jobs auto
```

**Large image sizes:**
```bash
# Check image composition
du -sh result/nixos.qcow2

# Optimize by removing unnecessary packages
# Edit environment.systemPackages in config
```

## File Structure

```
├── flake.nix                    # Flake definition with build targets
├── flake.lock                   # Dependency lock file
├── simple-ai-config.nix        # Minimal NixOS configuration  
├── ai-sandbox-config.nix       # Full-featured configuration
├── vibe-kanban-simple.nix      # Vibe-kanban package derivation
├── default.nix                 # Default Nix expression
├── build-vm.sh                 # Build script wrapper
├── run-vm.sh                   # VM execution script
├── run-vm-headless.sh          # Headless VM script
├── docs/
│   └── adr/                    # Architecture Decision Records
├── *.qcow2                     # Built VM images
└── result                      # Nix build result symlink
```

## Security Considerations

- **Default passwords**: Change `agent` user password for production
- **SSH access**: Disable password auth, use key-based authentication
- **Service exposure**: Review port forwarding for production deployments
- **Updates**: Regularly update flake inputs for security patches

```nix
# Production security hardening
services.openssh = {
  enable = true;
  settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
  };
};

users.users.agent.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... your-public-key"
];
```

## Production Deployment

### Multi-platform Builds

```bash
# Build for different platforms
nix build .#virtualbox  # Deploy to VirtualBox infrastructure
nix build .#vmware      # Deploy to VMware vSphere
nix build .#raw         # Deploy to bare metal/cloud

# Cross-platform compatibility
nix build .#iso         # Create installer for any platform
```

### CI/CD Integration

```yaml
# GitHub Actions example
name: Build VM Images
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: cachix/install-nix-action@v18
        with:
          extra_nix_config: "experimental-features = nix-command flakes"
      
      - name: Build QEMU image
        run: nix build .#qemu
      
      - name: Build VirtualBox image  
        run: nix build .#virtualbox
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: vm-images
          path: result/
```

## Contributing

1. Fork the repository
2. Make changes to `*.nix` configuration files
3. Test with `nix flake check` and `nix build .#qemu`
4. Submit pull request with detailed description

## License

MIT - Build VMs, not barriers.

---

## Migration from Packer/Ansible

This project previously supported Packer + Ansible builds. As of ADR-001, we've standardized on NixOS Flakes for improved reproducibility and maintainability. 

See `docs/adr/001-vm-build-system.md` for the technical decision rationale.