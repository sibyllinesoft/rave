{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.authentik;

  pathOrString = types.either types.path types.str;

  capitalize =
    str:
    let
      value = if str == null then "" else str;
      len = lib.stringLength value;
    in
    if len == 0 then ""
    else
      let
        first = lib.toUpper (lib.substring 0 1 value);
        rest = lib.substring 1 (len - 1) value;
      in "${first}${rest}";

  redisPlatform = config.services.rave.redis.platform or {};
  redisAllocations = redisPlatform.allocations or {};
  redisDbDefault = redisAllocations.authentik or 12;

  redisDb =
    if cfg.redis.database != null then cfg.redis.database else redisDbDefault;
  redisUnit = redisPlatform.unit or "redis-main.service";
  redisDockerHost =
    if cfg.redis.host != null then cfg.redis.host else redisPlatform.dockerHost or "host.docker.internal";
  redisPort =
    if cfg.redis.port != null then cfg.redis.port else redisPlatform.port or 6379;

  postgresDockerHost =
    if cfg.database.host == "127.0.0.1"
    then "host.docker.internal"
    else cfg.database.host;

  trimNewline = "${pkgs.coreutils}/bin/tr -d \"\\n\"";

  hostFromUrl = url:
    let matchResult = builtins.match "https?://([^/:]+).*" url;
    in if matchResult == null || matchResult == [] then null else builtins.head matchResult;

  schemeFromUrl = url:
    let matchResult = builtins.match "([^:]+)://.*" url;
    in if matchResult == null || matchResult == [] then "https" else builtins.head matchResult;

  pathFromUrl =
    url:
    let
      normalized = if url == null then "" else if lib.hasSuffix "/" url then url else "${url}/";
      matchResult = builtins.match "https?://[^/]+(.*)" normalized;
      tail =
        if matchResult == null || matchResult == [] then "/"
        else
          let candidate = builtins.head matchResult;
          in if candidate == "" then "/" else candidate;
    in tail;

  publicUrlNormalized =
    let val = cfg.publicUrl or "";
    in if lib.hasSuffix "/" val then val else "${val}/";

  publicHost = hostFromUrl publicUrlNormalized;
  publicScheme = schemeFromUrl publicUrlNormalized;
  publicPath = pathFromUrl publicUrlNormalized;

  cookieDomain =
    if cfg.cookieDomain != null then cfg.cookieDomain
    else if publicHost != null then publicHost
    else cfg.rootDomain;

  secretProvided = value: file: (value != null && value != "") || (file != null);

  readSecretSnippet = name: inline: file:
    if file != null then ''
      if [ -s ${lib.escapeShellArg file} ]; then
        ${name}="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg file} | ${trimNewline})"
      else
        ${name}=${lib.escapeShellArg (if inline != null then inline else "")}
      fi
    '' else ''
      ${name}=${lib.escapeShellArg (if inline != null then inline else "")}
    '';

  dbPasswordSqlExpr =
    if cfg.database.passwordFile != null
    then "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.database.passwordFile} | ${trimNewline})"
    else cfg.database.password;

  redisPasswordConfigured =
    (cfg.redis.password != null && cfg.redis.password != "") || (cfg.redis.passwordFile != null);

  bootstrapTokenConfigured =
    (cfg.bootstrap.token != null && cfg.bootstrap.token != "") || (cfg.bootstrap.tokenFile != null);

  emailPasswordConfigured =
    cfg.email.enable && ((cfg.email.password != null && cfg.email.password != "") || (cfg.email.passwordFile != null));

  dockerVolumeMounts = [
    { name = "authentik-media"; mount = "/media"; }
    { name = "authentik-templates"; mount = "/templates"; }
    { name = "authentik-geoip"; mount = "/geoip"; }
    { name = "authentik-blueprints"; mount = "/blueprints"; }
  ];

  volumeCreateCommands =
    map (vol: "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker volume create ${vol.name} >/dev/null || true'") dockerVolumeMounts;

  volumeRunArgs =
    lib.concatStrings (map (vol: "            -v ${vol.name}:${vol.mount} \\\n") dockerVolumeMounts);

  formatDockerEnv = value: "            -e ${value} \\\n";

  baseEnvLines =
    [
      ''AUTHENTIK_SECRET_KEY="$AUTHENTIK_SECRET_KEY"''
      "AUTHENTIK_BOOTSTRAP_EMAIL=${lib.escapeShellArg cfg.bootstrap.email}"
      ''AUTHENTIK_BOOTSTRAP_PASSWORD="$AUTHENTIK_BOOTSTRAP_PASSWORD"''
    ]
    ++ lib.optionals bootstrapTokenConfigured [
      ''AUTHENTIK_BOOTSTRAP_TOKEN="$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE"''
    ]
    ++ [
      "AUTHENTIK_POSTGRESQL__HOST=${lib.escapeShellArg postgresDockerHost}"
      "AUTHENTIK_POSTGRESQL__PORT=${toString cfg.database.port}"
      "AUTHENTIK_POSTGRESQL__NAME=${lib.escapeShellArg cfg.database.name}"
      "AUTHENTIK_POSTGRESQL__USER=${lib.escapeShellArg cfg.database.user}"
      ''AUTHENTIK_POSTGRESQL__PASSWORD="$AUTHENTIK_DB_PASSWORD"''
      "AUTHENTIK_POSTGRESQL__SSL_MODE=${lib.escapeShellArg cfg.database.sslMode}"
      "AUTHENTIK_REDIS__HOST=${lib.escapeShellArg redisDockerHost}"
      "AUTHENTIK_REDIS__PORT=${toString redisPort}"
      "AUTHENTIK_REDIS__DB=${toString redisDb}"
    ]
    ++ lib.optionals redisPasswordConfigured [
      ''AUTHENTIK_REDIS__PASSWORD="$AUTHENTIK_REDIS_PASSWORD"''
    ]
    ++ [
      "AUTHENTIK_LOG_LEVEL=${lib.escapeShellArg cfg.logLevel}"
      "AUTHENTIK_DISABLE_UPDATE_CHECK=${boolToString cfg.disableUpdateCheck}"
      "AUTHENTIK_ERROR_REPORTING__ENABLED=false"
      "AUTHENTIK_USE_X_FORWARDED_HOST=true"
      "AUTHENTIK_HTTP__TRUSTED_IPS=${lib.escapeShellArg "0.0.0.0/0"}"
      "AUTHENTIK_ROOT_DOMAIN=${lib.escapeShellArg cfg.rootDomain}"
      "AUTHENTIK_COOKIE_DOMAIN=${lib.escapeShellArg cookieDomain}"
      "AUTHENTIK_DEFAULT_HTTP_SCHEME=${lib.escapeShellArg publicScheme}"
      "AUTHENTIK_DEFAULT_HTTP_HOST=${lib.escapeShellArg (if publicHost != null then publicHost else cfg.rootDomain)}"
      "AUTHENTIK_DEFAULT_HTTP_PORT=${lib.escapeShellArg cfg.defaultExternalPort}"
      "AUTHENTIK_ROOT__PATH=${lib.escapeShellArg publicPath}"
      "AUTHENTIK_DEFAULT_USER__ENABLED=${boolToString cfg.bootstrap.enableDefaultUser}"
      "AUTHENTIK_EVENTS__STATE__RETENTION_DAYS=${toString cfg.retentionDays}"
      "TZ=${lib.escapeShellArg (config.time.timeZone or "UTC")}"
    ];

  emailEnvLines =
    if cfg.email.enable then
      [
        "AUTHENTIK_EMAIL__FROM=${lib.escapeShellArg cfg.email.fromAddress}"
        "AUTHENTIK_EMAIL__HOST=${lib.escapeShellArg cfg.email.host}"
        "AUTHENTIK_EMAIL__PORT=${toString cfg.email.port}"
        "AUTHENTIK_EMAIL__USERNAME=${lib.escapeShellArg cfg.email.username}"
        "AUTHENTIK_EMAIL__USE_TLS=${boolToString cfg.email.useTls}"
      ]
      ++ lib.optionals emailPasswordConfigured [
        ''AUTHENTIK_EMAIL__PASSWORD="$AUTHENTIK_EMAIL_PASSWORD"''
      ]
    else
      [];

  emailFromNameLine = lib.optionals (cfg.email.fromName != null) [
    "AUTHENTIK_EMAIL__FROM_NAME=${lib.escapeShellArg cfg.email.fromName}"
  ];

  extraEnvLines =
    map (name: "${name}=${lib.escapeShellArg cfg.extraEnv.${name}}") (builtins.attrNames cfg.extraEnv);

  oauthSourceSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether this OAuth source should be managed.";
        };

        displayName = mkOption {
          type = types.str;
          default = capitalize name;
          description = "Human readable name shown on the Authentik login page.";
        };

        slug = mkOption {
          type = types.str;
          default = name;
          description = "Unique slug for the source.";
        };

        providerType = mkOption {
          type = types.str;
          default = name;
          description = "Auth upstream identifier (for example: google, github, oidc).";
        };

        clientIdFile = mkOption {
          type = pathOrString;
          default = "/run/secrets/authentik/${name}-client-id";
          description = "Path to the file containing the OAuth client ID.";
        };

        clientSecretFile = mkOption {
          type = pathOrString;
          default = "/run/secrets/authentik/${name}-client-secret";
          description = "Path to the file containing the OAuth client secret.";
        };

        extraScopes = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional scopes to request beyond the defaults.";
        };

        identificationStages = mkOption {
          type = types.listOf types.str;
          default = [ "default-authentication-identification" ];
          description = "Identification stage slugs that should display this source.";
        };

        authenticationFlow = mkOption {
          type = types.nullOr types.str;
          default = "default-authentication-flow";
          description = "Authentication flow slug to attach to the source.";
        };

        enrollmentFlow = mkOption {
          type = types.nullOr types.str;
          default = "default-enrollment-flow";
          description = "Enrollment flow slug to attach to the source (optional).";
        };

        authorizationUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Override authorization URL for custom providers.";
        };

        accessTokenUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Override token URL for custom providers.";
        };

        profileUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Override profile URL for custom providers.";
        };

        oidcWellKnownUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional OIDC discovery URL (used for generic providers).";
        };

        oidcJwksUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional JWKS endpoint override.";
        };
      };
    }
  );

  oauthSourcesDefault = {
    google = {
      displayName = "Google";
      slug = "google";
      providerType = "google";
      extraScopes = [ "openid" "email" "profile" ];
    };
    github = {
      displayName = "GitHub";
      slug = "github";
      providerType = "github";
      extraScopes = [ "read:user" "user:email" ];
    };
  };

  enabledOauthSources =
    lib.filterAttrs (_: source: source.enable) cfg.oauthSources;

  oauthSourceEntries =
    lib.mapAttrsToList (
      _: source:
        {
          slug = source.slug;
          name = source.displayName;
          providerType = source.providerType;
          clientIdFile = source.clientIdFile;
          clientSecretFile = source.clientSecretFile;
          extraScopes = source.extraScopes;
          identificationStages = source.identificationStages;
          authenticationFlow = source.authenticationFlow;
          enrollmentFlow = source.enrollmentFlow;
          authorizationUrl = source.authorizationUrl;
          accessTokenUrl = source.accessTokenUrl;
          profileUrl = source.profileUrl;
          oidcWellKnownUrl = source.oidcWellKnownUrl;
          oidcJwksUrl = source.oidcJwksUrl;
          managed = "rave:oauth:${source.slug}";
        }
    ) enabledOauthSources;

  oauthSourcesManifest =
    if oauthSourceEntries == [] then null
    else pkgs.writeText "authentik-oauth-sources.json" (builtins.toJSON oauthSourceEntries);

  syncOAuthSourcesScript =
    if oauthSourcesManifest == null then null else
      let
        scriptLines = [
          "#!${pkgs.python3}/bin/python3"
          "import json"
          "import pathlib"
          "import subprocess"
          "import sys"
          "import time"
          ""
          "manifest_path = pathlib.Path(\"${oauthSourcesManifest}\")"
          "manifest = json.loads(manifest_path.read_text())"
          "payload = []"
          ""
          "for entry in manifest:"
          "    client_id_path = pathlib.Path(entry[\"clientIdFile\"])"
          "    client_secret_path = pathlib.Path(entry[\"clientSecretFile\"])"
          "    if not client_id_path.exists() or not client_secret_path.exists():"
          "        print(f\"[authentik-sync] missing credentials for {entry['slug']}\", file=sys.stderr)"
          "        continue"
          "    client_id = client_id_path.read_text().strip()"
          "    client_secret = client_secret_path.read_text().strip()"
          "    if not client_id or not client_secret:"
          "        print(f\"[authentik-sync] empty credentials for {entry['slug']}\", file=sys.stderr)"
          "        continue"
          "    payload.append({"
          "        \"slug\": entry[\"slug\"],"
          "        \"name\": entry[\"name\"],"
          "        \"providerType\": entry[\"providerType\"],"
          "        \"clientId\": client_id,"
          "        \"clientSecret\": client_secret,"
          "        \"extraScopes\": entry.get(\"extraScopes\", []),"
          "        \"identificationStages\": entry.get(\"identificationStages\", []),"
          "        \"authenticationFlow\": entry.get(\"authenticationFlow\"),"
          "        \"enrollmentFlow\": entry.get(\"enrollmentFlow\"),"
          "        \"authorization_url\": entry.get(\"authorizationUrl\"),"
          "        \"access_token_url\": entry.get(\"accessTokenUrl\"),"
          "        \"profile_url\": entry.get(\"profileUrl\"),"
          "        \"oidc_well_known_url\": entry.get(\"oidcWellKnownUrl\"),"
          "        \"oidc_jwks_url\": entry.get(\"oidcJwksUrl\"),"
          "        \"managed\": entry.get(\"managed\"),"
          "    })"
          ""
          "if not payload:"
          "    print(\"[authentik-sync] no OAuth sources to apply\", file=sys.stderr)"
          "    sys.exit(0)"
          ""
          "inner_template = \"\"\"import os"
          "import json"
          "import django"
          "os.environ.setdefault(\"DJANGO_SETTINGS_MODULE\", \"authentik.root.settings\")"
          "django.setup()"
          "from authentik.sources.oauth.models import OAuthSource"
          "from authentik.stages.identification.models import IdentificationStage"
          "from authentik.enterprise.stages.source.models import SourceStage"
          "from authentik.core.models import Source as CoreSource"
          "from authentik.flows.models import Flow, FlowStageBinding"
          ""
          "payload = json.loads(r'''__PAYLOAD__''')"
          ""
          "managed_slugs = []"
          "for entry in payload:"
          "    defaults = {"
          "        \"name\": entry[\"name\"],"
          "        \"provider_type\": entry[\"providerType\"],"
          "        \"consumer_key\": entry[\"clientId\"],"
          "        \"consumer_secret\": entry[\"clientSecret\"],"
          "        \"additional_scopes\": \" \".join(entry.get(\"extraScopes\") or []),"
          "        \"managed\": entry[\"managed\"],"
          "        \"enabled\": True,"
          "    }"
          "    for field in (\"authorization_url\", \"access_token_url\", \"profile_url\", \"oidc_well_known_url\", \"oidc_jwks_url\"):"
          "        value = entry.get(field)"
          "        if value:"
          "            defaults[field] = value"
          "    obj, _ = OAuthSource.objects.update_or_create(slug=entry[\"slug\"], defaults=defaults)"
          "    for attr, flow_slug in ((\"authentication_flow\", entry.get(\"authenticationFlow\")), (\"enrollment_flow\", entry.get(\"enrollmentFlow\"))):"
          "        if flow_slug:"
          "            flow = Flow.objects.filter(slug=flow_slug).first()"
          "            if flow:"
          "                setattr(obj, attr, flow)"
          "    obj.save()"
          "    for stage_slug in entry.get(\"identificationStages\") or []:"
          "        stage = IdentificationStage.objects.filter(name=stage_slug).first()"
          "        if stage:"
          "            stage.sources.add(obj)"
          "    managed_slugs.append(obj.slug)"
          ""
          "OAuthSource.objects.filter(managed__startswith=\"rave:oauth:\").exclude(slug__in=managed_slugs).delete()"
          ""
          "for entry in payload:"
          "    core_source = CoreSource.objects.filter(slug=entry[\"slug\"]).first()"
          "    if core_source is None:"
          "        continue"
          "    stage_name = f\"rave-oauth-source-{entry['slug']}\""
          "    stage, _ = SourceStage.objects.get_or_create(name=stage_name, defaults={\"source\": core_source})"
          "    if stage.source_id != core_source.pk:"
          "        stage.source = core_source"
          "        stage.save()"
          "    flow_slug = entry.get(\"authenticationFlow\") or \"default-authentication-flow\""
          "    flow = Flow.objects.filter(slug=flow_slug).first()"
          "    if not flow:"
          "        continue"
          "    orders = list(FlowStageBinding.objects.filter(target=flow).values_list(\"order\", flat=True))"
          "    desired_order = (min(orders) - 10) if orders else 0"
          "    binding, created = FlowStageBinding.objects.get_or_create(target=flow, stage=stage, defaults={\"order\": desired_order})"
          "    if not created and binding.order > desired_order:"
          "        binding.order = desired_order"
          "        binding.save()"
          "\"\"\""
          ""
          "inner_script = inner_template.replace(\"__PAYLOAD__\", json.dumps(payload))"
          ""
          "for attempt in range(12):"
          "    proc = subprocess.run(["
          "        \"${pkgs.docker}/bin/docker\","
          "        \"exec\","
          "        \"-i\","
          "        \"authentik-server\","
          "        \"python\","
          "        \"-\","
          "    ], input=inner_script, text=True)"
          "    if proc.returncode == 0:"
          "        break"
          "    time.sleep(5)"
          "else:"
          "    sys.exit(proc.returncode)"
        ];
        scriptText = (lib.concatStringsSep "\n" scriptLines) + "\n";
      in pkgs.writeScript "sync-authentik-oauth-sources" scriptText;

  waitForAuthentikContainer = pkgs.writeShellScript "wait-authentik-container" ''
    attempt=0
    while [ "$attempt" -lt 60 ]; do
      if ${pkgs.docker}/bin/docker ps --format '{{.Names}}' | ${pkgs.gnugrep}/bin/grep -qx authentik-server; then
        if ${pkgs.docker}/bin/docker exec authentik-server python - <<'PY' >/dev/null 2>&1; then
import os
import django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authentik.root.settings")
django.setup()
from authentik.sources.oauth.models import OAuthSource
OAuthSource.objects.count()
PY
          exit 0
        fi
      fi
      sleep 5
      attempt=$((attempt + 1))
    done
    echo "authentik-server container not ready after 5 minutes" >&2
    exit 1
  '';

  commonEnvArgs = lib.removeSuffix "\n" (
    lib.concatMapStrings formatDockerEnv (
      baseEnvLines
      ++ emailEnvLines
      ++ emailFromNameLine
      ++ extraEnvLines
    )
  );

in
{
  options.services.rave.authentik = {
    enable = mkEnableOption "Authentik identity provider (Dockerized)";

    dockerImage = mkOption {
      type = types.str;
      default = "ghcr.io/goauthentik/server:2024.6.2";
      description = "Container image tag used for both authentik server and worker.";
    };

    dockerImageArchive = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional path to a `docker save` tarball containing the Authentik image. When provided, the
        image is loaded from the tarball instead of pulling from the registry, allowing completely offline starts.
        Generate with `docker pull ${cfg.dockerImage} && docker save ${cfg.dockerImage} > artifacts/docker/authentik.tar`.
      '';
      example = ./artifacts/docker/authentik.tar;
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://auth.localtest.me:8443/";
      description = "External URL (including trailing slash) routed to Authentik via Traefik.";
    };

    rootDomain = mkOption {
      type = types.str;
      default = "auth.localtest.me";
      description = "Canonical domain Authentik should treat as its root domain.";
    };

    defaultExternalPort = mkOption {
      type = types.str;
      default = "8443";
      description = "Port advertised inside Authentik for generated callback URLs.";
    };

    cookieDomain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional override for the cookie domain (defaults to the host portion of publicUrl).";
    };

    hostPort = mkOption {
      type = types.int;
      default = 9130;
      description = "Loopback HTTP port exposed for Authentik inside the VM.";
    };

    metricsPort = mkOption {
      type = types.int;
      default = 9131;
      description = "Loopback port that exposes Authentik metrics (mapped from container port 9300).";
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
      description = "Log level passed to Authentik (debug, info, warning, error).";
    };

    disableUpdateCheck = mkOption {
      type = types.bool;
      default = true;
      description = "Disable upstream update checks/telemetry inside the container.";
    };

    secretKey = mkOption {
      type = types.nullOr types.str;
      default = "authentik-development-secret-key";
      description = "Inline Authentik secret key (ignored when secretKeyFile is set).";
    };

    secretKeyFile = mkOption {
      type = types.nullOr pathOrString;
      default = null;
      description = "Path to a file containing the Authentik secret key.";
    };

    bootstrap = {
      email = mkOption {
        type = types.str;
        default = "admin@example.com";
        description = "Bootstrap administrator email address.";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = "authentik-admin-password";
        description = "Bootstrap administrator password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "File containing the bootstrap administrator password.";
      };

      token = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional bootstrap token value (ignored when tokenFile is set).";
      };

      tokenFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Optional file path for the bootstrap token.";
      };

      enableDefaultUser = mkOption {
        type = types.bool;
        default = true;
        description = "Keep the default bootstrap user enabled after first run.";
      };
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "PostgreSQL host used by Authentik.";
      };

      port = mkOption {
        type = types.int;
        default = 5432;
        description = "PostgreSQL port.";
      };

      name = mkOption {
        type = types.str;
        default = "authentik";
        description = "Database name used by Authentik.";
      };

      user = mkOption {
        type = types.str;
        default = "authentik";
        description = "Database user Authentik authenticates as.";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = "authentik-db-password";
        description = "Database password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to a file containing the database password.";
      };

      sslMode = mkOption {
        type = types.str;
        default = "disable";
        description = "PostgreSQL SSL mode string.";
      };
    };

    redis = {
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host accessible from Docker containers for Redis (defaults to redis platform dockerHost).";
      };

      port = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Redis port override (defaults to redis platform port).";
      };

      database = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Logical Redis database index (defaults to redis.allocations.authentik when set).";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional Redis password.";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Optional Redis password file.";
      };
    };

    email = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SMTP settings for Authentik email notifications.";
      };

      fromAddress = mkOption {
        type = types.str;
        default = "authentik@localhost";
        description = "Default From address used for Authentik emails.";
      };

      fromName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional display name for the From header.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "SMTP host.";
      };

      port = mkOption {
        type = types.int;
        default = 25;
        description = "SMTP port.";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "SMTP username (optional).";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP password (ignored when passwordFile is set).";
      };

      passwordFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "File containing the SMTP password.";
      };

      useTls = mkOption {
        type = types.bool;
        default = false;
        description = "Enable STARTTLS/TLS for the SMTP transport.";
      };
    };

    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Event log retention window in days.";
    };

    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables passed to both server and worker containers.";
    };

    oauthSources = mkOption {
      type = types.attrsOf oauthSourceSubmodule;
      default = oauthSourcesDefault;
      description = ''
        Declarative OAuth sources (Google, GitHub, etc.) that Authentik should keep in sync.
        Each entry references client ID/secret files under /run/secrets and will be imported automatically.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = secretProvided cfg.secretKey cfg.secretKeyFile;
        message = "services.rave.authentik.secretKey or secretKeyFile must be provided.";
      }
      {
        assertion = secretProvided cfg.database.password cfg.database.passwordFile;
        message = "services.rave.authentik.database.password or passwordFile must be provided.";
      }
      {
        assertion = secretProvided cfg.bootstrap.password cfg.bootstrap.passwordFile;
        message = "services.rave.authentik.bootstrap.password or passwordFile must be provided.";
      }
      {
        assertion = !(cfg.email.enable && cfg.email.username != "" && !secretProvided cfg.email.password cfg.email.passwordFile);
        message = "services.rave.authentik.email.password or passwordFile must be set when email is enabled with a username.";
      }
    ];

    services.postgresql.ensureDatabases = lib.mkAfter [ cfg.database.name ];
    services.postgresql.ensureUsers = lib.mkAfter [
      { name = cfg.database.user; ensureDBOwnership = true; }
    ];
    systemd.services.postgresql.postStart = lib.mkAfter ''
      ${pkgs.postgresql}/bin/psql -U postgres -c "ALTER USER ${cfg.database.user} PASSWORD '${dbPasswordSqlExpr}';" || true
    '';

    systemd.services."docker-pull-authentik" = {
      description = "Pre-pull Authentik Docker image";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = pkgs.writeShellScript "authentik-prefetch-image" ''
          set -euo pipefail

          ${lib.optionalString (cfg.dockerImageArchive != null) ''
            if [ ! -r ${cfg.dockerImageArchive} ]; then
              echo "Authentik image archive missing at ${cfg.dockerImageArchive}" >&2
              exit 1
            fi
            echo "Loading Authentik Docker image from ${cfg.dockerImageArchive} ..."
            ${pkgs.docker}/bin/docker load -i ${cfg.dockerImageArchive} >/dev/null
          ''}
          ${lib.optionalString (cfg.dockerImageArchive == null) ''
            echo "Pulling Authentik Docker image ${cfg.dockerImage} ..."
            ${pkgs.docker}/bin/docker pull ${cfg.dockerImage}
          ''}
        '';
      };
    };

    systemd.services.authentik-server = {
      description = "Authentik server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "docker.service" "postgresql.service" redisUnit "docker-pull-authentik.service" ];
      requires = [ "docker.service" "postgresql.service" redisUnit "docker-pull-authentik.service" ];
      wants =
        [ "authentik-worker.service" ]
        ++ lib.optional (syncOAuthSourcesScript != null) "authentik-sync-oauth-sources.service";
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre =
          [
            "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f authentik-server >/dev/null 2>&1 || true'"
          ]
          ++ volumeCreateCommands;
        ExecStart = pkgs.writeShellScript "authentik-server-start" ''
          set -euo pipefail

          ${readSecretSnippet "AUTHENTIK_SECRET_KEY" cfg.secretKey cfg.secretKeyFile}
          ${readSecretSnippet "AUTHENTIK_DB_PASSWORD" cfg.database.password cfg.database.passwordFile}
          ${readSecretSnippet "AUTHENTIK_BOOTSTRAP_PASSWORD" cfg.bootstrap.password cfg.bootstrap.passwordFile}
          ${optionalString bootstrapTokenConfigured (readSecretSnippet "AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" cfg.bootstrap.token cfg.bootstrap.tokenFile)}
          ${optionalString redisPasswordConfigured (readSecretSnippet "AUTHENTIK_REDIS_PASSWORD" cfg.redis.password cfg.redis.passwordFile)}
          ${optionalString emailPasswordConfigured (readSecretSnippet "AUTHENTIK_EMAIL_PASSWORD" cfg.email.password cfg.email.passwordFile)}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name authentik-server \
            --add-host host.docker.internal:host-gateway \
            -p 127.0.0.1:${toString cfg.hostPort}:9000 \
            -p 127.0.0.1:${toString cfg.metricsPort}:9300 \
${volumeRunArgs}${commonEnvArgs}
            ${cfg.dockerImage} server
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop authentik-server";
      };
    };

    systemd.services.authentik-worker = {
      description = "Authentik worker";
      wantedBy = lib.mkForce [];
      partOf = [ "authentik-server.service" ];
      after = [ "authentik-server.service" ];
      requires = [ "authentik-server.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
        ExecStartPre =
          [
            "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker rm -f authentik-worker >/dev/null 2>&1 || true'"
          ]
          ++ volumeCreateCommands;
        ExecStart = pkgs.writeShellScript "authentik-worker-start" ''
          set -euo pipefail

          ${readSecretSnippet "AUTHENTIK_SECRET_KEY" cfg.secretKey cfg.secretKeyFile}
          ${readSecretSnippet "AUTHENTIK_DB_PASSWORD" cfg.database.password cfg.database.passwordFile}
          ${readSecretSnippet "AUTHENTIK_BOOTSTRAP_PASSWORD" cfg.bootstrap.password cfg.bootstrap.passwordFile}
          ${optionalString bootstrapTokenConfigured (readSecretSnippet "AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" cfg.bootstrap.token cfg.bootstrap.tokenFile)}
          ${optionalString redisPasswordConfigured (readSecretSnippet "AUTHENTIK_REDIS_PASSWORD" cfg.redis.password cfg.redis.passwordFile)}
          ${optionalString emailPasswordConfigured (readSecretSnippet "AUTHENTIK_EMAIL_PASSWORD" cfg.email.password cfg.email.passwordFile)}

          exec ${pkgs.docker}/bin/docker run \
            --rm \
            --name authentik-worker \
            --add-host host.docker.internal:host-gateway \
${volumeRunArgs}${commonEnvArgs}
            ${cfg.dockerImage} worker
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop authentik-worker";
      };
    };

    system.extraDependencies = lib.optionals (cfg.dockerImageArchive != null) [
      cfg.dockerImageArchive
    ];

    systemd.services.authentik-sync-oauth-sources = lib.mkIf (syncOAuthSourcesScript != null) {
      description = "Synchronize Authentik OAuth sources";
      wantedBy = [ "multi-user.target" ];
      requires = [ "authentik-server.service" ];
      bindsTo = [ "authentik-server.service" ];
      after = [ "authentik-server.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = waitForAuthentikContainer;
        Restart = "on-failure";
        RestartSec = 10;
        ExecStart = syncOAuthSourcesScript;
      };
    };
  };
}
