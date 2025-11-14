# nixos/modules/services/nats/default.nix
# NATS JetStream service module - Native NixOS implementation
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.rave.nats;
  nginxCfg = config.services.rave.nginx or {};
  nginxHost = nginxCfg.host or "localhost";
  
  natsConfig = pkgs.writeText "nats-server.conf" ''
    # Server configuration
    server_name: "${cfg.serverName}"
    
    # Network configuration  
    host: "${cfg.host}"
    port: ${toString cfg.port}
    
    # HTTP monitoring
    http_port: ${toString cfg.httpPort}
    
    # JetStream configuration
    jetstream: {
      store_dir: "${cfg.dataDir}/jetstream"
      max_memory_store: ${cfg.jetstream.maxMemory}
      max_file_store: ${cfg.jetstream.maxFileStore}
    }
    
    # Logging
    log_file: "${cfg.dataDir}/nats-server.log"
    logtime: true
    debug: ${if cfg.debug then "true" else "false"}
    trace: ${if cfg.trace then "true" else "false"}
    
    # Limits
    max_connections: ${toString cfg.limits.maxConnections}
    max_payload: ${toString cfg.limits.maxPayload}
    
    # Security
    ${optionalString (cfg.auth.enable) ''
    authorization: {
      users: [
        ${concatMapStrings (user: ''
        {
          user: "${user.name}"
          password: "${user.password}"
          permissions: {
            publish: ["${concatStringsSep "\", \"" user.publish}"]
            subscribe: ["${concatStringsSep "\", \"" user.subscribe}"]
          }
        }
        '') cfg.auth.users}
      ]
    }
    ''}
    
    ${cfg.extraConfig}
  '';

in {
  options = {
    services.rave.nats = {
      enable = mkEnableOption "NATS server with JetStream";
      
      serverName = mkOption {
        type = types.str;
        default = "nats-server";
        description = "Name of the NATS server";
      };
      
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host to bind NATS server to";
      };
      
      port = mkOption {
        type = types.port;
        default = 4222;
        description = "Port for client connections";
      };
      
      httpPort = mkOption {
        type = types.port;
        default = 8222;
        description = "Port for HTTP monitoring";
      };
      
      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/nats";
        description = "Data directory for NATS server";
      };
      
      jetstream = {
        maxMemory = mkOption {
          type = types.str;
          default = "256MB";
          description = "Maximum memory for JetStream";
        };
        
        maxFileStore = mkOption {
          type = types.str;
          default = "1GB";
          description = "Maximum file storage for JetStream";
        };
      };
      
      limits = {
        maxConnections = mkOption {
          type = types.int;
          default = 65536;
          description = "Maximum number of connections";
        };
        
        maxPayload = mkOption {
          type = types.int;
          default = 1048576; # 1MB
          description = "Maximum payload size in bytes";
        };
      };
      
      auth = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable authentication";
        };
        
        users = mkOption {
          type = types.listOf (types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Username";
              };
              
              password = mkOption {
                type = types.str;
                description = "Password";
              };
              
              publish = mkOption {
                type = types.listOf types.str;
                default = ["*"];
                description = "Allowed publish subjects";
              };
              
              subscribe = mkOption {
                type = types.listOf types.str;
                default = ["*"];
                description = "Allowed subscribe subjects";
              };
            };
          });
          default = [];
          description = "User accounts";
        };
      };
      
      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Enable debug logging";
      };
      
      trace = mkOption {
        type = types.bool;
        default = false;
        description = "Enable trace logging";
      };
      
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Additional configuration for NATS server";
      };

      safeMode = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SAFE mode with resource limits";
      };
    };
  };
  
  config = mkIf cfg.enable (mkMerge [
    {
    # Install NATS server and CLI tools
    environment.systemPackages = with pkgs; [
      nats-server
      natscli  # NATS CLI tools for management
    ];
    
    # Create nats user and group
    users.users.nats = {
      isSystemUser = true;
      group = "nats";
      home = cfg.dataDir;
      createHome = true;
      homeMode = "750";
    };
    
    users.groups.nats = {};
    
    # Systemd service
    systemd.services.nats = {
      description = "NATS Server with JetStream";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = mkMerge [
        {
          Type = "simple";
          User = "nats";
          Group = "nats";
          ExecStart = "${pkgs.nats-server}/bin/nats-server -c ${natsConfig}";
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          Restart = "always";
          RestartSec = "5s";
          
          # Security settings
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ cfg.dataDir ];
          PrivateTmp = true;
          
          # Network security
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
          
          # Process security
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
        }
        
        # SAFE mode resource limits
        (mkIf cfg.safeMode {
          MemoryMax = "512M";
          CPUQuota = "50%";
          TasksMax = "1024";
          OOMScoreAdjust = "200";  # Lower priority than critical services
        })
      ];
      
      preStart = ''
        # Ensure data directory exists with correct permissions
        mkdir -p ${cfg.dataDir}/jetstream
        chown -R nats:nats ${cfg.dataDir}
        chmod -R 750 ${cfg.dataDir}
      '';
    };
    
    # Firewall configuration
    networking.firewall.allowedTCPPorts = [ cfg.port cfg.httpPort ];
    
    # Log rotation for NATS logs
    services.logrotate.settings.nats = {
      files = "${cfg.dataDir}/nats-server.log";
      frequency = "daily";
      rotate = if cfg.safeMode then 7 else 30;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 nats nats";
    };

    # Health check script for NATS
    systemd.services.nats-health-check = {
      description = "NATS Health Check";
      after = [ "nats.service" ];
      wants = [ "nats.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        User = "nats";
        ExecStart = pkgs.writeShellScript "nats-health-check" ''
          # Wait for NATS to be ready
          timeout=30
          while [ $timeout -gt 0 ]; do
            if ${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.httpPort}/healthz > /dev/null 2>&1; then
              echo "NATS server is healthy"
              exit 0
            fi
            sleep 1
            timeout=$((timeout - 1))
          done
          echo "NATS server health check failed"
          exit 1
        '';
      };
    };

    # Timer for periodic health checks
    systemd.timers.nats-health-check = {
      description = "NATS Health Check Timer";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Unit = "nats-health-check.service";
      };
    };
    }
    (mkIf (nginxCfg.enable or false) {
      services.nginx.virtualHosts."${nginxHost}".locations."/nats/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.httpPort}/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Add NATS monitoring headers
          proxy_set_header NATS-Server "${cfg.serverName}";
        '';
      };
    })
  ]);
}
