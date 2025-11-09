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

  dashboardHtmlPath = ../../../static/dashboard.html;
  dashboardAssetsPath = ../../../static/assets;
  dashboardIconPath = ../../../static/vite.svg;
  dashboardStaticRoot = pkgs.runCommand "dashboard-static-root" {} ''
    mkdir -p $out
    cp ${dashboardHtmlPath} $out/index.html
    cp -r ${dashboardAssetsPath} $out/assets
    cp ${dashboardIconPath} $out/vite.svg
  '';

  penpotCardHtml = lib.optionalString config.services.rave.penpot.enable ''
                          <a href="/penpot/" class="service-card">
                              <div class="service-title">🎨 Penpot</div>
                              <div class="service-desc">Design collaboration (GitLab OIDC)</div>
                              <div class="service-url">${config.services.rave.penpot.publicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';
  outlineCardHtml = lib.optionalString config.services.rave.outline.enable ''
                          <a href="/outline/" class="service-card">
                              <div class="service-title">📚 Outline</div>
                              <div class="service-desc">Knowledge base and documentation hub</div>
                              <div class="service-url">${config.services.rave.outline.publicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';
  n8nCardHtml = lib.optionalString config.services.rave.n8n.enable ''
                          <a href="${config.services.rave.n8n.publicUrl}/" class="service-card">
                              <div class="service-title">🧠 n8n</div>
                              <div class="service-desc">Automation workflows & integrations</div>
                              <div class="service-url">${config.services.rave.n8n.publicUrl}/</div>
                              <span class="status active">Active</span>
                          </a>
'';

  defaultDashboardHtml = builtins.readFile dashboardHtmlPath;


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

  config = mkIf cfg.enable {
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

      virtualHosts =
        (
          {
            "${host}" = {
              forceSSL = true;
              enableACME = false;
              listen = [
                { addr = "0.0.0.0"; port = 443; ssl = true; default = true; }
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

            "${host}-http" = {
              listen = [ { addr = "0.0.0.0"; port = 80; } ];
              locations."/" = {
                return = "301 https://${host}$request_uri";
              };
            };

          }
        )
        // mkIf config.services.rave.gitlab.enable {
          "gitlab-internal" = {
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
        }
        // mkIf mattermostEnabled {
          "${host}-mattermost" = {
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
        }
        // mkIf (mattermostEnabled && chatDomain != null) (
          let
            chat = chatDomain;
          in {
            "${chat}" = {
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

            "${chat}-http" = {
              listen = [ { addr = "0.0.0.0"; port = 80; } ];
              serverName = chat;
              locations."/" = {
                return = "301 https://${chat}$request_uri";
              };
            };
          }
        );
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

  };
}
