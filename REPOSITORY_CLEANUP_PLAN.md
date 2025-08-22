# Repository Cleanup Plan - Packer/Ansible System Removal

## Overview
Following ADR-001 (VM Build System Selection), this document outlines the complete removal of the deprecated Packer/Ansible build system to establish NixOS Flakes as the single production build path.

## Files and Directories to Remove

### 1. Ansible Configuration Management
```
ansible/
├── playbooks/
│   └── base.yml
└── roles/
    └── desktop_base/
        ├── tasks/
        │   └── main.yml
        └── vars/
            └── main.yml
```
**Rationale**: Ansible roles and playbooks are specific to the Packer approach and duplicate functionality now handled declaratively in NixOS configuration files.

### 2. Packer Build Configuration
```
packer/
└── packer.pkr.hcl
```
**Rationale**: Packer configuration is superseded by nixos-generators in the NixOS flake approach.

### 3. Cloud-Init Configuration
```
cloud-init/
├── meta-data
└── user-data
```
**Rationale**: Cloud-init configuration was specific to the Packer build process. NixOS handles user and service configuration declaratively.

### 4. Packer-Specific Scripts
```
scripts/
└── postbuild-deflate.sh
```
**Rationale**: Post-processing script for Packer builds. NixOS handles image optimization natively.

### 5. Packer Build Automation
```
Makefile
```
**Rationale**: Make targets are specific to Packer workflow. Nix flake provides build automation via `nix build` commands.

### 6. HTTP Directory (if exists)
```
http/  (check for existence)
```
**Rationale**: Packer HTTP server directory for serving installation files during automated installs.

## Verification Commands

Before removal, verify these files exist:
```bash
# Check all files exist before removal
ls -la ansible/ packer/ cloud-init/ scripts/postbuild-deflate.sh Makefile
ls -la http/ 2>/dev/null || echo "http/ directory does not exist (expected)"
```

## Safe Removal Commands

Execute in order to safely remove deprecated components:

```bash
# 1. Remove Ansible configuration
rm -rf ansible/

# 2. Remove Packer configuration  
rm -rf packer/

# 3. Remove cloud-init configuration
rm -rf cloud-init/

# 4. Remove Packer post-processing script
rm -f scripts/postbuild-deflate.sh

# 5. Remove Packer Makefile
rm -f Makefile

# 6. Remove HTTP directory if it exists
rm -rf http/ 2>/dev/null || true

# 7. Clean up empty scripts directory if no other scripts remain
rmdir scripts/ 2>/dev/null || echo "scripts/ directory contains other files, keeping"
```

## Files to Retain

All NixOS-related files and build artifacts must be preserved:

### NixOS Configuration
```
flake.nix                        # Nix flake definition
flake.lock                       # Dependency lock file  
default.nix                      # Default Nix expression
simple-ai-config.nix            # Simplified NixOS configuration
ai-sandbox-config.nix           # Full NixOS configuration
vibe-kanban.nix                 # Vibe-kanban derivation
vibe-kanban-simple.nix          # Simplified vibe-kanban derivation
```

### Build Scripts (NixOS compatible)
```
build-vm.sh                     # Nix build wrapper
run-vm.sh                       # VM execution script
run-vm-headless.sh             # Headless VM execution
install-nix-*.sh               # Nix installation scripts
```

### Build Artifacts
```
*.qcow2                         # All VM image files
result                          # Nix build result symlink
```

### Project Files
```
README.md                       # Will be updated for NixOS approach
TODO.md                         # Project roadmap
docs/                          # Documentation including new ADR
```

## Post-Removal Verification

After removal, verify the repository state:

```bash
# Verify removed files are gone
! ls ansible/ packer/ cloud-init/ Makefile scripts/postbuild-deflate.sh 2>/dev/null

# Verify NixOS files remain
ls flake.nix simple-ai-config.nix *.qcow2

# Verify the repository is still functional
nix flake check
```

## Documentation Updates Required

1. **README.md**: Complete rewrite focusing on NixOS build process
2. **Add**: Build instructions using `nix build .#qemu`
3. **Add**: Multi-format build examples (VirtualBox, VMware, etc.)
4. **Remove**: All Packer/Ansible references and instructions

## Git Commit Strategy

Recommend single atomic commit to maintain repository history:

```bash
# Stage all removals
git rm -r ansible/ packer/ cloud-init/ scripts/postbuild-deflate.sh Makefile
git rm -r http/ 2>/dev/null || true

# Stage README update
git add README.md docs/adr/001-vm-build-system.md

# Commit with clear message
git commit -m "refactor: standardize on NixOS build system

- Remove deprecated Packer/Ansible build system
- Implement ADR-001: VM Build System Selection  
- Update documentation to reflect NixOS-only approach
- Eliminate dual maintenance overhead

BREAKING CHANGE: Packer/Ansible build method no longer supported.
Use 'nix build .#qemu' for VM image generation."
```

## Risk Mitigation

- **Backup Strategy**: All removed files are preserved in Git history
- **Rollback Plan**: Git revert can restore removed files if needed
- **Validation**: ADR-001 documents technical decision rationale
- **Evidence**: Multiple recent NixOS builds prove system functionality

## Success Criteria

- [ ] All Packer/Ansible files removed
- [ ] NixOS build system remains functional (`nix flake check` passes)
- [ ] README.md updated with NixOS instructions
- [ ] Repository size reduced by removing unused components
- [ ] Single, clear build path established for production use