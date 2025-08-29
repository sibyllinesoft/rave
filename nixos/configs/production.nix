# nixos/configs/production.nix
# P6 production configuration - all services with full security hardening
{ ... }:

{
  imports = [
    # Foundation modules (required for all VMs)
    ../modules/foundation/base.nix
    ../modules/foundation/nix-config.nix
    ../modules/foundation/networking.nix
    
    # Service modules
    ../modules/services/gitlab
    ../modules/services/matrix
    ../modules/services/monitoring
    
    # Security modules
    ../modules/security/hardening.nix
    ../modules/security/certificates.nix
  ];

  # Production-specific settings
  networking.hostName = "rave-production";
  
  # Certificate configuration for production
  rave.certificates = {
    domain = "rave.local";
    useACME = false; # Set to true when deploying to a real domain
    email = "admin@rave.local";
  };

  # Enable all required services
  services = {
    postgresql.enable = true;
    nginx.enable = true;
    redis.servers.default.enable = true;
  };

  # Production security overrides
  security.sudo.wheelNeedsPassword = true; # Require password for sudo in production
  services.openssh.settings.PasswordAuthentication = false; # Key-based auth only

  # Production system limits
  systemd.extraConfig = ''
    DefaultLimitNOFILE=65536
    DefaultLimitNPROC=32768
  '';

  # Enhanced logging for production
  services.journald.extraConfig = ''
    Storage=persistent
    Compress=true
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    ForwardToSyslog=true
  '';

  # Automatic updates (with reboot allowed during maintenance window)
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    dates = "Sun 03:00"; # Sunday at 3 AM
    channel = "nixos-24.11";
    randomizedDelaySec = "45min"; # Random delay up to 45 minutes
  };

  # Production backup configuration (placeholder)
  # systemd.services.rave-backup = {
  #   description = "RAVE System Backup";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "/path/to/backup-script";
  #   };
  # };
  # 
  # systemd.timers.rave-backup = {
  #   description = "Run RAVE backup daily";
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnCalendar = "daily";
  #     Persistent = true;
  #   };
  # };
}