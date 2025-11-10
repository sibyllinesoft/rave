{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.nginx;

  pathOrString = types.either types.path types.str;

  baseHttpsPort = toString config.services.rave.ports.https;
  host = cfg.host;
  chatDomain = cfg.chatDomain;
  certificate = cfg.certificate;

  mattermostEnabled = config.services.rave.mattermost.enable;
  mattermostPublicUrl = config.services.rave.mattermost.publicUrl;
  mattermostInternalBaseUrl = config.services.rave.mattermost.internalBaseUrl;
  mattermostProxyTarget = mattermostInternalBaseUrl;

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


  mattermostProxyConfig = ''
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

  n8nProxyConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Port $rave_forwarded_port;
          proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
          proxy_set_header X-Forwarded-Prefix ${n8nNormalizedPath};
          proxy_set_header X-Forwarded-Ssl on;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          client_max_body_size 100M;
          proxy_redirect off;
'';

  natsProxyConfig = ''
          proxy_set_header Host "$host:$rave_forwarded_port";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
'';

in
{
  options.services.rave.nginx = {
    enable = mkEnableOption "Front-door nginx configuration for the RAVE environment";

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "Primary hostname served by nginx.";
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
        description = "Path to the TLS certificate served by nginx.";
      };

      keyFile = mkOption {
        type = pathOrString;
        default = "/var/lib/acme/localhost/key.pem";
        description = "Path to the TLS key served by nginx.";
      };
    };

    mattermostLoopbackPorts = {
      https = mkOption {
        type = types.int;
        default = 8231;
        description = "HTTPS port exposed for the dedicated Mattermost loopback vhost.";
      };

      http = mkOption {
        type = types.int;
        default = 8230;
        description = "HTTP port exposed for the dedicated Mattermost loopback vhost.";
      };
    };

    dashboardHtml = mkOption {
      type = types.str;
      default = defaultDashboardHtml;
      description = "HTML content rendered on the root landing page.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.nginx = {
        enable = true;
        commonHttpConfig = ''
          map $http_host $rave_forwarded_port {
            default 443;
            ~:(?<port>\d+)$ $port;
          }
        '';
        clientMaxBodySize = "10G";
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = false;
        recommendedTlsSettings = true;
        logError = "/var/log/nginx/error.log debug";
        statusPage = true;
      };

      services.nginx.virtualHosts."${host}" = {
        forceSSL = true;
        enableACME = false;
        listen = [
          { addr = "0.0.0.0"; port = 443; ssl = true; }
          { addr = "0.0.0.0"; port = 80; ssl = false; }
        ];
        sslCertificate = certificate.certFile;
        sslCertificateKey = certificate.keyFile;
        locations = mkMerge (
          [
            {
              "/" = {
                root = dashboardStaticRoot;
                index = "index.html";
                tryFiles = "$uri /index.html";
              };
            }
          ]
          ++ optional gitlabEnabled (
            {
              "/gitlab/" = {
                proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
                proxyWebsockets = true;
                extraConfig = ''
                  proxy_set_header Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Ssl on;
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                  proxy_set_header Upgrade $http_upgrade;
                  proxy_set_header Connection $connection_upgrade;
                  proxy_cache_bypass $http_upgrade;
                  proxy_set_header X-Script-Name /gitlab;
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                  client_max_body_size 10G;
                  proxy_connect_timeout 300s;
                  proxy_send_timeout 300s;
                  proxy_read_timeout 300s;
                '';
              };
              "= /gitlab" = {
                return = "301 /gitlab/";
              };
              "~ ^/gitlab/assets/(.*)$" = {
                alias = "${gitlabPackage}/share/gitlab/public/assets/$1";
                extraConfig = ''
                  expires 1y;
                '';
              };
              "~ ^/gitlab/(-/.*)$" = {
                alias = "${gitlabPackage}/share/gitlab/public$1";
                extraConfig = ''
                  expires 1y;
                  try_files $uri =404;
                '';
              };
              "~ ^/gitlab/(uploads|files)/" = {
                proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
                extraConfig = ''
                  proxy_set_header Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Ssl on;
                  proxy_set_header X-Script-Name /gitlab;
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                '';
              };
              "~ ^/gitlab/.*/-/(artifacts|archive|raw)/" = {
                proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
                extraConfig = ''
                  proxy_set_header Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Forwarded-Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Ssl on;
                  proxy_set_header X-Script-Name /gitlab;
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                  client_max_body_size 10G;
                  proxy_request_buffering off;
                '';
              };
              "/registry/" = {
                proxyPass = "http://127.0.0.1:5000/";
                extraConfig = ''
                  proxy_set_header Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                  proxy_set_header Docker-Distribution-Api-Version registry/2.0;
                  client_max_body_size 0;
                  chunked_transfer_encoding on;
                '';
              };
              "/health/gitlab" = {
                proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/-/health";
                extraConfig = ''
                  access_log off;
                  proxy_set_header Host "$host:$rave_forwarded_port";
                  proxy_set_header X-Forwarded-Port $rave_forwarded_port;
                  proxy_intercept_errors on;
                  error_page 500 502 503 504 = @gitlab_unhealthy;
                '';
              };
              "@gitlab_unhealthy" = {
                return = "503 \"GitLab: Unavailable\"";
              };
            }
          )
          ++ optional mattermostEnabled {
            "/login" = {
              return = "302 ${mattermostPublicUrl}/";
            };

            "/mattermost/" = {
              proxyPass = mattermostProxyTarget;
              proxyWebsockets = true;
              extraConfig = mattermostProxyConfig;
            };

            "/mattermost" = {
              proxyPass = mattermostProxyTarget;
              proxyWebsockets = true;
              extraConfig = mattermostProxyConfig;
            };
          }
          ++ optional n8nEnabled {
            "${n8nNormalizedPath}" = {
              proxyPass = "http://127.0.0.1:${n8nHostPort}";
              proxyWebsockets = true;
              extraConfig = n8nProxyConfig;
            };
          }
          ++ optional (n8nEnabled && n8nRedirectPath != "/") {
            "${n8nRedirectPath}" = {
              return = "302 ${n8nNormalizedPath}";
            };
          }
          ++ optional natsEnabled {
            "/nats/" = {
              proxyPass = "http://127.0.0.1:${natsHttpPort}/";
              extraConfig = natsProxyConfig;
            };
          }
        );

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

      services.nginx.virtualHosts."${host}-http" = {
        listen = [ { addr = "0.0.0.0"; port = 80; } ];
        locations."/" = {
          return = "301 https://${host}$request_uri";
        };
      };

      systemd.services.nginx = {
        after =
          [ "generate-localhost-certs.service" ]
          ++ optionals config.services.rave.gitlab.enable [ "gitlab.service" ]
          ++ optionals config.services.rave.monitoring.enable [ "grafana.service" "prometheus.service" ]
          ++ optionals mattermostEnabled [ "mattermost.service" ]
          ++ optionals natsEnabled [ "nats.service" ]
          ++ optionals config.services.rave.penpot.enable [ "penpot-backend.service" "penpot-frontend.service" "penpot-exporter.service" ]
          ++ optionals config.services.rave.outline.enable [ "outline.service" ]
          ++ optionals n8nEnabled [ "n8n.service" ];
        requires = [ "generate-localhost-certs.service" ];
      };
    }
    (mkIf gitlabEnabled {
      services.nginx.virtualHosts."gitlab-internal" = {
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
    })
    (mkIf mattermostEnabled {
      services.nginx.virtualHosts."${host}-mattermost" = {
        forceSSL = true;
        enableACME = false;
        serverName = host;
        listen = [
          { addr = "0.0.0.0"; port = cfg.mattermostLoopbackPorts.https; ssl = true; }
          { addr = "0.0.0.0"; port = cfg.mattermostLoopbackPorts.http; ssl = false; }
        ];
        sslCertificate = certificate.certFile;
        sslCertificateKey = certificate.keyFile;
        locations = {
          "/mattermost/" = {
            proxyPass = mattermostProxyTarget;
            proxyWebsockets = true;
            extraConfig = mattermostProxyConfig;
          };
          "/mattermost" = {
            proxyPass = mattermostProxyTarget;
            proxyWebsockets = true;
            extraConfig = mattermostProxyConfig;
          };
        };
        extraConfig = ''
          port_in_redirect off;
          absolute_redirect off;
        '';
      };
    })
    (mkIf (mattermostEnabled && chatDomain != null) (
      let
        chat = chatDomain;
      in {
        services.nginx.virtualHosts."${chat}" = {
          forceSSL = false;
          enableACME = false;
          listen = [ { addr = "0.0.0.0"; port = 443; ssl = true; } ];
          http2 = true;
          sslCertificate = certificate.certFile;
          sslCertificateKey = certificate.keyFile;
          extraConfig = ''
            ssl_certificate ${certificate.certFile};
            ssl_certificate_key ${certificate.keyFile};
          '';
          locations."/" = {
            proxyPass = mattermostProxyTarget;
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

        services.nginx.virtualHosts."${chat}-http" = {
          listen = [ { addr = "0.0.0.0"; port = 80; } ];
          serverName = chat;
          locations."/" = {
            return = "301 https://${chat}$request_uri";
          };
        };
      }
    ))
  ])
  ;
}
