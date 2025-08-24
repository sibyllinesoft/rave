#!/usr/bin/env python3
"""
Security Hardening Script for Matrix Bridge
Installs security tools and configures security scanning.
"""

import subprocess
import sys
import os
from pathlib import Path

def install_security_tools():
    """Install required security scanning tools."""
    print("🔧 Installing security tools...")
    
    tools = [
        ("bandit", "Python static analysis security tool"),
        ("safety", "Python dependency vulnerability scanner"),
        ("flake8", "Python code quality checker"),
    ]
    
    for tool, description in tools:
        print(f"Installing {tool} ({description})...")
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", tool], check=True)
            print(f"✅ {tool} installed successfully")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to install {tool}: {e}")
            return False
    
    return True

def create_security_config():
    """Create security tool configuration files."""
    print("🔧 Creating security configuration files...")
    
    # Create .bandit configuration
    bandit_config = """[bandit]
# Bandit Security Configuration for Matrix Bridge
# https://bandit.readthedocs.io/en/latest/config.html

[bandit.assert_used]
# Skip assert checks as we use them for validation
skips = ["*"]

[bandit.hardcoded_password_string]
# Skip false positives for enum constants
skips = ["*/audit.py"]

[bandit.subprocess_popen_with_shell_equals_true]
# We use shell=False explicitly
confidence = HIGH

[bandit.subprocess_without_shell_equals_false]
# We explicitly avoid shell usage
confidence = HIGH

exclude_dirs = ["tests", ".git", "__pycache__", "reports"]
confidence = HIGH
severity = HIGH
"""
    
    with open(".bandit", "w") as f:
        f.write(bandit_config)
    print("✅ Created .bandit configuration")
    
    # Create .flake8 configuration  
    flake8_config = """[flake8]
# Flake8 Configuration for Matrix Bridge
max-line-length = 100
max-complexity = 12
exclude = 
    .git,
    __pycache__,
    .pytest_cache,
    reports,
    tests/fixtures

ignore = 
    E203,  # Whitespace before ':'
    W503,  # Line break before binary operator
    E501   # Line too long (handled by max-line-length)

per-file-ignores =
    __init__.py: F401  # Unused imports in __init__.py are OK
"""
    
    with open(".flake8", "w") as f:
        f.write(flake8_config)
    print("✅ Created .flake8 configuration")
    
    return True

def run_security_scan():
    """Run comprehensive security scanning."""
    print("🔍 Running security scans...")
    
    # Run Bandit
    print("\n📊 Running Bandit security analysis...")
    try:
        result = subprocess.run([
            "bandit", "-r", "src/", "-f", "json", "-o", "reports/bandit-report.json"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Bandit scan completed - no high severity issues found")
        else:
            print(f"⚠️ Bandit found potential issues (exit code: {result.returncode})")
            print("Check reports/bandit-report.json for details")
    except FileNotFoundError:
        print("❌ Bandit not found - installation may have failed")
        
    # Run Safety
    print("\n🛡️ Running Safety dependency scan...")
    try:
        result = subprocess.run([
            "safety", "check", "--json", "--output", "reports/safety-report.json"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Safety scan completed - no vulnerabilities found")
        else:
            print(f"⚠️ Safety found vulnerabilities (exit code: {result.returncode})")
            print("Check reports/safety-report.json for details")
    except FileNotFoundError:
        print("❌ Safety not found - installation may have failed")
        
    # Run Flake8
    print("\n📝 Running Flake8 code quality check...")
    try:
        result = subprocess.run([
            "flake8", "src/", "--output-file=reports/flake8-report.txt"
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✅ Flake8 check completed - no code quality issues found")
        else:
            print(f"⚠️ Flake8 found code quality issues (exit code: {result.returncode})")
            print("Check reports/flake8-report.txt for details")
    except FileNotFoundError:
        print("❌ Flake8 not found - installation may have failed")

def create_security_documentation():
    """Create security documentation and procedures."""
    print("📚 Creating security documentation...")
    
    security_readme = """# Matrix Bridge Security Documentation

## Security Architecture

The Matrix Bridge implements defense-in-depth security with multiple layers:

### 1. Input Validation Layer
- Command allowlisting with strict pattern matching
- Input sanitization with HTML escaping
- Length and complexity limits
- Dangerous pattern detection

### 2. Authentication & Authorization Layer  
- GitLab OIDC integration with JWT validation
- Role-based access control
- Token caching with TTL and integrity verification
- Failed attempt tracking and lockout

### 3. Rate Limiting Layer
- Adaptive rate limiting with system load awareness
- Per-client tracking and burst capacity
- Redis-based distributed rate limiting
- Circuit breaker pattern for resilience

### 4. Audit & Monitoring Layer
- Comprehensive audit logging with HMAC integrity
- Tamper-resistant log storage
- Real-time security event monitoring
- Performance metrics and alerting

## Security Controls

### OWASP Top 10 Mitigations

1. **Injection Prevention**
   - Strict input validation and sanitization
   - Command allowlisting (no SQL in this service)
   - Safe subprocess execution without shell

2. **Broken Authentication**
   - JWT token validation with cryptographic verification
   - Multi-factor authentication support
   - Session timeout and token expiration

3. **Sensitive Data Exposure**
   - No hardcoded secrets (configuration-based)
   - Token sanitization in logs
   - Secure token storage and transmission

4. **XML External Entities (XXE)**
   - No XML processing (JSON-only API)

5. **Broken Access Control**
   - Role-based authorization with permission checks
   - Principle of least privilege
   - Command-level access control

6. **Security Misconfiguration**
   - Secure defaults in all configurations
   - Regular security scanning (Bandit, Safety)
   - Environment-specific hardening

7. **Cross-Site Scripting (XSS)**
   - HTML escaping for all user inputs
   - Content-Type validation
   - Input sanitization

8. **Insecure Deserialization**
   - Safe JSON parsing only
   - Input validation before deserialization

9. **Using Components with Known Vulnerabilities**
   - Automated dependency scanning (Safety)
   - Regular dependency updates
   - Minimal dependency surface

10. **Insufficient Logging & Monitoring**
    - Comprehensive audit trail
    - Security event correlation
    - Real-time alerting

## Security Testing

### Automated Security Testing
- Static analysis with Bandit
- Dependency scanning with Safety
- Code quality checks with Flake8
- Custom security validation script

### Manual Security Testing
- Penetration testing procedures
- Security architecture reviews
- Code security reviews

## Incident Response

### Security Incident Procedures
1. **Detection** - Automated monitoring and alerts
2. **Containment** - Circuit breaker activation, rate limiting
3. **Investigation** - Audit log analysis, forensics
4. **Recovery** - Service restoration, security patches
5. **Post-Incident** - Review, documentation, improvements

### Contact Information
- Security Team: security@organization.com
- Incident Response: incident-response@organization.com
- Emergency Contact: +1-XXX-XXX-XXXX

## Compliance & Standards

### Security Frameworks
- OWASP Application Security Verification Standard (ASVS)
- NIST Cybersecurity Framework
- ISO 27001 Information Security Management

### Regular Security Activities
- Monthly vulnerability assessments
- Quarterly penetration testing
- Annual security architecture reviews
- Continuous security monitoring

## Security Configuration

### Environment Variables
```bash
# Authentication
GITLAB_URL=https://gitlab.example.com
OIDC_CLIENT_ID=your_client_id
OIDC_CLIENT_SECRET=your_client_secret

# Matrix Integration  
HOMESERVER_URL=https://matrix.example.com
AS_TOKEN=your_appservice_token
HS_TOKEN=your_homeserver_token

# Security Settings
RATE_LIMIT_RPM=60
RATE_LIMIT_BURST=10
AUTH_CACHE_TTL=300
LOCKOUT_DURATION=900
```

### Security Hardening Checklist
- [ ] All dependencies updated to latest secure versions
- [ ] Security scanning tools configured and running
- [ ] Audit logging enabled and monitored
- [ ] Rate limiting configured appropriately
- [ ] Authentication properly configured
- [ ] All security tests passing
- [ ] Security documentation up to date
"""

    with open("docs/SECURITY.md", "w") as f:
        f.write(security_readme)
    print("✅ Created comprehensive security documentation")

def main():
    """Main security hardening routine."""
    print("🛡️ Matrix Bridge Security Hardening")
    print("=" * 50)
    
    # Ensure reports directory exists
    reports_dir = Path("reports")
    reports_dir.mkdir(exist_ok=True)
    
    docs_dir = Path("docs")
    docs_dir.mkdir(exist_ok=True)
    
    # Install security tools
    if not install_security_tools():
        print("❌ Failed to install security tools")
        return False
    
    # Create security configurations
    if not create_security_config():
        print("❌ Failed to create security configurations")  
        return False
    
    # Run security scans
    run_security_scan()
    
    # Create security documentation
    create_security_documentation()
    
    print("\n" + "=" * 50)
    print("✅ Security hardening completed!")
    print("\n📊 Summary:")
    print("   - Security tools installed and configured")
    print("   - Security scans executed")
    print("   - Security documentation created")
    print("   - Configuration files updated")
    
    print("\n📋 Next Steps:")
    print("   1. Review scan reports in reports/ directory")
    print("   2. Address any findings from security scans")
    print("   3. Update security documentation as needed")
    print("   4. Schedule regular security assessments")
    
    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)