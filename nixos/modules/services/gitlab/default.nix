# nixos/modules/services/gitlab/default.nix
# GitLab service configuration module - extracted from P3 production config
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.gitlab;
  oauthCfg = cfg.oauth;

  providerMeta = {
    google = {
      providerName = "google_oauth2";
      providerLabel = "Google";
      args = clientId: secretFile: {
        access_type = "offline";
        prompt = "select_account consent";
        client_id = clientId;
        scope = "email,profile";
      } // optionalAttrs (secretFile != null) {
        client_secret = { _secret = secretFile; };
      };
    };
    github = {
      providerName = "github";
      providerLabel = "GitHub";
      args = clientId: secretFile: {
        client_id = clientId;
        scope = "user:email";
      } // optionalAttrs (secretFile != null) {
        client_secret = { _secret = secretFile; };
      };
    };
  };

in
{
  imports = [
    ./nginx.nix
  ];

  options = {
    services.rave.gitlab = {
      enable = mkEnableOption "GitLab service with runner";
      
      host = mkOption {
        type = types.str;
        default = "rave.local";
        description = "GitLab hostname";
      };
      
      useSecrets = mkOption {
        type = types.bool;
        default = true;
        description = "Use sops-nix secrets instead of plain text (disable for development)";
      };
      
      runner = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable GitLab Runner with Docker + KVM support";
        };
        
        token = mkOption {
          type = types.str;
          default = "dummy-runner-token";
          description = "GitLab Runner registration token";
        };
      };

      oauth = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable external OAuth/OIDC provider for GitLab sign-in";
        };

        provider = mkOption {
          type = types.enum [ "google" "github" ];
          default = "google";
          description = ''OAuth/OIDC provider to delegate GitLab sign-in to. Supported values: "google" or "github".'';
        };

        clientId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "OAuth client ID registered with the external provider (non-secret).";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to a file containing the OAuth client secret (managed outside the Nix store, e.g. via sops).";
        };

        autoSignIn = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically redirect users to the configured OAuth provider on the GitLab sign-in page.";
        };

        autoLinkUsers = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically link OAuth identities to existing GitLab users created by the CLI.";
        };

        allowLocalSignin = mkOption {
          type = types.bool;
          default = false;
          description = ''Allow the traditional GitLab username/password form. When disabled, users are forced through OAuth (root admins can still reach the form via `?auto_sign_in=false`).'';
        };
      };
    };
  };
  
  config = mkIf config.services.rave.gitlab.enable {
    assertions = lib.optionals (cfg.oauth.enable) [
      {
        assertion = cfg.oauth.clientId != null;
        message = "services.rave.gitlab.oauth.clientId must be set when OAuth is enabled.";
      }
      {
        assertion = cfg.oauth.clientSecretFile != null;
        message = "services.rave.gitlab.oauth.clientSecretFile must be set when OAuth is enabled.";
      }
    ];

    # P3: GitLab Service Integration
    services.gitlab = {
      enable = true;
      host = config.services.rave.gitlab.host;
      port = 8080;  # Internal port, nginx proxies from 443
      
      # Database configuration
      databaseHost = "127.0.0.1";
      databaseName = "gitlab";
      databaseUsername = "gitlab";
      
      # Secrets configuration - use sops-nix in production
      initialRootPasswordFile = if config.services.rave.gitlab.useSecrets
        then config.sops.secrets."gitlab/root-password".path or "/run/secrets/gitlab-root-password"
        else pkgs.writeText "gitlab-root-password" "development-password";
        
      databasePasswordFile = if config.services.rave.gitlab.useSecrets
        then config.sops.secrets."gitlab/db-password".path or "/run/secrets/gitlab-db-password"
        else pkgs.writeText "gitlab-db-password" "gitlab-production-password";
        
      # All required secrets for GitLab
      secrets = {
        secretFile = if config.services.rave.gitlab.useSecrets
          then config.sops.secrets."gitlab/secret-key-base".path or "/run/secrets/gitlab-secret"
          else pkgs.writeText "gitlab-secret-key-base" "development-secret-key-base-dummy";
          
        otpFile = if config.services.rave.gitlab.useSecrets
          then config.sops.secrets."gitlab/otp-key-base".path or "/run/secrets/gitlab-otp"
          else pkgs.writeText "gitlab-otp-key-base" "development-otp-key-base-dummy";
          
        dbFile = if config.services.rave.gitlab.useSecrets
          then config.sops.secrets."gitlab/db-key-base".path or "/run/secrets/gitlab-db"
          else pkgs.writeText "gitlab-db-key-base" "development-db-key-base-dummy";
          
        jwsFile = if config.services.rave.gitlab.useSecrets
          then config.sops.secrets."gitlab/jws-key-base".path or "/run/secrets/gitlab-jws"
          else pkgs.writeText "jwt-signing-key" "development-jwt-signing-key-dummy";
        
        # Add missing Active Record secrets to prevent build warnings
        # Note: activeRecord secrets options removed in NixOS 24.11
        # Using database secret file instead for minimal configuration
      };
      
      # GitLab configuration from P3
      extraConfig =
        let
          oauthSettings =
            if cfg.oauth.enable then
              let
                meta = providerMeta.${cfg.oauth.provider};
                providerArgs = meta.args cfg.oauth.clientId cfg.oauth.clientSecretFile;
                providerEntry = {
                  name = meta.providerName;
                  label = meta.providerLabel;
                  args = providerArgs;
                };
              in {
                omniauth = {
                  enabled = true;
                  allow_single_sign_on = [ meta.providerName ];
                  block_auto_created_users = true;
                  auto_link_user = if cfg.oauth.autoLinkUsers then [ meta.providerName ] else [];
                  providers = [ providerEntry ];
                } // optionalAttrs cfg.oauth.autoSignIn {
                  auto_sign_in_with_provider = meta.providerName;
                };
                gitlab_signin_enabled = cfg.oauth.allowLocalSignin;
                password_authentication_enabled_for_web = cfg.oauth.allowLocalSignin;
                gitlab_signup_enabled = false;
              }
            else
              {};
        in {
        gitlab = {
          host = config.services.rave.gitlab.host;
          port = 443;
          https = true;
          
          # Enable relative URL root for subdirectory routing
          relative_url_root = "/gitlab";
          
          # Large file handling
          max_request_size = "10G";
          
          # Memory optimization
          workhorse = {
            memory_limit = "8G";
            cpu_limit = "50%";
          };
        };
        
        # Enable container registry
        registry = {
          enable = true;
          host = "registry.${config.services.rave.gitlab.host}";
          port = 5000;
        };
        
        # Artifact configuration
        artifacts = {
          enabled = true;
          path = "/var/lib/gitlab/artifacts";
          max_size = "10G";
          };
          
          # LFS configuration
          lfs = {
            enabled = true;
            storage_path = "/var/lib/gitlab/lfs";
          };

          redis = {
            host = "127.0.0.1";
            port = 6380;
          };
          
          # Prevent nginx conflicts - we handle nginx separately
          nginx.enable = false;
      } // oauthSettings;
    };

    # P3: GitLab Runner configuration with Docker + KVM support
    services.gitlab-runner = mkIf config.services.rave.gitlab.runner.enable {
      enable = true;
      
      # Resource limits from P3
      settings = {
        concurrent = 2;
        check_interval = 30;
        
        runners = [{
          name = "rave-docker-runner";
          url = "https://${config.services.rave.gitlab.host}/gitlab/";
          token = config.services.rave.gitlab.runner.token;
          executor = "docker";
          
          # Docker configuration for privileged access
          docker = {
            image = "nixos/nix:latest";
            privileged = true;
            disable_cache = false;
            volumes = [
              "/var/run/docker.sock:/var/run/docker.sock:rw"
              "/dev/kvm:/dev/kvm:rw"  # KVM access for sandbox VMs
            ];
            
            # Resource limits
            memory = "4G";
            cpus = "2";
            
            # Network configuration
            network_mode = "gitlab-sandbox";
          };
          
          # Build directory configuration
          builds_dir = "/tmp/gitlab-runner-builds";
          cache_dir = "/tmp/gitlab-runner-cache";
          
          # Environment variables
          environment = [
            "DOCKER_DRIVER=overlay2"
            "DOCKER_TLS_CERTDIR=/certs"
          ];
        }];
      };
    };

    # Required dependencies for GitLab
    services.postgresql = {
      enable = mkDefault true;
      ensureDatabases = mkDefault [ "gitlab" ];
      ensureUsers = mkDefault [{
        name = "gitlab";
        ensureDBOwnership = true;
      }];
      
      # Connection pooling from P3
      settings = {
        max_connections = mkDefault 100;
        shared_buffers = mkDefault "256MB";
        effective_cache_size = mkDefault "1GB";
        maintenance_work_mem = mkDefault "64MB";
        checkpoint_completion_target = mkDefault 0.9;
        wal_buffers = mkDefault "16MB";
        default_statistics_target = mkDefault 100;
        random_page_cost = mkDefault 1.1;
        effective_io_concurrency = mkDefault 200;
      };
    };

    services.redis.servers.gitlab = {
      enable = true;
      port = 6380;
      
      # Memory configuration
      settings = {
        maxmemory = "512MB";
        maxmemory-policy = "allkeys-lru";
      };
    };

    # Enable Docker for GitLab Runner with enhanced configuration
    virtualisation.docker = {
      enable = true;
      
      # Enhanced Docker daemon settings for sandbox support
      daemon.settings = {
        data-root = "/var/lib/docker";
        storage-driver = "overlay2";
        
        # Resource management
        default-ulimits = {
          memlock = {
            Name = "memlock";
            Hard = 67108864;  # 64MB
            Soft = 67108864;
          };
          nofile = {
            Name = "nofile";
            Hard = 65536;
            Soft = 65536;
          };
        };
        
        # Networking for sandbox isolation
        bridge = "docker0";
        default-address-pools = [
          {
            base = "172.17.0.0/16";
            size = 24;
          }
          {
            base = "172.18.0.0/16";
            size = 24;
          }
        ];
      };
    };
    
    # Enhanced libvirtd for VM support
    virtualisation.libvirtd = {
      enable = true;
      qemu.ovmf.packages = [ pkgs.OVMF.fd ];
      qemu.runAsRoot = false;
      qemu.swtpm.enable = true;
      allowedBridges = [ "virbr0" "docker0" "gitlab-sandbox" ];
    };
    
    # GitLab Runner user configuration
    users.groups.gitlab-runner = {};
    users.users.gitlab-runner = {
      isSystemUser = true;
      group = "gitlab-runner";
      extraGroups = [ "docker" "kvm" "libvirtd" ];
    };
    
    # Enhanced KVM access
    users.groups.kvm.members = [ "gitlab-runner" ];

    # Firewall configuration for GitLab services
    networking.firewall.allowedTCPPorts = [ 
      8080  # GitLab
      5000  # Container registry
    ];
    
    # Service resource limits from P3
    systemd.services.gitlab.serviceConfig = {
      MemoryMax = "8G";
      CPUQuota = "50%";
      OOMScoreAdjust = "50";
    };
    
    # Enable Rails relative URL root for subdirectory routing
    systemd.services.gitlab.environment = {
      RAILS_RELATIVE_URL_ROOT = "/gitlab";
    };
    
    systemd.services.gitlab-runner.serviceConfig = mkIf config.services.rave.gitlab.runner.enable {
      MemoryMax = "4G";
      CPUQuota = "25%";
      OOMScoreAdjust = "100";
    };
  };
}
