# nixos/configs/complete-production.nix
# Complete, consolidated NixOS VM configuration with ALL services pre-configured
{ config, pkgs, lib, ... }:

let
  # Build-time port configuration (can be overridden via flake)
  baseHttpsPort = toString config.services.rave.ports.https;
  
  useSecrets = config.services.rave.gitlab.useSecrets;
  gitlabDbPasswordFile = if useSecrets
    then "/run/secrets/gitlab/db-password"
    else pkgs.writeText "gitlab-db-password" "gitlab-production-password";
  googleOauthClientId = "729118765955-7l2hgo3nrjaiol363cp8avf3m97shjo8.apps.googleusercontent.com";
  gitlabExternalUrl = "https://localhost:${baseHttpsPort}/gitlab";
  gitlabInternalHttpsUrl = "https://localhost:${baseHttpsPort}/gitlab";
  gitlabInternalHttpUrl = "https://localhost:${baseHttpsPort}/gitlab";
  gitlabPackage = config.services.gitlab.packages.gitlab;
  mattermostPublicUrl = "https://localhost:${baseHttpsPort}/mattermost";
  penpotPublicUrl = "https://localhost:${baseHttpsPort}/penpot";
  mattermostPath =
    let
      matchResult = builtins.match "https://[^/]+(.*)" mattermostPublicUrl;
    in
    if matchResult == null || matchResult == [] then "" else builtins.head matchResult;
  mattermostTeamName = "rave";
  mattermostTeamDisplayName = "RAVE";
  mattermostBuildsChannelName = "builds";
  mattermostBuildsChannelDisplayName = "Builds";
  mattermostLoginPath =
    if mattermostPath == "" then "/oauth/gitlab/login" else "${mattermostPath}/oauth/gitlab/login";
  mattermostLoginUrl = "${mattermostPublicUrl}/oauth/gitlab/login";
  mattermostBrandHtml = "Use the GitLab button below to sign in. If it does not appear, open ${mattermostLoginPath} manually.";
  mattermostGitlabClientId = "41622b028bfb499bcadfcdf42a8618734a6cebc901aa8f77661bceeebc7aabba";
  mattermostGitlabClientSecretFile = if useSecrets
    then "/run/secrets/gitlab/oauth-mattermost-client-secret"
    else null;
  mattermostGitlabSecretFallback = "gloas-18f9021e792192dda9f50be4df02cee925db5d36a09bf6867a33762fb874d539";
  mattermostAdminUsernameFile = if useSecrets
    then "/run/secrets/mattermost/admin-username"
    else pkgs.writeText "mattermost-admin-username" "admin";
  mattermostAdminPasswordFile = if useSecrets
    then "/run/secrets/mattermost/admin-password"
    else pkgs.writeText "mattermost-admin-password" "Password123!";
  mattermostAdminEmailFile = if useSecrets
    then "/run/secrets/mattermost/admin-email"
    else pkgs.writeText "mattermost-admin-email" "admin@example.com";
  gitlabApiTokenFile = if useSecrets
    then "/run/secrets/gitlab/api-token"
    else pkgs.writeText "gitlab-api-token" "development-token";
  penpotPublicUrl = "https://localhost:${baseHttpsPort}/penpot";
  outlinePublicUrl = "https://localhost:${baseHttpsPort}/outline";
  outlineDockerImage = "outlinewiki/outline:latest";
  outlineHostPort = 8310;
  outlineDbPassword = "outline-production-password";
  outlineSecretKey = "outline-secret-key-4c8d8a4c9f004aa4868b9e19767b2e8e";
  outlineUtilsSecret = "outline-utils-secret-d4c2b6a5a9c2474f8fb3b77d0b0fbd89";
  outlineRedisDb = 5;
  n8nPublicUrl = "https://localhost:${baseHttpsPort}/n8n";
  n8nDockerImage = "n8nio/n8n:latest";
  n8nHostPort = 5678;
  n8nDbPassword = "n8n-production-password";
  n8nEncryptionKey = "n8n-encryption-key-2d01b6dba90441e8a6f7ec2af3327ef2";
  n8nBasicAuthPassword = "n8n-basic-admin-password";
  n8nBasePath = "/n8n";
  penpotCardHtml = lib.optionalString config.services.rave.penpot.enable ''
                          <a href="/penpot/" class="service-card">
                              <div class="service-title">🎨 Penpot</div>
                              <div class="service-desc">Design collaboration (GitLab OIDC)</div>
                              <div class="service-url">${penpotPublicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';
  outlineCardHtml = lib.optionalString config.services.rave.outline.enable ''
                          <a href="/outline/" class="service-card">
                              <div class="service-title">📚 Outline</div>
                              <div class="service-desc">Knowledge base and documentation hub</div>
                              <div class="service-url">${outlinePublicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';
  n8nCardHtml = lib.optionalString config.services.rave.n8n.enable ''
                          <a href="/n8n/" class="service-card">
                              <div class="service-title">🧠 n8n</div>
                              <div class="service-desc">Automation workflows & integrations</div>
                              <div class="service-url">${n8nPublicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';
  penpotWelcomePrimary = lib.optionalString config.services.rave.penpot.enable ''
echo "  Penpot       : ${penpotPublicUrl}/"
'';
  outlineWelcomePrimary = lib.optionalString config.services.rave.outline.enable ''
echo "  Outline      : ${outlinePublicUrl}/"
'';
  n8nWelcomePrimary = lib.optionalString config.services.rave.n8n.enable ''
echo "  n8n          : ${n8nPublicUrl}/"
'';
  penpotWelcomeFancy = lib.optionalString config.services.rave.penpot.enable ''
echo "   🎨 Penpot:      ${penpotPublicUrl}/"
'';
  outlineWelcomeFancy = lib.optionalString config.services.rave.outline.enable ''
echo "   📚 Outline:     ${outlinePublicUrl}/"
'';
  n8nWelcomeFancy = lib.optionalString config.services.rave.n8n.enable ''
echo "   🧠 n8n:         ${n8nPublicUrl}/"
'';
  welcomeStatusServices = lib.concatStringsSep " " (
    [
      "postgresql"
      "redis-main"
      "nats"
      "prometheus"
      "grafana"
      "gitlab"
      "mattermost"
      "rave-chat-bridge"
      "nginx"
    ]
    ++ lib.optionals config.services.rave.penpot.enable [ "penpot-backend" "penpot-frontend" "penpot-exporter" ]
    ++ lib.optionals config.services.rave.outline.enable [ "outline" ]
    ++ lib.optionals config.services.rave.n8n.enable [ "n8n" ]
  );

in
{
  services.rave.outline = {
    enable = true;
    publicUrl = outlinePublicUrl;
    dockerImage = outlineDockerImage;
    hostPort = outlineHostPort;
    dbPassword = outlineDbPassword;
    secretKey = outlineSecretKey;
    utilsSecret = outlineUtilsSecret;
    redisDb = outlineRedisDb;
  };

  services.rave.n8n = {
    enable = true;
    publicUrl = n8nPublicUrl;
    dockerImage = n8nDockerImage;
    hostPort = n8nHostPort;
    dbPassword = n8nDbPassword;
    encryptionKey = n8nEncryptionKey;
    basicAuthPassword = n8nBasicAuthPassword;
    basePath = n8nBasePath;
  };

  services.rave.penpot = {
    enable = true;
    host = "localhost";
    publicUrl = penpotPublicUrl;
    database.password = "penpot-production-password";
    redis.port = 6380;
    oidc = {
      enable = true;
      gitlabUrl = gitlabExternalUrl;
      clientId = "penpot";
      clientSecret = "penpot-oidc-secret";
    };
  };

  services.rave.monitoring = {
    enable = true;
    retentionTime = "3d";
    grafana = {
      domain = "localhost";
      publicUrl = "https://localhost:${baseHttpsPort}/grafana/";
      adminUser = "admin";
      adminPassword = "admin123";
      secretKey = "grafana-production-secret-key";
      database = {
        host = "localhost:5432";
        name = "grafana";
        user = "grafana";
        password = "grafana-production-password";
      };
    };
    exporters.postgres.dataSourceName = "postgresql://prometheus:prometheus_pass@localhost:5432/postgres?sslmode=disable";
  };

  services.rave.mattermost = {
    enable = true;
    siteName = "RAVE Mattermost";
    publicUrl = mattermostPublicUrl;
    internalBaseUrl = "http://127.0.0.1:8065";
    brandHtml = mattermostBrandHtml;
    envFile = if useSecrets then "/run/secrets/mattermost/env" else null;
    databaseDatasource = "postgres://mattermost:mmpgsecret@localhost:5432/mattermost?sslmode=disable&connect_timeout=10";
    admin = {
      usernameFile = mattermostAdminUsernameFile;
      passwordFile = mattermostAdminPasswordFile;
      emailFile = mattermostAdminEmailFile;
    };
    team = {
      name = mattermostTeamName;
      displayName = mattermostTeamDisplayName;
      buildsChannelName = mattermostBuildsChannelName;
      buildsChannelDisplayName = mattermostBuildsChannelDisplayName;
      hookDisplayName = "GitLab CI Builds";
      hookUsername = "gitlab-ci";
    };
    gitlab = {
      baseUrl = gitlabExternalUrl;
      internalUrl = gitlabInternalHttpUrl;
      apiBaseUrl = "${gitlabExternalUrl}/api/v4";
      clientId = mattermostGitlabClientId;
      clientSecretFile = mattermostGitlabClientSecretFile;
      clientSecretFallback = mattermostGitlabSecretFallback;
      apiTokenFile = gitlabApiTokenFile;
      applicationName = "RAVE Mattermost";
    };
    callsPlugin = {
      enable = true;
      version = "v1.0.1";
      stunUrl = "stun:localhost:3478";
      turnUrl = "turn:localhost:3478";
      turnUsername = "mattermost";
      turnCredential = "rave-coturn-development-secret-2025";
      rtcServerPort = config.services.rave.ports.https;
      maxParticipants = 8;
      needsHttps = false;
      allowEnableCalls = true;
      enableTranscriptions = false;
      enableRecordings = false;
    };
    ciBridge = {
      enable = true;
      verifyMattermostTls = false;
      verifyGitlabTls = false;
    };
  };

  # Option definitions for RAVE configuration
  options.services.rave.ports = {
    https = lib.mkOption {
      type = lib.types.int;
      default = 8443;
      description = "HTTPS port for the RAVE VM services";
    };
  };

  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix

    # Service modules
    ../modules/services/gitlab/default.nix
    ../modules/services/monitoring/default.nix
    ../modules/services/mattermost/default.nix
    ../modules/services/outline/default.nix
    ../modules/services/n8n/default.nix

    # Security modules
    # ../modules/security/certificates.nix  # DISABLED: Using inline certificate generation instead
    ../modules/security/hardening.nix
  ];

# SOPS configuration - DISABLE built-in activation to prevent conflicts
# Only use our custom sops-init service which runs after AGE key is available
sops = lib.mkIf false {
  defaultSopsFile = ../../config/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
  validateSopsFiles = false;
  secrets = {
    "mattermost/env" = {
      owner = "mattermost";
      group = "mattermost";
      mode = "0600";
      path = "/run/secrets/mattermost/env";
      restartUnits = [ "mattermost.service" ];
    };
    "mattermost/admin-username" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/mattermost/admin-username";
      restartUnits = [ "mattermost.service" "gitlab-mattermost-ci-bridge.service" ];
    };
    "mattermost/admin-email" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/mattermost/admin-email";
      restartUnits = [ "mattermost.service" "gitlab-mattermost-ci-bridge.service" ];
    };
    "mattermost/admin-password" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/mattermost/admin-password";
      restartUnits = [ "mattermost.service" "gitlab-mattermost-ci-bridge.service" ];
    };
    "oidc/chat-control-client-secret" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/oidc/chat-control-client-secret";
    };
    "gitlab/api-token" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/gitlab/api-token";
      restartUnits = [ "gitlab-mattermost-ci-bridge.service" ];
    };
    "gitlab/root-password" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/root-password";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/db-password" = {
      owner = "postgres";
      group = "gitlab";
      mode = "0440";
      path = "/run/secrets/gitlab/db-password";
      restartUnits = [ "postgresql.service" ];
    };
    "gitlab/secret-key-base" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/secret-key-base";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/db-key-base" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/db-key-base";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/otp-key-base" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/otp-key-base";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/jws-key-base" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/jws-key-base";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/oauth-provider-client-secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/oauth-provider-client-secret";
      restartUnits = [ "gitlab.service" ];
    };
    "gitlab/oauth-mattermost-client-secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      path = "/run/secrets/gitlab/oauth-mattermost-client-secret";
      restartUnits = [ "gitlab.service" "gitlab-mattermost-oauth.service" ];
    };
  };
};

  # Mount SOPS keys filesystem (for AGE key access via virtfs)
  systemd.services.mount-sops-keys = lib.mkIf config.services.rave.gitlab.useSecrets {
    description = "Mount SOPS keys filesystem for AGE key access";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [ "install-age-key.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
    };
    script = ''
      set -euo pipefail
      
      # Create mount point
      mkdir -p /host-keys
      
      # Try to mount virtfs with detailed error reporting
      echo "Attempting to mount virtfs with tag 'sops-keys'..."
      if mount -t 9p -o trans=virtio,version=9p2000.L,rw sops-keys /host-keys; then
        echo "SOPS keys filesystem mounted successfully at /host-keys"
        ls -la /host-keys/
        if [ -f /host-keys/keys.txt ]; then
          echo "AGE keys file found in mounted filesystem"
        else
          echo "WARNING: AGE keys file not found in mounted filesystem"
        fi
      else
        echo "Failed to mount virtfs - this may be development mode"
        echo "Available virtio devices:"
        ls -la /sys/bus/virtio/devices/ || echo "No virtio devices found"
        echo "Supported filesystems:"
        grep 9p /proc/filesystems || echo "9p filesystem not supported"
      fi
    '';
  };

  # Install AGE key from host system for E2E testing
  systemd.services.install-age-key = lib.mkIf config.services.rave.gitlab.useSecrets {
    description = "Install AGE key from host system";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [ "sops-init.service" "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
    };
    script = ''
      set -euo pipefail
      
      # Create SOPS directory
      mkdir -p /var/lib/sops-nix
      
      # Create mount point for virtfs
      mkdir -p /host-keys
      
      # Try to mount virtfs first (preferred method)
      echo "Attempting to mount virtfs for AGE keys..."
      if mount -t 9p -o trans=virtio,version=9p2000.L,rw sops-keys /host-keys 2>/dev/null; then
        echo "✅ virtfs mounted successfully"
        if [ -f /host-keys/keys.txt ]; then
          echo "Installing AGE key from virtfs-mounted host directory (canonical)"
          cp /host-keys/keys.txt /var/lib/sops-nix/key.txt
          chmod 600 /var/lib/sops-nix/key.txt
          echo "AGE key installed successfully from virtfs"
          exit 0
        else
          echo "⚠️ virtfs mounted but keys.txt not found"
          umount /host-keys 2>/dev/null || true
        fi
      else
        echo "ℹ️ virtfs not available, trying fallback methods..."
      fi
      
      # Fallback to environment variable
      if [ -n "''${SOPS_AGE_KEY:-}" ]; then
        echo "Installing AGE key from environment variable (fallback)"
        echo "$SOPS_AGE_KEY" > /var/lib/sops-nix/key.txt
        chmod 600 /var/lib/sops-nix/key.txt
        echo "AGE key installed successfully from environment"
        exit 0
      fi
      
      # No AGE key available
      echo "⚠️ No AGE key found - VM will run in development mode"
      echo "To enable production mode:"
      echo "  1. Use RAVE CLI with AGE keys (preferred - auto virtfs)"
      echo "  2. Set SOPS_AGE_KEY environment variable (fallback)"
      exit 0
    '';
  };

  # SOPS initialization service to ensure secrets are available
  systemd.services.sops-init = lib.mkIf config.services.rave.gitlab.useSecrets {
    description = "Initialize SOPS secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "install-age-key.service" ];
    before = [ "gitlab-db-password.service" "gitlab.service" "mattermost.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
    };
    script = ''
      set -euo pipefail
      
      # Check if AGE key exists
      if [ ! -f /var/lib/sops-nix/key.txt ]; then
        echo "AGE key missing at /var/lib/sops-nix/key.txt"
        exit 1
      fi
      
      # Check if secrets file exists
      if [ ! -f ${../../config/secrets.yaml} ]; then
        echo "SOPS secrets file missing"
        exit 1
      fi
      
      # Export AGE key for SOPS
      export SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt
      
      # Create secrets directories with proper permissions
      mkdir -p /run/secrets/gitlab /run/secrets/mattermost /run/secrets/oidc
      
      # Helper function to extract and write secret
      extract_secret() {
        local key="$1"
        local path="$2"
        local owner="$3"
        local group="$4"
        local mode="$5"
        
        echo "Extracting secret: $key -> $path"
        ${pkgs.sops}/bin/sops -d --extract "[\"$key\"]" ${../../config/secrets.yaml} > "$path"
        chown "$owner:$group" "$path"
        chmod "$mode" "$path"
      }
      
      # Extract all the secrets that were previously defined in SOPS configuration
      # NOTE: Using nested YAML structure from secrets.yaml file
      
      # Mattermost secrets
      extract_secret "mattermost\"][\"env" "/run/secrets/mattermost/env" "mattermost" "mattermost" "0600"
      extract_secret "mattermost\"][\"admin-username" "/run/secrets/mattermost/admin-username" "root" "root" "0400"
      extract_secret "mattermost\"][\"admin-email" "/run/secrets/mattermost/admin-email" "root" "root" "0400"
      extract_secret "mattermost\"][\"admin-password" "/run/secrets/mattermost/admin-password" "root" "root" "0400"
      
      # OIDC secrets
      extract_secret "oidc\"][\"chat-control-client-secret" "/run/secrets/oidc/chat-control-client-secret" "root" "root" "0400"
      
      # GitLab secrets
      extract_secret "gitlab\"][\"api-token" "/run/secrets/gitlab/api-token" "root" "root" "0400"
      extract_secret "gitlab\"][\"root-password" "/run/secrets/gitlab/root-password" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"db-password" "/run/secrets/gitlab/db-password" "postgres" "gitlab" "0440"
      extract_secret "gitlab\"][\"secret-key-base" "/run/secrets/gitlab/secret-key-base" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"db-key-base" "/run/secrets/gitlab/db-key-base" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"otp-key-base" "/run/secrets/gitlab/otp-key-base" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"jws-key-base" "/run/secrets/gitlab/jws-key-base" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"oauth-provider-client-secret" "/run/secrets/gitlab/oauth-provider-client-secret" "gitlab" "gitlab" "0400"
      extract_secret "gitlab\"][\"oauth-mattermost-client-secret" "/run/secrets/gitlab/oauth-mattermost-client-secret" "gitlab" "gitlab" "0400"
      
      echo "SOPS secrets extracted successfully"
    '';
  };


  # ===== SYSTEM FOUNDATION =====
  
  # Boot configuration
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" "vmw_pvscsi" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" "9p" "9pnet" "9pnet_virtio" ];
  boot.extraModulePackages = [ ];

  # System
  system.stateVersion = "24.11";
  networking.hostName = "rave-complete";
  system.autoUpgrade.enable = lib.mkForce false;

  # Virtual filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # SOPS keys mount for AGE key (when available via virtfs)
  fileSystems."/host-keys" = {
    device = "sops-keys";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "rw" "noauto" "nofail" ];
  };

  # User configuration
  users.users.root = {
    hashedPassword = "$6$F0X5acx/cry2HLWf$lewtPoE8PdND7qVCw6FjphVszsDGluaqQUsFhhB2sRVoydZ0rfsQ8GKB6vuEh/dCiXDdLHlaM8RGx9U/khYPD0";  # "debug123"
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAmBj5iZFV2inopUhgTX++Wue6g5ePry+DiE3/XLxe2 rave-vm-access"
    ];
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce true;  # Override security hardening
      PermitRootLogin = lib.mkForce "yes";       # Override networking module
      X11Forwarding = false;
    };
  };

  # ===== CORE SERVICES =====

  # PostgreSQL with ALL required databases pre-configured
  services.postgresql = {
    enable = lib.mkForce true;
    package = pkgs.postgresql_15;
    
    # Pre-create ALL required databases and users
    ensureDatabases = [ "gitlab" "grafana" "mattermost" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "mattermost"; ensureDBOwnership = true; }
      { name = "prometheus"; ensureDBOwnership = false; }
    ];
    
    # Optimized settings for VM environment (merged with listen_addresses)
    settings = {
      listen_addresses = lib.mkForce "localhost,172.17.0.1";
      max_connections = 200;
      shared_buffers = "512MB";
      effective_cache_size = "2GB";
      maintenance_work_mem = "128MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "32MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      work_mem = "8MB";
      max_wal_size = "1GB";
      min_wal_size = "80MB";
    };
    
    # Initialize all databases with proper permissions
    initialScript = pkgs.writeText "postgres-init.sql" ''
      -- Ensure required roles exist
      SELECT format('CREATE ROLE %I LOGIN', 'gitlab')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gitlab')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'grafana')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'mattermost')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mattermost')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'prometheus')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prometheus')
      \gexec

      -- Ensure required databases exist
      SELECT format('CREATE DATABASE %I OWNER %I', 'gitlab', 'gitlab')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'gitlab')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'grafana', 'grafana')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'grafana')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'mattermost', 'mattermost')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'mattermost')
      \\gexec

      -- GitLab database setup
      ALTER ROLE gitlab CREATEDB;
      GRANT ALL PRIVILEGES ON DATABASE gitlab TO gitlab;
      
      -- Grafana permissions
      GRANT CONNECT ON DATABASE grafana TO grafana;
      GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;
      ALTER DATABASE grafana OWNER TO grafana;
      GRANT USAGE, CREATE ON SCHEMA public TO grafana;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO grafana;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO grafana;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO grafana;
      ALTER USER grafana WITH PASSWORD 'grafana-production-password';

      -- Mattermost database setup
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mattermost') THEN
          CREATE ROLE mattermost WITH LOGIN PASSWORD 'mmpgsecret';
        ELSE
          ALTER ROLE mattermost WITH PASSWORD 'mmpgsecret';
        END IF;
      END
      $$;
      GRANT ALL PRIVILEGES ON DATABASE mattermost TO mattermost;
      ALTER DATABASE mattermost OWNER TO mattermost;
      GRANT USAGE ON SCHEMA public TO mattermost;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mattermost;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mattermost;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO mattermost;

      -- Prometheus exporter
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'prometheus') THEN
          CREATE ROLE prometheus WITH LOGIN PASSWORD 'prometheus_pass';
        ELSE
          ALTER ROLE prometheus WITH PASSWORD 'prometheus_pass';
        END IF;
      END
      $$;
      GRANT pg_monitor TO prometheus;
    '';
  };

  # Single Redis instance (simplified - no clustering)
  services.redis.servers.main = {
    enable = true;
    port = 6379;
    settings = {
      # Listen on all interfaces to allow Docker container access
      bind = lib.mkForce "0.0.0.0";
      maxmemory = "1GB";
      maxmemory-policy = "allkeys-lru";
      save = [ "900 1" "300 10" "60 10000" ];
      # Allow multiple databases
      databases = 16;
    };
  };

  # ===== MESSAGING & MONITORING =====

  # NATS with JetStream
  services.nats = {
    enable = true;
    serverName = "rave-nats";
    port = 4222;
    
    settings = {
      # JetStream configuration
      jetstream = {
        store_dir = "/var/lib/nats/jetstream";
        max_memory_store = 512 * 1024 * 1024;  # 512MB
        max_file_store = 2 * 1024 * 1024 * 1024;  # 2GB
      };
      
      # Connection limits
      max_connections = 1000;
      max_payload = 2 * 1024 * 1024;  # 2MB
      
      # Monitoring
      http_port = 8222;
      
      # Cluster configuration disabled for single-node VM deployment
    };
  };

  # ===== GITLAB SERVICE =====


  # ===== COTURN STUN/TURN SERVER =====
  
  services.coturn = {
    enable = true;
    no-cli = true;
    no-tcp-relay = true;
    min-port = 49152;
    max-port = 65535;
    use-auth-secret = true;
    static-auth-secret = "rave-coturn-development-secret-2025";
    realm = "localhost";
    listening-ips = [ "0.0.0.0" ];
    
    extraConfig = ''
      # For development use - more permissive than production
      verbose
      fingerprint
      lt-cred-mech
      
      # Security: block private IP ranges
      no-multicast-peers
      denied-peer-ip=0.0.0.0-0.255.255.255
      denied-peer-ip=10.0.0.0-10.255.255.255
      denied-peer-ip=100.64.0.0-100.127.255.255
      denied-peer-ip=127.0.0.0-127.255.255.255
      denied-peer-ip=169.254.0.0-169.254.255.255
      denied-peer-ip=172.16.0.0-172.31.255.255
      denied-peer-ip=192.0.0.0-192.0.0.255
      denied-peer-ip=192.0.2.0-192.0.2.255
      denied-peer-ip=192.88.99.0-192.88.99.255
      denied-peer-ip=192.168.0.0-192.168.255.255
      denied-peer-ip=198.18.0.0-198.19.255.255
      denied-peer-ip=198.51.100.0-198.51.100.255
      denied-peer-ip=203.0.113.0-203.0.113.255
      denied-peer-ip=240.0.0.0-255.255.255.255
      denied-peer-ip=::1
      denied-peer-ip=64:ff9b::-64:ff9b::ffff:ffff
      denied-peer-ip=::ffff:0.0.0.0-::ffff:255.255.255.255
      denied-peer-ip=2001::-2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=2002::-2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
    '';
  };

  services.rave.gitlab = {
    enable = true;
    host = "localhost";
    useSecrets = true;
    runner.enable = false;
    oauth = {
      enable = true;
      provider = "google";
      clientId = googleOauthClientId;
      clientSecretFile = if config.services.rave.gitlab.useSecrets
        then "/run/secrets/gitlab/oauth-provider-client-secret"
        else pkgs.writeText "gitlab-oauth-client-secret" "development-client-secret";
      autoSignIn = false;
      autoLinkUsers = true;
      allowLocalSignin = true;
    };
  };

  services.gitlab.extraConfig.gitlab.omniauth.full_host = lib.mkForce gitlabExternalUrl;
  systemd.services.gitlab.environment.GITLAB_OMNIAUTH_FULL_HOST = gitlabExternalUrl;
  services.gitlab.extraConfig.gitlab.port = lib.mkForce (lib.toInt baseHttpsPort);

  # ===== NGINX CONFIGURATION =====

  services.nginx = {
    enable = true;
    commonHttpConfig = ''
      map $http_host $rave_forwarded_port {
        default 443;
        ~:(?<port>\d+)$ $port;
      }
    '';
    
    # Global configuration
    clientMaxBodySize = "10G";
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = false;
    recommendedTlsSettings = true;
    logError = "/var/log/nginx/error.log debug";
    
    # Status page for monitoring
    statusPage = true;
    
    virtualHosts."localhost" = {
      forceSSL = true;
      enableACME = false;
      listen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 80;
          ssl = false;
        }
      ];

      # Use manual certificate configuration
      sslCertificate = "/var/lib/acme/localhost/cert.pem";
      sslCertificateKey = "/var/lib/acme/localhost/key.pem";
      
      locations = {
        "/" = {
            root = pkgs.writeTextDir "index.html" ''
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>RAVE - Complete Production Environment</title>
                  <style>
                      * { margin: 0; padding: 0; box-sizing: border-box; }
                      body {
                          font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                          color: #333; min-height: 100vh; padding: 20px;
                      }
                      .container { max-width: 1200px; margin: 0 auto; }
                      .header { text-align: center; color: white; margin-bottom: 40px; }
                      .header h1 { font-size: 3rem; margin-bottom: 10px; }
                      .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
                      .service-card {
                          background: white; border-radius: 10px; padding: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.1);
                          transition: transform 0.3s ease; text-decoration: none; color: #333;
                      }
                      .service-card:hover { transform: translateY(-5px); }
                      .service-title { font-size: 1.5rem; margin-bottom: 10px; color: #667eea; }
                      .service-desc { color: #666; margin-bottom: 15px; }
                      .service-url { color: #764ba2; font-weight: bold; }
                      .status { display: inline-block; padding: 4px 8px; border-radius: 20px; font-size: 0.8rem; }
                      .status.active { background: #4ade80; color: white; }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <div class="header">
                          <h1>🚀 RAVE</h1>
                          <p>Complete Production Environment - All Services Ready</p>
                      </div>
                      <div class="services">
                          <a href="/gitlab/" class="service-card">
                              <div class="service-title">🦊 GitLab</div>
                              <div class="service-desc">Git repository management and CI/CD</div>
                              <div class="service-url">https://localhost:${baseHttpsPort}/gitlab/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/grafana/" class="service-card">
                              <div class="service-title">📊 Grafana</div>
                              <div class="service-desc">Monitoring dashboards and analytics</div>
                              <div class="service-url">https://localhost:${baseHttpsPort}/grafana/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="${mattermostPublicUrl}/" class="service-card">
                              <div class="service-title">💬 Mattermost</div>
                              <div class="service-desc">Secure team chat and agent control</div>
                              <div class="service-url">${mattermostPublicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/prometheus/" class="service-card">
                              <div class="service-title">🔍 Prometheus</div>
                              <div class="service-desc">Metrics collection and monitoring</div>
                              <div class="service-url">https://localhost:${baseHttpsPort}/prometheus/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/nats/" class="service-card">
                              <div class="service-title">⚡ NATS JetStream</div>
                              <div class="service-desc">High-performance messaging system</div>
                              <div class="service-url">https://localhost:${baseHttpsPort}/nats/</div>
                              <span class="status active">Active</span>
                          </a>
${penpotCardHtml}${outlineCardHtml}${n8nCardHtml}
                      </div>
                  </div>
              </body>
              </html>
            '';
          };

          "/login" = {
            return = "302 ${mattermostPublicUrl}/";
          };


          "/nats/" = {
            proxyPass = "http://127.0.0.1:8222/";
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };

          "/n8n/" = {
            proxyPass = "http://127.0.0.1:${toString n8nHostPort}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Port $rave_forwarded_port;
              proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
              proxy_set_header X-Forwarded-Prefix /n8n;
              proxy_set_header X-Forwarded-Ssl on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
              client_max_body_size 100M;
              proxy_redirect off;
            '';
          };

          "/n8n" = {
            return = "302 /n8n/";
          };

          "/mattermost/" = {
            proxyPass = "http://127.0.0.1:8065";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Port $rave_forwarded_port;
              proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
              proxy_set_header X-Forwarded-Ssl on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
              client_max_body_size 100M;
              proxy_redirect off;
              proxy_buffering off;
            '';
          };

          "/mattermost" = {
            proxyPass = "http://127.0.0.1:8065";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Port $rave_forwarded_port;
              proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
              proxy_set_header X-Forwarded-Ssl on;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
              client_max_body_size 100M;
              proxy_redirect off;
              proxy_buffering off;
            '';
          };
      };

      # Global security headers
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;  
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        port_in_redirect off;
        absolute_redirect off;
      '';
    };

    # Internal loopback virtual host exposing GitLab without SSL/redirects for backend services
    virtualHosts."gitlab-internal" = {
      listen = [ { addr = "127.0.0.1"; port = 8123; ssl = false; } ];
      serverName = "gitlab-internal";
      locations."/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "localhost";
          proxy_set_header X-Forwarded-Host "localhost";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto http;
          proxy_set_header X-Forwarded-Ssl off;
          proxy_set_header X-Forwarded-Port 8123;
          proxy_redirect off;
          rewrite ^/(.*)$ /gitlab/$1 break;
        '';
      };
    };
    
    # HTTP redirect to HTTPS
    virtualHosts."localhost-http" = {
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      locations."/" = {
        return = "301 https://localhost$request_uri";
      };
    };

    virtualHosts."chat.localtest.me" = {
      forceSSL = false;
      enableACME = false;
      listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
      http2 = true;
      sslCertificate = "/var/lib/acme/localhost/cert.pem";
      sslCertificateKey = "/var/lib/acme/localhost/key.pem";
      extraConfig = ''
        ssl_certificate /var/lib/acme/localhost/cert.pem;
        ssl_certificate_key /var/lib/acme/localhost/key.pem;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:8065";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          client_max_body_size 100M;
          proxy_redirect off;
        '';
      };
    };

    virtualHosts."localhost-mattermost" = {
      forceSSL = true;
      enableACME = false;
      serverName = "localhost";
      listen = [
        {
          addr = "0.0.0.0";
          port = 8231;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 8230;
          ssl = false;
        }
      ];

      sslCertificate = "/var/lib/acme/localhost/cert.pem";
      sslCertificateKey = "/var/lib/acme/localhost/key.pem";


      locations."/mattermost/" = {
        proxyPass = "http://127.0.0.1:8065";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          client_max_body_size 100M;
          proxy_redirect off;
          proxy_buffering off;
        '';
      };

      locations."/mattermost" = {
        proxyPass = "http://127.0.0.1:8065";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          client_max_body_size 100M;
          proxy_redirect off;
          proxy_buffering off;
        '';
      };


      extraConfig = ''
        port_in_redirect off;
        absolute_redirect off;
      '';
    };

    virtualHosts."chat.localtest.me-http" = {
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      serverName = "chat.localtest.me";
      locations."/" = {
        return = "301 https://chat.localtest.me$request_uri";
      };
    };
  };

  # Ensure GitLab is started after the database configuration completes.
  systemd.services."gitlab-db-config".unitConfig = {
    OnSuccess = [ "gitlab-autostart.service" ];
  } // lib.optionalAttrs useSecrets {
    ConditionPathExists = "/run/secrets/gitlab/db-password";
  };

  systemd.services."gitlab-autostart" = {
    description = "Ensure GitLab starts after database configuration";
    wantedBy = [ "multi-user.target" ];
    after = [
      "postgresql.service"
      "redis-main.service"
      "gitlab-config.service"
      "gitlab-db-config.service"
    ];
    wants = [ "gitlab-db-config.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "gitlab-autostart.sh" ''
        set -euo pipefail

        systemctl_bin='${lib.getExe' pkgs.systemd "systemctl"}'
        attempts=0
        max_attempts=12

        # Wait (with retries) for gitlab-db-config to report active.
        while ! "$systemctl_bin" is-active --quiet gitlab-db-config.service; do
          if (( attempts >= max_attempts )); then
            echo "gitlab-db-config.service did not become active" >&2
            exit 1
          fi

          # If the config unit is in failed state, reset it so systemd can retry.
          if "$systemctl_bin" is-failed --quiet gitlab-db-config.service; then
            "$systemctl_bin" reset-failed gitlab-db-config.service || true
            "$systemctl_bin" start gitlab-db-config.service || true
          fi

          attempts=$(( attempts + 1 ))
          sleep $(( 5 * attempts ))
        done

        "$systemctl_bin" reset-failed gitlab.service || true
        "$systemctl_bin" start gitlab.service
      '';
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  # ===== SSL CERTIFICATE CONFIGURATION =====

  # Generate self-signed certificates for localhost
  systemd.services.generate-localhost-certs = {
    description = "Generate self-signed SSL certificates for localhost";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      set -e
      
      CERT_DIR="/var/lib/acme/localhost"
      
      # Create certificate directory
      mkdir -p "$CERT_DIR"
      
      # Only generate if certificates don't exist
      if [[ ! -f "$CERT_DIR/cert.pem" ]]; then
        echo "Generating SSL certificates for localhost..."
        
        # Generate CA private key
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/ca-key.pem" 4096
        
        # Generate CA certificate
        ${pkgs.openssl}/bin/openssl req -new -x509 -days 365 -key "$CERT_DIR/ca-key.pem" -out "$CERT_DIR/ca.pem" -subj "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=RAVE-CA"
        
        # Generate server private key  
        ${pkgs.openssl}/bin/openssl genrsa -out "$CERT_DIR/key.pem" 4096
        
        # Generate certificate signing request
        ${pkgs.openssl}/bin/openssl req -new -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.csr" -subj "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=localhost"
        
        # Create certificate with SAN for localhost
        cat > "$CERT_DIR/cert.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = SF
O = RAVE
OU = Dev
CN = localhost

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = rave.local
DNS.3 = chat.localtest.me
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
        
        # Generate final certificate
        ${pkgs.openssl}/bin/openssl x509 -req -in "$CERT_DIR/cert.csr" -CA "$CERT_DIR/ca.pem" -CAkey "$CERT_DIR/ca-key.pem" -CAcreateserial -out "$CERT_DIR/cert.pem" -days 365 -extensions v3_req -extfile "$CERT_DIR/cert.conf"
        
        # Set proper permissions
        chmod 755 "$CERT_DIR"
        chmod 644 "$CERT_DIR"/{cert.pem,ca.pem}
        chmod 640 "$CERT_DIR/key.pem"
        
        # Set nginx group ownership for key access
        chgrp nginx "$CERT_DIR"/{cert.pem,key.pem} || true
        
        echo "SSL certificates generated successfully!"
      else
        echo "SSL certificates already exist, skipping generation."
      fi
    '';
  };

  # ===== SYSTEM CONFIGURATION =====

  # Enable required services
  services.dbus.enable = true;
  
  # Environment packages
  environment.systemPackages = with pkgs; [
    # System utilities
    curl wget htop btop tree vim nano
    git jq yq-go
    
    # Network utilities
    netcat-gnu nmap tcpdump
    
    # Monitoring tools
    prometheus-node-exporter
    
    # Development tools
    docker-compose
    python3 nodejs nodePackages.npm
    
    # SSL utilities
    openssl
  ];

  # Enable Docker
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/var/lib/docker";
      storage-driver = "overlay2";
    };
  };


  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      22    # SSH
      80    # HTTP
      443   # HTTPS
      8443  # HTTPS (alternate)
      8220  # HTTP (VM forwarded)
      8221  # HTTPS (VM forwarded)
      8230  # Mattermost HTTP
      8231  # Mattermost HTTPS
      8080  # GitLab internal
      3000  # Grafana internal
      8065  # Mattermost internal
      9090  # Prometheus internal
      8222  # NATS monitoring
      5000  # GitLab registry
      4222  # NATS
    ];
  };

  # System services dependency management
  systemd.services = {
    # Ensure PostgreSQL users exist before other services start
    postgresql = {
      after = [ "postgres-gitlab-group-fix.service" ];
      wants = [ "postgres-gitlab-group-fix.service" ];
    };
    postgresql.postStart = ''
      # Wait for PostgreSQL to be ready
      while ! ${pkgs.postgresql_15}/bin/pg_isready -d postgres > /dev/null 2>&1; do
        sleep 1
      done

      # Update user passwords (non-SOPS secrets only)
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER grafana PASSWORD 'grafana-production-password';" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER penpot PASSWORD 'penpot-production-password';" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER n8n PASSWORD '${n8nDbPassword}';" || true

      # Grant additional permissions
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT CONNECT ON DATABASE postgres TO grafana;" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT USAGE ON SCHEMA public TO grafana;" || true
    '';
    
    # Separate service for GitLab password setup after SOPS is fully ready
    gitlab-password-setup = {
      description = "Set GitLab database password from SOPS secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "sops-init.service" ];
      requires = [ "postgresql.service" "sops-init.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";  # Run as root to ensure secret access
      };
      environment.PATH = lib.mkForce "${pkgs.postgresql_15}/bin:${pkgs.sudo}/bin:${pkgs.coreutils}/bin";
      script = ''
        # Wait for PostgreSQL to be ready
        while ! ${pkgs.postgresql_15}/bin/pg_isready -d postgres > /dev/null 2>&1; do
          echo "Waiting for PostgreSQL to be ready..."
          sleep 2
        done

        # Wait for SOPS secret to be available
        timeout=30
        while [ ! -f "/run/secrets/gitlab/db-password" ] || [ ! -s "/run/secrets/gitlab/db-password" ]; do
          if [ $timeout -le 0 ]; then
            echo "Timeout waiting for SOPS secret"
            exit 1
          fi
          echo "Waiting for SOPS secret to be available..."
          sleep 1
          timeout=$((timeout - 1))
        done

        # Set GitLab password from SOPS secret
        GITLAB_PASSWORD=$(cat /run/secrets/gitlab/db-password)
        
        # Create gitlab role if it doesn't exist, then set password
        # Use a simpler approach without heredoc to avoid syntax issues
        sudo -u postgres ${pkgs.postgresql_15}/bin/psql -d postgres -c \
          "DO \$\$ BEGIN
             IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gitlab') THEN
               CREATE ROLE gitlab WITH LOGIN CREATEDB;
             END IF;
           END \$\$;" || {
          echo "Failed to create GitLab role"
          exit 1
        }
        
        # Set the password securely using stdin to avoid command line exposure
        echo "ALTER ROLE gitlab WITH PASSWORD '$GITLAB_PASSWORD';" | \
          sudo -u postgres ${pkgs.postgresql_15}/bin/psql -d postgres || {
          echo "Failed to set GitLab password"
          exit 1
        }
        echo "GitLab database password successfully updated from SOPS secret"
      '';
    };

    # GitLab depends on database, certificates, and password setup
    gitlab.after = [
      "postgresql.service"
      "redis-main.service"
      "generate-localhost-certs.service"
      "gitlab-password-setup.service"
    ];
    gitlab.requires = [
      "postgresql.service"
      "redis-main.service"
      "gitlab-password-setup.service"
    ];
    # GitLab database password now set by gitlab-password-setup.service
    
    # Grafana depends on database and certificates
    grafana.after = [ "postgresql.service" "generate-localhost-certs.service" ];
    grafana.requires = [ "postgresql.service" ];
    
    # nginx depends on certificates and all backend services
    nginx.after = 
      [
        "generate-localhost-certs.service" 
        "gitlab.service"
        "grafana.service" 
        "mattermost.service"
        "prometheus.service"
        "nats.service"
      ]
      ++ lib.optionals config.services.rave.penpot.enable [ "penpot-backend.service" "penpot-frontend.service" "penpot-exporter.service" ]
      ++ lib.optionals config.services.rave.outline.enable [ "outline.service" ]
      ++ lib.optionals config.services.rave.n8n.enable [ "n8n.service" ];
    nginx.requires = [ "generate-localhost-certs.service" ];
  };

  systemd.tmpfiles.rules = [
    "d /run/secrets 0755 root root -"
    "d /run/secrets/gitlab 0750 postgres gitlab -"
    "d /run/secrets/mattermost 0750 root mattermost -"
    "d /run/secrets/oidc 0700 root root -"
  ];

  system.activationScripts.installRootWelcome = {
    text = ''
      cat <<'WELCOME' > /root/welcome.sh
#!/bin/sh
echo "Welcome to the RAVE complete VM"
echo "Forwarded ports:"
echo "  SSH          : localhost:12222 (user root, password rave-root)"
echo "  GitLab HTTPS : https://localhost:${baseHttpsPort}/gitlab/"
echo "  Mattermost   : ${mattermostPublicUrl}/"
echo "  Grafana      : https://localhost:${baseHttpsPort}/grafana/"
echo "  Prometheus   : http://localhost:19090/"
${penpotWelcomePrimary}${outlineWelcomePrimary}${n8nWelcomePrimary}
echo ""
WELCOME
      chmod 0755 /root/welcome.sh
    '';
  };

  # Create welcome script
  systemd.services.create-welcome-script = {
    description = "Create system welcome script";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      cat > /root/welcome.sh << 'EOF'
#!/bin/bash
echo "🚀 RAVE Complete Production Environment"
echo "====================================="
echo ""
echo "✅ All Services Ready:"
echo "   🦊 GitLab:      https://localhost:${baseHttpsPort}/gitlab/"
echo "   📊 Grafana:     https://localhost:${baseHttpsPort}/grafana/"  
echo "   💬 Mattermost:  https://localhost:${baseHttpsPort}/mattermost/"
echo "   🔍 Prometheus:  https://localhost:${baseHttpsPort}/prometheus/"
echo "   ⚡ NATS:        https://localhost:${baseHttpsPort}/nats/"
${penpotWelcomeFancy}${outlineWelcomeFancy}${n8nWelcomeFancy}
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status ${welcomeStatusServices} --no-pager -l
echo ""
echo "🌐 Dashboard: https://localhost:${baseHttpsPort}/"
echo ""
EOF
      chmod +x /root/welcome.sh
      echo "/root/welcome.sh" >> /root/.bashrc
    '';
  };
}
