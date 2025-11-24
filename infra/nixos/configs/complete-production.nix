# nixos/configs/complete-production.nix
# Complete, consolidated NixOS VM configuration with ALL services pre-configured
{ config, pkgs, lib, ... }:

let
  # Build-time port configuration (can be overridden via flake)
  baseHttpsPort = toString config.services.rave.ports.https;
  # External host/port clients use to reach the VM front door (keep host in sync with Traefik host override).
  externalHost = config.services.rave.traefik.host or "auth.localtest.me";
  externalHttpsBase = "https://${externalHost}:${baseHttpsPort}";
  
  useSecrets = config.services.rave.gitlab.useSecrets;
  gitlabDbPasswordFile = if useSecrets
    then "/run/secrets/gitlab/db-password"
    else pkgs.writeText "gitlab-db-password" "gitlab-production-password";
  # Populated from environment to avoid committing secrets; provide safe placeholders for dev.
  googleOauthClientId =
    let val = builtins.getEnv "GOOGLE_OAUTH_CLIENT_ID";
    in if val != "" then val else "google-client-id-placeholder";
  googleOauthClientSecret =
    let val = builtins.getEnv "GOOGLE_OAUTH_CLIENT_SECRET";
    in if val != "" then val else "google-client-secret-placeholder";
  # Helper: prefer real secret file, otherwise fall back to env value, then to a safe placeholder.
  fallbackSecretFile = name: path: value: default:
    if builtins.pathExists path then path
    else if value != "" then pkgs.writeText name value
    else pkgs.writeText name default;

  googleOauthClientIdFile = fallbackSecretFile "authentik-google-client-id" "/run/secrets/authentik/google-client-id" googleOauthClientId "google-client-id-placeholder";
  googleOauthClientSecretFile = fallbackSecretFile "authentik-google-client-secret" "/run/secrets/authentik/google-client-secret" googleOauthClientSecret "google-client-secret-placeholder";
  gitlabExternalUrl = "${externalHttpsBase}/gitlab";
  gitlabInternalHttpsUrl = gitlabExternalUrl;
  gitlabInternalHttpUrl = gitlabExternalUrl;
  gitlabPackage = config.services.gitlab.packages.gitlab;
  mattermostPublicUrl = "${externalHttpsBase}/mattermost";
  penpotPublicUrl = "${externalHttpsBase}/penpot";
  localCertDir = config.security.rave.localCerts.certDir or "/var/lib/acme/localhost";
  localCaPath = "${localCertDir}/ca.pem";
  # Keep the generated TLS cert aligned with the public host Traefik serves.
  localCertSubject = "/C=US/ST=CA/L=SF/O=RAVE/OU=Dev/CN=${externalHost}";
  localCertSan = ''
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
CN = ${externalHost}

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${externalHost}
DNS.2 = *.localtest.me
DNS.3 = localhost
DNS.4 = rave.local
DNS.5 = *.rave.local
DNS.6 = outline.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
'';
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
  mattermostDbPassword = "mmpgsecret";
  mattermostGitlabClientId = "41622b028bfb499bcadfcdf42a8618734a6cebc901aa8f77661bceeebc7aabba";
  mattermostGitlabClientSecretFile = if useSecrets
    then "/run/secrets/gitlab/oauth-mattermost-client-secret"
    else null;
  mattermostGitlabSecretFallback = "gloas-18f9021e792192dda9f50be4df02cee925db5d36a09bf6867a33762fb874d539";
  mattermostOidcClientSecretFile =
    if mattermostGitlabClientSecretFile != null
    then mattermostGitlabClientSecretFile
    else pkgs.writeText "mattermost-openid-secret" mattermostGitlabSecretFallback;
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
  githubOauthClientId =
    let val = builtins.getEnv "GITHUB_OAUTH_CLIENT_ID";
    in if val != "" then val else "github-client-id-placeholder";
  githubOauthClientSecret =
    let val = builtins.getEnv "GITHUB_OAUTH_CLIENT_SECRET";
    in if val != "" then val else "github-client-secret-placeholder";
  githubOauthClientIdFile = fallbackSecretFile "authentik-github-client-id" "/run/secrets/authentik/github-client-id" githubOauthClientId "github-client-id-placeholder";
  githubOauthClientSecretFile = fallbackSecretFile "authentik-github-client-secret" "/run/secrets/authentik/github-client-secret" githubOauthClientSecret "github-client-secret-placeholder";
  outlinePublicUrl = "${externalHttpsBase}/outline/";
  outlineDockerImage = "outlinewiki/outline:latest";
  outlineHostPort = 8310;
  outlineDbPassword = "outline-production-password";
  outlineSecretKey = "outline-secret-key-4c8d8a4c9f004aa4868b9e19767b2e8e";
  outlineUtilsSecret = "outline-utils-secret-d4c2b6a5a9c2474f8fb3b77d0b0fbd89";
  outlineRedisDb = 5;
  outlineWebhookSecret = "outline-webhook-secret-1e3dc9d6bd784d7d8b1d5b5f7c6a8890";
  outlineWebhookSecretFile = if useSecrets
    then "/run/secrets/outline/webhook-secret"
    else pkgs.writeText "outline-webhook-secret" outlineWebhookSecret;
  outlineOidcClientId = "rave-outline";
  outlineOidcClientSecretFile = if useSecrets
    then "/run/secrets/outline/oidc-client-secret"
    else pkgs.writeText "outline-oidc-client-secret" "outline-oidc-secret";
  outlineIcon = "https://raw.githubusercontent.com/outline/brand/main/logo/outline-logo-mark-only.svg";
  benthosGitlabWebhookSecret = "benthos-gitlab-webhook-secret-d4fe4b589da0417287cc7f51f6d9987b";
  benthosGitlabWebhookSecretFile = if useSecrets
    then "/run/secrets/benthos/gitlab-webhook-secret"
    else pkgs.writeText "benthos-gitlab-webhook-secret" benthosGitlabWebhookSecret;
  n8nPublicUrl = "${externalHttpsBase}/n8n";
  n8nDockerImage = "n8nio/n8n:latest";
  n8nHostPort = 5678;
  n8nDbPassword = "n8n-production-password";
  n8nEncryptionKey = "n8n-encryption-key-2d01b6dba90441e8a6f7ec2af3327ef2";
  n8nBasicAuthPassword = "n8n-basic-admin-password";
  n8nBasePath = "/n8n";
  n8nOidcClientId = "rave-n8n";
  n8nOidcClientSecretFile = if useSecrets
    then "/run/secrets/n8n/oidc-client-secret"
    else pkgs.writeText "n8n-oidc-client-secret" "n8n-oidc-secret";
  mattermostInternalBaseUrl = "http://127.0.0.1:8065";
  gitlabOidcSlug = "gitlab";
  gitlabOidcClientId = "rave-gitlab";
  gitlabOidcClientSecretFallback = "gitlab-oidc-secret";
  gitlabOidcClientSecretFile = if useSecrets
    then "/run/secrets/gitlab/oauth-provider-client-secret"
    else pkgs.writeText "gitlab-oidc-client-secret" gitlabOidcClientSecretFallback;
  gitlabOidcIssuer = "${authentikPublicUrl}application/o/${gitlabOidcSlug}/";
  grafanaHttpPort = config.services.rave.monitoring.grafana.httpPort;
  grafanaDbPassword = config.services.rave.monitoring.grafana.database.password;
  pomeriumRouteHost = externalHttpsBase;
  pomeriumBaseUrl = pomeriumRouteHost;
  pomeriumRedirectUri = "${externalHttpsBase}/oauth2/callback";
  pomeriumIdp = config.services.rave.pomerium.idp;
  pomeriumInlineSecret = pomeriumIdp.clientSecret or "";
  pomeriumSecretFile = pomeriumIdp.clientSecretFile;
  gitlabSchemaSeed = builtins.path {
    path = ../assets/gitlab-schema.sql;
    name = "gitlab-schema.sql";
  };
  authentikPublicUrl = "${externalHttpsBase}/";
  authentikHostPort = 9130;
  authentikMetricsPort = 9131;
  authentikDockerArchivePath = ../../../artifacts/docker/authentik-server-2024.6.2.tar;
  authentikDockerArchive =
    if builtins.pathExists authentikDockerArchivePath then
      builtins.path {
        path = authentikDockerArchivePath;
        name = "authentik-server-2024.6.2.tar";
      }
    else
      null;
  authentikSecretKeyFile = if useSecrets
    then "/run/secrets/authentik/secret-key"
    else pkgs.writeText "authentik-secret-key" "authentik-development-secret";
  authentikBootstrapPasswordFile = if useSecrets
    then "/run/secrets/authentik/bootstrap-password"
    else pkgs.writeText "authentik-bootstrap-password" "SuperSecurePassword123!";
  authentikDbPassword = "authentik-db-password";
  authentikDbPasswordFile = if useSecrets
    then "/run/secrets/database/authentik-password"
    else pkgs.writeText "authentik-db-password" authentikDbPassword;
  authentikGrafanaClientId = "rave-grafana";
  authentikGrafanaClientSecretFile = if useSecrets
    then "/run/secrets/grafana/oidc-client-secret"
    else pkgs.writeText "grafana-oidc-client-secret" "grafana-oidc-secret";
  penpotOidcClientId = "rave-penpot";
  penpotOidcClientSecretFile = if useSecrets
    then "/run/secrets/penpot/oidc-client-secret"
    else pkgs.writeText "penpot-oidc-client-secret" "penpot-oidc-secret";
  traefikBackendPort = 9443;
  traefikBackendUrl = "http://127.0.0.1:${toString traefikBackendPort}";
  authManagerListenAddr = config.services.rave.auth-manager.listenAddress or ":8088";
  authManagerPort =
    let
      listenParts = lib.splitString ":" authManagerListenAddr;
      maybePort = lib.lists.last listenParts;
    in lib.toInt (if maybePort == "" then "8088" else maybePort);
  authManagerLoopback = "http://127.0.0.1:${toString authManagerPort}";
  gitlabRailsRunner = "${config.system.path}/bin/gitlab-rails";
  traefikHost = "auth.localtest.me";

  hasLocalPostgres = config.services.rave.postgresql.enable;

  dbPasswordUnitSpecs = lib.optionals hasLocalPostgres [
    {
      name = "grafana";
      role = "grafana";
      secret = "/run/secrets/grafana/db-password";
      fallback = grafanaDbPassword;
      dependent = "grafana";
      extraScript = "";
    }
    {
      name = "mattermost";
      role = "mattermost";
      secret = "/run/secrets/database/mattermost-password";
      fallback = mattermostDbPassword;
      dependent = "mattermost";
      extraScript = "";
    }
    {
      name = "penpot";
      role = "penpot";
      secret = "/run/secrets/database/penpot-password";
      fallback = config.services.rave.penpot.database.password;
      dependent = "penpot-backend";
      extraScript = "";
    }
    {
      name = "n8n";
      role = "n8n";
      secret = "/run/secrets/database/n8n-password";
      fallback = n8nDbPassword;
      dependent = "n8n";
      extraScript = "";
    }
    {
      name = "prometheus";
      role = "prometheus";
      secret = "/run/secrets/database/prometheus-password";
      fallback = "prometheus_pass";
      dependent = "prometheus-postgres-exporter";
      extraScript =
        lib.optionalString (config.services.rave.monitoring.exporters.postgres.dsnEnvFile != null) ''
          DSN_FILE=/run/secrets/database/prometheus-dsn.env
          mkdir -p /run/secrets/database
          printf 'DATA_SOURCE_NAME=postgresql://prometheus:%s@localhost:5432/postgres?sslmode=disable\n' "$PASSWORD" > "$DSN_FILE"
          chown prometheus-postgres-exporter:prometheus-postgres-exporter "$DSN_FILE"
          chmod 0400 "$DSN_FILE"
        '';
    }
  ] ++ lib.optionals config.services.rave.authentik.enable [
    {
      name = "authentik";
      role = "authentik";
      secret = "/run/secrets/database/authentik-password";
      fallback = authentikDbPassword;
      dependent = "authentik-server";
      extraScript = "";
    }
  ];

  mkPasswordUnit = unit:
    let
      hasFallback = unit ? fallback && unit.fallback != null;
      shouldRun = useSecrets || hasFallback;
    in {
      name = "postgres-set-${unit.name}-password";
      value = lib.mkIf shouldRun {
        description = "Set ${unit.role} PostgreSQL password";
        wantedBy = [ "multi-user.target" ];
        after = [ "postgresql.service" ] ++ lib.optionals useSecrets [ "sops-init.service" ];
        requires = [ "postgresql.service" ] ++ lib.optionals useSecrets [ "sops-init.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          RemainAfterExit = true;
        };
        script = ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          ${lib.optionalString useSecrets ''
          SECRET_FILE=${lib.escapeShellArg unit.secret}
          if [ ! -s "$SECRET_FILE" ]; then
            echo "Secret missing at $SECRET_FILE for role ${unit.role}" >&2
            exit 1
          fi
          PASSWORD="$(tr -d '\n' < "$SECRET_FILE")"
          ''}
          ${lib.optionalString (!useSecrets && hasFallback) ''
          PASSWORD=${lib.escapeShellArg unit.fallback}
          ''}

          ESCAPED=''${PASSWORD//\'/\'\'}

          ${pkgs.sudo}/bin/sudo -u postgres ${config.services.postgresql.package}/bin/psql \
            -v ON_ERROR_STOP=1 -d postgres \
            -c "ALTER ROLE ${unit.role} WITH PASSWORD '$ESCAPED';"
${unit.extraScript}
        '';
      };
    };

  passwordUnitServices = lib.listToAttrs (map mkPasswordUnit dbPasswordUnitSpecs);

  mkPasswordDependency = unit:
    let
      hasFallback = unit ? fallback && unit.fallback != null;
      shouldRun = useSecrets || hasFallback;
    in {
      name = unit.dependent;
      value = lib.mkIf shouldRun {
        after = lib.mkAfter [ "postgres-set-${unit.name}-password.service" ];
        requires = lib.mkAfter [ "postgres-set-${unit.name}-password.service" ];
      };
    };

  passwordDependentOverrides = lib.listToAttrs (map mkPasswordDependency dbPasswordUnitSpecs);
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
    webhook = {
      enable = true;
      endpoint = "http://127.0.0.1:4195/hooks/outline";
      secretFile = if useSecrets then outlineWebhookSecretFile else null;
      secret = outlineWebhookSecret;
    };
  };

  services.rave.gitlab = {
    benthosWebhook = {
      enable = true;
      url = "http://127.0.0.1:4195/hooks/gitlab";
      secretFile = if useSecrets then benthosGitlabWebhookSecretFile else null;
      secret = benthosGitlabWebhookSecret;
      verifyTls = false;
    };
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

  services.rave.authentik = {
    enable = true;
    publicUrl = authentikPublicUrl;
    hostPort = authentikHostPort;
    metricsPort = authentikMetricsPort;
    dockerImageArchive = authentikDockerArchive;
    rootDomain = "auth.localtest.me";
    defaultExternalPort = baseHttpsPort;
    secretKey = if useSecrets then null else "authentik-development-secret";
    secretKeyFile = if useSecrets then authentikSecretKeyFile else null;
    bootstrap = {
      email = "admin@auth.localtest.me";
      password = if useSecrets then null else "authentik-admin-password";
      passwordFile = if useSecrets then authentikBootstrapPasswordFile else null;
    };
    database = {
      host = "127.0.0.1";
      port = 5432;
      name = "authentik";
      user = "authentik";
      password = if useSecrets then null else "authentik-db-password";
      passwordFile = if useSecrets then authentikDbPasswordFile else null;
    };
    redis = {
      database = config.services.rave.redis.allocations.authentik or 12;
    };
    email.enable = false;
    oauthSources.google.clientIdFile = lib.mkForce googleOauthClientIdFile;
    oauthSources.google.clientSecretFile = lib.mkForce googleOauthClientSecretFile;
    oauthSources.github.clientIdFile = lib.mkForce githubOauthClientIdFile;
    oauthSources.github.clientSecretFile = lib.mkForce githubOauthClientSecretFile;
    applicationProviders = {
      mattermost = {
        enable = true;
        slug = "mattermost";
        displayName = "Mattermost";
        clientId = mattermostGitlabClientId;
        clientSecretFile = mattermostOidcClientSecretFile;
        redirectUris = [ "${mattermostPublicUrl}/signup/openid/complete" ];
        scopes = [ "openid" "profile" "email" ];
        signingKeyName = "authentik Internal JWT Certificate";
        application = {
          slug = "mattermost";
          name = "Mattermost";
          launchUrl = mattermostPublicUrl;
          description = "Mattermost chat via Authentik";
        };
      };
      gitlab = {
        enable = true;
        slug = gitlabOidcSlug;
        displayName = "GitLab";
        clientId = gitlabOidcClientId;
        clientSecretFile = gitlabOidcClientSecretFile;
        redirectUris = [ "${gitlabExternalUrl}/users/auth/openid_connect/callback" ];
        scopes = [ "openid" "profile" "email" ];
        signingKeyName = "authentik Internal JWT Certificate";
        application = {
          slug = "gitlab";
          name = "GitLab";
          launchUrl = gitlabExternalUrl;
          description = "GitLab via Authentik";
        };
      };
      grafana = {
        enable = true;
        slug = "grafana";
        displayName = "Grafana";
        clientId = authentikGrafanaClientId;
        clientSecretFile = authentikGrafanaClientSecretFile;
        redirectUris = [ "https://localhost:${baseHttpsPort}/grafana/login/generic_oauth" ];
        scopes = [ "openid" "profile" "email" ];
        application = {
          slug = "grafana";
          name = "Grafana";
          launchUrl = "https://localhost:${baseHttpsPort}/grafana/";
          description = "Grafana via Authentik";
        };
      };
      penpot = {
        enable = true;
        slug = "penpot";
        displayName = "Penpot";
        clientId = penpotOidcClientId;
        clientSecretFile = penpotOidcClientSecretFile;
        redirectUris = [ "${penpotPublicUrl}/auth/oidc/callback" ];
        scopes = [ "openid" "profile" "email" ];
        application = {
          slug = "penpot";
          name = "Penpot";
          launchUrl = penpotPublicUrl;
          description = "Penpot via Authentik";
        };
      };
      outline = {
        enable = true;
        slug = "outline";
        displayName = "Outline";
        clientId = outlineOidcClientId;
        clientSecretFile = outlineOidcClientSecretFile;
        redirectUris = [ "${outlinePublicUrl}auth/oidc.callback" ];
        scopes = [ "openid" "profile" "email" ];
        application = {
          slug = "outline";
          name = "Outline";
          launchUrl = outlinePublicUrl;
          description = "Outline wiki via Authentik";
          icon = outlineIcon;
        };
      };
      n8n = {
        enable = true;
        slug = "n8n";
        displayName = "n8n";
        clientId = n8nOidcClientId;
        clientSecretFile = n8nOidcClientSecretFile;
        redirectUris = [ "${n8nPublicUrl}/rest/oauth2-credential/callback" ];
        scopes = [ "openid" "profile" "email" ];
        application = {
          slug = "n8n";
          name = "n8n";
          launchUrl = n8nPublicUrl;
          description = "n8n automations via Authentik";
        };
      };
    };
  };

  services.rave.auth-manager = {
    enable = lib.mkDefault (config.services.rave.pomerium.enable);
    listenAddress = "0.0.0.0:8088";
    openFirewall = true;
    sourceIdp = "gitlab";
    signingKey = lib.mkIf (!useSecrets) "auth-manager-dev-signing-key";
    signingKeyFile = lib.mkIf useSecrets "/run/secrets/auth-manager/signing-key";
    pomeriumSharedSecret = lib.mkIf (!useSecrets) config.services.rave.pomerium.sharedSecret;
    pomeriumSharedSecretFile = lib.mkIf useSecrets "/run/secrets/auth-manager/pomerium-shared-secret";
    mattermost = {
      url = mattermostPublicUrl;
      internalUrl = mattermostInternalBaseUrl;
      adminToken = lib.mkIf (!useSecrets) "mattermost-admin-token";
      adminTokenFile = lib.mkIf useSecrets "/run/secrets/auth-manager/mattermost-admin-token";
    };
  };

  services.rave.pomerium = {
    enable = lib.mkDefault false;
    publicUrl = pomeriumBaseUrl;
    httpPort = config.services.rave.ports.https;
    tls = {
      enable = true;
      certificateFile = "${localCertDir}/cert.pem";
      keyFile = "${localCertDir}/key.pem";
    };
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
        to = "${authManagerLoopback}/mattermost";
        allowPublicUnauthenticated = false;
        passIdentityHeaders = true;
        preserveHost = true;
      }
      {
        name = "Grafana via Pomerium";
        from = pomeriumRouteHost;
        path = "/grafana";
        to = traefikBackendUrl;
        allowPublicUnauthenticated = true;
      }
      {
        name = "RAVE Front Door";
        from = pomeriumRouteHost;
        path = "/";
        to = traefikBackendUrl;
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

  services.rave.traefik = {
    enable = true;
    host = traefikHost;
    chatDomain = null;
    behindPomerium = config.services.rave.pomerium.enable;
    backendPort = traefikBackendPort;
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
      authentik = 12;
    };
  };

  security.rave.localCerts = {
    enable = true;
    certDir = "/var/lib/acme/localhost";
    commonName = externalHost;
    serverSubject = localCertSubject;
    sanConfig = localCertSan;
  };

  services.rave.monitoring = {
    enable = true;
    retentionTime = "3d";
    grafana = {
      # Serve Grafana on the shared front door host/port
      domain = traefikHost;
      publicUrl = "${externalHttpsBase}/grafana/";
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
      enable = true;
      baseUrl = gitlabExternalUrl;
      internalUrl = gitlabInternalHttpUrl;
      apiBaseUrl = "${gitlabExternalUrl}/api/v4";
      clientId = mattermostGitlabClientId;
      clientSecretFile = mattermostGitlabClientSecretFile;
      clientSecretFallback = mattermostGitlabSecretFallback;
      apiTokenFile = gitlabApiTokenFile;
      applicationName = "RAVE Mattermost";
    };
    openid = {
      enable = false;
      clientId = mattermostGitlabClientId;
      clientSecretFile = mattermostOidcClientSecretFile;
      clientSecretFallback = mattermostGitlabSecretFallback;
      scope = "openid profile email";
      discoveryEndpoint = "${authentikPublicUrl}application/o/mattermost/.well-known/openid-configuration";
      authEndpoint = "${authentikPublicUrl}application/o/authorize/";
      tokenEndpoint = "${authentikPublicUrl}application/o/token/";
      userApiEndpoint = "${authentikPublicUrl}application/o/userinfo/";
      buttonText = "Sign in with Authentik";
      buttonColor = "#0C6DFF";
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
    ../modules/services/traefik/default.nix
    ../modules/services/postgresql/default.nix
    ../modules/services/auth-manager/default.nix
    ../modules/services/mattermost/default.nix
    ../modules/services/outline/default.nix
    ../modules/services/n8n/default.nix
    ../modules/services/authentik/default.nix
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
  defaultSopsFile = ../../../config/secrets.yaml;
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
    sopsFile = ../../../config/secrets.yaml;
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
      { selector = "[\"database\"][\"authentik-password\"]"; path = "/run/secrets/database/authentik-password"; owner = "root"; group = "postgres"; mode = "0440"; }
      { selector = "[\"database\"][\"grafana-password\"]"; path = "/run/secrets/grafana/admin-password"; owner = "grafana"; group = "grafana"; mode = "0400"; }
      { selector = "[\"outline\"][\"secret-key\"]"; path = "/run/secrets/outline/secret-key"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"outline\"][\"utils-secret\"]"; path = "/run/secrets/outline/utils-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"outline\"][\"webhook-secret\"]"; path = "/run/secrets/outline/webhook-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"benthos\"][\"gitlab-webhook-secret\"]"; path = "/run/secrets/benthos/gitlab-webhook-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"signing-key\"]"; path = "/run/secrets/auth-manager/signing-key"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"pomerium-shared-secret\"]"; path = "/run/secrets/auth-manager/pomerium-shared-secret"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"auth-manager\"][\"mattermost-admin-token\"]"; path = "/run/secrets/auth-manager/mattermost-admin-token"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"authentik\"][\"secret-key\"]"; path = "/run/secrets/authentik/secret-key"; owner = "root"; group = "root"; mode = "0400"; }
      { selector = "[\"authentik\"][\"bootstrap-password\"]"; path = "/run/secrets/authentik/bootstrap-password"; owner = "root"; group = "root"; mode = "0400"; }
    ];
    extraTmpfiles = [
      "d /run/secrets/grafana 0750 root grafana -"
      "d /run/secrets/database 0750 root postgres -"
      "d /run/secrets/outline 0750 root root -"
      "d /run/secrets/benthos 0750 root root -"
      "d /run/secrets/auth-manager 0750 root root -"
      "d /run/secrets/authentik 0750 root root -"
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
    ensureDatabases = [ "gitlab" "grafana" "mattermost" "penpot" "n8n" ]
      ++ lib.optionals config.services.rave.authentik.enable [ "authentik" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "mattermost"; ensureDBOwnership = true; }
      { name = "penpot"; ensureDBOwnership = true; }
      { name = "n8n"; ensureDBOwnership = true; }
      { name = "prometheus"; ensureDBOwnership = false; }
    ] ++ lib.optionals config.services.rave.authentik.enable [
      { name = "authentik"; ensureDBOwnership = true; }
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

      SELECT format('CREATE ROLE %I LOGIN', 'penpot')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'penpot')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'authentik')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authentik')
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

      SELECT format('CREATE DATABASE %I OWNER %I', 'penpot', 'penpot')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'penpot')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'n8n', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'n8n')
      \gexec

      SELECT format('CREATE DATABASE %I OWNER %I', 'authentik', 'authentik')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'authentik')
      \gexec

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

      -- Penpot database setup
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'penpot') THEN
          CREATE ROLE penpot WITH LOGIN;
        END IF;
      END
      $$;
      GRANT ALL PRIVILEGES ON DATABASE penpot TO penpot;
      ALTER DATABASE penpot OWNER TO penpot;
      GRANT USAGE ON SCHEMA public TO penpot;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO penpot;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO penpot;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO penpot;

      -- n8n database setup
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n') THEN
          CREATE ROLE n8n WITH LOGIN;
        END IF;
      END
      $$;
      GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
      ALTER DATABASE n8n OWNER TO n8n;
      GRANT USAGE ON SCHEMA public TO n8n;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO n8n;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO n8n;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n;

      -- Authentik database setup
      GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;
      ALTER DATABASE authentik OWNER TO authentik;
      GRANT USAGE ON SCHEMA public TO authentik;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authentik;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authentik;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authentik;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authentik;

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
    host    all     all     10.244.0.0/16   md5
    host    all     all     10.0.0.0/8      md5
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
      gitlab-pomerium-oauth = lib.mkIf config.services.rave.pomerium.enable {
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
    host = traefikHost;
    useSecrets = true;
    publicUrl = gitlabExternalUrl;
    externalPort = 18443;
    databaseSeedFile = gitlabSchemaSeed;
    runner.enable = false;
    oauth = {
      enable = true;
      provider = "authentik";
      clientId = gitlabOidcClientId;
      clientSecretFile = gitlabOidcClientSecretFile;
      autoSignIn = true;
      autoLinkUsers = true;
      allowLocalSignin = false;
      authentik = {
        slug = gitlabOidcSlug;
        scope = "openid profile email";
        issuer = gitlabOidcIssuer;
        caFile = localCaPath;
      };
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
      8080  # GitLab internal
      3000  # Grafana internal
      8065  # Mattermost internal
      9090  # Prometheus internal
      8222  # NATS monitoring
      5000  # GitLab registry
      4222  # NATS
    ];
  };

  system.extraDependencies = [ gitlabSchemaSeed ];

}
