# nixos/modules/services/gitlab/default.nix
# GitLab service configuration module - extracted from P3 production config
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.gitlab;
  oauthCfg = cfg.oauth;
  redisPlatform = config.services.rave.redis.platform or {};
  redisHostLocal = redisPlatform.host or "127.0.0.1";
  redisPort = redisPlatform.port or 6379;
  redisUnit = redisPlatform.unit or "redis-main.service";
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
  boolToString = value: if value then "true" else "false";

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

  useSecrets = cfg.useSecrets;

  secretPath = name: fallback:
    if useSecrets then
      config.sops.secrets."gitlab/${name}".path or "/run/secrets/gitlab/${name}"
    else fallback;

  rootPasswordFile = secretPath "root-password"
    (pkgs.writeText "gitlab-root-password" "development-password");

  dbPasswordFile = secretPath "db-password"
    (pkgs.writeText "gitlab-db-password-dummy" "dummy");

  secretKeyBaseFile = secretPath "secret-key-base"
    (pkgs.writeText "gitlab-secret-key-base" "development-secret-key-base-dummy");

  dbKeyBaseFile = secretPath "db-key-base"
    (pkgs.writeText "gitlab-db-key-base" "development-db-key-base-dummy");

  otpKeyBaseFile = secretPath "otp-key-base"
    (pkgs.writeText "gitlab-otp-key-base" "development-otp-key-base-dummy");

  jwsKeyBaseFile = secretPath "jws-key-base"
    (pkgs.writeText "jwt-signing-key" "development-jwt-signing-key-dummy");

  gitlabApiTokenFile = secretPath "api-token"
    (pkgs.writeText "gitlab-api-token" "development-token");

  gitlabApiBaseUrl = "${lib.removeSuffix "/" cfg.publicUrl}/api/v4";

  ensureGitlabBenthosHookScript = pkgs.writeScript "ensure-gitlab-benthos-webhook.py" ''
#!${pythonWithRequests}/bin/python3
import os
import time
from pathlib import Path
from typing import Any

import requests


def read_optional(path: str | None) -> str | None:
    if not path:
        return None
    data = Path(path)
    if not data.exists():
        raise SystemExit(f"secret file missing: {path}")
    content = data.read_text(encoding="utf-8").strip()
    if not content:
        raise SystemExit(f"secret file {path} was empty")
    return content


def parse_verify_flag(raw: str | None) -> Any:
    if raw is None:
        return False
    value = raw.strip().lower()
    if value in ("", "false", "0", "no", "off"):
        return False
    if value in ("true", "1", "yes", "on"):
        return True
    return raw


def wait_for_gitlab(session: requests.Session, base_url: str) -> None:
    version_url = f"{base_url}/version"
    for _ in range(60):
        try:
            response = session.get(version_url, timeout=5)
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(5)
    raise SystemExit("GitLab API did not become ready")


def ensure_system_hook(session: requests.Session, base_url: str, hook_url: str, secret_token: str | None) -> None:
    hooks_url = f"{base_url}/hooks"
    try:
        response = session.get(hooks_url, timeout=10)
    except requests.RequestException as exc:
        raise SystemExit(f"failed to list GitLab system hooks: {exc}") from exc

    if response.status_code != 200:
        raise SystemExit(f"failed to list GitLab system hooks: {response.status_code} {response.text}")

    try:
        hooks = response.json()
    except ValueError as exc:
        raise SystemExit(f"GitLab hooks response was not JSON: {exc}") from exc

    for hook in hooks:
        if hook.get("url") == hook_url:
            return

    payload = {
        "url": hook_url,
        "enable_ssl_verification": False,
        "push_events": True,
        "issues_events": True,
        "confidential_issues_events": True,
        "merge_requests_events": True,
        "tag_push_events": True,
        "note_events": True,
        "job_events": True,
        "pipeline_events": True,
        "deployment_events": True,
        "wiki_page_events": True,
        "releases_events": True,
    }
    if secret_token:
        payload["token"] = secret_token

    try:
        response = session.post(hooks_url, json=payload, timeout=10)
    except requests.RequestException as exc:
        raise SystemExit(f"failed to create GitLab system hook: {exc}") from exc

    if response.status_code not in (200, 201, 204):
        raise SystemExit(f"failed to create GitLab system hook: {response.status_code} {response.text}")


def main() -> None:
    gitlab_base = os.environ.get("GITLAB_API_BASE_URL", "https://localhost:8443/gitlab/api/v4").rstrip("/")
    token_file = os.environ.get("GITLAB_API_TOKEN_FILE")
    if not token_file:
        raise SystemExit("GITLAB_API_TOKEN_FILE is required")

    hook_url = os.environ.get("BENTHOS_WEBHOOK_URL", "http://127.0.0.1:4195/hooks/gitlab").rstrip("/")
    secret_file = os.environ.get("BENTHOS_WEBHOOK_SECRET_FILE")
    verify_flag = parse_verify_flag(os.environ.get("GITLAB_VERIFY_TLS"))

    token = read_optional(token_file)
    if not token:
        raise SystemExit("GitLab API token file was empty")
    secret_token = read_optional(secret_file) if secret_file else None

    session = requests.Session()
    session.headers["PRIVATE-TOKEN"] = token
    session.verify = verify_flag

    wait_for_gitlab(session, gitlab_base)
    ensure_system_hook(session, gitlab_base, hook_url, secret_token)


if __name__ == "__main__":
    main()
'';

  systemctl = lib.getExe' pkgs.systemd "systemctl";

in
{

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

      publicUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab";
        description = "Externally reachable GitLab URL (used for Omniauth redirects).";
      };

      externalPort = mkOption {
        type = types.int;
        default = 8443;
        description = "Port advertised to clients for GitLab HTTPS.";
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

      benthosWebhook = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Ensure a GitLab system hook forwards events to the Benthos ingress.";
        };

        url = mkOption {
          type = types.str;
          default = "http://127.0.0.1:4195/hooks/gitlab";
          description = "Local Benthos HTTP endpoint that receives GitLab events.";
        };

        secretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Optional secret token file attached to the GitLab webhook.";
        };

        secret = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Literal secret token for the GitLab webhook (dev/test convenience).";
        };

        verifyTls = mkOption {
          type = types.bool;
          default = false;
          description = "Verify GitLab TLS certificates when calling the API.";
        };
      };

      databaseSeedFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional SQL dump applied to the `gitlab` PostgreSQL database before GitLab's migrations run.
          Populate this with a schema-only `pg_dump` from a previously migrated instance to skip the costly
          first-boot migration step. When unset, the service falls back to the normal migration flow.
        '';
        example = ./artifacts/gitlab/schema.sql;
      };
    };
  };
  
  config = mkIf cfg.enable (
    let
      seedWanted = cfg.databaseSeedFile != null;
      gitlabSeedScript =
        if !seedWanted then null else
        pkgs.writeShellScript "gitlab-db-seed.sh" ''
          set -euo pipefail

          SEED_FILE=${lib.escapeShellArg cfg.databaseSeedFile}
          if [ ! -s "$SEED_FILE" ]; then
            echo "GitLab seed file missing or empty at $SEED_FILE" >&2
            exit 1
          fi

          while ! ${pkgs.postgresql_15}/bin/pg_isready -d gitlab >/dev/null 2>&1; do
            sleep 2
          done

          HAS_SCHEMA="$(${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_15}/bin/psql -d gitlab -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations';" || true)"

          if [ -n "$HAS_SCHEMA" ]; then
            echo "GitLab schema already present; skipping seed import."
            exit 0
          fi

          echo "📥 Importing GitLab schema from $SEED_FILE ..."
          ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_15}/bin/psql -v ON_ERROR_STOP=1 -d gitlab -f "$SEED_FILE"
        '';
    in {
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
      initialRootPasswordFile = rootPasswordFile;
      databasePasswordFile = dbPasswordFile;
        
      # All required secrets for GitLab
      secrets = {
        secretFile = secretKeyBaseFile;
        otpFile = otpKeyBaseFile;
        dbFile = dbKeyBaseFile;
        jwsFile = jwsKeyBaseFile;
        
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
                  block_auto_created_users = false;
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
          baseConfig = {
            gitlab = {
              host = cfg.host;
              port = cfg.externalPort;
              https = true;
              relative_url_root = "/gitlab";
              max_request_size = "10G";
              workhorse = {
                memory_limit = "8G";
                cpu_limit = "50%";
              };
            };

            omniauth = {
              full_host = cfg.publicUrl;
            };

            registry = {
              enable = true;
              host = "registry.${cfg.host}";
              port = 5000;
            };

            artifacts = {
              enabled = true;
              path = "/var/lib/gitlab/artifacts";
              max_size = "10G";
            };

            lfs = {
              enabled = true;
              storage_path = "/var/lib/gitlab/lfs";
            };

            redis = {
              host = redisHostLocal;
              port = redisPort;
            };

            nginx = {
              enable = false;
            };
          };
        in lib.recursiveUpdate baseConfig oauthSettings;
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
    
    # Fix: Add postgres user to gitlab group via systemd service
    # This resolves the gitlab-db-password.service failure where postgres user
    # cannot read /run/secrets/gitlab/db-password due to group permissions
    systemd.services.postgres-gitlab-group-fix = {
      description = "Add postgres user to gitlab group for secret access";
      wantedBy = [ "multi-user.target" ];
      before = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = ''
        # Add postgres user to gitlab group
        ${pkgs.shadow}/bin/usermod -a -G gitlab postgres
        echo "Added postgres user to gitlab group"
      '';
    };

    systemd.services.gitlab-benthos-webhook = lib.mkIf cfg.benthosWebhook.enable {
      description = "Ensure GitLab system hook for Benthos";
      wantedBy = [ "multi-user.target" ];
      after = [ "gitlab.service" "network-online.target" ];
      requires = [ "gitlab.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        TimeoutStartSec = "600s";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      environment = lib.mkMerge [
        {
          GITLAB_API_TOKEN_FILE = gitlabApiTokenFile;
          GITLAB_API_BASE_URL = gitlabApiBaseUrl;
          GITLAB_VERIFY_TLS = boolToString cfg.benthosWebhook.verifyTls;
          BENTHOS_WEBHOOK_URL = cfg.benthosWebhook.url;
        }
        (lib.optionalAttrs (cfg.benthosWebhook.secretFile != null) {
          BENTHOS_WEBHOOK_SECRET_FILE = cfg.benthosWebhook.secretFile;
        })
        (lib.optionalAttrs (cfg.benthosWebhook.secretFile == null && cfg.benthosWebhook.secret != null) {
          BENTHOS_WEBHOOK_SECRET = cfg.benthosWebhook.secret;
        })
      ];
      script = ''
        set -euo pipefail
        ${ensureGitlabBenthosHookScript}
      '';
    };

    # Firewall configuration for GitLab services
    networking.firewall.allowedTCPPorts = [ 
      8080  # GitLab
      5000  # Container registry
    ];
    
    # Service resource limits from P3
    systemd.services.gitlab = {
      serviceConfig = {
        MemoryMax = "8G";
        CPUQuota = "50%";
        OOMScoreAdjust = "50";
      };
      environment = {
        RAILS_RELATIVE_URL_ROOT = "/gitlab";
        GITLAB_OMNIAUTH_FULL_HOST = cfg.publicUrl;
      };
      after = mkAfter [
        "postgresql.service"
        redisUnit
        "generate-localhost-certs.service"
        "gitlab-password-setup.service"
      ];
      requires = mkAfter [ "postgresql.service" redisUnit "gitlab-password-setup.service" ];
    };
    
    systemd.services.gitlab-runner.serviceConfig = mkIf config.services.rave.gitlab.runner.enable {
      MemoryMax = "4G";
      CPUQuota = "25%";
      OOMScoreAdjust = "100";
    };

    systemd.services."gitlab-db-config" =
      {
        unitConfig = mkMerge [
          { OnSuccess = [ "gitlab-autostart.service" ]; }
          (mkIf cfg.useSecrets {
            ConditionPathExists = dbPasswordFile;
          })
        ];
      }
      // (mkIf seedWanted {
        after = mkAfter [ "gitlab-db-seed.service" ];
        requires = mkAfter [ "gitlab-db-seed.service" ];
      });

    systemd.services."gitlab-autostart" = {
      description = "Ensure GitLab starts after database configuration";
      wantedBy = [ "multi-user.target" ];
      after = [
        "postgresql.service"
        redisUnit
        "gitlab-config.service"
        "gitlab-db-config.service"
      ];
      wants = [ "gitlab-db-config.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "gitlab-autostart.sh" ''
          set -euo pipefail

          systemctl_bin='${systemctl}'
          attempts=0
          max_attempts=12

          while ! "$systemctl_bin" is-active --quiet gitlab-db-config.service; do
            if (( attempts >= max_attempts )); then
              echo "gitlab-db-config.service did not become active" >&2
              exit 1
            fi

            if "$systemctl_bin" is-failed --quiet gitlab-db-config.service; then
              "$systemctl_bin" reset-failed gitlab-db-config.service || true
              "$systemctl_bin" start gitlab-db-config.service || true
            fi

            attempts=$(( attempts + 1 ))
            sleep $(( 5 * attempts ))
          done

          "$systemctl_bin" reset-failed gitlab.service || true
          "$systemctl_bin" start gitlab.service
          "$systemctl_bin" reset-failed gitlab-sidekiq.service || true
          "$systemctl_bin" start gitlab-sidekiq.service
        '';
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    systemd.services.gitlab-password-setup = {
      description = "Set GitLab database password from SOPS secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ] ++ lib.optionals cfg.useSecrets [ "sops-init.service" ];
      requires = [ "postgresql.service" ] ++ lib.optionals cfg.useSecrets [ "sops-init.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      environment.PATH = lib.mkForce "${pkgs.postgresql_15}/bin:${pkgs.sudo}/bin:${pkgs.coreutils}/bin";
      script = ''
        while ! ${pkgs.postgresql_15}/bin/pg_isready -d postgres > /dev/null 2>&1; do
          echo "Waiting for PostgreSQL to be ready..."
          sleep 2
        done

        if [ ! -s ${dbPasswordFile} ]; then
          echo "GitLab DB password file missing: ${dbPasswordFile}"
          exit 1
        fi

        GITLAB_PASSWORD=$(cat ${dbPasswordFile})

        sudo -u postgres ${pkgs.postgresql_15}/bin/psql -d postgres -c \
          "DO \$\$ BEGIN
             IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'gitlab') THEN
               CREATE ROLE gitlab WITH LOGIN CREATEDB;
             END IF;
           END \$\$;" || {
          echo "Failed to create GitLab role"
          exit 1
        }

        echo "ALTER ROLE gitlab WITH PASSWORD '$GITLAB_PASSWORD';" | \
          sudo -u postgres ${pkgs.postgresql_15}/bin/psql -d postgres || {
          echo "Failed to set GitLab password"
          exit 1
        }
        echo "GitLab database password successfully updated"
      '';
    };

    systemd.services.postgresql = {
      after = mkAfter [ "postgres-gitlab-group-fix.service" ];
      wants = mkAfter [ "postgres-gitlab-group-fix.service" ];
    };
    systemd.services.gitlab-db-seed = mkIf seedWanted {
      description = "Preload GitLab database from seed file";
      wantedBy = [ "gitlab-db-config.service" ];
      before = [ "gitlab-db-config.service" ];
      after =
        [ "postgresql.service" "gitlab-password-setup.service" ]
        ++ lib.optionals cfg.useSecrets [ "sops-init.service" ];
      requires = [ "postgresql.service" "gitlab-password-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = gitlabSeedScript;
      };
    };
  });
}
