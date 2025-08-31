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
    ../modules/services/penpot   # Enable Penpot design tool
    # ../modules/services/matrix   # Enable Matrix/Element for development (temporarily disabled)
    ../modules/services/monitoring # Enable Grafana monitoring stack
    
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

  # Enable Penpot design tool for development
  services.rave.penpot = {
    enable = true;
    host = "rave.local";
    useSecrets = false;  # Disable sops-nix secrets for development
    
    oidc = {
      enable = true;
      gitlabUrl = "https://rave.local/gitlab";
      clientId = "penpot";
    };
  };

  # Enable Matrix/Element for development (temporarily disabled)
  # services.rave.matrix = {
  #   enable = true;
  #   serverName = "rave.local";
  #   useSecrets = false;  # Disable sops-nix secrets for development
  #   
  #   oidc = {
  #     enable = true;
  #     gitlabUrl = "https://rave.local/gitlab";
  #   };
  # };
  
  # Enable monitoring stack for development
  services.rave.monitoring = {
    enable = true;
    safeMode = true;  # Enable SAFE mode with memory limits for development
  };
  
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

  # Override the main rave.local root location to serve the dashboard
  services.nginx.virtualHosts."rave.local".locations."/" = lib.mkForce {
    root = "/var/www/html";
    index = "dashboard.html";
    tryFiles = "$uri $uri/ /dashboard.html";
    extraConfig = ''
      access_log off;
      # Security headers for HTTPS
      add_header X-Frame-Options DENY always;
      add_header X-Content-Type-Options nosniff always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' wss: https:;" always;
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    '';
  };

  # Services are now enabled and routed by their respective modules

  # Setup dashboard files in the VM  
  environment.etc."dashboard.html".text = ''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RAVE Development Environment</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Michroma:wght@400&display=swap" rel="stylesheet">
    <script src="https://unpkg.com/lucide@latest/dist/umd/lucide.js"></script>
    <style>
        body {
            font-family: 'Inter', sans-serif;
            margin: 0;
            background: linear-gradient(135deg, #2d2d2d 0%, #3a3a3a 50%, #2d2d2d 100%);
            min-height: 100vh;
            color: #e0e0e0;
        }
        .header {
            background: linear-gradient(135deg, #3a3a3a 0%, #4a4a4a 50%, #3a3a3a 100%);
            padding: 2rem 0;
            text-align: center;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
            border-bottom: 1px solid #4a4a4a;
        }
        .header h1 {
            font-family: 'Michroma', monospace;
            font-size: 2.5rem;
            color: #3498db;
            margin: 0;
        }
        .header p {
            font-family: 'Inter', sans-serif;
            font-size: 1.1rem;
            color: #bdc3c7;
            margin: 0.5rem 0 0 0;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 3rem 1rem;
        }
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
        }
        .service-card {
            background: linear-gradient(135deg, #3a3a3a 0%, #404040 100%);
            border: 1px solid #4a4a4a;
            border-radius: 16px;
            padding: 2rem;
            text-decoration: none;
            color: inherit;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
            cursor: pointer;
            display: block;
        }
        .service-card:hover {
            transform: translateY(-8px) scale(1.02);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4), 
                        0 0 0 1px rgba(52, 152, 219, 0.3);
            border-color: #3498db;
        }
        .service-card.disabled {
            opacity: 0.6;
            cursor: not-allowed;
            pointer-events: none;
        }
        .service-card.disabled:hover {
            transform: none;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            background: linear-gradient(135deg, #3a3a3a, #2d2d2d);
            border-color: #4a4a4a;
        }
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }
        .service-title {
            font-family: 'Inter', sans-serif;
            color: #ecf0f1;
            font-size: 1.25rem;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            transition: color 0.3s ease;
        }
        .service-card:hover .service-title {
            color: #3498db;
        }
        .service-icon {
            width: 24px;
            height: 24px;
            color: #3498db;
            transition: transform 0.3s ease;
        }
        .service-card:hover .service-icon {
            transform: scale(1.1);
        }
        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            position: absolute;
            top: 1.5rem;
            right: 1.5rem;
            transition: all 0.3s ease;
        }
        .service-card:hover .status-dot {
            transform: scale(1.2);
        }
        .status-active {
            background: #27ae60;
            box-shadow: 0 0 8px rgba(39, 174, 96, 0.4);
        }
        .status-inactive {
            background: #e74c3c;
            box-shadow: 0 0 8px rgba(231, 76, 60, 0.4);
        }
        .service-description {
            font-family: 'Inter', sans-serif;
            color: #bdc3c7;
            line-height: 1.6;
            margin-bottom: 1.5rem;
            transition: color 0.3s ease;
        }
        .service-card:hover .service-description {
            color: #ecf0f1;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>RAVE Development Environment</h1>
        <p>Reproducible AI Virtual Environment - Development Instance</p>
    </div>
    <div class="container">
        <div class="services-grid">
            <a href="/gitlab/" class="service-card">
                <div class="status-dot status-active"></div>
                <div class="service-header">
                    <h3 class="service-title">
                        <i data-lucide="git-branch" class="service-icon"></i>
                        GitLab
                    </h3>
                </div>
                <p class="service-description">Complete DevOps platform with Git repositories, CI/CD pipelines, and issue tracking.</p>
            </a>
            <a href="/grafana/" class="service-card">
                <div class="status-dot status-active"></div>
                <div class="service-header">
                    <h3 class="service-title">
                        <i data-lucide="bar-chart" class="service-icon"></i>
                        Grafana
                    </h3>
                </div>
                <p class="service-description">Observability and monitoring platform with dashboards for metrics, logs, and traces.</p>
            </a>
            <a href="/element/" class="service-card">
                <div class="status-dot status-active"></div>
                <div class="service-header">
                    <h3 class="service-title">
                        <i data-lucide="message-circle" class="service-icon"></i>
                        Matrix/Element
                    </h3>
                </div>
                <p class="service-description">Secure, decentralized communication platform for team collaboration.</p>
            </a>
            <a href="/penpot/" class="service-card">
                <div class="status-dot status-active"></div>
                <div class="service-header">
                    <h3 class="service-title">
                        <i data-lucide="palette" class="service-icon"></i>
                        Penpot
                    </h3>
                </div>
                <p class="service-description">Open-source design and prototyping platform for UI/UX design collaboration.</p>
            </a>
        </div>
    </div>
    <script>lucide.createIcons();</script>
</body>
</html>
  '';

  systemd.services.setup-dashboard = {
    description = "Setup RAVE dashboard files";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Create web directory
      mkdir -p /var/www/html
      
      # Copy dashboard from /etc
      cp /etc/dashboard.html /var/www/html/dashboard.html
      
      # Set proper permissions
      chown -R nginx:nginx /var/www/html
      chmod 755 /var/www/html
      chmod 644 /var/www/html/dashboard.html
      
      echo "✅ Dashboard files setup completed"
    '';
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