{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.traefik;
  behindPomerium = cfg.behindPomerium;
  backendPort = cfg.backendPort;

  pathOrString = types.either types.path types.str;

  baseHttpsPortValue = config.services.rave.ports.https;
  baseHttpsPort = toString baseHttpsPortValue;
  host = cfg.host;
  chatDomain = cfg.chatDomain;
  certificate = cfg.certificate;

  mattermostEnabled = config.services.rave.mattermost.enable;
  mattermostPublicUrl = config.services.rave.mattermost.publicUrl;
  mattermostInternalBaseUrl = config.services.rave.mattermost.internalBaseUrl;
  mattermostProxyTarget = if pomeriumEnabled && !behindPomerium then pomeriumLoopbackBase else mattermostInternalBaseUrl;

  gitlabEnabled = config.services.rave.gitlab.enable;
  gitlabPackage = config.services.gitlab.packages.gitlab or null;

  natsEnabled = config.services.rave.nats.enable;
  natsHttpPort = toString config.services.rave.nats.httpPort;

  n8nEnabled = config.services.rave.n8n.enable;
  n8nHostPort = toString config.services.rave.n8n.hostPort;
  n8nBasePath =
    let
      raw = if config.services.rave.n8n.basePath == ""
        then "/n8n"
        else config.services.rave.n8n.basePath;
      withLeading = if lib.hasPrefix "/" raw then raw else "/${raw}";
    in withLeading;
  n8nNormalizedPath = if lib.hasSuffix "/" n8nBasePath then n8nBasePath else "${n8nBasePath}/";
  n8nRedirectPath =
    let trimmed = lib.removeSuffix "/" n8nNormalizedPath;
    in if trimmed == "" then "/" else trimmed;

  monitoringEnabled = config.services.rave.monitoring.enable;
  grafanaHttpPort = toString config.services.rave.monitoring.grafana.httpPort;
  grafanaPath = pathFromUrl grafanaUrl;
  grafanaRedirectPath = trimTrailingSlash grafanaPath;
  promPath = normalizePath config.services.rave.monitoring.prometheus.publicPath;
  promRedirectPath = trimTrailingSlash promPath;
  promPortStr = toString config.services.rave.monitoring.prometheus.port;

  outlineEnabled = config.services.rave.outline.enable;
  outlinePortStr = toString config.services.rave.outline.hostPort;
  outlineUrl = normalizeUrl config.services.rave.outline.publicUrl;
  outlinePath = pathFromUrl outlineUrl;
  outlineRedirectPath = trimTrailingSlash outlinePath;
  hostFromUrl = url:
    if url == null then null
    else
      let matchResult = builtins.match "https?://([^/:]+).*" url;
      in if matchResult == null || matchResult == [] then null else builtins.head matchResult;
  outlineHostName = hostFromUrl outlineUrl;
  outlineSeparateHost = outlineEnabled && outlineHostName != null && outlineHostName != host;
  outlineLegacyPath = "/outline/";
  outlineAssetPrefixes = [
    "/_next/"
    "/static/"
    "/images/"
    "/email/"
    "/fonts/"
    "/locales/"
    "/s/"
    "/share/"
    "/doc/"
    "/embeds/"
  ];
  outlineAssetFiles = [
    "/opensearch.xml"
    "/robots.txt"
    "/manifest.webmanifest"
    "/sw.js"
    "/favicon.ico"
    "/icon.png"
    "/icon-192x192.png"
    "/icon-512x512.png"
    "/apple-touch-icon.png"
  ];

  penpotEnabled = config.services.rave.penpot.enable;
  penpotPortStr = toString config.services.rave.penpot.frontendPort;
  penpotUrl = normalizeUrl config.services.rave.penpot.publicUrl;
  penpotPath = pathFromUrl penpotUrl;
  penpotRedirectPath = trimTrailingSlash penpotPath;

  authentikEnabled = config.services.rave.authentik.enable;
  authentikPortStr = toString config.services.rave.authentik.hostPort;
  authentikUrl = normalizeUrl config.services.rave.authentik.publicUrl;
  authentikPath = pathFromUrl authentikUrl;
  authentikHostName = hostFromUrl authentikUrl;
  authentikSeparateHost = authentikEnabled && authentikHostName != null && authentikHostName != host;

  pomeriumEnabled = config.services.rave.pomerium.enable;
  pomeriumLoopbackBase = "http://127.0.0.1:${toString config.services.rave.pomerium.httpPort}";
  pomeriumLoopbackConsole = "${pomeriumLoopbackBase}/";
  pomeriumPublicUrl = normalizeUrl config.services.rave.pomerium.publicUrl;
  pomeriumPath = pathFromUrl pomeriumPublicUrl;
  pomeriumRedirectPath = trimTrailingSlash pomeriumPath;
  pomeriumProxyConfig = mkProxyExtra pomeriumPath;

  inherit (lib.strings) escapeXML;

  normalizeUrl = url:
    if url == null then null
    else if lib.hasSuffix "/" url then url else "${url}/";

  baseHttpsUrl = "https://${host}:${baseHttpsPort}";

  grafanaUrl =
    let grafanaCfg = config.services.rave.monitoring.grafana;
        derived =
          if grafanaCfg.publicUrl != null then grafanaCfg.publicUrl
          else "${baseHttpsUrl}/grafana/";
    in normalizeUrl derived;

  ensureLeadingSlash = path: if lib.hasPrefix "/" path then path else "/${path}";
  ensureTrailingSlash = path: if lib.hasSuffix "/" path then path else "${path}/";
  normalizePath = path: ensureTrailingSlash (ensureLeadingSlash (if path == "" then "/" else path));

  pathFromUrl = url:
    if url == null then "/"
    else
      let
        normalized = normalizeUrl url;
        matchResult = builtins.match "https?://[^/]+(.*)" normalized;
        tail =
          if matchResult == null || matchResult == [] then "/"
          else builtins.head matchResult;
      in normalizePath tail;

  trimTrailingSlash = path:
    if path == "/" then "/"
    else
      let trimmed = lib.removeSuffix "/" path;
      in if trimmed == "" then "/" else trimmed;

  mkProxyExtra =
    path:
    let
      normalized =
        if path == null then null else ensureTrailingSlash path;
      prefixHeaderWithSlash =
        if normalized == null || normalized == "/" then null else normalized;
      prefixHeaderNoSlash =
        if normalized == null then null
        else
          let trimmed = trimTrailingSlash normalized;
          in if trimmed == "/" then null else trimmed;
    in ''
      proxy_set_header Host "$host:$rave_forwarded_port";
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Port $rave_forwarded_port;
      proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
      proxy_set_header X-Forwarded-Ssl on;
      ${optionalString (prefixHeaderWithSlash != null) "proxy_set_header X-Forwarded-Prefix ${prefixHeaderWithSlash};"}
      ${optionalString (prefixHeaderNoSlash != null) "proxy_set_header X-Script-Name ${prefixHeaderNoSlash};"}
      proxy_set_header X-Forwarded-Uri $request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_redirect off;
    '';

  mkCard = { title, description, url, icon, status }:
    let
      safeTitle = escapeXML title;
      safeDesc = escapeXML description;
      safeUrl = escapeXML url;
      safeStatus = escapeXML status;
    in ''
      <a class="service-card" href="${safeUrl}" target="_blank" rel="noopener noreferrer">
        <div class="service-header">
          <div class="service-icon" aria-hidden="true">
            <i data-lucide="${icon}"></i>
          </div>
          <span class="service-status">${safeStatus}</span>
        </div>
        <div class="service-title">${safeTitle}</div>
        <p class="service-desc">${safeDesc}</p>
        <span class="service-url">${safeUrl}</span>
      </a>
    '';

  serviceCards =
    (lib.optionals gitlabEnabled [
      (mkCard {
        title = "GitLab";
        description = "Source control, issues, and CI/CD";
        icon = "git-branch";
        url = normalizeUrl config.services.rave.gitlab.publicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals mattermostEnabled [
      (mkCard {
        title = "Mattermost";
        description = "Team chat and incident comms";
        icon = "messages-square";
        url = normalizeUrl mattermostPublicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals config.services.rave.monitoring.enable [
      (mkCard {
        title = "Grafana";
        description = "Observability dashboards";
        icon = "activity";
        url = grafanaUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals config.services.rave.penpot.enable [
      (mkCard {
        title = "Penpot";
        description = "Design collaboration";
        icon = "pen-tool";
        url = normalizeUrl config.services.rave.penpot.publicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals authentikEnabled [
      (mkCard {
        title = "Authentik";
        description = "Identity provider";
        icon = "shield";
        url = normalizeUrl config.services.rave.authentik.publicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals config.services.rave.outline.enable [
      (mkCard {
        title = "Outline";
        description = "Knowledge base & docs";
        icon = "book-open-check";
        url = normalizeUrl config.services.rave.outline.publicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals n8nEnabled [
      (mkCard {
        title = "n8n";
        description = "Automation workflows";
        icon = "workflow";
        url = normalizeUrl config.services.rave.n8n.publicUrl;
        status = "Enabled";
      })
    ])
    ++ (lib.optionals (pomeriumEnabled && !behindPomerium) [
      (mkCard {
        title = "Pomerium";
        description = "Identity-aware proxy gateway";
        icon = "shield-check";
        url = pomeriumPublicUrl;
        status = "Enabled";
      })
    ]);

  cardsHtml = lib.concatStringsSep "\n" serviceCards;
  cardsCount = builtins.length serviceCards;
  cardsSummary =
    if cardsCount == 0 then "No web services enabled in this image"
    else if cardsCount == 1 then "1 service available"
    else "${toString cardsCount} services available";

  generatedDashboardHtml = ''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${escapeXML host} · RAVE services</title>
    <link rel="preconnect" href="https://unpkg.com" />
    <script defer src="https://unpkg.com/lucide@latest"></script>
    <style>
      :root {
        color-scheme: dark;
        --bg: #0b0c0f;
        --bg-soft: #11141a;
        --panel: #161a21;
        --panel-gradient: linear-gradient(145deg, rgba(30,34,41,0.9), rgba(14,16,19,0.95));
        --border: rgba(255,255,255,0.08);
        --text: #f5f7fa;
        --muted: #9aa3b5;
        --accent: #3ce0a1;
        --status-ok: #4ade80;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        background: radial-gradient(circle at 20% 20%, #1d1f29, #08090c 70%);
        font-family: "Inter", system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
        color: var(--text);
      }
      .page {
        max-width: 1100px;
        margin: 0 auto;
        padding: 64px 24px 96px;
      }
      .hero {
        margin-bottom: 40px;
        padding: 32px;
        background: var(--panel);
        border-radius: 24px;
        border: 1px solid var(--border);
        box-shadow: 0 25px 80px rgba(0,0,0,0.4), inset 0 0 0 1px rgba(255,255,255,0.02);
      }
      .hero .kicker {
        text-transform: uppercase;
        letter-spacing: 0.4em;
        font-size: 12px;
        color: var(--muted);
        margin: 0 0 12px;
      }
      .hero h1 {
        margin: 0;
        font-size: 34px;
      }
      .hero p {
        margin: 8px 0 0;
        color: var(--muted);
      }
      .service-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 20px;
      }
      .service-card {
        display: block;
        text-decoration: none;
        background: var(--panel-gradient);
        border: 1px solid var(--border);
        border-radius: 20px;
        padding: 24px;
        transition: transform 150ms ease, border-color 150ms ease, box-shadow 150ms ease;
        color: var(--text);
        box-shadow: 0 12px 30px rgba(0,0,0,0.35);
        position: relative;
        overflow: hidden;
      }
      .service-card::after {
        content: "";
        position: absolute;
        inset: 0;
        opacity: 0;
        background: radial-gradient(circle at top right, rgba(60,224,161,0.15), transparent 60%);
        transition: opacity 150ms ease;
      }
      .service-card:hover {
        transform: translateY(-6px);
        border-color: var(--accent);
        box-shadow: 0 30px 60px rgba(0,0,0,0.45);
      }
      .service-card:hover::after {
        opacity: 1;
      }
      .service-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 18px;
      }
      .service-icon {
        display: inline-flex;
        width: 56px;
        height: 56px;
        border-radius: 16px;
        background: rgba(255,255,255,0.08);
        align-items: center;
        justify-content: center;
      }
      .service-icon i {
        width: 28px;
        height: 28px;
      }
      .service-status {
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--status-ok);
        background: rgba(74, 222, 128, 0.12);
        border: 1px solid rgba(74, 222, 128, 0.35);
        border-radius: 999px;
        padding: 4px 11px;
        font-weight: 600;
      }
      .service-title {
        font-size: 20px;
        font-weight: 600;
        margin: 0 0 6px;
      }
      .service-desc {
        margin: 6px 0 16px;
        color: var(--muted);
        font-size: 14px;
      }
      .service-url {
        font-size: 12px;
        color: var(--accent);
        word-break: break-word;
      }
      .empty-state {
        padding: 32px;
        text-align: center;
        border: 1px dashed var(--border);
        border-radius: 16px;
        background: rgba(255,255,255,0.02);
        color: var(--muted);
      }
    </style>
  </head>
  <body>
    <div class="page">
      <header class="hero">
        <p class="kicker">RAVE VM</p>
        <h1>${escapeXML host}</h1>
        <p>${escapeXML cardsSummary}</p>
      </header>
      <section class="service-grid">
        ${if cardsCount > 0 then cardsHtml else ''
          <div class="empty-state">
            No optional web applications are enabled. Enable GitLab, Mattermost, or another service in your Nix profile to populate this dashboard.
          </div>
        ''}
      </section>
    </div>
    <script>
      document.addEventListener('DOMContentLoaded', () => {
        if (window.lucide) {
          window.lucide.createIcons();
        }
      });
    </script>
  </body>
</html>
'';

  defaultDashboardHtml = generatedDashboardHtml;
  dashboardStaticRoot = pkgs.writeTextDir "index.html" cfg.dashboardHtml;


  dashboardPort = cfg.dashboard.port;
  gitlabProxyPort = config.services.rave.gitlab.proxy.port or 8235;

  hostRule = domain: "Host(`" + domain + "`)";
  pathPrefixRule = path: "PathPrefix(`" + path + "`)";
  exactPathRule = path: "Path(`" + path + "`)";

  loopbackEnabled = (!behindPomerium) && baseHttpsPortValue != 443;
  mattermostLoopbackEnabled = mattermostEnabled && !behindPomerium;

  entryPoints =
    let
      base =
        if behindPomerium then {
          backend = { address = "127.0.0.1:${toString backendPort}"; };
        } else {
          web = {
            address = ":80";
            http.redirections.entryPoint = {
              to = "websecure";
              scheme = "https";
              permanent = true;
            };
          };
          websecure = {
            address = ":443";
            http.tls = {};
          };
        };
    in
      base
      // optionalAttrs loopbackEnabled {
        loopback = {
          address = "127.0.0.1:${baseHttpsPort}";
          http.tls = {};
        };
      }
      // optionalAttrs mattermostLoopbackEnabled {
        mattermostHttps = {
          address = ":${toString cfg.mattermostLoopbackPorts.https}";
          http.tls = {};
        };
        mattermostHttp = {
          address = ":${toString cfg.mattermostLoopbackPorts.http}";
          http.redirections.entryPoint = {
            to = "mattermostHttps";
            scheme = "https";
            permanent = true;
          };
        };
      };

  primaryEntrypoints =
    if behindPomerium then [ "backend" ]
    else [ "websecure" ] ++ optional loopbackEnabled "loopback";

  defaultSecurityMiddlewares = [ "rave-security-headers" ];


  middlewareSets =
    [
      { "rave-security-headers" = {
          headers.customResponseHeaders = {
            "Strict-Transport-Security" = "max-age=31536000; includeSubDomains; preload";
            "X-Content-Type-Options" = "nosniff";
            "X-Frame-Options" = "DENY";
            "X-XSS-Protection" = "1; mode=block";
            "Referrer-Policy" = "strict-origin-when-cross-origin";
          };
        };
      }
    ]
    ++ optionals gitlabEnabled [
      { "gitlab-headers" = {
          headers.customRequestHeaders = {
            "X-Script-Name" = "/gitlab";
            "X-Forwarded-Prefix" = "/gitlab";
            "X-Forwarded-Proto" = "https";
            "X-Forwarded-Port" = baseHttpsPort;
          };
        };
      }
      { "gitlab-buffering" = {
          buffering = {
            maxRequestBodyBytes = 10737418240;
            maxResponseBodyBytes = 10737418240;
            memRequestBodyBytes = 268435456;
            memResponseBodyBytes = 268435456;
          };
        };
      }
      { "gitlab-slash-redirect" = {
          redirectRegex = {
            regex = "^(https?://[^/]+/gitlab)$";
            replacement = "$1/";
            permanent = true;
          };
        };
      }
      { "gitlab-health-rewrite" = {
          replacePath.path = "/-/health";
        };
      }
      { "registry-headers" = {
          headers.customRequestHeaders."Docker-Distribution-Api-Version" = "registry/2.0";
        };
      }
    ]
    ++ optionals mattermostEnabled [
      { "mattermost-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = "/mattermost";
        };
      }
      { "mattermost-buffering" = {
          buffering.maxRequestBodyBytes = 104857600;
        };
      }
    ]
    ++ optionals n8nEnabled [
      { "n8n-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = n8nNormalizedPath;
        };
      }
      { "n8n-buffering" = {
          buffering.maxRequestBodyBytes = 104857600;
        };
      }
    ]
    ++ optionals natsEnabled [
      { "nats-headers" = {
          headers.customRequestHeaders."NATS-Server" = config.services.rave.nats.serverName;
        };
      }
    ]
    ++ optionals monitoringEnabled [
      { "grafana-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = grafanaPath;
        };
      }
      { "prometheus-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = promPath;
        };
      }
    ]
    ++ optionals outlineEnabled [
      { "outline-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = outlinePath;
        };
      }
    ]
    ++ optionals (outlineEnabled && outlineSeparateHost) [
      { "outline-legacy-redirect" = {
          redirectRegex = {
            regex = "^https?://[^/]+${trimTrailingSlash outlineLegacyPath}$";
            replacement = outlineUrl;
            permanent = true;
          };
        };
      }
    ]
    ++ optionals penpotEnabled [
      { "penpot-headers" = {
          headers.customRequestHeaders."X-Forwarded-Prefix" = penpotPath;
        };
      }
    ];

  middlewares = mkMerge middlewareSets;

  serviceSets =
    [
      { "dashboard" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${toString dashboardPort}"; } ];
          };
        };
      }
    ]
    ++ optionals gitlabEnabled [
      { "gitlab" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${toString gitlabProxyPort}"; } ];
          };
        };
      }
      { "gitlab-registry" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:5000"; } ];
          };
        };
      }
    ]
    ++ optionals mattermostEnabled [
      { "mattermost" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = mattermostProxyTarget; } ];
          };
        };
      }
    ]
    ++ optionals n8nEnabled [
      { "n8n" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${n8nHostPort}"; } ];
          };
        };
      }
    ]
    ++ optionals monitoringEnabled [
      { "grafana" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${grafanaHttpPort}"; } ];
          };
        };
      }
      { "prometheus" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${promPortStr}"; } ];
          };
        };
      }
    ]
    ++ optionals outlineEnabled [
      { "outline" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${outlinePortStr}"; } ];
          };
        };
      }
    ]
    ++ optionals penpotEnabled [
      { "penpot" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${penpotPortStr}"; } ];
          };
        };
      }
    ]
    ++ optionals authentikEnabled [
      { "authentik" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${authentikPortStr}"; } ];
          };
        };
      }
    ]
    ++ optionals (pomeriumEnabled && !behindPomerium) [
      { "pomerium-console" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = pomeriumLoopbackConsole; } ];
          };
        };
      }
      { "pomerium-internal" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = pomeriumLoopbackBase; } ];
          };
        };
      }
    ]
    ++ optionals natsEnabled [
      { "nats" = {
          loadBalancer = {
            passHostHeader = true;
            servers = [ { url = "http://127.0.0.1:${natsHttpPort}"; } ];
          };
        };
      }
    ];

  services = mkMerge serviceSets;

  rootService = if authentikEnabled then "authentik" else "dashboard";

  routerSets =
    [
      { "root" = {
          rule = "${hostRule host} && (Path(`/`) || Path(`/index.html`))";
          service = rootService;
        };
      }
    ]
    ++ optionals gitlabEnabled [
      { "gitlab-main" = {
          rule = "${hostRule host} && ${pathPrefixRule "/gitlab"}";
          service = "gitlab";
          middlewares = defaultSecurityMiddlewares ++ [ "gitlab-headers" "gitlab-buffering" ];
        };
      }
      { "gitlab-root-redirect" = {
          rule = "${hostRule host} && ${exactPathRule "/gitlab"}";
          service = "gitlab";
          middlewares = [ "gitlab-slash-redirect" ];
        };
      }
      { "gitlab-registry" = {
          rule = "${hostRule host} && ${pathPrefixRule "/registry"}";
          service = "gitlab-registry";
          middlewares = defaultSecurityMiddlewares ++ [ "registry-headers" ];
        };
      }
      { "gitlab-health" = {
          rule = "${hostRule host} && ${pathPrefixRule "/health/gitlab"}";
          service = "gitlab";
          middlewares = defaultSecurityMiddlewares ++ [ "gitlab-health-rewrite" ];
        };
      }
    ]
    ++ optionals mattermostEnabled [
      { "mattermost-main" = {
          rule = "${hostRule host} && ${pathPrefixRule "/mattermost"}";
          service = "mattermost";
          middlewares = defaultSecurityMiddlewares ++ [ "mattermost-headers" "mattermost-buffering" ];
        };
      }
    ]
    ++ optionals mattermostLoopbackEnabled [
      { "mattermost-loopback" = {
          rule = "${hostRule host} && ${pathPrefixRule "/mattermost"}";
          service = "mattermost";
          entryPoints = [ "mattermostHttps" ];
          middlewares = defaultSecurityMiddlewares ++ [ "mattermost-headers" "mattermost-buffering" ];
        };
      }
    ]
    ++ optionals (mattermostEnabled && chatDomain != null && !behindPomerium) [
      { "mattermost-chat-domain" = {
          rule = hostRule chatDomain;
          service = "mattermost";
          middlewares = defaultSecurityMiddlewares ++ [ "mattermost-headers" "mattermost-buffering" ];
        };
      }
    ]
    ++ optionals n8nEnabled [
      { "n8n" = {
          rule = "${hostRule host} && ${pathPrefixRule n8nNormalizedPath}";
          service = "n8n";
          middlewares = defaultSecurityMiddlewares ++ [ "n8n-headers" "n8n-buffering" ];
        };
      }
    ]
    ++ optionals monitoringEnabled [
      { "grafana" = {
          rule = "${hostRule host} && ${pathPrefixRule grafanaPath}";
          service = "grafana";
          middlewares = defaultSecurityMiddlewares ++ [ "grafana-headers" ];
        };
      }
      { "prometheus" = {
          rule = "${hostRule host} && ${pathPrefixRule promPath}";
          service = "prometheus";
          middlewares = defaultSecurityMiddlewares ++ [ "prometheus-headers" ];
        };
      }
    ]
    ++ optionals natsEnabled [
      { "nats" = {
          rule = "${hostRule host} && ${pathPrefixRule "/nats"}";
          service = "nats";
          middlewares = defaultSecurityMiddlewares ++ [ "nats-headers" ];
        };
      }
    ]
    ++ optionals (outlineEnabled && !outlineSeparateHost) [
      { "outline" = {
          rule = "${hostRule host} && ${pathPrefixRule outlinePath}";
          service = "outline";
          middlewares = defaultSecurityMiddlewares ++ [ "outline-headers" ];
        };
      }
    ]
    ++ optionals (outlineEnabled && outlineSeparateHost) [
      { "outline-host" = {
          rule = hostRule outlineHostName;
          service = "outline";
          middlewares = defaultSecurityMiddlewares;
        };
      }
      { "outline-legacy" = {
          rule = "${hostRule host} && ${pathPrefixRule outlineLegacyPath}";
          service = "outline";
          middlewares = [ "outline-legacy-redirect" ];
        };
      }
    ]
    ++ optionals (outlineEnabled && outlinePath != "/" && !outlineSeparateHost) [
      { "outline-api" = {
          rule = "${hostRule host} && ${pathPrefixRule "/api"}";
          service = "outline";
          middlewares = defaultSecurityMiddlewares ++ [ "outline-headers" ];
        };
      }
    ]
    ++ optionals penpotEnabled [
      { "penpot" = {
          rule = "${hostRule host} && ${pathPrefixRule penpotPath}";
          service = "penpot";
          middlewares = defaultSecurityMiddlewares ++ [ "penpot-headers" ];
        };
      }
    ]
    ++ optionals (authentikEnabled && !authentikSeparateHost) [
      { "authentik" = {
          rule = "${hostRule host} && ${pathPrefixRule authentikPath}";
          service = "authentik";
          middlewares = defaultSecurityMiddlewares;
        };
      }
    ]
    ++ optionals (authentikEnabled && authentikSeparateHost) [
      { "authentik-host" = {
          rule = "${hostRule authentikHostName} && ${pathPrefixRule authentikPath}";
          service = "authentik";
          middlewares = defaultSecurityMiddlewares;
        };
      }
    ]
    ++ optionals (authentikEnabled && authentikSeparateHost) [
      { "authentik-fallback" = {
          rule = hostRule host;
          service = "authentik";
          priority = -10;
        };
      }
    ]
    ++ optionals (pomeriumEnabled && !behindPomerium && pomeriumPath != "/") [
      { "pomerium-console" = {
          rule = "${hostRule host} && ${pathPrefixRule pomeriumPath}";
          service = "pomerium-console";
        };
      }
    ]
    ++ optionals (pomeriumEnabled && !behindPomerium) [
      { "pomerium-system" = {
          rule = "${hostRule host} && ${pathPrefixRule "/.pomerium"}";
          service = "pomerium-internal";
        };
      }
    ];

  routers = mkMerge routerSets;

  staticConfigOptions = {
    inherit entryPoints;
    providers.file.watch = true;
    log.level = "INFO";
    accessLog.filePath = "/var/log/traefik/access.log";
    api.dashboard = false;
  };

  dynamicConfigOptions =
    {
      http = {
        inherit routers services middlewares;
      };
    }
    // optionalAttrs (!behindPomerium) {
      tls.certificates = [
        {
          certFile = certificate.certFile;
          keyFile = certificate.keyFile;
        }
      ];
    };

in
{
  options.services.rave.traefik = {
    enable = mkEnableOption "Traefik front-door configuration for the RAVE environment";

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "Primary hostname served by Traefik.";
    };

    behindPomerium = mkOption {
      type = types.bool;
      default = false;
      description = "Expose Traefik only on loopback and expect Pomerium to terminate TLS.";
    };

    backendPort = mkOption {
      type = types.int;
      default = 9443;
      description = "Loopback port used when Traefik runs behind Pomerium.";
    };

    chatDomain = mkOption {
      type = types.nullOr types.str;
      default = "chat.localtest.me";
      description = "Optional vanity domain that proxies directly to Mattermost.";
    };

    certificate = {
      certFile = mkOption {
        type = pathOrString;
        default = "/var/lib/acme/localhost/cert.pem";
        description = "Path to the TLS certificate served by Traefik.";
      };

      keyFile = mkOption {
        type = pathOrString;
        default = "/var/lib/acme/localhost/key.pem";
        description = "Path to the TLS key served by Traefik.";
      };
    };

    mattermostLoopbackPorts = {
      https = mkOption {
        type = types.int;
        default = 8231;
        description = "HTTPS port exposed for the dedicated Mattermost loopback entrypoint.";
      };

      http = mkOption {
        type = types.int;
        default = 8230;
        description = "HTTP port exposed for the dedicated Mattermost loopback entrypoint.";
      };
    };

    dashboardHtml = mkOption {
      type = types.str;
      default = defaultDashboardHtml;
      description = "HTML content rendered on the root landing page.";
    };

    dashboard = {
      port = mkOption {
        type = types.int;
        default = 11880;
        description = "Loopback port used by the static dashboard helper service.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      systemd.services.rave-dashboard = {
        description = "Serve RAVE landing page";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = dashboardStaticRoot;
          ExecStart = ''
            ${pkgs.python3}/bin/python -m http.server ${toString dashboardPort}               --bind 127.0.0.1               --directory ${dashboardStaticRoot}
          '';
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      services.traefik = {
        enable = true;
        inherit staticConfigOptions dynamicConfigOptions;
      };

      systemd.services.traefik = {
        after = mkAfter (
          [ "network.target" "rave-dashboard.service" ]
          ++ optional (!behindPomerium) "generate-localhost-certs.service"
          ++ optional gitlabEnabled "gitlab-proxy-nginx.service"
        );
        wants = [ "rave-dashboard.service" ] ++ optional gitlabEnabled "gitlab-proxy-nginx.service";
        requires = optional (!behindPomerium) "generate-localhost-certs.service";
      };

      systemd.tmpfiles.rules = [
        "d /var/log/traefik 0755 traefik traefik -"
      ];
    }
  ]);
}
