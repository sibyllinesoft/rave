# nixos/modules/security/hardening.nix
# P1 security hardening configuration
{ config, pkgs, lib, ... }:

{
  # P1: Production Security Hardening
  
  # Kernel security parameters
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.ip_forward" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    
    # IPv6 security
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    
    # Kernel security
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    
    # Memory protection
    "kernel.randomize_va_space" = 2;
    "vm.mmap_min_addr" = 65536;
  };

  # Enhanced SSH security
  services.openssh = {
    enable = true;
    settings = {
      # Authentication
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      ChallengeResponseAuthentication = false;
      KbdInteractiveAuthentication = false;
      
      # Protocol settings
      Protocol = 2;
      X11Forwarding = false;
      AllowTcpForwarding = "no";
      AllowAgentForwarding = false;
      PermitTunnel = "no";
      GatewayPorts = "no";
      
      # Session settings
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      LoginGraceTime = 60;
      MaxAuthTries = 3;
      MaxSessions = 8;
      MaxStartups = "40:40:200";
      
      # Encryption
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
        "aes256-ctr"
        "aes192-ctr"
        "aes128-ctr"
      ];
      
      KexAlgorithms = [
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
        "diffie-hellman-group14-sha256"
      ];
      
      Macs = [
        "hmac-sha2-256-etm@openssh.com"
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256"
        "hmac-sha2-512"
      ];
    };
    
    # Generate new host keys with stronger algorithms
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  # Firewall hardening
  networking.firewall = {
    enable = true;
    
    # Default policy: deny all
    allowPing = false;
    
    # Log dropped packets for security analysis
    logReversePathDrops = true;
    logRefusedConnections = true;
    logRefusedPackets = false; # Avoid log spam
    
    # Rate limiting for SSH
    extraCommands = ''
      # Allow unrestricted SSH from the local QEMU host (10.0.2.2) for automated testing
      iptables -I INPUT -p tcp --dport 22 -s 10.0.2.2 -j ACCEPT

      # Rate limit SSH connections (max ~12 per minute per IP)
      iptables -I INPUT -p tcp --dport 22 -i eth0 -m state --state NEW -m recent --set
      iptables -I INPUT -p tcp --dport 22 -i eth0 -m state --state NEW -m recent --update --seconds 60 --hitcount 12 -j DROP
      
      # Block common attack patterns
      iptables -I INPUT -p tcp --tcp-flags ALL NONE -j DROP
      iptables -I INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
      iptables -I INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
      iptables -I INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
      iptables -I INPUT -p tcp --tcp-flags ACK,FIN FIN -j DROP
      iptables -I INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
      iptables -I INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
    '';
  };

  # System security settings
  security = {
    # Disable sudo password for development convenience (override in production)
    sudo.wheelNeedsPassword = lib.mkDefault false;
    
    # Enable AppArmor
    apparmor.enable = true;
    
    # Protect kernel modules
    lockKernelModules = true;
    
    # Prevent privilege escalation (but allow for nix sandbox)
    # Note: allowUserNamespaces must be true for Nix sandbox to work
    allowUserNamespaces = true; # Required for nix.settings.sandbox = true
    unprivilegedUsernsClone = false;
    
    # PAM security configuration (using newer NixOS syntax)
    pam.loginLimits = [
      { domain = "*"; type = "hard"; item = "nofile"; value = "65536"; }
      { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
      { domain = "*"; type = "hard"; item = "nproc"; value = "32768"; }
      { domain = "*"; type = "soft"; item = "nproc"; value = "16384"; }
    ];
  };

  # Audit system
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Monitor privilege escalation
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privilege-escalation"
      "-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privilege-escalation"
      
      # Monitor file access
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/sudoers -p wa -k privilege-escalation"
      "-w /etc/ssh/sshd_config -p wa -k ssh-config"
      
      # Monitor network configuration
      "-w /etc/hosts -p wa -k network-config"
      "-w /etc/resolv.conf -p wa -k network-config"
      
      # Monitor system calls
      "-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts"
      "-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts"
    ];
  };

  # Fail2ban for intrusion prevention
  services.fail2ban = {
    enable = true;
    
    jails = {
      ssh = {
        settings = {
          enabled = true;
          filter = "sshd";
          logpath = "/var/log/auth.log";
          maxretry = 3;
          findtime = 300;
          bantime = 1800;
        };
      };
      
      nginx-http-auth = {
        settings = {
          enabled = true;
          filter = "nginx-http-auth";
          logpath = "/var/log/nginx/error.log";
          maxretry = 3;
          findtime = 600;
          bantime = 3600;
        };
      };
      
      nginx-noscript = {
        settings = {
          enabled = true;
          filter = "nginx-noscript";
          logpath = "/var/log/nginx/access.log";
          maxretry = 6;
          findtime = 600;
          bantime = 3600;
        };
      };
      
      nginx-badbots = {
        settings = {
          enabled = true;
          filter = "nginx-badbots";
          logpath = "/var/log/nginx/access.log";
          maxretry = 2;
          findtime = 600;
          bantime = 3600;
        };
      };
    };
  };

  # ClamAV antivirus (optional, resource intensive)
  services.clamav = {
    daemon.enable = false; # Enable in high-security environments
    updater.enable = false;
  };

  # Automatic security updates (defaults that can be overridden)
  system.autoUpgrade = {
    enable = lib.mkDefault true;
    allowReboot = lib.mkDefault false; # Set to true in production with proper scheduling
    channel = lib.mkDefault "nixos-24.11";
    dates = lib.mkDefault "04:00"; # Run at 4 AM
    flags = [
      "--upgrade-all"
      "--no-build-output"
    ];
  };

  # Enhanced logging (using systemd-journald which is default in NixOS)
  services.journald.extraConfig = ''
    # Enhanced security logging configuration
    Storage=persistent
    Compress=true
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    ForwardToSyslog=false
    MaxRetentionSec=2592000
  '';

  # File integrity monitoring (basic)
  systemd.services.file-integrity-check = {
    description = "File integrity monitoring";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeScript "file-integrity-check" ''
        #!${pkgs.bash}/bin/bash
        
        # Check critical system files
        CRITICAL_FILES=(
          "/etc/passwd"
          "/etc/shadow"
          "/etc/group"
          "/etc/sudoers"
          "/etc/ssh/sshd_config"
          "/etc/nixos/configuration.nix"
        )
        
        for file in "''${CRITICAL_FILES[@]}"; do
          if [ -f "$file" ]; then
            sha256sum "$file" >> /var/log/file-integrity.log
          fi
        done
      '';
    };
  };

  systemd.timers.file-integrity-check = {
    description = "Run file integrity check daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
  
  # Add security scanning tools from P1
  environment.systemPackages = with pkgs; [
    # Security scanning tools
    nmap
    netcat
    tcpdump
    wireshark-cli
    
    # Certificate management
    openssl
  ];
}
