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
  localCertDir = config.security.rave.localCerts.certDir or "/var/lib/acme/localhost";
  localCaPath = "${localCertDir}/ca.pem";
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
  outlinePublicUrl = "https://outline.localhost:${baseHttpsPort}/";
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
  mattermostInternalBaseUrl = "http://127.0.0.1:8065";
  grafanaHttpPort = config.services.rave.monitoring.grafana.httpPort;
  pomeriumRouteHost = "https://localhost:${baseHttpsPort}";
  pomeriumConsolePath = "/pomerium";
  pomeriumBaseUrl = "${pomeriumRouteHost}${pomeriumConsolePath}";
  pomeriumRedirectUri = "https://localhost:${baseHttpsPort}/oauth2/callback";
  pomeriumIdp = config.services.rave.pomerium.idp;
  pomeriumInlineSecret = pomeriumIdp.clientSecret or "";
  pomeriumSecretFile = pomeriumIdp.clientSecretFile;
  gitlabRailsRunner = "${config.system.path}/bin/gitlab-rails";

  dbPasswordUnitSpecs = [
    {
      name = "grafana";
      role = "grafana";
      secret = "/run/secrets/grafana/db-password";
      dependent = "grafana";
      extraScript = "";
    }
    {
      name = "mattermost";
      role = "mattermost";
      secret = "/run/secrets/database/mattermost-password";
      dependent = "mattermost";
      extraScript = "";
    }
    {
      name = "penpot";
      role = "penpot";
      secret = "/run/secrets/database/penpot-password";
      dependent = "penpot-backend";
      extraScript = "";
    }
    {
      name = "n8n";
      role = "n8n";
      secret = "/run/secrets/database/n8n-password";
      dependent = "n8n";
      extraScript = "";
    }
    {
      name = "prometheus";
      role = "prometheus";
      secret = "/run/secrets/database/prometheus-password";
      dependent = "prometheus-postgres-exporter";
      extraScript = ''
        DSN_FILE=/run/secrets/database/prometheus-dsn.env
        mkdir -p /run/secrets/database
        printf 'DATA_SOURCE_NAME=postgresql://prometheus:%s@localhost:5432/postgres?sslmode=disable\n' "$PASSWORD" > "$DSN_FILE"
        chown prometheus-postgres-exporter:prometheus-postgres-exporter "$DSN_FILE"
        chmod 0400 "$DSN_FILE"
      '';
    }
  ];

  mkPasswordUnit = unit: {
    name = "postgres-set-${unit.name}-password";
    value = lib.mkIf useSecrets {
      description = "Set ${unit.role} PostgreSQL password from secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "sops-init.service" ];
      requires = [ "postgresql.service" "sops-init.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        RemainAfterExit = true;
      };
      script = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        SECRET_FILE=${lib.escapeShellArg unit.secret}
        if [ ! -s "$SECRET_FILE" ]; then
          echo "Secret missing at $SECRET_FILE for role ${unit.role}" >&2
          exit 1
        fi

        PASSWORD="$(tr -d '\n' < "$SECRET_FILE")"
        ESCAPED=''${PASSWORD//\'/\'\'}

        ${pkgs.sudo}/bin/sudo -u postgres ${config.services.postgresql.package}/bin/psql \
          -v ON_ERROR_STOP=1 -d postgres \
          -c "ALTER ROLE ${unit.role} WITH PASSWORD '$ESCAPED';"
${unit.extraScript}
      '';
    };
  };

  passwordUnitServices = lib.listToAttrs (map mkPasswordUnit dbPasswordUnitSpecs);

  passwordDependentOverrides = lib.listToAttrs (map (unit: {
    name = unit.dependent;
    value = lib.mkIf useSecrets {
      after = lib.mkAfter [ "postgres-set-${unit.name}-password.service" ];
      requires = lib.mkAfter [ "postgres-set-${unit.name}-password.service" ];
    };
  }) dbPasswordUnitSpecs);
in
{
  services.rave.outline = {
    enable = true;
    publicUrl = outlinePublicUrl;
    dockerImage = outlineDockerImage;
    hostPort = outlineHostPort;
    dbPassword = outlineDbPassword;
    dbPasswordFile = null;
    secretKey = outlineSecretKey;
    secretKeyFile = null;
    utilsSecret = outlineUtilsSecret;
    utilsSecretFile = null;
    redisDb = outlineRedisDb;
  };

  services.rave.n8n = {
    enable = true;
    publicUrl = n8nPublicUrl;
    dockerImage = n8nDockerImage;
    hostPort = n8nHostPort;
    dbPassword = n8nDbPassword;
    dbPasswordFile = if useSecrets then "/run/secrets/database/n8n-password" else null;
    encryptionKey = n8nEncryptionKey;
    basicAuthPassword = n8nBasicAuthPassword;
    basePath = n8nBasePath;
  };

  services.rave.auth-manager = {
    enable = true;
    listenAddress = "0.0.0.0:8088";
    openFirewall = true;
    sourceIdp = "gitlab";
    signingKey = lib.mkIf (!useSecrets) "auth-manager-dev-signing-key";
    signingKeyFile = lib.mkIf useSecrets "/run/secrets/auth-manager/signing-key";
    pomeriumSharedSecret = lib.mkIf (!useSecrets) config.services.rave.pomerium.sharedSecret;
    pomeriumSharedSecretFile = lib.mkIf useSecrets "/run/secrets/auth-manager/pomerium-shared-secret";
    mattermost = {
      url = mattermostPublicUrl;
      adminToken = lib.mkIf (!useSecrets) "mattermost-admin-token";
      adminTokenFile = lib.mkIf useSecrets "/run/secrets/auth-manager/mattermost-admin-token";
    };
  };

  services.rave.pomerium = {
    enable = true;
    publicUrl = pomeriumBaseUrl;
    idp = {
      provider = "gitlab";
      providerUrl = gitlabExternalUrl;
      clientId = "rave-pomerium";
      clientSecret = "rave-pomerium-client-secret";
      clientSecretFile = null;
      scopes = [ "openid" "profile" "email" ];
      providerCaFile = localCaPath;
    };
    policies = [
      {
        name = "Mattermost via Pomerium";
        from = pomeriumRouteHost;
        path = "/mattermost";
        to = mattermostInternalBaseUrl;
        allowPublicUnauthenticated = true;
        passIdentityHeaders = true;
        preserveHost = true;
      }
      {
        name = "Grafana via Pomerium";
        from = pomeriumRouteHost;
        path = "/grafana";
        to = "http://127.0.0.1:${toString grafanaHttpPort}";
        allowPublicUnauthenticated = true;
      }
    ];
    extraSettings = {};
  };

  services.rave.penpot = {
    enable = true;
    host = "localhost";
    publicUrl = penpotPublicUrl;
    database.password = "penpot-production-password";
    database.passwordFile = if useSecrets then "/run/secrets/database/penpot-password" else null;
    oidc = {
      enable = true;
      gitlabUrl = gitlabExternalUrl;
      clientId = "penpot";
      clientSecret = "penpot-oidc-secret";
    };
  };

  services.rave.nats = {
    enable = true;
    serverName = "rave-nats";
    port = 4222;
    httpPort = 8222;
    jetstream = {
      maxMemory = "512MB";
      maxFileStore = "2GB";
    };
    limits = {
      maxConnections = 1000;
      maxPayload = 2 * 1024 * 1024;
    };
  };

  services.rave.coturn = {
    enable = true;
    staticAuthSecret = "rave-coturn-development-secret-2025";
    realm = "localhost";
    listeningIps = [ "0.0.0.0" ];
  };

  services.rave.nginx = {
    enable = true;
    host = "localhost";
    chatDomain = null;
  };

  services.rave.welcome.enable = true;

  services.rave.redis = {
    enable = true;
    bind = "0.0.0.0";
    port = 6379;
    dockerHost = "host.docker.internal";
    maxMemory = "1GB";
    maxMemoryPolicy = "allkeys-lru";
    save = [ "900 1" "300 10" "60 10000" ];
    databases = 16;
    extraSettings.protected-mode = "no";
    allocations = {
      gitlab = 0;
      outline = 5;
      penpot = 10;
    };
  };

  security.rave.localCerts = {
    enable = true;
    certDir = "/var/lib/acme/localhost";
    commonName = "localhost";
  };

  services.rave.monitoring = {
    enable = true;
    retentionTime = "3d";
    grafana = {
      domain = "localhost";
      publicUrl = "https://localhost:${baseHttpsPort}/grafana/";
      adminUser = "admin";
      adminPassword = "admin123";
      adminPasswordFile = if useSecrets then "/run/secrets/grafana/admin-password" else null;
      secretKey = "grafana-production-secret-key";
      secretKeyFile = if useSecrets then "/run/secrets/grafana/secret-key" else null;
      database = {
        host = "localhost:5432";
        name = "grafana";
        user = "grafana";
        password = "grafana-production-password";
        passwordFile = if useSecrets then "/run/secrets/grafana/db-password" else null;
      };
    };
    exporters.postgres = {
      dataSourceName = "postgresql://prometheus:prometheus_pass@localhost:5432/postgres?sslmode=disable";
      dsnEnvFile = if useSecrets then "/run/secrets/database/prometheus-dsn.env" else null;
    };
  };

  services.rave.mattermost = {
    enable = true;
    siteName = "RAVE Mattermost";
    publicUrl = mattermostPublicUrl;
    internalBaseUrl = mattermostInternalBaseUrl;
    brandHtml = mattermostBrandHtml;
    envFile = null;
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

  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix
    ../modules/foundation/ports.nix

    # Service modules
    ../modules/services/gitlab/default.nix
    ../modules/services/monitoring/default.nix
    ../modules/services/nats/default.nix
    ../modules/services/coturn/default.nix
    ../modules/services/nginx/default.nix
    ../modules/services/postgresql/default.nix
    ../modules/services/auth-manager/default.nix
    ../modules/services/mattermost/default.nix
    ../modules/services/outline/default.nix
    ../modules/services/n8n/default.nix
    ../modules/services/pomerium/default.nix
    ../modules/services/penpot/default.nix
    ../modules/services/redis/default.nix
    ../modules/services/welcome/default.nix

    # Security modules
    # ../modules/security/certificates.nix  # DISABLED: Using inline certificate generation instead
    ../modules/security/hardening.nix
    ../modules/security/local-certs/default.nix
    ../modules/security/sops-bootstrap/default.nix
  ];

# SOPS configuration - DISABLE built-in activation to prevent conflicts
# Only use our custom sops-init service which runs after AGE key is available
sops = lib.mkIf false {
  defaultSopsFile = ../../config/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
  validateSopsFiles = false;
  secrets = {
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

  security.rave.sopsBootstrap = {
    enable = config.services.rave.gitlab.useSecrets;
    sopsFile = ../../config/secrets.yaml;
    secretMappings = [
      { selector = "[\"mattermost\"][\"admin-username\"]"; path = "/run/secrets/mattermost/admin-username"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"mattermost\"][\"admin-email\"]"; path = "/run/secrets/mattermost/admin-email"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"mattermost\"][\"admin-password\"]"; path = "/run/secrets/mattermost/admin-password"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"oidc\"][\"chat-control-client-secret\"]"; path = "/run/secrets/oidc/chat-control-client-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"api-token\"]"; path = "/run/secrets/gitlab/api-token"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"root-password\"]"; path = "/run/secrets/gitlab/root-password"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"db-password\"]"; path = "/run/secrets/gitlab/db-password"; owner = "postgres"; group = "gitlab"; mode = "0440"; }
      { selector = "[\"gitlab\"][\"secret-key-base\"]"; path = "/run/secrets/gitlab/secret-key-base"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"db-key-base\"]"; path = "/run/secrets/gitlab/db-key-base"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"otp-key-base\"]"; path = "/run/secrets/gitlab/otp-key-base"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"jws-key-base\"]"; path = "/run/secrets/gitlab/jws-key-base"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"oauth-provider-client-secret\"]"; path = "/run/secrets/gitlab/oauth-provider-client-secret"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"gitlab\"][\"oauth-mattermost-client-secret\"]"; path = "/run/secrets/gitlab/oauth-mattermost-client-secret"; owner = "gitlab"; group = "gitlab"; mode = "0400"; }
      { selector = "[\"grafana\"][\"secret-key\"]"; path = "/run/secrets/grafana/secret-key"; owner = "grafana"; group = "grafana"; mode = "0400"; }
      { selector = "[\"grafana\"][\"db-password\"]"; path = "/run/secrets/grafana/db-password"; owner = "grafana"; group = "grafana"; mode = "0400"; }
      { selector = "[\"database\"][\"mattermost-password\"]"; path = "/run/secrets/database/mattermost-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"penpot-password\"]"; path = "/run/secrets/database/penpot-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"n8n-password\"]"; path = "/run/secrets/database/n8n-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"outline-password\"]"; path = "/run/secrets/database/outline-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"prometheus-password\"]"; path = "/run/secrets/database/prometheus-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"grafana-password\"]"; path = "/run/secrets/grafana/admin-password"; owner = "grafana"; group = "grafana"; mode = "0400"; }
      { selector = "[\"outline\"][\"secret-key\"]"; path = "/run/secrets/outline/secret-key"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"outline\"][\"utils-secret\"]"; path = "/run/secrets/outline/utils-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"signing-key\"]"; path = "/run/secrets/auth-manager/signing-key"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"pomerium-shared-secret\"]"; path = "/run/secrets/auth-manager/pomerium-shared-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"mattermost-admin-token\"]"; path = "/run/secrets/auth-manager/mattermost-admin-token"; owner = "root"; group = "root"; mode = "0400"; }
    ];
    extraTmpfiles = [
      "d /run/secrets/grafana 0750 root grafana -"
      "d /run/secrets/database 0750 root postgres -"
      "d /run/secrets/outline 0750 root root -"
      "d /run/secrets/auth-manager 0750 root root -"
    ];
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

  services.rave.postgresql = {
    enable = true;
    listenAddresses = "0.0.0.0";
    ensureDatabases = [ "gitlab" "grafana" "mattermost" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "mattermost"; ensureDBOwnership = true; }
      { name = "prometheus"; ensureDBOwnership = false; }
    ];
    settings = {
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
    initialSql = ''
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

      -- Mattermost database setup
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mattermost') THEN
          CREATE ROLE mattermost WITH LOGIN;
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
    postStartSql = [
      "GRANT CONNECT ON DATABASE postgres TO grafana;"
      "GRANT USAGE ON SCHEMA public TO grafana;"
    ];
  };

  services.postgresql.authentication = ''
    local   all     all                     trust
    host    all     all     127.0.0.1/32    trust
    host    all     all     ::1/128         trust
    host    all     all     172.17.0.0/16   md5
  '';

  systemd.services = lib.mkMerge [
    passwordUnitServices
    passwordDependentOverrides
    {
      postgresql = {
        after = lib.mkAfter [ "docker.service" ];
        wants = lib.mkAfter [ "docker.service" ];
      };
      gitlab-sidekiq = {
        unitConfig.BindsTo = lib.mkForce "";
        after = lib.mkAfter [ "gitlab.service" ];
        requires = lib.mkAfter [ "gitlab.service" ];
      };
      gitlab-pomerium-oauth = {
        description = "Ensure GitLab OAuth client for Pomerium exists";
        wantedBy = [ "multi-user.target" ];
        after = [ "gitlab-db-config.service" "gitlab.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "gitlab";
          Group = "gitlab";
          TimeoutStartSec = "900s";
          Restart = "on-failure";
          RestartSec = "30s";
        };
        environment = {
          HOME = "/var/gitlab/state/home";
          RAILS_ENV = "production";
        };
        script = ''
          set -euo pipefail

          until ${pkgs.systemd}/bin/systemctl is-active --quiet gitlab-db-config.service; do
            sleep 5
          done

          until ${pkgs.systemd}/bin/systemctl is-active --quiet gitlab.service; do
            sleep 5
          done

          export POMERIUM_UID=${lib.escapeShellArg pomeriumIdp.clientId}
          export POMERIUM_REDIRECT_URI=${lib.escapeShellArg pomeriumRedirectUri}
          export POMERIUM_SCOPES="openid profile email"
          export POMERIUM_NAME="Pomerium SSO"
          export POMERIUM_SECRET=${lib.escapeShellArg pomeriumInlineSecret}
${lib.optionalString (pomeriumSecretFile != null) ''
          if [ -s ${lib.escapeShellArg pomeriumSecretFile} ]; then
            export POMERIUM_SECRET="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg pomeriumSecretFile})"
          fi
''}

          ${gitlabRailsRunner} runner - <<'RUBY'
uid = ENV.fetch("POMERIUM_UID")
redirect_uri = ENV.fetch("POMERIUM_REDIRECT_URI")
secret = ENV.fetch("POMERIUM_SECRET")
scopes = ENV.fetch("POMERIUM_SCOPES")
name = ENV.fetch("POMERIUM_NAME")

app = Doorkeeper::Application.find_or_initialize_by(uid: uid)
app.name = name
app.redirect_uri = redirect_uri
app.secret = secret
app.scopes = scopes
app.confidential = true
app.trusted = true if app.respond_to?(:trusted=)
app.skip_authorization = true if app.respond_to?(:skip_authorization=)
app.save!
RUBY
        '';
      };
      pomerium = lib.mkIf config.services.rave.pomerium.enable {
        after = lib.mkAfter [ "gitlab-pomerium-oauth.service" ];
        requires = lib.mkAfter [ "gitlab-pomerium-oauth.service" ];
      };
    }
  ];

  services.rave.gitlab = {
    enable = true;
    host = "localhost";
    useSecrets = false;
    publicUrl = gitlabExternalUrl;
    externalPort = lib.toInt baseHttpsPort;
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

  # ===== NGINX CONFIGURATION =====



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
      5432  # PostgreSQL (dockerized services like n8n need host access)
      6379  # Redis (dockerized services)
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

}
