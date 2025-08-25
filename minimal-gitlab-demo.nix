# Minimal GitLab Demo Configuration - Fast startup, HTTP only
# Designed for immediate demo purposes with <2 minute startup time
{ config, pkgs, lib, ... }:

{
  # Basic system configuration
  system.stateVersion = "24.11";
  
  # Network configuration
  networking = {
    hostName = "gitlab-demo";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 8080 ];
    };
    # Use Google DNS for reliability
    nameservers = [ "8.8.8.8" "8.8.4.4" ];
  };

  # Enable SSH for debugging
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Set root password for easy access
  users.users.root.password = "demo";

  # Minimal GitLab CE configuration
  services.gitlab = {
    enable = true;
    
    # Use HTTP only for speed
    https = false;
    port = 8080;
    host = "localhost";
    
    # Minimal resource configuration
    databasePasswordFile = pkgs.writeText "db-password" "gitlab_demo_password";
    initialRootPasswordFile = pkgs.writeText "root-password" "gitlab_demo_root";
    
    # Disable heavy features for fast startup
    registry.enable = false;
    pages.enable = false;
    
    # Simple configuration
    extraConfig = {
      gitlab = {
        host = "localhost";
        port = 8080;
        https = false;
        default_projects_limit = 10;
      };
      
      # Disable external dependencies
      omniauth.enabled = false;
      
      # Minimal email configuration (local only)
      gitlab_email_from = "gitlab@localhost";
      gitlab_email_display_name = "GitLab Demo";
      gitlab_email_reply_to = "noreply@localhost";
      
      # Disable features that might hang
      sidekiq = {
        concurrency = 5;  # Reduce from default 25
      };
      
      # Simple logging
      production = {
        log_level = "info";
      };
    };
  };

  # Simple nginx proxy (no SSL complexity)
  services.nginx = {
    enable = true;
    
    virtualHosts."localhost" = {
      listen = [{
        addr = "0.0.0.0";
        port = 80;
        ssl = false;
      }];
      
      locations = {
        "/" = {
          return = "302 http://localhost:8080/";
        };
        
        "/health" = {
          return = "200 'GitLab Demo Ready'";
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
      };
    };
  };

  # PostgreSQL with minimal configuration
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    
    # Minimal performance tuning for fast startup
    settings = {
      max_connections = 100;
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      maintenance_work_mem = "64MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "16MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
    };
    
    # Ensure GitLab database exists
    ensureDatabases = [ "gitlabhq_production" ];
    ensureUsers = [
      {
        name = "gitlab";
        ensureDBOwnership = true;
      }
    ];
  };

  # Redis with minimal configuration
  services.redis.servers.gitlab = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    # Reduce memory usage
    settings = {
      maxmemory = "256mb";
      maxmemory-policy = "allkeys-lru";
    };
  };

  # Ensure services start in correct order
  systemd.services = {
    gitlab-config = {
      after = [ "postgresql.service" "redis-gitlab.service" ];
      requires = [ "postgresql.service" "redis-gitlab.service" ];
    };
    
    gitlab = {
      after = [ "gitlab-config.service" ];
      requires = [ "gitlab-config.service" ];
    };
    
    nginx = {
      after = [ "gitlab.service" ];
      wants = [ "gitlab.service" ];
    };
  };

  # System optimization for fast boot
  boot.tmp.cleanOnBoot = true;
  
  # Minimal environment
  environment.systemPackages = with pkgs; [
    curl
    htop
    git
  ];
  
  # Reduce systemd timeout for faster failure detection
  systemd.extraConfig = ''
    DefaultTimeoutStartSec=90s
    DefaultTimeoutStopSec=30s
  '';
}