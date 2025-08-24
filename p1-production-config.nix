# P1 Production Security Hardening Configuration
# Implements Phase P1: Security Hardening - Critical Path
# Extends P0 foundation with comprehensive security measures
{ config, pkgs, lib, ... }:

{
  # Import P0 baseline configuration
  imports = [ ./p0-production-config.nix ];
  
  # Override hostname for P1
  networking.hostName = lib.mkDefault "rave-p1";
  
  # P1.1: Enhanced user security with no password authentication
  users.users.agent = lib.mkForce {
    isNormalUser = true;
    description = "AI Agent - Production Security Hardened";
    extraGroups = [ "wheel" ];
    hashedPassword = null;  # Completely remove password authentication
    password = null;       # Ensure no password fallback
    shell = pkgs.bash;
    
    # P1.1: SSH public key authentication ONLY
    openssh.authorizedKeys.keys = [
      # TODO: Replace with actual team SSH public keys before production deployment
      # Generate keys with: ssh-keygen -t ed25519 -C "team-member@company.com"
      # Example entries (replace with actual team keys):
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGNrJFQV... security-team-lead@company.com"
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHqp7WGK... devops-admin@company.com"  
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMth9k2L... sre-team@company.com"
      
      # Placeholder warning key (REMOVE in production)
      "# WARNING: No production SSH keys configured - access will be BLOCKED"
      "# Add actual team SSH public keys here before deployment"
    ];
  };
  
  # P1.1: Enhanced SSH security - overrides P0 with stronger settings
  services.openssh = lib.mkForce {
    enable = true;
    settings = {
      # P1.1: Enforce key-only authentication (no passwords)
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      AuthenticationMethods = "publickey";
      PermitRootLogin = "no";  # No root login permitted
      
      # P1.1: Disable all password-based methods
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;
      KbdInteractiveAuthentication = false;
      UsePAM = false;
      
      # P1.1: Disable potentially dangerous features
      X11Forwarding = false;
      AllowTcpForwarding = "no";
      GatewayPorts = "no";
      PermitTunnel = "no";
      AllowAgentForwarding = false;
      
      # P1.1: Connection hardening
      MaxAuthTries = 2;  # Reduced from P0's 3
      MaxSessions = 2;   # Reduced from P0's 10
      MaxStartups = "2:50:10";  # Limit concurrent connections
      LoginGraceTime = 30;  # Reduced from P0's 60
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      
      # P1.1: Enhanced logging and monitoring
      LogLevel = "VERBOSE";  # Enhanced logging for security monitoring
      SyslogFacility = "AUTH";
      
      # P1.1: Restrict to specific users and groups
      AllowUsers = [ "agent" ];
      AllowGroups = [ "users" ];
      
      # P1.1: Enhanced cryptography (stronger than P0)
      Protocol = 2;
      Ciphers = [
        "chacha20-poly1305@openssh.com"  # Most secure
        "aes256-gcm@openssh.com" 
        # Removed weaker ciphers from P0
      ];
      KexAlgorithms = [
        "curve25519-sha256@libssh.org"   # Most secure
        "diffie-hellman-group16-sha512"
        # Removed weaker algorithms
      ];
      Macs = [
        "hmac-sha2-256-etm@openssh.com"
        "hmac-sha2-512-etm@openssh.com"
      ];
      
      # P1.1: Host-based security 
      IgnoreRhosts = true;
      HostbasedAuthentication = false;
      PrintMotd = false;
      PrintLastLog = true;
      
      # P1.1: Network security
      AddressFamily = "inet";  # IPv4 only
      ListenAddress = "0.0.0.0:22";
      
      # P1.1: Additional hardening
      StrictModes = true;
      Compression = false;  # Disable compression for security
    };
    
    # P1.1: SSH host key configuration
    hostKeys = [
      {
        type = "ed25519";
        path = "/etc/ssh/ssh_host_ed25519_key";
        rounds = 100;
      }
    ];
    
    # P1.1: Additional SSH hardening
    extraConfig = ''
      # P1.1: Additional security settings
      PermitUserEnvironment no
      AllowStreamLocalForwarding no
      DisableForwarding yes
      ExposeAuthInfo no
      FingerprintHash sha256
      RekeyLimit 512M 1h
      
      # P1.1: Rate limiting and DDoS protection
      Match all
        MaxAuthTries 2
        MaxSessions 2
    '';
  };
  
  # P1.1: Enhanced firewall configuration with stricter rules
  networking.firewall = lib.mkForce {
    enable = true;
    allowedTCPPorts = [ 22 3002 ];  # SSH and HTTPS only
    allowedUDPPorts = [ ];  # No UDP ports by default
    
    # Block all other inbound traffic explicitly
    extraCommands = ''
      # Drop all other inbound traffic
      iptables -P INPUT DROP
      iptables -P FORWARD DROP
      iptables -P OUTPUT ACCEPT
      
      # Allow loopback
      iptables -A INPUT -i lo -j ACCEPT
      
      # Allow established and related connections
      iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      
      # Rate limiting for SSH to prevent brute force
      iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
      iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
    '';
    
    extraStopCommands = ''
      # Reset to default policies
      iptables -P INPUT ACCEPT
      iptables -P FORWARD ACCEPT
      iptables -P OUTPUT ACCEPT
    '';
  };
  
  # P1: Enhanced system hardening
  # Disable unnecessary services
  services.printing.enable = false;
  services.avahi.enable = false;
  services.gnome.gnome-keyring.enable = false;
  
  # Kernel hardening
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.accept_source_route" = false;
    "net.ipv4.conf.default.accept_source_route" = false;
    "net.ipv4.icmp_ignore_bogus_error_responses" = true;
    "net.ipv4.tcp_syncookies" = true;
    "net.ipv4.conf.all.rp_filter" = true;
    "net.ipv4.conf.default.rp_filter" = true;
    
    # Memory protection
    "kernel.dmesg_restrict" = true;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    
    # File system hardening
    "fs.protected_hardlinks" = true;
    "fs.protected_symlinks" = true;
    "fs.suid_dumpable" = false;
  };
  
  # P1: Enhanced security headers in nginx
  services.nginx.virtualHosts."rave.local".extraConfig = lib.mkAfter ''
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;
  '';
  
  # P1: Add security scanning tools
  environment.systemPackages = with pkgs; [
    # Security scanning tools
    nmap
    netcat
    tcpdump
    wireshark-cli
    
    # Certificate management
    openssl
  ];
  
  # P1: Security-focused environment setup update
  systemd.services.setup-agent-environment.serviceConfig.ExecStart = lib.mkForce (pkgs.writeScript "setup-agent-env-p1" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    # Create directories
    mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
    
    # P1: Enhanced security notice
    cat > /home/agent/welcome.sh << 'WELCOMEEOF'
#!/bin/bash
echo "🔒 RAVE P1 Security Hardened Environment"
echo "========================================"
echo ""
echo "🛡️ P1 Security Features Active:"
echo "  • SSH key authentication only (no passwords)"
echo "  • Enhanced firewall with rate limiting"
echo "  • Security headers on all HTTPS responses"
echo "  • Kernel hardening and memory protection"
echo "  • Disabled unnecessary services"
echo ""
echo "🎯 Services Available:"
echo "  • Vibe Kanban: https://rave.local:3002/"
echo "  • Grafana: https://rave.local:3002/grafana/ (admin/admin)"
echo "  • Claude Code Router: https://rave.local:3002/ccr-ui/"
echo ""
echo "🔧 Security Tools Available:"
echo "  • nmap, netcat, tcpdump, wireshark-cli"
echo "  • openssl for certificate management"
echo ""
echo "⚠️ Production Setup Required:"
echo "  • Add team SSH public keys to agent user"
echo "  • Configure actual TLS certificates"
echo "  • Set up proper authentication for services"
echo "  • Configure security monitoring and alerting"
echo ""
echo "📖 Next Phase: P2 adds comprehensive observability"
WELCOMEEOF
    chmod +x /home/agent/welcome.sh
    
    # Update bashrc with security context
    echo "" >> /home/agent/.bashrc
    echo "# RAVE P1 Security Environment" >> /home/agent/.bashrc
    echo "export BROWSER=chromium" >> /home/agent/.bashrc
    echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
    echo "export SAFE=1" >> /home/agent/.bashrc
    echo "export FULL_PIPE=0" >> /home/agent/.bashrc
    echo "export NODE_OPTIONS=\"--max-old-space-size=1536\"" >> /home/agent/.bashrc
    echo "~/welcome.sh" >> /home/agent/.bashrc
    
    # Set secure permissions
    chmod 700 /home/agent/.ssh
    chown -R agent:users /home/agent
    
    echo "P1 security hardened environment setup complete!"
  '');
}