# AI Agent Sandbox - NixOS Configuration
{ config, pkgs, lib, modulesPath, ... }:

{
  # Import base VM modules
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/profiles/qemu-guest.nix"
  ];
  
  # Basic system configuration
  system.stateVersion = "24.05";
  
  # Boot configuration for VM
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.enable = true;
  boot.loader.timeout = 0;
  
  # Network configuration
  networking.hostName = "ai-sandbox";
  networking.networkmanager.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3000 3001 3002 ];
  };
  
  # Time zone
  time.timeZone = "UTC";
  
  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  
  # User configuration
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent";
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    password = "agent"; # Simple password for development
    packages = with pkgs; [
      firefox
      tree
      htop
    ];
  };
  
  # Enable sudo without password for agent user
  security.sudo.wheelNeedsPassword = false;
  
  # Desktop environment - minimal XFCE
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    displayManager.autoLogin.enable = true;
    displayManager.autoLogin.user = "agent";
    desktopManager.xfce.enable = true;
    
    # Basic X11 configuration
    xkb.layout = "us";
  };
  
  # Sound
  hardware.pulseaudio.enable = true;
  
  # SSH Security Hardening
  services.openssh = {
    enable = true;
    settings = {
      # Disable password authentication - use keys only
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      AuthenticationMethods = "publickey";
      
      # Security hardening
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;
      UsePAM = false;
      X11Forwarding = false;
      
      # Connection limits and timeouts
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      LoginGraceTime = 60;
      MaxSessions = 10;
    };
  };

  # Intrusion Prevention with fail2ban
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    jails = {
      sshd = {
        settings = {
          enabled = true;
          filter = "sshd";
          action = "iptables[name=SSH, port=ssh, protocol=tcp]";
          backend = "systemd";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };
    };
  };
  
  # VNC server for remote access (commented out - service may not be available)
  # services.x11vnc = {
  #   enable = true;
  #   display = 0;
  #   passwordFile = "/run/secrets/vncpasswd";
  # };
  
  # System packages for AI agents
  environment.systemPackages = with pkgs; [
    # Development tools
    git
    curl
    wget
    vim
    nano
    
    # Build tools
    gcc
    gnumake
    
    # Python ecosystem
    python3
    python3Packages.pip
    python3Packages.virtualenv
    
    # Node.js ecosystem  
    nodejs
    npm
    
    # Browser automation
    chromium
    
    # X11 tools
    xorg.xvfb
    x11vnc
    
    # Utilities
    unzip
    zip
    tree
    htop
    
    # Container tools
    docker
    docker-compose
  ];
  
  # Enable Docker
  virtualisation.docker.enable = true;
  
  # Python packages available system-wide
  environment.variables = {
    PYTHONPATH = "${pkgs.python3Packages.playwright}/lib/python3.11/site-packages";
  };
  
  # Services to auto-start
  systemd.services.install-playwright = {
    description = "Install Playwright browsers";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      ExecStart = "${pkgs.python3Packages.pip}/bin/pip install --user playwright && ${pkgs.python3}/bin/python -m playwright install chromium";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
}