# nixos/modules/services/matrix/bridge.nix
# RAVE Matrix Bridge service configuration
{ config, pkgs, lib, ... }:

let
  # Python environment with required dependencies for the RAVE Matrix Bridge
  matrixBridgeApp = pkgs.python3.withPackages (ps: with ps; [
    aiohttp
    pyjwt
    cryptography
    pyyaml
    aiolimiter
    structlog
    prometheus-client
    aiomqtt
    tenacity
  ]);

  # Bridge configuration file
  bridgeConfig = pkgs.writeText "bridge-config.yaml" ''
    # RAVE Matrix Bridge Configuration
    matrix:
      homeserver_url: "http://localhost:8008"
      access_token: "dummy-access-token-replace-in-production"
      user_id: "@rave-bridge:rave.local"
      device_id: "RAVE_BRIDGE"
    
    gitlab:
      base_url: "http://localhost:8080/gitlab"
      api_token: "dummy-gitlab-token-replace-in-production"
    
    bridge:
      command_prefix: "!rave"
      admin_room: "!admin:rave.local"
      log_level: "INFO"
      
    security:
      rate_limit:
        requests_per_minute: 60
        burst: 10
      allowed_users: []  # Empty means all users allowed
      
    agent_control:
      enabled: true
      sandbox_mode: true
      max_concurrent_tasks: 5
      timeout_seconds: 300
  '';
in
{
  # P5: RAVE Matrix Bridge Service
  systemd.services.rave-matrix-bridge = {
    description = "RAVE Matrix Bridge Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "matrix-synapse.service" "network.target" ];
    wants = [ "matrix-synapse.service" ];
    
    serviceConfig = {
      Type = "simple";
      User = "rave-bridge";
      Group = "rave-bridge";
      WorkingDirectory = "/var/lib/rave-matrix-bridge";
      
      # Use the bridge source from the repository
      ExecStart = "${matrixBridgeApp}/bin/python3 -m src.main --config ${bridgeConfig}";
      
      Restart = "always";
      RestartSec = 10;
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/rave-matrix-bridge" "/var/log/rave-matrix-bridge" ];
      
      # Resource limits
      MemoryMax = "512M";
      CPUQuota = "50%";
    };
    
    environment = {
      PYTHONPATH = "/var/lib/rave-matrix-bridge";
      LOG_LEVEL = "INFO";
    };

    preStart = ''
      # Ensure bridge directories are available
      if [ ! -d /var/lib/rave-matrix-bridge/src ]; then
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/rave-matrix-bridge/src
        # Note: Matrix bridge source installation not yet implemented
        echo "Matrix bridge source code setup skipped - not yet implemented"
        ${pkgs.coreutils}/bin/chown -R rave-bridge:rave-bridge /var/lib/rave-matrix-bridge
      fi
      
      # Create log directory
      ${pkgs.coreutils}/bin/mkdir -p /var/log/rave-matrix-bridge
      ${pkgs.coreutils}/bin/chown rave-bridge:rave-bridge /var/log/rave-matrix-bridge
    '';
  };

  # Create the bridge user
  users.users.rave-bridge = {
    isSystemUser = true;
    group = "rave-bridge";
    home = "/var/lib/rave-matrix-bridge";
    createHome = true;
  };

  users.groups.rave-bridge = {};

  # Log rotation for bridge logs
  services.logrotate.settings.rave-matrix-bridge = {
    files = "/var/log/rave-matrix-bridge/*.log";
    frequency = "daily";
    rotate = 7;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    create = "644 rave-bridge rave-bridge";
  };
}