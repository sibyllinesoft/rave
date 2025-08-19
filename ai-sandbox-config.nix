# AI Agent Sandbox - NixOS Configuration
{ config, pkgs, ... }:

{
  # Basic system configuration
  system.stateVersion = "24.05";
  
  # Boot configuration for VM
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.enable = true;
  
  # Network configuration
  networking.hostName = "ai-sandbox";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false; # Disable for development VM
  
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
  
  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };
  
  # VNC server for remote access
  services.x11vnc = {
    enable = true;
    display = 0;
    passwordFile = "/run/secrets/vncpasswd";
  };
  
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