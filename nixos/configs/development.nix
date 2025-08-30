# nixos/configs/development.nix
# Development configuration - HTTP-only, minimal security for local testing
{ config, pkgs, lib, ... }:

{
  imports = [
    # Foundation modules (required for all VMs)
    ../modules/foundation/base.nix
    ../modules/foundation/nix-config.nix
    ../modules/foundation/networking.nix
    
    # Service modules (choose which services to enable for development)
    ../modules/services/gitlab   # Enable GitLab for development
    ../modules/services/nats     # Enable NATS JetStream
    # ../modules/services/penpot   # Enable Penpot design tool (disabled for rebuild)
    # ../modules/services/matrix    # Uncomment if needed for development
    # ../modules/services/monitoring # Uncomment if needed for development
    
    # Minimal security (no hardening in development)
    ../modules/security/certificates.nix
    # ../modules/security/secrets.nix
  ];

  # Development-specific settings
  networking.hostName = "rave-dev";
  
  # Certificate configuration for development - use self-signed certificates
  rave.certificates = {
    domain = "rave.local";
    useACME = false; # Use self-signed certs in development
    email = "dev@rave.local";
  };

  # Enable required services for development
  services = {
    postgresql.enable = true;
    # nginx.enable = true; # Configured separately below
    redis.servers.default.enable = true;
  };
  
  # Enable secret generation for development
  # services.rave.secrets.enable = true;

  # Enable GitLab service for development
  services.rave.gitlab = {
    enable = true;
    host = "rave.local";
    useSecrets = false;  # Disable sops-nix secrets for development
    runner.enable = false;  # Disable runner for simpler development setup
  };


  # Enable NATS JetStream service for development
  services.rave.nats = {
    enable = true;
    serverName = "rave-dev-nats";
    debug = true;   # Enable debug logging for development
    trace = false;  # Keep trace off to avoid log spam
    safeMode = true;  # Enable SAFE mode resource limits
    
    # Development-friendly limits
    jetstream = {
      maxMemory = "128MB";    # Smaller memory limit for development
      maxFileStore = "512MB"; # Smaller file store for development
    };
    
    limits = {
      maxConnections = 1000;  # Reduced for development
      maxPayload = 1048576;   # 1MB payload limit
    };
  };

  # Enable Penpot design tool for development (disabled for rebuild)
  # services.rave.penpot = {
  #   enable = true;
  #   host = "rave.local";
  #   useSecrets = false;  # Disable sops-nix secrets for development
  #   
  #   oidc = {
  #     enable = true;
  #     gitlabUrl = "https://rave.local/gitlab";
  #     clientId = "penpot";
  #   };
  # };
  
  # GitLab port is managed by the service module

  # Development overrides for convenience - SSH key-based authentication
  security.sudo.wheelNeedsPassword = false; # No password required in development
  
  # SSH Configuration - temporarily enable password auth for debugging
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true; # Temporarily enable password auth for debugging
      PermitRootLogin = lib.mkForce "yes"; # Allow root login with password temporarily
      PubkeyAuthentication = true;
      AuthorizedKeysFile = ".ssh/authorized_keys";
    };
  };
  
  # Set a temporary root password for debugging
  users.users.root.hashedPassword = "$6$VspFT61JPz44H5o8$oCYt2Zz7gDFCRNwF8ZufhSFid91d/zlElpCc40Fvj7S9bHy7dCg1h4WIIZLc3ZGx4JzNVGk6CdrkkbVQrmQA40";  # password: "debug123"

  # Configure root user with SSH key
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJyaG9HvY1Evx6DmiuAcTkCsifIpcKe/M0Oe0NUUN/i rave-vm-access"
  ];

  # Also configure the agent user with SSH key
  users.users.agent.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJyaG9HvY1Evx6DmiuAcTkCsifIpcKe/M0Oe0NUUN/i rave-vm-access"
  ];

  # Add development-friendly virtual host for testing
  services.nginx.virtualHosts."localhost" = {
    listen = [
      { addr = "0.0.0.0"; port = 8080; }
    ];
    locations."/" = {
      return = "200 \"Hello from RAVE VM!\"";
    };
  };

  # Development-friendly networking
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP
      8080  # GitLab
      4222  # NATS client connections
      8222  # NATS HTTP monitoring
      3449  # Penpot Frontend
      6060  # Penpot Backend
      6061  # Penpot Exporter
      6380  # Redis for Penpot
      3000  # Grafana (if monitoring enabled)
      9090  # Prometheus (if monitoring enabled)
      8008  # Matrix (if enabled)
    ];
    # More permissive firewall rules for development
    trustedInterfaces = [ "lo" ];
  };

  # Development logging (less verbose)
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=100M
  '';

  # Disable automatic updates in development
  system.autoUpgrade.enable = false;

  # Development environment packages
  environment.systemPackages = with pkgs; [
    # Additional development tools
    curl
    wget
    tcpdump
    netcat-gnu
    nmap
    tree
    git
    vim
    nano
    
    # Development debugging tools
    lsof
    strace
    wireshark-cli
    dig
    
    # For interacting with services
    postgresql
    redis
  ];
}