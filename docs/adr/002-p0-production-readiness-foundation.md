# ADR-002: Phase P0 Production Readiness Foundation

## Status
**ACCEPTED** - Date: 2025-08-23

## Context

Building upon ADR-001's decision to adopt NixOS Flakes as the sole build system, we need to establish the foundational infrastructure for production readiness. This ADR covers Phase P0 (Foundational Strategy & Cleanup + TLS/OIDC Baseline) of the RAVE production readiness plan.

Phase P0 encompasses three critical areas:
1. **P0.1**: Repository standardization and cleanup
2. **P0.2**: Memory-disciplined build system with Nix optimization
3. **P0.3**: TLS ingress and OIDC authentication baseline

The current system lacks production-grade security, memory discipline in builds, and proper authentication mechanisms. This phase establishes the security and infrastructure foundation upon which subsequent phases will build.

## Technical Requirements

### Memory Discipline Requirements
Current Nix builds can consume excessive memory and compile everything locally, leading to:
- Build failures on memory-constrained systems
- Unnecessary compilation overhead
- Poor developer experience
- Resource exhaustion in CI/CD pipelines

### Security Requirements
The current system lacks:
- TLS encryption for web services
- Centralized authentication (OIDC)
- Proper certificate management
- Production-grade security baseline

### Infrastructure Services
Production readiness requires core services:
- **Element**: Secure team communication
- **Grafana**: System observability and monitoring  
- **Penpot**: Design collaboration platform
- **TLS Termination**: Secure ingress at nginx proxy layer

## Decision

**We implement Phase P0 production readiness foundation with memory-disciplined builds and TLS/OIDC security baseline.**

### P0.1: Repository Standardization
- **ADR Documentation**: Establish this ADR as foundation for subsequent phases
- **Single Build Path**: Reinforce NixOS Flakes as the authoritative build system
- **Documentation Update**: Ensure README reflects production readiness goals

### P0.2: Memory-Disciplined Nix Configuration
- **Binary Substituters**: Use pre-built binaries to avoid local compilation
- **Build Parallelism**: Cap at max-jobs=2, cores=4 for memory constraints
- **Storage Optimization**: Enable auto-optimise-store and garbage collection
- **Temporary Storage**: Disable tmpfs for /tmp, use /var/tmp for large operations
- **Known-Good Pinning**: Pin flake.lock to stable nixpkgs-24.11 revision

### P0.3: TLS + OIDC Security Foundation
- **TLS Ingress**: Enable ACME or self-signed certificates at nginx (:3002)
- **OIDC Integration**: Configure GitLab as Identity Provider for all services
- **Service Security**: 
  - Element with OIDC authentication
  - Grafana with OIDC authentication
  - Penpot with OIDC authentication
- **Access Control**: Disable anonymous/guest access across all services

## Implementation Plan

### 1. Nix Configuration Updates

**flake.nix nixConfig:**
```nix
nixConfig = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
  max-jobs = 2;
  cores = 4;
  experimental-features = [ "nix-command" "flakes" ];
};
```

**NixOS System Configuration:**
```nix
# Memory and storage discipline
nix.settings = {
  auto-optimise-store = true;
  max-jobs = 2;
  cores = 4;
};

nix.gc = {
  automatic = true;
  dates = "daily";
  options = "--delete-older-than 7d";
};

# Disable tmpfs for /tmp to avoid memory pressure
boot.tmp.useTmpfs = false;
boot.tmp.tmpfsSize = "50%";  # Fallback if tmpfs enabled

# Use /var/tmp for large temporary operations
environment.variables.TMPDIR = "/var/tmp";
```

### 2. TLS Configuration

**Self-signed Certificate Generation:**
```nix
security.acme = {
  acceptTerms = true;
  defaults.email = "admin@rave.local";
  
  # For development/internal use - self-signed
  certs."rave.local" = {
    domain = "*.rave.local";
    dnsProvider = "manual";
  };
};
```

**Nginx TLS Termination:**
```nix
services.nginx = {
  enable = true;
  
  virtualHosts."rave.local" = {
    enableACME = true;
    forceSSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 3002; ssl = true; }
    ];
    
    # Service routing with TLS
    locations = {
      "/" = { proxyPass = "http://127.0.0.1:3000"; };  # Vibe Kanban
      "/element/" = { proxyPass = "http://127.0.0.1:8009"; };  # Element
      "/grafana/" = { proxyPass = "http://127.0.0.1:3030"; };  # Grafana
      "/penpot/" = { proxyPass = "http://127.0.0.1:9001"; };  # Penpot
    };
  };
};
```

### 3. OIDC + Service Configuration

**GitLab OIDC Application Setup:**
- Create OAuth application in GitLab
- Configure redirect URIs for each service
- Generate client ID and secret for each service

**Element with OIDC:**
```nix
services.matrix-synapse = {
  enable = true;
  
  settings = {
    oidc_providers = [{
      idp_id = "gitlab";
      idp_name = "GitLab";
      issuer = "https://gitlab.com";
      client_id = "your-gitlab-client-id";
      client_secret = "your-gitlab-client-secret";
    }];
    
    # Disable registration
    enable_registration = false;
    registrations_require_3pid = [ "email" ];
  };
};
```

**Grafana with OIDC:**
```nix
services.grafana = {
  enable = true;
  
  settings = {
    "auth.generic_oauth" = {
      enabled = true;
      name = "GitLab";
      client_id = "your-gitlab-client-id";
      client_secret = "your-gitlab-client-secret";
      scopes = "openid profile email";
      auth_url = "https://gitlab.com/oauth/authorize";
      token_url = "https://gitlab.com/oauth/token";
      api_url = "https://gitlab.com/api/v4/user";
    };
    
    # Disable anonymous access
    "auth.anonymous" = {
      enabled = false;
    };
  };
};
```

**Penpot with OIDC:**
```nix
services.penpot = {
  enable = true;
  
  config = {
    # OIDC configuration
    oidc-client-id = "your-gitlab-client-id";
    oidc-client-secret = "your-gitlab-client-secret";
    oidc-base-uri = "https://gitlab.com";
    
    # Disable registration
    registration-enabled = false;
  };
};
```

## Success Criteria

### P0.1 Repository Standardization
- ✅ ADR-002 documents phase P0 foundation
- ✅ README emphasizes single NixOS build path
- ✅ No deprecated build artifacts remain

### P0.2 Memory Discipline
- ✅ Nix builds use binary substituters (>90% cache hits)
- ✅ Build parallelism capped (max-jobs=2, cores=4)
- ✅ Automatic store optimization enabled
- ✅ Daily garbage collection configured
- ✅ /tmp tmpfs disabled, TMPDIR=/var/tmp

### P0.3 TLS + OIDC Security
- ✅ HTTPS on :3002 with valid certificates
- ✅ Element accessible via OIDC (no anonymous access)
- ✅ Grafana accessible via OIDC (no anonymous access)
- ✅ Penpot accessible via OIDC (no registration enabled)
- ✅ All services route through TLS-terminated nginx

## Consequences

### Immediate Benefits
- **Memory Efficiency**: Builds complete on 4GB+ systems without swapping
- **Security Foundation**: TLS + OIDC establishes authentication/authorization baseline
- **Service Integration**: Core production services (communication, monitoring, design) available
- **Performance**: Binary substituters eliminate local compilation overhead

### Operational Changes
- **Build Requirements**: Developers need GitLab accounts for OIDC access
- **Certificate Management**: Self-signed certificates need periodic renewal
- **Service Dependencies**: All services now require authentication workflow

### Future Foundation
- **Phase P1 Ready**: Observability services (Grafana) available for metrics
- **Phase P2 Ready**: Secure communication (Element) available for team coordination
- **Phase P3 Ready**: TLS ingress pattern established for additional services

### Risks Mitigated
- **Resource Exhaustion**: Memory discipline prevents build failures
- **Security Exposure**: TLS + OIDC eliminates anonymous access vectors  
- **Configuration Drift**: Single NixOS configuration source prevents inconsistency

## References

- [ADR-001: VM Build System Selection](./001-vm-build-system.md)
- [RAVE Production Readiness Plan](../../TODO.md)
- [NixOS Manual - Security](https://nixos.org/manual/infra/nixos/stable/index.html#ch-security)
- [OIDC Specification](https://openid.net/connect/)
- [ACME Protocol](https://tools.ietf.org/html/rfc8555)

## Next Phase

Phase P1 (Observability Foundation) builds upon this TLS + OIDC foundation to establish comprehensive monitoring, logging, and alerting capabilities using the Grafana instance configured in this phase.