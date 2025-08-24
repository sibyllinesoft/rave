# GitLab Service Configuration for RAVE
# Implements GitLab CE with Docker runner and KVM support
{ config, pkgs, lib, ... }:

{
  # P3.1: GitLab CE service configuration
  services.gitlab = {
    enable = true;
    
    # Host configuration
    host = "rave.local";
    port = 443;
    https = true;
    
    # Initial root password from secrets (conditional on sops configuration)
    initialRootPasswordFile = if config.sops.secrets ? "gitlab/root-password" 
                              then config.sops.secrets."gitlab/root-password".path
                              else null;
    
    # GitLab configuration
    extraConfig = {
      # GitLab Rails configuration
      gitlab = {
        host = "rave.local";
        port = 443;
        https = true;
        relative_url_root = "/gitlab";
        
        # Email configuration (disabled for local development)
        email_enabled = false;
        
        # Default project features
        default_projects_features = {
          issues = true;
          merge_requests = true;
          wiki = true;
          snippets = true;
          builds = true;
          container_registry = false;  # Disabled to save resources
        };
        
        # Repository storage configuration
        repository_storage_path = "/var/lib/gitlab/repositories";
        
        # Backup configuration
        backup = {
          path = "/var/lib/gitlab/backups";
          keep_time = 604800;  # 7 days
        };
      };
      
      # GitLab Shell configuration
      gitlab_shell = {
        ssh_port = 22;
      };
      
      # Workhorse configuration for large file uploads
      gitlab_workhorse = {
        # Support large artifacts and LFS files
        client_max_body_size = "10g";
        proxy_read_timeout = 300;
        proxy_connect_timeout = 300;
        proxy_send_timeout = 300;
      };
      
      # GitLab CI configuration
      gitlab_ci = {
        # Build artifacts configuration
        builds_path = "/var/lib/gitlab/builds";
        artifacts = {
          enabled = true;
          path = "/var/lib/gitlab/artifacts";
          max_size = "1gb";
          expire_in = "7d";
        };
        
        # GitLab Pages (disabled to save resources)
        pages = {
          enabled = false;
        };
      };
      
      # Monitoring configuration
      monitoring = {
        # Enable Prometheus metrics endpoint
        prometheus = {
          enabled = true;
          address = "localhost";
          port = 9168;
        };
      };
      
      # Security configuration
      omniauth = {
        enabled = false;  # Will be configured in P4 for OIDC
        block_auto_created_users = false;
      };
      
      # LDAP configuration (disabled, will use OIDC in P4)
      ldap = {
        enabled = false;
      };
    };
    
    # Database configuration will use PostgreSQL service defaults
    # Database setup handled by NixOS GitLab module automatically
    
    # Secrets configuration (conditional on sops)
    secrets = lib.mkIf (config.sops.secrets ? "gitlab/secret-key-base") {
      secretFile = config.sops.secrets."gitlab/secret-key-base".path;
      dbFile = if config.sops.secrets ? "gitlab/db-password"
               then config.sops.secrets."gitlab/db-password".path
               else null;
    };
    
    # User and group configuration
    user = "gitlab";
    group = "gitlab";
    
    # State directory
    statePath = "/var/lib/gitlab";
    
    # Log directory  
    logDir = "/var/log/gitlab";
  };
  
  # P3.2: PostgreSQL database configuration for GitLab
  services.postgresql = lib.mkAfter {
    ensureDatabases = [ "gitlab" ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
        ensureClauses = {
          createdb = true;
          createrole = false;
          login = true;
          replication = false;
          superuser = false;
        };
      }
    ];
    
    # PostgreSQL configuration optimized for GitLab
    extraConfig = ''
      # Performance tuning for GitLab workload
      shared_buffers = 256MB
      effective_cache_size = 1GB
      maintenance_work_mem = 64MB
      checkpoint_completion_target = 0.9
      wal_buffers = 16MB
      default_statistics_target = 100
      random_page_cost = 1.1
      effective_io_concurrency = 200
      
      # Connection and logging
      max_connections = 200
      log_min_duration_statement = 1000
      log_statement = 'none'
      log_line_prefix = '%m [%p] %q%u@%d '
    '';
  };
  
  # P3.3: GitLab Runner service configuration
  services.gitlab-runner = {
    enable = true;
    
    # Runner configuration
    settings = {
      concurrent = 4;  # Number of concurrent jobs
      check_interval = 10;  # Check for jobs every 10 seconds
      
      # Session server for interactive debugging (disabled for security)
      session_server = {
        listen_address = "0.0.0.0:8093";
        advertise_address = "localhost:8093";  
        session_timeout = 1800;
      };
    };
    
    # Register runners
    services = {
      # Main Docker runner with KVM support
      default-docker = lib.mkIf (config.sops.secrets ? "gitlab/runner-token") {
        registrationConfigFile = config.sops.secrets."gitlab/runner-token".path;
        
        # Runner configuration
        description = "RAVE Docker Runner with KVM";
        tags = [ "docker" "kvm" "rave" "vm" ];
        
        # Docker executor configuration
        executor = "docker";
        dockerConfig = {
          image = "alpine:latest";
          privileged = true;  # Required for KVM access
          
          # Volume mounts for KVM and Nix
          volumes = [
            "/dev/kvm:/dev/kvm"  # KVM device access
            "/nix/store:/nix/store:ro"  # Nix store access
            "/var/cache/gitlab-runner:/cache"  # Build cache
          ];
          
          # Network configuration
          network_mode = "bridge";
          
          # Resource limits
          cpus = "2.0";
          memory = "4g";
          memory_swap = "4g";
          
          # Security configuration  
          security_opt = [
            "apparmor:unconfined"  # Required for some VM operations
          ];
          
          # Additional capabilities for VM management
          cap_add = [
            "SYS_ADMIN"  # Required for KVM
            "NET_ADMIN"  # Network management for VMs
          ];
          
          # Shared data configuration
          shm_size = "1g";
          
          # Docker-in-Docker configuration
          docker_in_docker = true;
        };
        
        # Build directory configuration
        buildsDir = "/var/lib/gitlab-runner/builds";
        cacheDir = "/var/cache/gitlab-runner";
        
        # Request concurrency
        requestConcurrency = 1;
        
        # Runner limits
        limit = 2;  # Maximum concurrent jobs for this runner
      };
    };
  };
  
  # P3.4: Enable Docker for GitLab Runner
  virtualisation.docker = {
    enable = true;
    
    # Docker daemon configuration
    daemon.settings = {
      # Storage configuration
      storage-driver = "overlay2";
      
      # Performance and resource limits
      default-runtime = "runc";
      max-concurrent-downloads = 3;
      max-concurrent-uploads = 5;
      
      # Security configuration
      userland-proxy = false;
      live-restore = true;
      
      # Logging configuration
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
      
      # Registry configuration  
      insecure-registries = [];
      registry-mirrors = [];
    };
    
    # Enable rootless mode for improved security (when not using privileged)
    rootless = {
      enable = false;  # Disabled because we need privileged access for KVM
      setSocketVariable = false;
    };
    
    # Docker package
    package = pkgs.docker;
  };
  
  # P3.5: Add gitlab-runner user to docker and virtualization groups
  users.users.gitlab-runner = {
    extraGroups = [ "docker" "kvm" "libvirtd" ];
  };
  
  # P3.6: Enable KVM for nested virtualization support
  virtualisation.libvirtd = {
    enable = true;
    qemu.ovmf.enable = true;
    qemu.swtpm.enable = true;
  };
  
  # P3.7: SystemD service dependencies and resource limits
  systemd.services.gitlab = {
    after = [ "postgresql.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "postgresql.service" ];
    
    # Resource limits for GitLab
    serviceConfig = {
      MemoryMax = "8G";
      CPUQuota = "50%";
      TasksMax = 4096;
      
      # Security hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/gitlab" "/var/log/gitlab" ];
      
      # Process limits
      LimitNOFILE = 65535;
      LimitNPROC = 65535;
    };
    
    # Environment variables for GitLab
    environment = {
      RAILS_ENV = "production";
      NODE_ENV = "production";
      GITLAB_ROOT_URL = "https://rave.local:3002/gitlab";
    };
  };
  
  systemd.services.gitlab-runner = {
    after = [ "docker.service" "gitlab.service" ];
    wants = [ "docker.service" ];
    requires = [ "docker.service" ];
    
    # Resource limits for GitLab Runner
    serviceConfig = {
      MemoryMax = "4G";
      CPUQuota = "25%";
      TasksMax = 2048;
      
      # Security configuration
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ 
        "/var/lib/gitlab-runner" 
        "/var/cache/gitlab-runner" 
        "/var/log/gitlab-runner"
        "/dev/kvm"  # KVM device access
      ];
      
      # Process limits
      LimitNOFILE = 32768;
      LimitNPROC = 32768;
    };
  };
  
  # P3.8: Backup scripts for GitLab
  systemd.services.gitlab-backup = {
    description = "GitLab backup service";
    serviceConfig = {
      Type = "oneshot";
      User = "gitlab";
      Group = "gitlab";
      ExecStart = "${pkgs.sudo}/bin/sudo -u gitlab /run/current-system/sw/bin/gitlab-backup create";
      
      # Resource limits for backup process
      MemoryMax = "2G";
      CPUQuota = "25%";
    };
  };
  
  systemd.timers.gitlab-backup = {
    description = "GitLab daily backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      AccuracySec = "1h";
    };
  };
  
  # P3.9: Log rotation for GitLab services
  services.logrotate = {
    enable = true;
    extraConfig = ''
      /var/log/gitlab/*.log {
        daily
        missingok
        rotate 7
        compress
        delaycompress
        notifempty
        copytruncate
        su gitlab gitlab
      }
      
      /var/log/gitlab-runner/*.log {
        daily
        missingok
        rotate 7
        compress  
        delaycompress
        notifempty
        copytruncate
        su gitlab-runner gitlab-runner
      }
    '';
  };
  
  # P3.10: Additional packages needed for GitLab CI/CD
  environment.systemPackages = with pkgs; [
    # Git and version control
    git
    git-lfs
    
    # Container tools
    docker
    docker-compose
    
    # Build tools
    gnumake
    gcc
    
    # Virtualization tools for KVM access
    qemu
    libvirt
    virt-manager
    
    # Monitoring tools
    htop
    iotop
    
    # Network tools for debugging
    netcat
    curl
    wget
  ];
  
  # P3.11: Firewall configuration for GitLab
  networking.firewall = lib.mkMerge [
    {
      # GitLab-specific ports (internal access only)
      allowedTCPPorts = [ 9168 ];  # GitLab metrics endpoint
      
      # Docker bridge network
      trustedInterfaces = [ "docker0" ];
      
      # Allow Docker containers to communicate
      extraCommands = ''
        # Allow Docker bridge network
        iptables -A INPUT -i docker0 -j ACCEPT
        iptables -A FORWARD -i docker0 -o docker0 -j ACCEPT
      '';
    }
  ];
}