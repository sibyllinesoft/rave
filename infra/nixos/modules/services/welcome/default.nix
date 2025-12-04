{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.welcome;
  redisPlatform = config.services.rave.redis.platform or {};
  redisUnit = redisPlatform.unit or "redis-main.service";

  baseHttpsPort = toString config.services.rave.ports.https;
  host = config.services.rave.traefik.host;
  mattermostPublicUrl = config.services.rave.mattermost.publicUrl;
  grafanaPublicUrl = config.services.rave.monitoring.grafana.publicUrl;
  authentikPublicUrl = config.services.rave.authentik.publicUrl;
  dashboardUrl = "https://${host}:${baseHttpsPort}/";

  penpotWelcomePrimary = optionalString config.services.rave.penpot.enable ''
  echo "  Penpot       : ${config.services.rave.penpot.publicUrl}/"
'';
  outlineWelcomePrimary = optionalString config.services.rave.outline.enable ''
  echo "  Outline      : ${config.services.rave.outline.publicUrl}/"
'';
  n8nWelcomePrimary = optionalString config.services.rave.n8n.enable ''
  echo "  n8n          : ${config.services.rave.n8n.publicUrl}/"
'';
  pomeriumWelcomePrimary = optionalString config.services.rave.pomerium.enable ''
  echo "  Pomerium     : ${config.services.rave.pomerium.publicUrl}"
'';
  authentikWelcomePrimary = optionalString config.services.rave.authentik.enable ''
  echo "  Authentik    : ${authentikPublicUrl}"
'';

  penpotWelcomeFancy = optionalString config.services.rave.penpot.enable ''
  echo "   🎨 Penpot:      ${config.services.rave.penpot.publicUrl}/"
'';
  outlineWelcomeFancy = optionalString config.services.rave.outline.enable ''
  echo "   📚 Outline:     ${config.services.rave.outline.publicUrl}/"
'';
  n8nWelcomeFancy = optionalString config.services.rave.n8n.enable ''
  echo "   🧠 n8n:         ${config.services.rave.n8n.publicUrl}/"
'';
  pomeriumWelcomeFancy = optionalString config.services.rave.pomerium.enable ''
  echo "   🛡  Pomerium:   ${config.services.rave.pomerium.publicUrl}"
'';
  authentikWelcomeFancy = optionalString config.services.rave.authentik.enable ''
  echo "   🔐 Authentik:   ${authentikPublicUrl}"
'';

  statusServices =
    [
      "postgresql"
      redisUnit
      "traefik"
    ]
    ++ optionals config.services.rave.gitlab.enable [ "gitlab" ]
    ++ optionals config.services.rave.monitoring.enable [ "prometheus" "grafana" ]
    ++ optionals config.services.rave.nats.enable [ "nats" ]
    ++ optionals config.services.rave.mattermost.enable [ "mattermost" "rave-chat-bridge" ]
    ++ optionals config.services.rave.penpot.enable [ "penpot-backend" "penpot-frontend" "penpot-exporter" ]
    ++ optionals config.services.rave.outline.enable [ "outline" ]
    ++ optionals config.services.rave.n8n.enable [ "n8n" ]
    ++ optionals config.services.rave.pomerium.enable [ "pomerium" ]
    ++ optionals config.services.rave.authentik.enable [ "authentik" "authentik-worker" ]
    ++ cfg.extraStatusServices;

  statusServicesStr = concatStringsSep " " statusServices;

  welcomeScript = ''
#!/bin/bash
set -euo pipefail

echo "Welcome to the RAVE complete VM"
echo "Forwarded ports:"
echo "  SSH          : localhost:12222 (user root, password rave-root)"
echo "  GitLab HTTPS : https://${host}:${baseHttpsPort}/gitlab/"
echo "  Mattermost   : ${mattermostPublicUrl}/"
echo "  Grafana      : ${grafanaPublicUrl}"
echo "  Prometheus   : http://localhost:19090/"${penpotWelcomePrimary}${outlineWelcomePrimary}${n8nWelcomePrimary}${pomeriumWelcomePrimary}${authentikWelcomePrimary}
echo ""
echo "🚀 RAVE Complete Production Environment"
echo "====================================="
echo ""
echo "✅ All Services Ready:"
echo "   🦊 GitLab:      https://${host}:${baseHttpsPort}/gitlab/"
echo "   📊 Grafana:     ${grafanaPublicUrl}"
echo "   💬 Mattermost:  ${mattermostPublicUrl}/"
echo "   🔍 Prometheus:  https://${host}:${baseHttpsPort}/prometheus/"
echo "   ⚡ NATS:        https://${host}:${baseHttpsPort}/nats/"${penpotWelcomeFancy}${outlineWelcomeFancy}${n8nWelcomeFancy}${pomeriumWelcomeFancy}${authentikWelcomeFancy}
echo ""
echo "🔑 Default Credentials:"
echo "   GitLab root:    admin123456"
echo "   Grafana:        admin/admin123"
echo ""
echo "🔧 Service Status:"
systemctl status ${statusServicesStr} --no-pager -l || true
echo ""
echo "🌐 Dashboard: ${dashboardUrl}"
echo ""
'';

in {
  options.services.rave.welcome = {
    enable = mkEnableOption "Generate the /root/welcome.sh helper script";

    scriptPath = mkOption {
      type = types.str;
      default = "/root/welcome.sh";
      description = "Filesystem path where the welcome script is written.";
    };

    appendToBashrc = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to append the welcome script invocation to /root/.bashrc.";
    };

    extraStatusServices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional systemd units to include in the status summary.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.rave-create-welcome-script = {
      description = "Create system welcome script";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        cat > ${cfg.scriptPath} <<'WELCOME'
${welcomeScript}
WELCOME
        chmod +x ${cfg.scriptPath}
${optionalString cfg.appendToBashrc ''
        marker="# RAVE welcome script"
        if ! grep -qF "$marker" /root/.bashrc; then
          cat >> /root/.bashrc <<EOF_RAVE_WELCOME
$marker
if [ -n "\$PS1" ] && [ -x ${cfg.scriptPath} ]; then
  ${cfg.scriptPath}
fi
EOF_RAVE_WELCOME
        fi
''}
      '';
    };
  };
}
