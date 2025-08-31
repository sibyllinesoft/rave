# ADR-003: P1 Security Hardening - Critical Path Implementation

**Status:** Implemented
**Date:** 2025-01-23
**Deciders:** Security Team, DevOps Team
**Technical Story:** Phase P1 Security Hardening Implementation

## Context

Following the successful implementation of P0 Production Readiness Foundation, RAVE requires comprehensive security hardening to meet production security standards. This phase implements critical security measures including defense-in-depth strategies, secrets management, secure communications, and automated vulnerability scanning.

## Decision

We will implement P1 Security Hardening with the following components:

### P1.1: SSH + Firewall + User Security
- **SSH Hardening:** Enforce key-based authentication only, disable root login
- **Agent User Security:** Remove password authentication, inject authorized SSH keys
- **Firewall Enhancement:** Strict inbound rules (22, 3002 only), rate limiting, explicit deny-all

### P1.2: Secrets Management with sops-nix
- **Encrypted Secrets:** All production secrets encrypted with sops-nix using age encryption
- **Team Key Management:** Multi-key access with team member age keys
- **Secret Integration:** Wire encrypted secrets into Nginx TLS, OIDC, GitLab, Matrix, webhooks

### P1.3: Dispatcher Hardening + Event Schema
- **Webhook Security:** GitLab webhook signature verification via X-Gitlab-Token header
- **Event Deduplication:** SQLite-based event_uuid persistence for at-least-once delivery
- **Event Schema v1:** JSON schema for IssueAssigned, ReviewAppDeployed, DesignApproved events
- **Status Emission:** Structured JSON logging with Matrix and MR note integration points

### P1.4: Automated Vulnerability Scanning
- **Trivy Integration:** Container image and filesystem vulnerability scanning
- **NPM Audit:** Production dependency security assessment  
- **CI Pipeline:** Fail builds on HIGH/CRITICAL vulnerabilities with allowlist support
- **Security Reporting:** Automated SARIF upload to GitHub Security tab

## Technical Implementation

### Configuration Architecture
```
p1-production-config.nix
├── imports: p0-production-config.nix (extends foundation)  
├── sops-nix integration for secrets management
├── enhanced SSH and firewall configurations
├── webhook-dispatcher service with security hardening
├── nginx security headers and rate limiting
└── kernel hardening parameters

secrets.yaml (sops-encrypted)
├── TLS certificates and private keys
├── OIDC client secrets for GitLab OAuth
├── GitLab root password and admin tokens
├── Matrix shared secrets and admin credentials
├── Webhook secrets for signature verification
└── Database and service encryption keys

.github/workflows/p1-security-scan.yml  
├── Trivy container and filesystem scanning
├── NPM audit for production dependencies
├── Security configuration validation
├── Secrets detection and prevention
└── Comprehensive security reporting
```

### Security Hardening Measures

**Defense in Depth:**
- Network layer: Firewall with explicit deny-all, rate limiting
- Transport layer: TLS 1.3 with strong ciphers, security headers
- Application layer: Webhook signature verification, input validation
- System layer: Kernel hardening, service isolation, resource limits

**Secrets Management:**
- Age-encrypted secrets with team key distribution
- Runtime secret injection via /run/secrets paths
- No plaintext secrets in repository or logs
- Secret rotation capabilities and audit trails

**Event Processing Security:**
- Cryptographic webhook signature verification
- Event deduplication prevents replay attacks
- SQLite persistence with ACID guarantees
- Structured logging for security monitoring

**Automated Security Validation:**
- Daily vulnerability database updates
- Container and dependency scanning
- Configuration drift detection
- Secret leak prevention

## Security Architecture

### Trust Boundaries
1. **External → Nginx:** TLS termination, security headers, rate limiting
2. **Nginx → Services:** Internal HTTP with authentication headers
3. **Services → Secrets:** sops-nix encrypted secret access
4. **Webhook → Dispatcher:** Cryptographic signature verification

### Access Control Matrix
| Service | Network Access | Secret Access | User Context |
|---------|---------------|---------------|--------------|
| Nginx | 0.0.0.0:3002 (TLS) | TLS certs | nginx:nginx |
| Webhook Dispatcher | 127.0.0.1:3001 | Webhook secrets | agent:users |
| Grafana | 127.0.0.1:3030 | OIDC secrets | grafana:grafana |
| Vibe Kanban | 127.0.0.1:3000 | None | agent:users |
| CCR | 127.0.0.1:3456 | None | agent:users |

### Vulnerability Management
- **Trivy:** Daily scans for OS, library, and container vulnerabilities
- **NPM Audit:** Production dependency vulnerability assessment
- **Security Configuration:** Automated validation of security settings
- **CI/CD Integration:** Security gates prevent vulnerable deployments

## Consequences

### Positive
- **Defense in Depth:** Multiple security layers protect against attack vectors
- **Secrets Security:** All sensitive data encrypted and access-controlled
- **Automated Security:** Continuous vulnerability scanning and validation
- **Compliance Ready:** Security controls align with industry standards
- **Audit Trail:** Comprehensive logging for security monitoring and forensics
- **Zero Trust:** Every communication channel authenticated and encrypted

### Negative
- **Complexity:** More complex deployment process with secrets management
- **Key Management:** Team must securely distribute and rotate age keys
- **CI/CD Impact:** Security scans may slow build and deployment pipelines
- **Initial Setup:** Manual configuration required for OAuth apps and secrets

### Risks and Mitigations
1. **Key Loss:** Mitigated by multiple team keys and secure backup procedures
2. **False Positives:** Mitigated by allowlist system for known security findings
3. **Performance Impact:** Mitigated by targeted scanning and caching strategies
4. **Operational Complexity:** Mitigated by comprehensive documentation and automation

## Implementation Status

### Completed ✅
- P1.1: SSH hardening, firewall configuration, user security
- P1.2: sops-nix integration, secrets.yaml template, secret wiring
- P1.3: Webhook dispatcher with signature verification and event schema
- P1.4: Comprehensive CI security scanning pipeline
- Configuration: p1-production-config.nix extends P0 foundation
- Documentation: Security configuration and deployment procedures

### Production Setup Required ⚠️
- Generate and distribute team age keys for secrets access
- Replace placeholder secrets in secrets.yaml with actual production values
- Configure GitLab OAuth application for Grafana OIDC integration
- Add actual team SSH public keys to agent user authorized_keys
- Set up GitLab webhook with matching secret for signature verification
- Configure Matrix homeserver integration and shared secrets

### Verification Steps ✅
- Security configuration validation in CI pipeline
- Container and filesystem vulnerability scanning
- NPM production dependency audit
- Secrets detection and leak prevention
- Automated security reporting and GitHub Security integration

## Security Compliance

This implementation addresses:
- **OWASP Top 10:** Injection prevention, authentication, sensitive data exposure
- **CIS Controls:** Secure configuration, access control, vulnerability management
- **SOC 2:** Security monitoring, access controls, change management
- **ISO 27001:** Risk management, security policies, incident response preparation

## Next Phase

P2 will build on this security foundation with:
- Advanced threat detection and SIEM integration
- Security incident response automation
- Advanced access controls and RBAC
- Security compliance reporting and attestation

## References

- [OWASP Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [sops-nix Documentation](https://github.com/Mic92/sops-nix)
- [Trivy Security Scanner](https://trivy.dev/)
- [NixOS Security Hardening](https://nixos.org/manual/nixos/stable/index.html#sec-hardening)