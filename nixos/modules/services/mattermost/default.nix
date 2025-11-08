{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.mattermost;

  pathOrString = types.either types.path types.str;

  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);

  mattermostPath =
    let
      matchResult = builtins.match "https?://[^/]+(.*)" cfg.publicUrl;
    in
    if matchResult == null || matchResult == [] then "" else builtins.head matchResult;

  mattermostLoginPath =
    if mattermostPath == ""
    then "/oauth/gitlab/login"
    else "${mattermostPath}/oauth/gitlab/login";

  brandHtmlValue = if cfg.brandHtml == null
    then "Use the GitLab button below to sign in. If it does not appear, open ${mattermostLoginPath} manually."
    else cfg.brandHtml;

  publicUrlTrimmed = lib.removeSuffix "/" cfg.publicUrl;
  internalBaseUrlTrimmed = lib.removeSuffix "/" cfg.internalBaseUrl;
  gitlabApiBaseTrimmed = lib.removeSuffix "/" cfg.gitlab.apiBaseUrl;

  gitlabRedirectUri = "${publicUrlTrimmed}/signup/gitlab/complete";

  gitlabSecretFile = cfg.gitlab.clientSecretFile;
  hasGitlabSecretFile = gitlabSecretFile != null && gitlabSecretFile != "";

  gitlabSettingsJSON = builtins.toJSON {
    Enable = true;
    EnableSync = true;
    AuthEndpoint = "${cfg.gitlab.baseUrl}/oauth/authorize";
    TokenEndpoint = "${cfg.gitlab.internalUrl}/oauth/token";
    UserAPIEndpoint = "${cfg.gitlab.internalUrl}/api/v4/user";
    Id = cfg.gitlab.clientId;
    Scope = cfg.gitlab.oauthScopes;
    SkipTLSVerification = true;
  };

  envFilePath =
    if cfg.envFile != null then cfg.envFile else
    pkgs.writeText "mattermost-env" ''
      MM_SERVICESETTINGS_SITEURL=${cfg.publicUrl}
      MM_SERVICESETTINGS_ENABLELOCALMODE=false
      MM_SERVICESETTINGS_ENABLEINSECUREOUTGOINGCONNECTIONS=true
      MM_SQLSETTINGS_DRIVERNAME=postgres
      MM_SQLSETTINGS_DATASOURCE=${cfg.databaseDatasource}
      MM_BLEVESETTINGS_INDEXDIR=/var/lib/mattermost/bleve-indexes
      MM_GITLABSETTINGS_ENABLE=true
      MM_GITLABSETTINGS_ID=${cfg.gitlab.clientId}
      MM_GITLABSETTINGS_SECRET=${cfg.gitlab.clientSecretFallback}
      MM_GITLABSETTINGS_SCOPE=${cfg.gitlab.oauthScopes}
      MM_GITLABSETTINGS_AUTHENDPOINT=${cfg.gitlab.baseUrl}/oauth/authorize
      MM_GITLABSETTINGS_TOKENENDPOINT=${cfg.gitlab.internalUrl}/oauth/token
      MM_GITLABSETTINGS_USERAPIENDPOINT=${cfg.gitlab.internalUrl}/api/v4/user
      MM_GITLABSETTINGS_SKIPTLSVERIFICATION=true
    '';

  callsPluginUrl = if cfg.callsPlugin.downloadUrl == null
    then "https://github.com/mattermost/mattermost-plugin-calls/releases/download/${cfg.callsPlugin.version}/com.mattermost.calls-${cfg.callsPlugin.version}.tar.gz"
    else cfg.callsPlugin.downloadUrl;

  gitlabRailsRunner = "${config.system.path}/bin/gitlab-rails";

  ensureGitlabMattermostCiScript = pkgs.writeScript "ensure-gitlab-mattermost-ci.py" ''
#!${pythonWithRequests}/bin/python3
${builtins.readFile ./ensure-gitlab-mattermost-ci.py}
'';

  updateMattermostScript = pkgs.writeText "update-mattermost-config.py"
    (lib.replaceStrings
      [ "@SITE_URL@" "@BRAND_TEXT@" "@GITLAB_SETTINGS@" ]
      [ (builtins.toJSON cfg.publicUrl) (builtins.toJSON brandHtmlValue) gitlabSettingsJSON ]
      (builtins.readFile ./update-mattermost-config.py));

in
{
  options.services.rave.mattermost = {
    enable = mkEnableOption "Mattermost chat service with GitLab integration";

    package = mkOption {
      type = types.package;
      default = pkgs.mattermost;
      description = "Mattermost package derivation to deploy.";
    };

    siteName = mkOption {
      type = types.str;
      default = "RAVE Mattermost";
      description = "Displayed site name.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://localhost:8443/mattermost";
      description = "Externally reachable Mattermost URL.";
    };

    internalBaseUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8065";
      description = "Internal HTTP URL used for service-to-service communication.";
    };

    brandHtml = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional custom HTML rendered on the login screen.";
    };

    envFile = mkOption {
      type = types.nullOr pathOrString;
      default = null;
      description = "Environment file passed to the Mattermost service. When null, a file is generated automatically.";
    };

    databaseDatasource = mkOption {
      type = types.str;
      default = "postgres://mattermost:mmpgsecret@localhost:5432/mattermost?sslmode=disable&connect_timeout=10";
      description = "Value used for MM_SQLSETTINGS_DATASOURCE.";
    };

    admin = {
      usernameFile = mkOption {
        type = pathOrString;
        default = "/run/secrets/mattermost/admin-username";
        description = "Path to the admin username secret.";
      };

      passwordFile = mkOption {
        type = pathOrString;
        default = "/run/secrets/mattermost/admin-password";
        description = "Path to the admin password secret.";
      };

      emailFile = mkOption {
        type = pathOrString;
        default = "/run/secrets/mattermost/admin-email";
        description = "Path to the admin email secret.";
      };
    };

    team = {
      name = mkOption {
        type = types.str;
        default = "rave";
        description = "Mattermost team slug used for automation.";
      };

      displayName = mkOption {
        type = types.str;
        default = "RAVE";
        description = "Team display name.";
      };

      buildsChannelName = mkOption {
        type = types.str;
        default = "builds";
        description = "Channel slug for CI notifications.";
      };

      buildsChannelDisplayName = mkOption {
        type = types.str;
        default = "Builds";
        description = "Display name for the CI channel.";
      };

      hookDisplayName = mkOption {
        type = types.str;
        default = "GitLab CI Builds";
        description = "Display name used for the incoming webhook.";
      };

      hookUsername = mkOption {
        type = types.str;
        default = "gitlab-ci";
        description = "Username shown for webhook posts.";
      };
    };

    gitlab = {
      baseUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab";
        description = "External GitLab URL used for Oauth links.";
      };

      internalUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab";
        description = "Internal GitLab URL for API calls.";
      };

      apiBaseUrl = mkOption {
        type = types.str;
        default = "https://localhost:8443/gitlab/api/v4";
        description = "GitLab API endpoint used by automation.";
      };

      clientId = mkOption {
        type = types.str;
        default = "mattermost-client-id";
        description = "OAuth client ID used by Mattermost.";
      };

      clientSecretFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to the GitLab OAuth client secret for Mattermost.";
      };

      clientSecretFallback = mkOption {
        type = types.str;
        default = "development-mattermost-secret";
        description = "Fallback client secret used when no secret file is supplied.";
      };

      apiTokenFile = mkOption {
        type = pathOrString;
        default = "/run/secrets/gitlab/api-token";
        description = "Path to the GitLab personal access token used by the CI bridge.";
      };

      oauthScopes = mkOption {
        type = types.str;
        default = "read_user";
        description = "Scopes requested for the GitLab OAuth application.";
      };

      applicationName = mkOption {
        type = types.str;
        default = "RAVE Mattermost";
        description = "Display name used for the GitLab OAuth application.";
      };
    };

    callsPlugin = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install/configure the Mattermost Calls plugin.";
      };

      version = mkOption {
        type = types.str;
        default = "v1.0.1";
        description = "Version of the Calls plugin to download.";
      };

      downloadUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional override for the Calls plugin tarball URL.";
      };

      defaultEnabled = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the Calls plugin starts enabled for all teams.";
      };

      enableRinging = mkOption {
        type = types.bool;
        default = true;
        description = "Toggle ringtone support in the Calls plugin.";
      };

      stunUrl = mkOption {
        type = types.str;
        default = "stun:localhost:3478";
        description = "STUN server URL provided to the Calls plugin.";
      };

      turnUrl = mkOption {
        type = types.str;
        default = "turn:localhost:3478";
        description = "TURN server URL provided to the Calls plugin.";
      };

      turnUsername = mkOption {
        type = types.str;
        default = "mattermost";
        description = "TURN username advertised to clients.";
      };

      turnCredential = mkOption {
        type = types.str;
        default = "change-me-turn-secret";
        description = "TURN credential or shared secret used by the Calls plugin.";
      };

      rtcServerPort = mkOption {
        type = types.int;
        default = 8443;
        description = "Port exposed by the Calls plugin RTC server.";
      };

      maxParticipants = mkOption {
        type = types.int;
        default = 8;
        description = "Maximum concurrent call participants.";
      };

      needsHttps = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the Calls plugin enforces HTTPS.";
      };

      allowEnableCalls = mkOption {
        type = types.bool;
        default = true;
        description = "Whether team admins may enable calls.";
      };

      enableTranscriptions = mkOption {
        type = types.bool;
        default = false;
        description = "Toggle experimental transcription support.";
      };

      enableRecordings = mkOption {
        type = types.bool;
        default = false;
        description = "Toggle call recording support.";
      };
    };

    ciBridge = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the GitLab → Mattermost CI bridge automation.";
      };

      verifyMattermostTls = mkOption {
        type = types.bool;
        default = false;
        description = "Verify TLS certificates when the CI bridge talks to Mattermost.";
      };

      verifyGitlabTls = mkOption {
        type = types.bool;
        default = false;
        description = "Verify TLS certificates when the CI bridge talks to GitLab.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.mattermost = {
      enable = true;
      package = cfg.package;
      siteUrl = cfg.publicUrl;
      siteName = cfg.siteName;
      localDatabaseCreate = false;
      mutableConfig = true;
      environmentFile = envFilePath;
      extraConfig = {
        ServiceSettings = {
          SiteURL = cfg.publicUrl;
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
          CustomBrandText = brandHtmlValue;
        };

        GitLabSettings = builtins.fromJSON gitlabSettingsJSON;

        PluginSettings = (
          {
            Enable = true;
            EnableUploads = true;
            ClientDirectory = "/var/lib/mattermost/plugins/client";
            Directory = "/var/lib/mattermost/plugins/server";
          }
          // lib.optionalAttrs cfg.callsPlugin.enable {
            Plugins = {
              "com.mattermost.calls" = {
                enable = true;
                DefaultEnabled = cfg.callsPlugin.defaultEnabled;
                EnableRinging = cfg.callsPlugin.enableRinging;
                ICEServers = [
                  { urls = [ cfg.callsPlugin.stunUrl ]; }
                  {
                    urls = [ cfg.callsPlugin.turnUrl ];
                    username = cfg.callsPlugin.turnUsername;
                    credential = cfg.callsPlugin.turnCredential;
                  }
                ];
                RTCServerPort = cfg.callsPlugin.rtcServerPort;
                TURNServerCredentials = cfg.callsPlugin.turnCredential;
                MaxCallParticipants = cfg.callsPlugin.maxParticipants;
                NeedsHTTPS = cfg.callsPlugin.needsHttps;
                AllowEnableCalls = cfg.callsPlugin.allowEnableCalls;
                EnableTranscriptions = cfg.callsPlugin.enableTranscriptions;
                EnableRecordings = cfg.callsPlugin.enableRecordings;
              };
            };
          }
        );
      };
    };

    systemd.services.mattermost.preStart = lib.mkMerge [
      (lib.mkBefore ''
        if [ -d /var/lib/mattermost/client ] && [ ! -L /var/lib/mattermost/client ]; then
          ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/client
        fi
      '')
      (lib.mkAfter ''
        SITE_URL=${lib.escapeShellArg cfg.publicUrl} \
        GITLAB_AUTH_BASE=${lib.escapeShellArg cfg.gitlab.baseUrl} \
        GITLAB_API_BASE=${lib.escapeShellArg cfg.gitlab.internalUrl} \
        GITLAB_CLIENT_ID=${lib.escapeShellArg cfg.gitlab.clientId} \
        BRAND_HTML=${lib.escapeShellArg brandHtmlValue} \
        ${optionalString hasGitlabSecretFile ''
        GITLAB_SECRET_FILE=${lib.escapeShellArg gitlabSecretFile} \
        ''}${optionalString (!hasGitlabSecretFile) ''
        GITLAB_SECRET=${lib.escapeShellArg cfg.gitlab.clientSecretFallback} \
        ''}GITLAB_REDIRECT=${lib.escapeShellArg gitlabRedirectUri} \
        ${pkgs.python3}/bin/python3 <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

config_path = Path('/var/lib/mattermost/config/config.json')
if not config_path.exists():
    raise SystemExit(0)

site_url = os.environ.get('SITE_URL', 'https://localhost:8443/mattermost').rstrip('/')
login_url = f"{site_url}/oauth/gitlab/login"
login_path = urlparse(login_url).path or "/oauth/gitlab/login"
gitlab_auth_base = os.environ.get('GITLAB_AUTH_BASE', site_url).rstrip('/')
gitlab_api_base = os.environ.get('GITLAB_API_BASE', site_url).rstrip('/')
gitlab_client_id = os.environ.get('GITLAB_CLIENT_ID', '')
secret_path = os.environ.get('GITLAB_SECRET_FILE', '')
gitlab_secret = os.environ.get('GITLAB_SECRET', '')
if secret_path:
    secret_file = Path(secret_path)
    if secret_file.is_file():
        gitlab_secret = secret_file.read_text(encoding='utf-8').strip()
gitlab_redirect = os.environ.get('GITLAB_REDIRECT', '')
brand_html = os.environ.get('BRAND_HTML')
if not brand_html:
    brand_html = "Use the GitLab button below to sign in. If it does not appear, open {path} manually.".format(
        path=login_path
    )

gitlab_scope = os.environ.get('GITLAB_SCOPE', 'read_user')
config = json.loads(config_path.read_text())

service = config.setdefault('ServiceSettings', {})
service['SiteURL'] = site_url

team = config.setdefault('TeamSettings', {})
team['EnableCustomBrand'] = True
team['CustomDescriptionText'] = ''
team['CustomBrandText'] = brand_html

gitlab = config.setdefault('GitLabSettings', {})
gitlab['Enable'] = True
gitlab['Id'] = gitlab_client_id
gitlab['Secret'] = gitlab_secret
gitlab['Scope'] = gitlab_scope
gitlab['AuthEndpoint'] = f"{gitlab_auth_base}/oauth/authorize"
gitlab['TokenEndpoint'] = f"{gitlab_api_base}/oauth/token"
gitlab['UserAPIEndpoint'] = f"{gitlab_api_base}/api/v4/user"
gitlab['SkipTLSVerification'] = True
gitlab['DiscoveryEndpoint'] = ''
gitlab['EnableAuth'] = True
gitlab['EnableSync'] = True
gitlab['AutoLogin'] = False
gitlab['RedirectUri'] = gitlab_redirect
config.pop('GoogleSettings', None)

config_path.write_text(json.dumps(config, indent=2) + '\n')
PY
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/mattermost
        ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/.client-tmp
        ${pkgs.coreutils}/bin/cp -R ${cfg.package}/client /var/lib/mattermost/.client-tmp
        ${pkgs.coreutils}/bin/rm -rf /var/lib/mattermost/client
        ${pkgs.coreutils}/bin/mv /var/lib/mattermost/.client-tmp /var/lib/mattermost/client
        ${pkgs.coreutils}/bin/chown -R mattermost:mattermost /var/lib/mattermost/client
        ${pkgs.coreutils}/bin/chmod -R u+rwX,go+rX /var/lib/mattermost/client
        ${pkgs.coreutils}/bin/install -Dm755 ${updateMattermostScript} /var/lib/rave/update-mattermost-config.py
      '')
    ];

    systemd.services.mattermost.after = mkAfter [ "gitlab-mattermost-oauth.service" ];

    systemd.services."gitlab-mattermost-oauth" = {
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
redirect_uri = '${gitlabRedirectUri}'
uid = '${cfg.gitlab.clientId}'
secret_file = '${if hasGitlabSecretFile then gitlabSecretFile else ""}'
secret = if !secret_file.empty? && File.exist?(secret_file)
  File.read(secret_file).strip
else
  '${cfg.gitlab.clientSecretFallback}'
end
name = '${cfg.gitlab.applicationName}'
scopes = '${cfg.gitlab.oauthScopes}'

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
    systemd.services.mattermost-calls-plugin = lib.mkIf cfg.callsPlugin.enable {
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
        DOWNLOAD_URL=${lib.escapeShellArg callsPluginUrl}

        echo "Installing Mattermost Calls plugin..."
        mkdir -p "$PLUGIN_DIR"

        if [ -d "$PLUGIN_DIR/$PLUGIN_ID" ]; then
          echo "Calls plugin already installed at $PLUGIN_DIR/$PLUGIN_ID"
          exit 0
        fi

        echo "Downloading Calls plugin from $DOWNLOAD_URL"
        cd "$PLUGIN_DIR"
        if ! ${pkgs.wget}/bin/wget -O calls-plugin.tar.gz "$DOWNLOAD_URL"; then
          echo "Failed to download Calls plugin, continuing without it"
          exit 0
        fi

        ${pkgs.gnutar}/bin/tar -xzf calls-plugin.tar.gz
        rm -f calls-plugin.tar.gz
        chown -R mattermost:mattermost "$PLUGIN_DIR"
        echo "Mattermost Calls plugin installed successfully"
      '';
    };

    systemd.services."gitlab-mattermost-ci-bridge" = lib.mkIf cfg.ciBridge.enable {
      description = "Configure Mattermost builds channel and GitLab CI notifications";
      wantedBy = [ "multi-user.target" ];
      after = [
        "gitlab-mattermost-oauth.service"
        "gitlab.service"
        "mattermost.service"
      ];
      requires = [ "gitlab.service" "mattermost.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        TimeoutStartSec = "600s";
        Restart = "on-failure";
        RestartSec = "30s";
      };
      environment = {
        MATTERMOST_BASE_URL = internalBaseUrlTrimmed;
        MATTERMOST_SITE_URL = cfg.publicUrl;
        MATTERMOST_TEAM_NAME = cfg.team.name;
        MATTERMOST_TEAM_DISPLAY_NAME = cfg.team.displayName;
        MATTERMOST_CHANNEL_NAME = cfg.team.buildsChannelName;
        MATTERMOST_CHANNEL_DISPLAY_NAME = cfg.team.buildsChannelDisplayName;
        MATTERMOST_HOOK_DISPLAY_NAME = cfg.team.hookDisplayName;
        MATTERMOST_HOOK_USERNAME = cfg.team.hookUsername;
        MATTERMOST_ADMIN_USERNAME_FILE = cfg.admin.usernameFile;
        MATTERMOST_ADMIN_PASSWORD_FILE = cfg.admin.passwordFile;
        MATTERMOST_ADMIN_EMAIL_FILE = cfg.admin.emailFile;
        MATTERMOST_VERIFY_TLS = boolToString cfg.ciBridge.verifyMattermostTls;
        GITLAB_API_BASE_URL = gitlabApiBaseTrimmed;
        GITLAB_API_TOKEN_FILE = cfg.gitlab.apiTokenFile;
        GITLAB_VERIFY_TLS = boolToString cfg.ciBridge.verifyGitlabTls;
      };
      script = ''
        set -euo pipefail
        ${ensureGitlabMattermostCiScript}
      '';
    };
  };
}
