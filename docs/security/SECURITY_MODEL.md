# AI Agent Sandbox VM - Security Model

## Overview

The AI Agent Sandbox VM implements a defense-in-depth security architecture designed for secure deployment in cloud and virtualized environments while maintaining usability for AI development workflows.

## Security Architecture

### Trust Model

**Trust Boundaries:**
- **Host System**: Trusted hypervisor/cloud provider infrastructure
- **VM Boundary**: Isolated virtual machine with minimal attack surface
- **Network Perimeter**: Controlled network access with firewall protection
- **Service Isolation**: Services run with minimal privileges and segregated access

**Threat Model:**
- External network attackers attempting system compromise
- Malicious actors exploiting weak authentication mechanisms
- Privilege escalation from unprivileged service accounts
- Data exfiltration from compromised services
- Resource exhaustion and denial of service attacks

### Network Security Architecture

```
Internet/Cloud Provider Network
            │
    ┌───────▼────────┐
    │   Firewall     │
    │   (iptables)   │  Ports: 22, 3000, 3001, 3002
    └───────┬────────┘
            │
    ┌───────▼────────┐
    │  fail2ban      │  Intrusion Prevention
    │  SSH Monitor   │  Max 3 attempts, 1h ban
    └───────┬────────┘
            │
    ┌───────▼────────┐
    │   SSH Service  │  Key-based auth only
    │   Port 22      │  No password auth
    └────────────────┘
            │
    ┌───────▼────────┐
    │  Nginx Proxy   │  Port 3002 (unified access)
    │                │  ├── / → Vibe Kanban (3000)
    │                │  └── /ccr-ui → CCR (3456)
    └────────────────┘
```

### Authentication & Authorization

**SSH Access:**
- **Authentication Method**: Public key authentication only
- **Key Sources**: Cloud metadata, environment variables, or manual injection
- **No Password Authentication**: Completely disabled to prevent brute force attacks
- **Root Access**: Completely disabled (`PermitRootLogin = "no"`)
- **Connection Limits**: Maximum 3 authentication attempts, 10 concurrent sessions

**Service Authentication:**
- **User Context**: All services run as unprivileged `agent` user
- **No Inter-service Authentication**: Services trust each other within VM boundary
- **Web Interface Access**: No authentication (assumed trusted network)

### Data Protection

**Data at Rest:**
- **User Data**: Stored in `/home/agent` with standard Unix permissions
- **Configuration Files**: Protected by file system permissions
- **No Disk Encryption**: VM disk encryption responsibility of host/cloud provider

**Data in Transit:**
- **SSH**: Encrypted with modern ciphers (ChaCha20-Poly1305, AES-GCM)
- **Web Services**: HTTP only (HTTPS termination expected at load balancer)
- **API Communication**: Unencrypted local communication between services

### Secret Management

**SSH Keys:**
- **Automated Injection**: Keys sourced from cloud metadata or environment
- **Key Rotation**: Manual process, requires VM rebuild or manual update
- **Key Storage**: Standard SSH authorized_keys with proper permissions (600)

**Service Credentials:**
- **Claude API Keys**: Stored in user configuration files
- **Database Access**: SQLite with file system permissions
- **No Centralized Secret Store**: Secrets managed per-service

## Service Security Configuration

### SSH Service Hardening

```nix
services.openssh = {
  settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    PubkeyAuthentication = true;
    AuthenticationMethods = "publickey";
    MaxAuthTries = 3;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
    LoginGraceTime = 60;
    MaxSessions = 10;
    Protocol = 2;
    # Modern cipher suites only
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
      "aes256-ctr"
      "aes192-ctr" 
      "aes128-ctr"
    ];
    # Strong key exchange algorithms
    KexAlgorithms = [
      "curve25519-sha256@libssh.org"
      "diffie-hellman-group16-sha512"
      "diffie-hellman-group18-sha512"
      "diffie-hellman-group14-sha256"
    ];
    # Secure MAC algorithms
    Macs = [
      "hmac-sha2-256-etm@openssh.com"
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256"
      "hmac-sha2-512"
    ];
  };
};
```

### Firewall Configuration

**Enabled Ports:**
- **22**: SSH access (restricted to key-based authentication)
- **3000**: Vibe Kanban project management interface
- **3001**: Claude Code Router UI (mapped from internal 3456)
- **3002**: Nginx unified access proxy

**Blocked Traffic:**
- All other inbound traffic blocked by default
- Outbound traffic allowed (required for package installation and AI services)

### Intrusion Prevention (fail2ban)

**SSH Protection:**
- **Detection**: Monitor SSH authentication failures via systemd logs
- **Threshold**: 3 failed attempts within 10 minutes
- **Response**: 1-hour IP ban via iptables
- **Backend**: systemd journal monitoring for real-time detection

## Security Monitoring

### Logging Architecture

**System Logs:**
- **SSH Access**: All authentication attempts logged via syslog
- **Service Status**: systemd service logs available via journalctl
- **Network Access**: Basic iptables logging for dropped packets
- **fail2ban Actions**: Ban/unban actions logged to syslog

**No Centralized Logging:**
- Logs stored locally in systemd journal
- Manual extraction required for analysis
- No automated log forwarding configured

### Monitoring Capabilities

**Current Monitoring:**
- **SSH**: fail2ban monitors authentication failures
- **Services**: systemd monitors service health and restarts
- **Resources**: Basic system monitoring via systemctl status

**Missing Monitoring:**
- No SIEM or security analytics
- No file integrity monitoring
- No network traffic analysis
- No behavioral anomaly detection

## Incident Response

### Emergency Procedures

**SSH Compromise Response:**
1. Identify compromise via fail2ban logs or unusual authentication patterns
2. Add attacker IPs to permanent fail2ban ban list
3. Rotate SSH keys by updating cloud metadata or rebuilding VM
4. Review system logs for evidence of successful compromise

**Service Compromise Response:**
1. Stop affected service via systemctl
2. Review service logs for compromise indicators
3. Restore service from known-good configuration
4. Update service credentials if applicable

**VM Compromise Response:**
1. Isolate VM by blocking network access at hypervisor level
2. Create VM snapshot for forensic analysis
3. Deploy new VM from clean image with rotated credentials
4. Analyze logs and determine root cause

### Security Contacts

**Escalation Path:**
- No automated alerting configured
- Manual monitoring and response required
- Responsibility of deploying organization to monitor and respond

## Compliance Considerations

### Security Standards Alignment

**CIS Benchmarks:**
- SSH hardening aligns with CIS SSH security recommendations
- Firewall configuration follows defense-in-depth principles
- Service isolation reduces attack surface

**NIST Cybersecurity Framework:**
- **Identify**: Basic asset inventory and threat identification
- **Protect**: Access controls and protective technology implemented
- **Detect**: Limited detection capabilities (fail2ban only)
- **Respond**: Basic incident response procedures documented
- **Recover**: VM rebuild process enables rapid recovery

### Regulatory Requirements

**Data Protection:**
- No PII processing by default configuration
- User responsible for compliance with data protection regulations
- VM can be configured for specific compliance requirements (GDPR, HIPAA, etc.)

## Security Limitations

### Known Limitations

**Authentication:**
- No multi-factor authentication for SSH
- No session management or timeout for web interfaces
- Service-to-service communication unencrypted

**Authorization:**
- No role-based access controls
- All services run as same user account
- No fine-grained permissions within services

**Monitoring:**
- No real-time security monitoring
- Limited log retention and analysis
- No automated threat detection

**Encryption:**
- No disk encryption at VM level
- Web services communicate over HTTP
- Service configuration stored in plaintext

### Recommendations for Production

**Enhanced Security:**
1. **Implement MFA**: Add multi-factor authentication for SSH access
2. **Enable Disk Encryption**: Use LUKS or similar for VM disk encryption  
3. **Deploy SIEM**: Implement security information and event management
4. **Network Segmentation**: Isolate AI services on separate network segments
5. **Regular Patching**: Implement automated security update process
6. **Secret Management**: Deploy centralized secret management solution
7. **Backup Encryption**: Encrypt all backups and implement secure storage
8. **Certificate Management**: Implement TLS/SSL for all web services
9. **Vulnerability Scanning**: Regular security vulnerability assessments
10. **Penetration Testing**: Periodic penetration testing to validate security controls

## Security Validation

Refer to `SSH_KEY_MANAGEMENT.md` for key management procedures and `../test/security/ssh_security_test.sh` for automated security validation tests.

---

**Classification**: Internal Use  
**Last Updated**: 2024-12-19  
**Next Review**: 2025-03-19