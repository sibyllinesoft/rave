# ADR-001: VM Build System Selection

## Status
**ACCEPTED** - Date: 2025-08-22

## Context

The RAVE (Reproducible AI Virtual Environment) project currently maintains two parallel VM build systems:

1. **Packer + Ansible**: Traditional infrastructure-as-code approach using Packer for base image creation and Ansible for configuration management, with cloud-init for per-VM customization
2. **NixOS Flakes**: Declarative system configuration using Nix flakes with nixos-generators for multi-format VM image generation

This dual approach creates several problems:
- **Maintenance Overhead**: Two systems require separate maintenance, testing, and documentation
- **Consistency Risk**: Potential for configuration drift between the two approaches
- **Production Uncertainty**: Unclear which system should be used for production deployments
- **Resource Waste**: Development time split between maintaining two solutions

## Technical Analysis

### Evidence of Current Usage

**NixOS System:**
- 14+ recent VM images built between August 19-20, 2025
- Active iteration and refinement shown by multiple builds with incremental names
- Complex service orchestration (nginx proxy, systemd services, multi-application setup)
- Multi-format support (qcow2, VirtualBox, VMware, ISO, raw)

**Packer/Ansible System:**
- No recent build artifacts (no `out/` directory found)
- Comprehensive documentation but unused in practice
- Simpler single-format output (qcow2 only)

### Evaluation Criteria Analysis

| Criterion | NixOS Flakes | Packer + Ansible | Winner |
|-----------|--------------|-------------------|---------|
| **Reproducibility** | ✅ Deterministic builds with flake.lock | ⚠️ Apt packages can change between builds | NixOS |
| **Declarative Configuration** | ✅ Fully declarative, everything in code | ⚠️ Mix of declarative (Ansible) and imperative (shell) | NixOS |
| **Multi-format Support** | ✅ qcow2, VirtualBox, VMware, ISO, raw | ❌ qcow2 only | NixOS |
| **Service Management** | ✅ Native systemd service definitions | ⚠️ Manual shell script orchestration | NixOS |
| **Package Management** | ✅ 80,000+ packages via Nix | ⚠️ Limited to Debian repositories | NixOS |
| **Rollback Capability** | ✅ Atomic system state rollbacks | ❌ No built-in rollback | NixOS |
| **Current Momentum** | ✅ Actively developed and used | ❌ No recent development | NixOS |
| **Industry Familiarity** | ⚠️ Requires Nix knowledge | ✅ Standard DevOps tools | Packer/Ansible |
| **Image Size** | ⚠️ 6-10GB current builds | ✅ ~3GB target with compression | Packer/Ansible |
| **Build Complexity** | ⚠️ Sophisticated system | ✅ Straightforward approach | Packer/Ansible |

### Production Requirements Assessment

For production deployment, the following requirements are critical:

1. **Reproducibility**: Essential for debugging, compliance, and reliability
2. **Maintainability**: Single source of truth reduces operational complexity
3. **Service Orchestration**: Complex multi-service setup requires sophisticated coordination
4. **Deployment Flexibility**: Multiple output formats support various deployment targets
5. **Rollback Capability**: Critical for production incident recovery

## Decision

**We choose NixOS Flakes as the single VM build system for RAVE.**

### Primary Rationale

1. **Evidence-Based**: The NixOS system is actively used with 14+ recent builds, demonstrating it meets current development needs

2. **Production Readiness**: Deterministic builds and atomic rollbacks are essential for production reliability

3. **Service Complexity**: The current system requires orchestrating multiple services (nginx proxy, vibe-kanban, claude-code-router) which is better handled by NixOS's declarative systemd integration

4. **Future-Proof**: Multi-format support enables deployment to various virtualization platforms without rebuild

5. **Alignment with Goals**: The TODO.md explicitly recommends this path: "Delete the ansible/packer stuff" and "Officially designate the NixOS build as the production path"

### Trade-offs Accepted

- **Learning Curve**: Team must develop Nix expertise (mitigated by existing working system)
- **Image Size**: Current 6-10GB builds vs 3GB target (addressable through optimization)
- **Complexity**: More sophisticated system (justified by production requirements)

## Consequences

### Immediate Actions Required

1. **Repository Cleanup**: Remove Packer/Ansible system to eliminate maintenance overhead
2. **Documentation Update**: Update README.md to reflect single build system
3. **Team Training**: Ensure team members understand Nix flake concepts

### Files to Remove

```
ansible/                          # Ansible roles and playbooks
packer/                           # Packer configuration
cloud-init/                       # Cloud-init configuration specific to Packer
scripts/postbuild-deflate.sh     # Packer post-processing script
Makefile                          # Packer-specific build automation
http/                            # Packer HTTP server directory (if exists)
```

### Files to Retain

```
flake.nix, flake.lock            # Nix flake definition and lock file
*.nix                            # All NixOS configuration files
*.qcow2                          # Built VM images
```

### Future Optimizations

1. **Image Size Reduction**: Optimize NixOS configuration to reduce build size
2. **Build Time**: Implement build caching and incremental builds
3. **Documentation**: Create comprehensive Nix-specific documentation
4. **CI/CD Integration**: Implement automated builds and testing using Nix

### Success Metrics

- **Single Maintenance Path**: Elimination of dual system maintenance overhead
- **Build Reproducibility**: 100% deterministic builds across environments
- **Deployment Flexibility**: Support for 3+ virtualization platforms
- **Service Reliability**: Robust multi-service orchestration in production

## References

- [TODO.md Production Readiness Plan](/TODO.md)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [nixos-generators Documentation](https://github.com/nix-community/nixos-generators)
- Current NixOS configuration: `simple-ai-config.nix`
