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
  gitlabRailsRunner = "${config.system.path}/bin/gitlab-rails";
  gitlabPackage = config.services.gitlab.packages.gitlab;
  mattermostPkg = config.services.mattermost.package or pkgs.mattermost;
  mattermostPublicUrl = "https://localhost:${baseHttpsPort}/mattermost";
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
  mattermostGitlabRedirectUri = "${mattermostPublicUrl}/signup/gitlab/complete";
  gitlabSettingsJSON = builtins.toJSON {
    Enable = true;
    EnableSync = true;
    Id = mattermostGitlabClientId;
    Scope = "read_user";
    AuthEndpoint = "${gitlabExternalUrl}/oauth/authorize";
    TokenEndpoint = "${gitlabInternalHttpUrl}/oauth/token";
    UserAPIEndpoint = "${gitlabInternalHttpUrl}/api/v4/user";
    SkipTLSVerification = true;
  };
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
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
  ensureGitlabMattermostCiScript = pkgs.writeScript "ensure-gitlab-mattermost-ci.py" ''
#!${pythonWithRequests}/bin/python3
import json
import os
import time
from pathlib import Path
from typing import Any, Dict, Iterable

import requests
from requests import Session


def read_first_line(path: str) -> str:
    try:
        data = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"required secret file missing: {path}")
    value = data.strip()
    if not value:
        raise SystemExit(f"secret file {path} was empty")
    return value


def parse_verify_flag(raw: str) -> Any:
    value = raw.strip().lower()
    if value in ("", "false", "0", "no", "off"):
        return False
    if value in ("true", "1", "yes", "on"):
        return True
    return raw


def wait_for_api(session: Session, url: str, name: str, *, attempts: int = 60, delay: float = 5.0) -> None:
    for _ in range(attempts):
        try:
            response = session.get(url, timeout=5)
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(delay)
    raise SystemExit(f"{name} API did not become ready: {url}")


def mattermost_login(session: Session, base_url: str, login_ids: Iterable[str], password: str) -> None:
    for login_id in login_ids:
        if not login_id:
            continue
        try:
            response = session.post(
                f"{base_url}/api/v4/users/login",
                json={"login_id": login_id, "password": password},
                timeout=10,
            )
        except requests.RequestException as exc:
            last_error = exc
            continue

        if response.status_code == 200:
            token = response.headers.get("Token")
            if not token:
                last_error = RuntimeError("Mattermost login response missing session token")
                break
            session.headers["Authorization"] = f"Bearer {token}"
            return

        last_error = RuntimeError(f"Mattermost login failed: {response.status_code} {response.text}")

    if 'last_error' in locals():
        raise SystemExit(str(last_error))
    raise SystemExit("Mattermost login failed: no login IDs were provided")


def ensure_team(session: Session, base_url: str, name: str, display_name: str) -> Dict[str, Any]:
    response = session.get(f"{base_url}/api/v4/teams/name/{name}", timeout=10)
    if response.status_code == 200:
        return response.json()
    if response.status_code != 404:
        raise SystemExit(f"failed to query team '{name}': {response.status_code} {response.text}")

    response = session.post(
        f"{base_url}/api/v4/teams",
        json={"name": name, "display_name": display_name, "type": "O"},
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost team '{name}': {response.status_code} {response.text}")
    return response.json()


def ensure_channel(session: Session, base_url: str, team_id: str, name: str, display_name: str) -> Dict[str, Any]:
    response = session.get(
        f"{base_url}/api/v4/teams/{team_id}/channels/name/{name}",
        timeout=10,
    )
    if response.status_code == 200:
        return response.json()
    if response.status_code != 404:
        raise SystemExit(f"failed to query channel '{name}': {response.status_code} {response.text}")

    response = session.post(
        f"{base_url}/api/v4/channels",
        json={"team_id": team_id, "name": name, "display_name": display_name, "type": "O"},
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost channel '{name}': {response.status_code} {response.text}")
    return response.json()


def list_incoming_hooks(session: Session, base_url: str) -> Iterable[Dict[str, Any]]:
    page = 0
    per_page = 200
    while True:
        response = session.get(
            f"{base_url}/api/v4/hooks/incoming",
            params={"page": page, "per_page": per_page},
            timeout=10,
        )
        if response.status_code != 200:
            raise SystemExit(f"failed to list Mattermost incoming hooks: {response.status_code} {response.text}")
        hooks = response.json()
        if not hooks:
            break
        yield from hooks
        if len(hooks) < per_page:
            break
        page += 1


def ensure_incoming_hook(
    session: Session,
    base_url: str,
    team_id: str,
    channel_id: str,
    display_name: str,
    username: str,
) -> Dict[str, Any]:
    for hook in list_incoming_hooks(session, base_url):
        if hook.get("channel_id") == channel_id and hook.get("display_name") == display_name:
            return hook

    response = session.post(
        f"{base_url}/api/v4/hooks/incoming",
        json={
            "team_id": team_id,
            "channel_id": channel_id,
            "display_name": display_name,
            "description": "GitLab CI pipeline notifications",
            "username": username,
        },
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(f"failed to create Mattermost incoming webhook: {response.status_code} {response.text}")
    return response.json()


def fetch_all_projects(session: Session, base_url: str) -> Iterable[Dict[str, Any]]:
    page = 1
    per_page = 100
    while True:
        response = session.get(
            f"{base_url}/projects",
            params={"membership": True, "simple": True, "per_page": per_page, "page": page},
            timeout=10,
        )
        if response.status_code != 200:
            raise SystemExit(f"failed to list GitLab projects: {response.status_code} {response.text}")
        chunk = response.json()
        if not chunk:
            break
        yield from chunk
        if len(chunk) < per_page:
            break
        page += 1


def configure_project_integration(
    session: Session,
    base_url: str,
    project_id: int,
    webhook_url: str,
    channel_name: str,
    username: str,
) -> None:
    payload = {
        "webhook": webhook_url,
        "username": username,
        "channel": f"#{channel_name}",
        "notify_only_broken_pipelines": False,
        "branches_to_be_notified": "all",
        "push_events": False,
        "issues_events": False,
        "confidential_issues_events": False,
        "merge_requests_events": True,  # Enable MR notifications for code review workflow
        "tag_push_events": True,        # Enable tag notifications for releases
        "note_events": False,
        "confidential_note_events": False,
        "pipeline_events": True,
        "wiki_page_events": False,
        "job_events": True,             # Enable job failure notifications
        "deployment_events": True,      # Enable deployment notifications
        "active": True,
    }
    response = session.put(
        f"{base_url}/projects/{project_id}/services/mattermost",
        json=payload,
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise SystemExit(
            f"failed to configure Mattermost integration for project {project_id}: "
            f"{response.status_code} {response.text}"
        )


def main() -> None:
    mattermost_base = os.environ.get("MATTERMOST_BASE_URL", "http://127.0.0.1:8065").rstrip("/")
    mattermost_site = os.environ.get("MATTERMOST_SITE_URL", mattermost_base).rstrip("/")
    mattermost_team_name = os.environ["MATTERMOST_TEAM_NAME"]
    mattermost_team_display = os.environ["MATTERMOST_TEAM_DISPLAY_NAME"]
    mattermost_channel_name = os.environ["MATTERMOST_CHANNEL_NAME"]
    mattermost_channel_display = os.environ["MATTERMOST_CHANNEL_DISPLAY_NAME"]
    mattermost_hook_display = os.environ.get("MATTERMOST_HOOK_DISPLAY_NAME", "GitLab CI Builds")
    mattermost_username = os.environ.get("MATTERMOST_HOOK_USERNAME", "gitlab-ci")
    mattermost_verify = parse_verify_flag(os.environ.get("MATTERMOST_VERIFY_TLS", "false"))

    mattermost_username_file = os.environ["MATTERMOST_ADMIN_USERNAME_FILE"]
    mattermost_password_file = os.environ["MATTERMOST_ADMIN_PASSWORD_FILE"]
    mattermost_email_file = os.environ.get("MATTERMOST_ADMIN_EMAIL_FILE", "")
    gitlab_token_file = os.environ["GITLAB_API_TOKEN_FILE"]
    gitlab_base = os.environ.get("GITLAB_API_BASE_URL", f"https://localhost:{os.environ.get('RAVE_HOST_HTTPS_PORT', '8443')}/gitlab/api/v4").rstrip("/")
    gitlab_verify = parse_verify_flag(os.environ.get("GITLAB_VERIFY_TLS", "false"))

    mm_username = read_first_line(mattermost_username_file)
    mm_password = read_first_line(mattermost_password_file)
    mm_email = ""
    if mattermost_email_file:
        try:
            mm_email = read_first_line(mattermost_email_file)
        except SystemExit:
            mm_email = ""
    gitlab_token = read_first_line(gitlab_token_file)

    mm_session = requests.Session()
    mm_session.verify = mattermost_verify
    wait_for_api(mm_session, f"{mattermost_base}/api/v4/system/ping", "Mattermost")
    login_candidates = []
    seen = set()
    for candidate in (mm_email, mm_username):
        candidate = candidate.strip()
        if candidate and candidate not in seen:
            login_candidates.append(candidate)
            seen.add(candidate)
    mattermost_login(mm_session, mattermost_base, login_candidates, mm_password)

    team = ensure_team(mm_session, mattermost_base, mattermost_team_name, mattermost_team_display)
    channel = ensure_channel(mm_session, mattermost_base, team["id"], mattermost_channel_name, mattermost_channel_display)
    hook = ensure_incoming_hook(
        mm_session,
        mattermost_base,
        team["id"],
        channel["id"],
        mattermost_hook_display,
        mattermost_username,
    )
    hook_id = hook["id"]
    webhook_internal = f"{mattermost_base}/hooks/{hook_id}"

    gitlab_session = requests.Session()
    gitlab_session.headers["PRIVATE-TOKEN"] = gitlab_token
    gitlab_session.verify = gitlab_verify
    wait_for_api(gitlab_session, f"{gitlab_base}/version", "GitLab")

    projects = list(fetch_all_projects(gitlab_session, gitlab_base))
    for project in projects:
        configure_project_integration(
            gitlab_session,
            gitlab_base,
            project["id"],
            webhook_internal,
            mattermost_channel_name,
            mattermost_hook_display,
        )

    print(f"[ci-bridge] Mattermost webhook {hook_id} linked to channel '{mattermost_channel_name}' in team '{mattermost_team_name}'")
    print(f"[ci-bridge] Configured {len(projects)} GitLab project(s) for Mattermost notifications")

    summary = {
        "mattermost_team": mattermost_team_name,
        "mattermost_channel": mattermost_channel_name,
        "incoming_hook": hook_id,
        "configured_projects": [p["path_with_namespace"] for p in projects],
        "webhook_url_internal": webhook_internal,
        "webhook_url_external": f"{mattermost_site}/hooks/{hook_id}",
    }
    output_path = Path("/var/lib/rave/gitlab-mattermost-ci.json")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    output_path.chmod(0o600)


if __name__ == "__main__":
    main()
  '';
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
    ../modules/services/outline/default.nix

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

  systemd.services.mattermost.preStart = lib.mkMerge [
    (lib.mkBefore ''
      if [ -d /var/lib/mattermost/client ] && [ ! -L /var/lib/mattermost/client ]; then
        ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/client
      fi
    '')
    (lib.mkAfter ''
    SITE_URL=${lib.escapeShellArg mattermostPublicUrl} \
    GITLAB_AUTH_BASE=${lib.escapeShellArg gitlabExternalUrl} \
    GITLAB_API_BASE=${lib.escapeShellArg gitlabInternalHttpUrl} \
    GITLAB_CLIENT_ID=${lib.escapeShellArg mattermostGitlabClientId} \
    ${if useSecrets then ''
    GITLAB_SECRET_FILE=${lib.escapeShellArg mattermostGitlabClientSecretFile} \
    '' else ''
    GITLAB_SECRET=${lib.escapeShellArg mattermostGitlabSecretFallback} \
    ''}GITLAB_REDIRECT=${lib.escapeShellArg mattermostGitlabRedirectUri} \
    ${pkgs.python3}/bin/python3 <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

config_path = Path('/var/lib/mattermost/config/config.json')
if not config_path.exists():
    raise SystemExit(0)

site_url = os.environ.get('SITE_URL', f'https://localhost:{os.environ.get("RAVE_HOST_HTTPS_PORT", "8443")}/mattermost').rstrip('/')
login_url = f"{site_url}/oauth/gitlab/login"
login_path = urlparse(login_url).path or "/oauth/gitlab/login"
gitlab_auth_base = os.environ.get('GITLAB_AUTH_BASE', f'https://localhost:{os.environ.get("RAVE_HOST_HTTPS_PORT", "8443")}/gitlab').rstrip('/')
gitlab_api_base = os.environ.get('GITLAB_API_BASE', f'https://localhost:{os.environ.get("RAVE_HOST_HTTPS_PORT", "8443")}/gitlab').rstrip('/')
gitlab_client_id = os.environ.get("GITLAB_CLIENT_ID", "")
secret_path = os.environ.get("GITLAB_SECRET_FILE", "")
gitlab_secret = os.environ.get("GITLAB_SECRET", "")
if secret_path:
    secret_file = Path(secret_path)
    if secret_file.is_file():
        gitlab_secret = secret_file.read_text(encoding="utf-8").strip()
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
gitlab['AuthEndpoint'] = f"{gitlab_auth_base}/oauth/authorize"
gitlab['TokenEndpoint'] = f"{gitlab_api_base}/oauth/token"
gitlab['UserAPIEndpoint'] = f"{gitlab_api_base}/api/v4/user"
gitlab['SkipTLSVerification'] = True
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
    ensureDatabases = [ "gitlab" "grafana" "penpot" "mattermost" "n8n" ];
    ensureUsers = [
      { name = "gitlab"; ensureDBOwnership = true; }
      { name = "grafana"; ensureDBOwnership = true; }
      { name = "penpot"; ensureDBOwnership = true; }
      { name = "mattermost"; ensureDBOwnership = true; }
      { name = "n8n"; ensureDBOwnership = true; }
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

      SELECT format('CREATE ROLE %I LOGIN', 'penpot')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'penpot')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'mattermost')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mattermost')
      \gexec

      SELECT format('CREATE ROLE %I LOGIN', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n')
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

      SELECT format('CREATE DATABASE %I OWNER %I', 'n8n', 'n8n')
      WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'n8n')
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
      ALTER USER grafana WITH PASSWORD 'grafana-production-password';

      -- Penpot database setup  
      GRANT ALL PRIVILEGES ON DATABASE penpot TO penpot;
      ALTER USER penpot WITH PASSWORD 'penpot-production-password';

      -- n8n automation database setup
      GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
      ALTER USER n8n WITH PASSWORD '${n8nDbPassword}';

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
        root_url = "https://localhost:${baseHttpsPort}/grafana/";
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

  # ===== MATTERMOST CHAT =====

  services.mattermost = {
    enable = true;
    localDatabaseCreate = false;
    siteUrl = mattermostPublicUrl;
    siteName = "RAVE Mattermost";
    mutableConfig = true;
    extraConfig = {
      ServiceSettings = {
        SiteURL = mattermostPublicUrl;
        EnableLocalMode = false;
        EnableInsecureOutgoingConnections = true;
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
        TokenEndpoint = "${gitlabInternalHttpUrl}/oauth/token";
        UserAPIEndpoint = "${gitlabInternalHttpUrl}/api/v4/user";
        Id = mattermostGitlabClientId;
        Scope = "read_user";
        SkipTLSVerification = true;
      };
      PluginSettings = {
        Enable = true;
        EnableUploads = true;
        ClientDirectory = "/var/lib/mattermost/plugins/client";
        Directory = "/var/lib/mattermost/plugins/server";
        Plugins = {
          "com.mattermost.calls" = {
            enable = true;
            # Calls plugin configuration
            DefaultEnabled = true;
            EnableRinging = true;
            ICEServers = [
              {
                urls = [ "stun:localhost:3478" ];
              }
              {
                urls = [ "turn:localhost:3478" ];
                username = "mattermost";
                credential = "rave-coturn-development-secret-2025";
              }
            ];
            RTCServerPort = lib.toInt baseHttpsPort;
            TURNServerCredentials = "rave-coturn-development-secret-2025";
            MaxCallParticipants = 8;
            NeedsHTTPS = false; # Dev environment
            AllowEnableCalls = true;
            EnableTranscriptions = false; # Disable transcriptions for development
            EnableRecordings = false; # Disable recordings for development
          };
        };
      };
    };
    # Use Mattermost defaults for data and log directories

    environmentFile = if config.services.rave.gitlab.useSecrets
      then "/run/secrets/mattermost/env"
      else pkgs.writeText "mattermost-env" ''
        MM_SERVICESETTINGS_SITEURL=${mattermostPublicUrl}
        MM_SERVICESETTINGS_ENABLELOCALMODE=false
        MM_SERVICESETTINGS_ENABLEINSECUREOUTGOINGCONNECTIONS=true
        MM_SQLSETTINGS_DRIVERNAME=postgres
        MM_SQLSETTINGS_DATASOURCE=postgres://mattermost:mmpgsecret@localhost:5432/mattermost?sslmode=disable&connect_timeout=10
        MM_BLEVESETTINGS_INDEXDIR=/var/lib/mattermost/bleve-indexes
        MM_GITLABSETTINGS_ENABLE=true
        MM_GITLABSETTINGS_ID=${mattermostGitlabClientId}
        MM_GITLABSETTINGS_SECRET=${mattermostGitlabSecretFallback}
        MM_GITLABSETTINGS_SCOPE=read_user
        MM_GITLABSETTINGS_AUTHENDPOINT=${gitlabExternalUrl}/oauth/authorize
        MM_GITLABSETTINGS_TOKENENDPOINT=${gitlabInternalHttpUrl}/oauth/token
        MM_GITLABSETTINGS_USERAPIENDPOINT=${gitlabInternalHttpUrl}/api/v4/user
        MM_GITLABSETTINGS_SKIPTLSVERIFICATION=true
      '';

  };

  # ===== N8N AUTOMATION PLATFORM =====

  systemd.services.n8n = {
    description = "n8n automation service (Docker)";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "postgresql.service" ];
    requires = [ "docker.service" "postgresql.service" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      ExecStartPre = [
        "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f n8n || true'"
        "${pkgs.docker}/bin/docker pull ${n8nDockerImage}"
        "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create n8n-data || true'"
      ];
      ExecStart = pkgs.writeShellScript "n8n-start" ''
        exec ${pkgs.docker}/bin/docker run \
          --name n8n \
          --rm \
          -p 127.0.0.1:${toString n8nHostPort}:5678 \
          -v n8n-data:/home/node/.n8n \
          -e DB_TYPE=postgresdb \
          -e DB_POSTGRESDB_DATABASE=n8n \
          -e DB_POSTGRESDB_USER=n8n \
          -e DB_POSTGRESDB_PASSWORD=${n8nDbPassword} \
          -e DB_POSTGRESDB_HOST=172.17.0.1 \
          -e DB_POSTGRESDB_PORT=5432 \
          -e N8N_ENCRYPTION_KEY=${n8nEncryptionKey} \
          -e N8N_HOST=localhost \
          -e N8N_PORT=5678 \
          -e N8N_PROTOCOL=https \
          -e N8N_BASE_PATH=${n8nBasePath} \
          -e N8N_EDITOR_BASE_URL=${n8nPublicUrl} \
          -e WEBHOOK_URL=${n8nPublicUrl} \
          -e GENERIC_TIMEZONE=UTC \
          -e N8N_DIAGNOSTICS_ENABLED=false \
          -e N8N_VERSION_NOTIFICATIONS_ENABLED=false \
          -e N8N_BASIC_AUTH_ACTIVE=true \
          -e N8N_BASIC_AUTH_USER=admin \
          -e N8N_BASIC_AUTH_PASSWORD=${n8nBasicAuthPassword} \
          -e NODE_ENV=production \
          ${n8nDockerImage}
      '';
      ExecStop = "${pkgs.docker}/bin/docker stop n8n";
    };
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

  systemd.services.gitlab-mattermost-oauth = {
    description = "Ensure GitLab OAuth client for Mattermost exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "gitlab-db-config.service" "gitlab.service" ];
    wants = [ "gitlab.service" ];
    requires = [ "gitlab-db-config.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gitlab";
      Group = "gitlab";
      TimeoutStartSec = "900s";
      Restart = "on-failure";
      RestartSec = "30s";
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
secret_file = '${if useSecrets then mattermostGitlabClientSecretFile else ""}'
secret = if !secret_file.empty? && File.exist?(secret_file)
  File.read(secret_file).strip
else
  '${mattermostGitlabSecretFallback}'
end
name = 'RAVE Mattermost'
scopes = 'read_user'

# Force delete existing application to ensure clean configuration
existing_app = Doorkeeper::Application.find_by(uid: uid)
existing_app&.destroy!

app = Doorkeeper::Application.new
app.uid = uid
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

  # Mattermost Calls plugin installation service
  systemd.services.mattermost-calls-plugin = {
    description = "Install Mattermost Calls plugin";
    wantedBy = [ "multi-user.target" ];
    after = [ "mattermost.service" ];
    wants = [ "mattermost.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "mattermost";
      Group = "mattermost";
      RemainAfterExit = true;
    };
    
    script = ''
      set -euo pipefail
      
      PLUGIN_DIR="/var/lib/mattermost/plugins"
      PLUGIN_ID="com.mattermost.calls"
      PLUGIN_VERSION="v1.0.1"
      DOWNLOAD_URL="https://github.com/mattermost/mattermost-plugin-calls/releases/download/$PLUGIN_VERSION/$PLUGIN_ID-$PLUGIN_VERSION.tar.gz"
      
      echo "Installing Mattermost Calls plugin..."
      
      # Create plugin directory if it doesn't exist
      mkdir -p "$PLUGIN_DIR"
      
      # Check if plugin is already installed
      if [ -d "$PLUGIN_DIR/$PLUGIN_ID" ]; then
        echo "Calls plugin already installed at $PLUGIN_DIR/$PLUGIN_ID"
        exit 0
      fi
      
      # Download and extract plugin
      echo "Downloading Calls plugin from $DOWNLOAD_URL"
      cd "$PLUGIN_DIR"
      ${pkgs.wget}/bin/wget -O calls-plugin.tar.gz "$DOWNLOAD_URL" || {
        echo "Failed to download Calls plugin, continuing without it"
        exit 0
      }
      
      ${pkgs.gnutar}/bin/tar -xzf calls-plugin.tar.gz
      rm calls-plugin.tar.gz
      
      # Set proper permissions
      chown -R mattermost:mattermost "$PLUGIN_DIR"
      
      echo "Mattermost Calls plugin installed successfully"
    '';
  };

  systemd.services.gitlab-mattermost-ci-bridge = {
    description = "Configure Mattermost builds channel and GitLab CI notifications";
    wantedBy = [ "multi-user.target" ];
    after = [
      "gitlab-mattermost-oauth.service"
      "gitlab.service"
      "mattermost.service"
    ];
    requires = [
      "gitlab.service"
      "mattermost.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      TimeoutStartSec = "600s";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    environment = {
      MATTERMOST_BASE_URL = "http://127.0.0.1:8065";
      MATTERMOST_SITE_URL = mattermostPublicUrl;
      MATTERMOST_TEAM_NAME = mattermostTeamName;
      MATTERMOST_TEAM_DISPLAY_NAME = mattermostTeamDisplayName;
      MATTERMOST_CHANNEL_NAME = mattermostBuildsChannelName;
      MATTERMOST_CHANNEL_DISPLAY_NAME = mattermostBuildsChannelDisplayName;
      MATTERMOST_HOOK_DISPLAY_NAME = "GitLab CI Builds";
      MATTERMOST_HOOK_USERNAME = "gitlab-ci";
      MATTERMOST_ADMIN_USERNAME_FILE = mattermostAdminUsernameFile;
      MATTERMOST_ADMIN_PASSWORD_FILE = mattermostAdminPasswordFile;
      MATTERMOST_ADMIN_EMAIL_FILE = mattermostAdminEmailFile;
      MATTERMOST_VERIFY_TLS = "false";
      GITLAB_API_BASE_URL = "https://localhost:${baseHttpsPort}/gitlab/api/v4";
      GITLAB_API_TOKEN_FILE = gitlabApiTokenFile;
      GITLAB_VERIFY_TLS = "false";
    };
    script = ''
      set -euo pipefail
      ${ensureGitlabMattermostCiScript}
    '';
  };

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
                          <a href="/outline/" class="service-card">
                              <div class="service-title">📚 Outline</div>
                              <div class="service-desc">Knowledge base and documentation hub</div>
                              <div class="service-url">${outlinePublicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
                          <a href="/n8n/" class="service-card">
                              <div class="service-title">🧠 n8n</div>
                              <div class="service-desc">Low-code automation and workflows</div>
                              <div class="service-url">${n8nPublicUrl}/</div>
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
    nginx.after = [ 
      "generate-localhost-certs.service" 
      "gitlab.service"
      "grafana.service" 
      "mattermost.service"
      "outline.service"
      "n8n.service"
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
echo "  GitLab HTTPS : https://localhost:${baseHttpsPort}/gitlab/"
echo "  Mattermost   : ${mattermostPublicUrl}/"
echo "  Grafana      : https://localhost:${baseHttpsPort}/grafana/"
echo "  Prometheus   : http://localhost:19090/"
echo "  Outline      : ${outlinePublicUrl}/"
echo "  n8n          : ${n8nPublicUrl}/"
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
echo "   📚 Outline:     ${outlinePublicUrl}/"
echo "   🧠 n8n:         ${n8nPublicUrl}/"
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status postgresql redis-main nats prometheus grafana gitlab mattermost outline n8n rave-chat-bridge nginx --no-pager -l
echo ""
echo "🌐 Dashboard: https://localhost:${baseHttpsPort}/"
echo ""
EOF
      chmod +x /root/welcome.sh
      echo "/root/welcome.sh" >> /root/.bashrc
    '';
  };
}
