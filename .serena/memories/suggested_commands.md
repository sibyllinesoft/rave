# Essential Commands for RAVE Development

## Building VMs
```bash
# Build default QEMU image
nix build .#qemu

# Build other formats
nix build .#virtualbox    # VirtualBox OVA
nix build .#vmware        # VMware VMDK
nix build .#iso           # ISO installer
nix build .#raw           # Raw disk image

# Validate flake
nix flake check

# Update dependencies
nix flake update
```

## Running VMs
```bash
# Run built VM with scripts
./run-vm.sh                # With GUI
./run-vm-headless.sh      # Headless mode

# Manual QEMU execution
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file=result/nixos.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::3000-:3000,hostfwd=tcp::3001-:3001,hostfwd=tcp::3002-:3002,hostfwd=tcp::2223-:22 \
  -device virtio-net,netdev=net0
```

## Development Workflow
```bash
# Edit configuration
vim simple-ai-config.nix

# Rebuild and test
nix build .#qemu && ./run-vm.sh

# SSH into running VM
ssh -p 2223 agent@localhost

# Check service status (in VM)
sudo systemctl status vibe-kanban claude-code-router nginx
```

## Service URLs
- Vibe Kanban: http://localhost:3000
- Claude Code Router: http://localhost:3001 
- Unified Access: http://localhost:3002
- SSH Access: ssh -p 2223 agent@localhost