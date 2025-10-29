# nixos/configs/complete-production.nix
# Complete, consolidated NixOS VM configuration with ALL services pre-configured
{ config, pkgs, lib, ... }:

let
  useSecrets = config.services.rave.gitlab.useSecrets;
  gitlabDbPasswordFile = if useSecrets
    then config.sops.secrets."gitlab/db-password".path
    else pkgs.writeText "gitlab-db-password" "gitlab-production-password";
  googleOauthClientId = "729118765955-7l2hgo3nrjaiol363cp8avf3m97shjo8.apps.googleusercontent.com";
  gitlabExternalUrl = "https://localhost:18221/gitlab";
  gitlabRailsRunner = "${config.system.path}/bin/gitlab-rails";
  gitlabPackage = config.services.gitlab.packages.gitlab;
  mattermostPkg = config.services.mattermost.package or pkgs.mattermost;
  mattermostPublicUrl = "https://localhost:18231/mattermost";
  mattermostPath =
    let
      matchResult = builtins.match "https://[^/]+(.*)" mattermostPublicUrl;
    in
    if matchResult == null || matchResult == [] then "" else builtins.head matchResult;
  mattermostLoginPath =
    if mattermostPath == "" then "/oauth/gitlab/login" else "${mattermostPath}/oauth/gitlab/login";
  mattermostLoginUrl = "${mattermostPublicUrl}/oauth/gitlab/login";
  mattermostBrandHtml = "Use the GitLab button below to sign in. If it does not appear, open ${mattermostLoginPath} manually.";
  mattermostGitlabClientId = "rave-mattermost";
  mattermostGitlabClientSecret = "rave-mattermost-secret";
  mattermostGitlabRedirectUri = "${mattermostPublicUrl}/signup/gitlab/complete";
  gitlabSettingsJSON = builtins.toJSON {
    Enable = true;
    EnableSync = true;
    Id = mattermostGitlabClientId;
    Secret = mattermostGitlabClientSecret;
    Scope = "read_user";
    AuthEndpoint = "${gitlabExternalUrl}/oauth/authorize";
    TokenEndpoint = "${gitlabExternalUrl}/oauth/token";
    UserAPIEndpoint = "${gitlabExternalUrl}/api/v4/user";
  };
  updateMattermostScript = pkgs.writeText "update-mattermost-config.py" ''
#!/usr/bin/env python3
import json
from pathlib import Path

CONFIG_PATH = Path("/var/lib/mattermost/config/config.json")
LOG_PATH = Path("/var/lib/rave/update-mattermost-config.log")
SITE_URL = ${builtins.toJSON mattermostPublicUrl}
BRAND_TEXT = ${builtins.toJSON mattermostBrandHtml}
GITLAB_SETTINGS = json.loads(${builtins.toJSON gitlabSettingsJSON})


def main() -> None:
    if not CONFIG_PATH.exists():
        LOG_PATH.write_text("config.json missing\n")
        return

    config = json.loads(CONFIG_PATH.read_text())

    service = config.setdefault("ServiceSettings", {})
    service["SiteURL"] = SITE_URL

    team = config.setdefault("TeamSettings", {})
    team["EnableCustomBrand"] = True
    team["CustomDescriptionText"] = ""
    team["CustomBrandText"] = BRAND_TEXT

    gitlab = config.setdefault("GitLabSettings", {})
    gitlab.update(GITLAB_SETTINGS)

    config.pop("GoogleSettings", None)

    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n")
    LOG_PATH.write_text("updated:gitlab\n")


if __name__ == "__main__":
    main()
  '';
in
{
  imports = [
    # Foundation modules
    ../modules/foundation/base.nix
    ../modules/foundation/networking.nix
    ../modules/foundation/nix-config.nix

    # Service modules
    ../modules/services/gitlab/default.nix

    # Security modules
    # ../modules/security/certificates.nix  # DISABLED: Using inline certificate generation instead
    ../modules/security/hardening.nix
  ];

sops = lib.mkIf config.services.rave.gitlab.useSecrets {
  defaultSopsFile = ../../config/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
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
      restartUnits = [ "mattermost.service" ];
    };
    "mattermost/admin-email" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/mattermost/admin-email";
      restartUnits = [ "mattermost.service" ];
    };
    "mattermost/admin-password" = {
      owner = "root";
      group = "root";
      mode = "0400";
      path = "/run/secrets/mattermost/admin-password";
      restartUnits = [ "mattermost.service" ];
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
      restartUnits = [ "gitlab-db-password.service" ];
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
  };
};

  systemd.services.mattermost.preStart = lib.mkMerge [
    (lib.mkBefore ''
      if [ -d /var/lib/mattermost/client ] && [ ! -L /var/lib/mattermost/client ]; then
        ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/client
      fi
    '')
    (lib.mkAfter ''
    SITE_URL=${lib.escapeShellArg mattermostPublicUrl} \
    GITLAB_BASE=${lib.escapeShellArg gitlabExternalUrl} \
    GITLAB_CLIENT_ID=${lib.escapeShellArg mattermostGitlabClientId} \
    GITLAB_SECRET=${lib.escapeShellArg mattermostGitlabClientSecret} \
    GITLAB_REDIRECT=${lib.escapeShellArg mattermostGitlabRedirectUri} \
    ${pkgs.python3}/bin/python3 <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

config_path = Path('/var/lib/mattermost/config/config.json')
if not config_path.exists():
    raise SystemExit(0)

site_url = os.environ.get('SITE_URL', 'https://localhost:18231/mattermost').rstrip('/')
login_url = f"{site_url}/oauth/gitlab/login"
login_path = urlparse(login_url).path or "/oauth/gitlab/login"
gitlab_base = os.environ.get('GITLAB_BASE', 'https://localhost:18221/gitlab').rstrip('/')
gitlab_client_id = os.environ.get("GITLAB_CLIENT_ID", "")
gitlab_secret = os.environ.get("GITLAB_SECRET", "")
gitlab_redirect = os.environ.get("GITLAB_REDIRECT", "")
brand_html = "Use the GitLab button below to sign in. If it does not appear, open {path} manually.".format(
    path=login_path
)

config = json.loads(config_path.read_text())

service = config.setdefault('ServiceSettings', {})
service['SiteURL'] = site_url

team = config.setdefault('TeamSettings', {})
team['EnableCustomBrand'] = True
team['CustomDescriptionText'] = ""
team['CustomBrandText'] = brand_html

gitlab = config.setdefault('GitLabSettings', {})
gitlab['Enable'] = True
gitlab['Id'] = gitlab_client_id
gitlab['Secret'] = gitlab_secret
gitlab['Scope'] = 'read_user'
gitlab['AuthEndpoint'] = f"{gitlab_base}/oauth/authorize"
gitlab['TokenEndpoint'] = f"{gitlab_base}/oauth/token"
gitlab['UserAPIEndpoint'] = f"{gitlab_base}/api/v4/user"
gitlab['DiscoveryEndpoint'] = ""
gitlab['EnableAuth'] = True
gitlab['EnableSync'] = True
gitlab['AutoLogin'] = False
gitlab['RedirectUri'] = gitlab_redirect
config.pop('GoogleSettings', None)

config_path.write_text(json.dumps(config, indent=2) + '\n')
PY
    ${pkgs.coreutils}/bin/mkdir -p /var/lib/mattermost
    ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/.client-tmp
    ${pkgs.coreutils}/bin/cp -R ${mattermostPkg}/client /var/lib/mattermost/.client-tmp
    ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/client
    ${pkgs.coreutils}/bin/mv /var/lib/mattermost/.client-tmp /var/lib/mattermost/client
    ${pkgs.coreutils}/bin/chown -R mattermost:mattermost /var/lib/mattermost/client
    ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX /var/lib/mattermost/client
    ${pkgs.coreutils}/bin/install -Dm755 ${updateMattermostScript} /var/lib/rave/update-mattermost-config.py
  '')
  ];

  # ===== SYSTEM FOUNDATION =====
  
  # Boot configuration
  boot.loader.grub.device = "/dev/vda";
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" "vmw_pvscsi" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
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
    ensureDatabases = [ "gitlab" "grafana" "penpot" "mattermost" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "penpot"; ensureDBOwnership = true; }
      { name = "mattermost"; ensureDBOwnership = true; }
      { name = "prometheus"; ensureDBOwnership = false; }
    ];
    
    # Optimized settings for VM environment
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
    
    # Initialize all databases with proper permissions
    initialScript = pkgs.writeText "postgres-init.sql" ''
      -- Ensure required roles exist
      SELECT format('CREATE ROLE %I LOGIN', 'gitlab')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gitlab')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'grafana')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'penpot')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'penpot')
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

      SELECT format('CREATE DATABASE %I OWNER %I', 'penpot', 'penpot')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'penpot')
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

      -- Penpot database setup  
      GRANT ALL PRIVILEGES ON DATABASE penpot TO penpot;
      ALTER USER penpot WITH PASSWORD 'penpot-production-password';

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

  # Prometheus monitoring
  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "3d";
    
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "localhost:9090" ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
      {
        job_name = "nginx";
        static_configs = [{ targets = [ "localhost:9113" ]; }];
      }
      {
        job_name = "postgres";
        static_configs = [{ targets = [ "localhost:9187" ]; }];
      }
      {
        job_name = "redis";
        static_configs = [{ targets = [ "localhost:9121" ]; }];
      }
      {
        job_name = "nats";
        static_configs = [{ targets = [ "localhost:7777" ]; }];
      }
    ];
  };

  # Prometheus exporters
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" "processes" "cpu" "meminfo" "diskstats" "filesystem" ];
    };
    
    nginx = {
      enable = true;
      port = 9113;
    };
    
    postgres = {
      enable = true;
      port = 9187;
      dataSourceName = "postgresql://prometheus:prometheus_pass@localhost:5432/postgres?sslmode=disable";
    };
    
    redis = {
      enable = true;
      port = 9121;
    };
  };

  # ===== GITLAB SERVICE =====


  # ===== GRAFANA SERVICE =====

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_port = 3000;
        domain = "localhost";  # Changed from rave.local to localhost  
        root_url = "https://localhost:18221/grafana/";
        serve_from_sub_path = true;
      };

      database = {
        type = "postgres";
        host = "localhost:5432";
        name = "grafana";
        user = "grafana";
        password = "grafana-production-password";
      };

      security = {
        admin_user = "admin";
        admin_password = "admin123";
        secret_key = "grafana-production-secret-key";
        cookie_secure = true;
        cookie_samesite = "strict";
      };

      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
    };

    # Pre-configured datasources
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
        }
        {
          name = "PostgreSQL";
          type = "postgres";
          access = "proxy";
          url = "localhost:5432";
          database = "postgres";
          user = "grafana";
          password = "grafana-production-password";
        }
      ];
    };
  };

  # ===== MATTERMOST CHAT =====

  services.mattermost = {
    enable = true;
    localDatabaseCreate = false;
    siteUrl = mattermostPublicUrl;
    siteName = "RAVE Mattermost";
    mutableConfig = true;
    extraConfig = {
      ServiceSettings = {
        EnableLocalMode = false;
      };
      EmailSettings = {
        EnableSignUpWithEmail = false;
        EnableSignInWithEmail = false;
        EnableSignInWithUsername = false;
      };
      TeamSettings = {
        EnableCustomBrand = true;
        CustomDescriptionText = "";
        CustomBrandText = mattermostBrandHtml;
      };
      GitLabSettings = {
        Enable = true;
        EnableSync = true;
        AuthEndpoint = "${gitlabExternalUrl}/oauth/authorize";
        TokenEndpoint = "${gitlabExternalUrl}/oauth/token";
        UserAPIEndpoint = "${gitlabExternalUrl}/api/v4/user";
        Id = mattermostGitlabClientId;
        Secret = mattermostGitlabClientSecret;
        Scope = "read_user";
      };
    };
    # Use Mattermost defaults for data and log directories

    environmentFile = if config.services.rave.gitlab.useSecrets
      then config.sops.secrets."mattermost/env".path
      else pkgs.writeText "mattermost-env" ''
        MM_SERVICESETTINGS_SITEURL=${mattermostPublicUrl}
        MM_SERVICESETTINGS_ENABLELOCALMODE=false
        MM_SQLSETTINGS_DRIVERNAME=postgres
        MM_SQLSETTINGS_DATASOURCE=postgres://mattermost:mmpgsecret@localhost:5432/mattermost?sslmode=disable&connect_timeout=10
        MM_BLEVESETTINGS_INDEXDIR=/var/lib/mattermost/bleve-indexes
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
        then config.sops.secrets."gitlab/oauth-provider-client-secret".path
        else pkgs.writeText "gitlab-oauth-client-secret" "development-client-secret";
      autoSignIn = false;
      autoLinkUsers = true;
      allowLocalSignin = true;
    };
  };

  services.gitlab.extraConfig.gitlab.omniauth.full_host = lib.mkForce gitlabExternalUrl;
  systemd.services.gitlab.environment.GITLAB_OMNIAUTH_FULL_HOST = gitlabExternalUrl;
  services.gitlab.extraConfig.gitlab.port = lib.mkForce 18221;

  systemd.services.gitlab-mattermost-oauth = {
    description = "Ensure GitLab OAuth client for Mattermost exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "gitlab.service" ];
    wants = [ "gitlab.service" ];
    requires = [ "gitlab.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gitlab";
      Group = "gitlab";
      TimeoutStartSec = "60s";
      RemainAfterExit = false;
    };
    environment = {
      HOME = "/var/gitlab/state/home";
      RAILS_ENV = "production";
    };
    script = ''
      set -euo pipefail
      cd /var/gitlab/state
      ${gitlabRailsRunner} runner - <<'RUBY'
redirect_uri = '${mattermostGitlabRedirectUri}'
uid = '${mattermostGitlabClientId}'
secret = '${mattermostGitlabClientSecret}'
name = 'RAVE Mattermost'
scopes = 'read_user'

app = Doorkeeper::Application.find_or_initialize_by(uid: uid)
app.name = name
app.redirect_uri = redirect_uri
app.secret = secret
app.scopes = scopes
app.confidential = true
app.trusted = true if app.respond_to?(:trusted=)
app.save!
RUBY
    '';
  };

  systemd.services.mattermost.after = lib.mkAfter [ "gitlab-mattermost-oauth.service" ];

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
          port = 8221;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 8220;
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
                              <div class="service-url">https://localhost:18221/gitlab/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/grafana/" class="service-card">
                              <div class="service-title">📊 Grafana</div>
                              <div class="service-desc">Monitoring dashboards and analytics</div>
                              <div class="service-url">https://localhost:18221/grafana/</div>
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
                              <div class="service-url">https://localhost:18221/prometheus/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/nats/" class="service-card">
                              <div class="service-title">⚡ NATS JetStream</div>
                              <div class="service-desc">High-performance messaging system</div>
                              <div class="service-url">https://localhost:18221/nats/</div>
                              <span class="status active">Active</span>
                          </a>
                      </div>
                  </div>
              </body>
              </html>
            '';
          };

          "/login" = {
            return = "302 ${mattermostPublicUrl}/";
          };

          "= /" = {
            return = "302 ${mattermostPublicUrl}/";
          };

          "/grafana/" = {
            proxyPass = "http://127.0.0.1:3000/";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };

          "/prometheus/" = {
            proxyPass = "http://127.0.0.1:9090/";
            extraConfig = ''
              proxy_set_header Host "$host:$rave_forwarded_port";
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
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

      locations."= /" = {
        return = "302 /mattermost/";
      };

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
  systemd.services."gitlab-db-config".unitConfig.OnSuccess = [ "gitlab-autostart.service" ];

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
    postgresql.postStart = ''
      # Wait for PostgreSQL to be ready
      sleep 5

      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER grafana PASSWORD 'grafana-production-password';" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER penpot PASSWORD 'penpot-production-password';" || true

      # Grant additional permissions
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT CONNECT ON DATABASE postgres TO grafana;" || true
      ${pkgs.postgresql}/bin/psql -U postgres -c "GRANT USAGE ON SCHEMA public TO grafana;" || true
    '';
    "gitlab-db-password" = lib.mkIf useSecrets {
      description = "Synchronize GitLab database role password from sops secret";
      wantedBy = [ "multi-user.target" ];
      requiredBy = [ "gitlab-db-config.service" ];
      before = [ "gitlab-db-config.service" ];
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        TimeoutStartSec = "180s";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        password_file='${gitlabDbPasswordFile}'
        if [ ! -r "$password_file" ]; then
          echo "gitlab-db-password: missing password secret at $password_file" >&2
          exit 1
        fi

        for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
          if ${pkgs.postgresql}/bin/pg_isready -q -d postgres; then
            break
          fi
          sleep 2
        done

        if ! ${pkgs.postgresql}/bin/pg_isready -q -d postgres; then
          echo "gitlab-db-password: PostgreSQL did not become ready" >&2
          exit 1
        fi

        password="$(${pkgs.coreutils}/bin/tr -d '\n' < "$password_file")"
        if [ -z "$password" ]; then
          echo "gitlab-db-password: secret file was empty" >&2
          exit 1
        fi

        ${pkgs.postgresql}/bin/psql \
          --set=ON_ERROR_STOP=1 \
          -v pass="$password" \
          -d postgres <<'SQL'
ALTER ROLE gitlab WITH PASSWORD :'pass';
SQL
      '';
    };

    # GitLab depends on database and certificates
    gitlab.after = [
      "postgresql.service"
      "gitlab-db-password.service"
      "gitlab-db-config.service"
      "redis-main.service"
      "generate-localhost-certs.service"
    ];
    gitlab.requires = [
      "postgresql.service"
      "gitlab-db-password.service"
      "gitlab-db-config.service"
      "redis-main.service"
    ];
    "gitlab-db-config".after = lib.mkAfter [ "postgresql.service" "gitlab-db-password.service" ];
    "gitlab-db-config".requires = lib.mkAfter [ "gitlab-db-password.service" ];
    
    # Grafana depends on database and certificates
    grafana.after = [ "postgresql.service" "generate-localhost-certs.service" ];
    grafana.requires = [ "postgresql.service" ];
    
    # nginx depends on certificates and all backend services
    nginx.after = [ 
      "generate-localhost-certs.service" 
      "gitlab.service"
      "grafana.service" 
      "mattermost.service"
      "prometheus.service"
      "nats.service"
    ];
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
echo "  GitLab HTTPS : https://localhost:18221/gitlab/"
echo "  Mattermost   : ${mattermostPublicUrl}/"
echo "  Grafana      : https://localhost:18221/grafana/"
echo "  Prometheus   : http://localhost:19090/"
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
echo "   🦊 GitLab:      https://localhost:18221/gitlab/"
echo "   📊 Grafana:     https://localhost:18221/grafana/"  
echo "   💬 Mattermost:  https://localhost:18231/mattermost/"
echo "   🔍 Prometheus:  https://localhost:18221/prometheus/"
echo "   ⚡ NATS:        https://localhost:18221/nats/"
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status postgresql redis-main nats prometheus grafana gitlab mattermost rave-chat-bridge nginx --no-pager -l
echo ""
echo "🌐 Dashboard: https://localhost:18221/"
echo ""
EOF
      chmod +x /root/welcome.sh
      echo "/root/welcome.sh" >> /root/.bashrc
    '';
  };
}
