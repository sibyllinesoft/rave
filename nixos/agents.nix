# RAVE Agent Services Configuration
# Defines systemd services for autonomous development agents

{ config, pkgs, lib, ... }:

let
  # Agent service configuration
  agentServices = {
    backend-architect = {
      description = "RAVE Backend Architect Agent";
      command = "${pkgs.python3}/bin/python3 -m backend_architect.main";
      workingDir = "/opt/rave/agents/backend-architect";
      environment = {
        PYTHONPATH = "/opt/rave/agents/backend-architect";
        AGENT_TYPE = "backend-architect";
        AGENT_CONFIG = "/etc/rave/agents/backend-architect.yaml";
      };
    };
    
    frontend-developer = {
      description = "RAVE Frontend Developer Agent";
      command = "${pkgs.nodejs}/bin/node index.js";
      workingDir = "/opt/rave/agents/frontend-developer";
      environment = {
        NODE_ENV = "production";
        AGENT_TYPE = "frontend-developer";
        AGENT_CONFIG = "/etc/rave/agents/frontend-developer.yaml";
      };
    };
    
    test-writer-fixer = {
      description = "RAVE Test Writer and Fixer Agent";
      command = "${pkgs.python3}/bin/python3 -m test_writer.main";
      workingDir = "/opt/rave/agents/test-writer-fixer";
      environment = {
        PYTHONPATH = "/opt/rave/agents/test-writer-fixer";
        AGENT_TYPE = "test-writer-fixer";
        AGENT_CONFIG = "/etc/rave/agents/test-writer-fixer.yaml";
      };
    };
    
    ui-designer = {
      description = "RAVE UI Designer Agent";
      command = "${pkgs.python3}/bin/python3 -m ui_designer.main";
      workingDir = "/opt/rave/agents/ui-designer";
      environment = {
        PYTHONPATH = "/opt/rave/agents/ui-designer";
        AGENT_TYPE = "ui-designer";
        AGENT_CONFIG = "/etc/rave/agents/ui-designer.yaml";
      };
    };
    
    devops-automator = {
      description = "RAVE DevOps Automator Agent";
      command = "${pkgs.python3}/bin/python3 -m devops_automator.main";
      workingDir = "/opt/rave/agents/devops-automator";
      environment = {
        PYTHONPATH = "/opt/rave/agents/devops-automator";
        AGENT_TYPE = "devops-automator";
        AGENT_CONFIG = "/etc/rave/agents/devops-automator.yaml";
      };
    };
    
    api-tester = {
      description = "RAVE API Tester Agent";
      command = "${pkgs.python3}/bin/python3 -m api_tester.main";
      workingDir = "/opt/rave/agents/api-tester";
      environment = {
        PYTHONPATH = "/opt/rave/agents/api-tester";
        AGENT_TYPE = "api-tester";
        AGENT_CONFIG = "/etc/rave/agents/api-tester.yaml";
      };
    };
    
    performance-benchmarker = {
      description = "RAVE Performance Benchmarker Agent";
      command = "${pkgs.python3}/bin/python3 -m performance_benchmarker.main";
      workingDir = "/opt/rave/agents/performance-benchmarker";
      environment = {
        PYTHONPATH = "/opt/rave/agents/performance-benchmarker";
        AGENT_TYPE = "performance-benchmarker";
        AGENT_CONFIG = "/etc/rave/agents/performance-benchmarker.yaml";
      };
    };
    
    rapid-prototyper = {
      description = "RAVE Rapid Prototyper Agent";
      command = "${pkgs.python3}/bin/python3 -m rapid_prototyper.main";
      workingDir = "/opt/rave/agents/rapid-prototyper";
      environment = {
        PYTHONPATH = "/opt/rave/agents/rapid-prototyper";
        AGENT_TYPE = "rapid-prototyper";
        AGENT_CONFIG = "/etc/rave/agents/rapid-prototyper.yaml";
      };
    };
    
    refactoring-specialist = {
      description = "RAVE Refactoring Specialist Agent";
      command = "${pkgs.python3}/bin/python3 -m refactoring_specialist.main";
      workingDir = "/opt/rave/agents/refactoring-specialist";
      environment = {
        PYTHONPATH = "/opt/rave/agents/refactoring-specialist";
        AGENT_TYPE = "refactoring-specialist";
        AGENT_CONFIG = "/etc/rave/agents/refactoring-specialist.yaml";
      };
    };
  };

  # Generate systemd service configuration for an agent
  mkAgentService = name: config: {
    description = config.description;
    wantedBy = []; # Don't auto-start, controlled by chat bridge
    after = [ "network-online.target" "postgresql.service" ];
    wants = [ "network-online.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = "rave-agent";
      Group = "rave-agent";
      
      # Command and working directory
      ExecStart = config.command;
      WorkingDirectory = config.workingDir;
      
      # Environment variables
      Environment = lib.mapAttrsToList (k: v: "${k}=${v}") config.environment;
      
      # Security hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      
      # Capability restrictions
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      
      # System call filtering
      SystemCallFilter = [
        "@system-service"
        "~@debug"
        "~@mount" 
        "~@cpu-emulation"
        "~@privileged"
        "~@resources"
        "~@reboot"
        "~@swap"
        "~@raw-io"
      ];
      
      # File system access
      ReadWritePaths = [
        "/tmp"
        "/var/lib/rave/agents/${name}"
        "/var/log/rave/agents/${name}"
      ];
      
      ReadOnlyPaths = [
        "/etc/rave/agents"
        config.workingDir
      ];
      
      # Resource limits
      MemoryMax = "2G";
      CPUQuota = "100%";  # 1 CPU core
      TasksMax = 1024;
      
      # Process limits
      LimitNOFILE = 4096;
      LimitNPROC = 512;
      
      # Restart configuration
      Restart = "on-failure";
      RestartSec = "10s";
      StartLimitInterval = "5m";
      StartLimitBurst = 3;
      
      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "rave-agent-${name}";
    };
    
    # Pre-start script to ensure directories exist
    preStart = ''
      # Create data directories
      mkdir -p /var/lib/rave/agents/${name}
      mkdir -p /var/log/rave/agents/${name}
      
      # Set permissions
      chown rave-agent:rave-agent /var/lib/rave/agents/${name}
      chown rave-agent:rave-agent /var/log/rave/agents/${name}
      
      # Create config if it doesn't exist
      if [ ! -f /etc/rave/agents/${name}.yaml ]; then
        cat > /etc/rave/agents/${name}.yaml << 'EOF'
# RAVE Agent Configuration - ${name}
agent:
  type: "${name}"
  name: "${config.description}"
  version: "1.0.0"

# Logging configuration
logging:
  level: "INFO"
  file: "/var/log/rave/agents/${name}/agent.log"
  max_size: "100MB"
  backup_count: 5

# Security configuration  
security:
  enable_audit_logging: true
  audit_file: "/var/log/rave/agents/${name}/audit.log"
  
# Performance configuration
performance:
  max_concurrent_tasks: 3
  task_timeout: 300  # 5 minutes
  memory_limit: "1GB"

# Chat control integration
chat_control:
  bridge_url: "http://127.0.0.1:9100"
  
# Agent-specific configuration
# (Add agent-specific settings here)
EOF
      fi
    '';
  };

in
{
  # Create systemd services for all agents
  systemd.services = lib.mapAttrs 
    (name: config: mkAgentService name config)
    agentServices // {
      
      # Mattermost chat-control bridge service
      rave-chat-bridge = {
        description = "RAVE Mattermost Chat Control Service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "postgresql.service" "gitlab.service" "mattermost.service" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "simple";
          User = "rave-bridge";
          Group = "rave-bridge";

          ExecStart = "${pkgs.python3}/bin/python3 /opt/rave/mattermost-bridge/src/main.py";
          WorkingDirectory = "/opt/rave/mattermost-bridge";

          Environment = [
            "PYTHONPATH=/opt/rave/chat-control/src:/opt/rave/mattermost-bridge/src"
            "CHAT_BRIDGE_CONFIG=/etc/rave/mattermost-bridge/config.yaml"
          ];

          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          RestrictRealtime = true;
          RestrictNamespaces = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;

          CapabilityBoundingSet = "";
          AmbientCapabilities = "";

          SystemCallFilter = [
            "@system-service"
            "~@debug"
            "~@mount"
            "~@cpu-emulation"
            "~@privileged"
            "~@resources"
            "~@reboot"
            "~@swap"
            "~@raw-io"
          ];

          ReadWritePaths = [
            "/tmp"
            "/var/lib/rave/mattermost-bridge"
            "/var/log/rave/mattermost-bridge"
          ];

          ReadOnlyPaths = [
            "/etc/rave/mattermost-bridge"
            "/opt/rave/chat-control"
            "/opt/rave/mattermost-bridge"
          ];

          MemoryMax = "1G";
          CPUQuota = "50%";
          TasksMax = 512;
          LimitNOFILE = 8192;
          LimitNPROC = 256;

          Restart = "always";
          RestartSec = "10s";
          StartLimitInterval = "5m";
          StartLimitBurst = 5;

          StandardOutput = "journal";
          StandardError = "journal";
          SyslogIdentifier = "rave-chat-bridge";
        };

        preStart = ''
          mkdir -p /var/lib/rave/mattermost-bridge
          mkdir -p /var/log/rave/mattermost-bridge
          mkdir -p /etc/rave/mattermost-bridge

          chown rave-bridge:rave-bridge /var/lib/rave/mattermost-bridge
          chown rave-bridge:rave-bridge /var/log/rave/mattermost-bridge

          rm -rf /opt/rave/mattermost-bridge
          rm -rf /opt/rave/chat-control
          mkdir -p /opt/rave
          
          cp -r /etc/rave/mattermost-bridge/src /opt/rave/mattermost-bridge
          cp /etc/rave/mattermost-bridge/requirements.txt /opt/rave/mattermost-bridge/requirements.txt
          cp ${./services/mattermost-bridge/setup_baseline.sh} /opt/rave/mattermost-bridge/setup_baseline.sh
          cp -r /etc/rave/chat-control/src /opt/rave/chat-control

          chown -R rave-bridge:rave-bridge /opt/rave/mattermost-bridge
          chown -R rave-bridge:rave-bridge /opt/rave/chat-control

          chmod +x /opt/rave/mattermost-bridge/setup_baseline.sh

          export CHAT_BRIDGE_ADMIN_USERNAME="$(cat ${config.sops.secrets."mattermost/admin-username".path})"
          export CHAT_BRIDGE_ADMIN_EMAIL="$(cat ${config.sops.secrets."mattermost/admin-email".path})"
          export CHAT_BRIDGE_ADMIN_PASSWORD="$(cat ${config.sops.secrets."mattermost/admin-password".path})"
          export CHAT_BRIDGE_TEAM="rave"
          export CHAT_BRIDGE_TEAM_DISPLAY="RAVE Ops"
          export CHAT_BRIDGE_CHANNEL="agent-control"
          export CHAT_BRIDGE_CHANNEL_DISPLAY="Agent Control"
          export CHAT_BRIDGE_TRIGGER="rave"
          export CHAT_BRIDGE_COMMAND_DESCRIPTION="RAVE agent control commands"
          export CHAT_BRIDGE_COMMAND_HINT="[command]"
          export CHAT_BRIDGE_URL="http://127.0.0.1:9100/webhook"
          export CHAT_BRIDGE_TOKEN_DESCRIPTION="${config.services.rave.chat.tokenDescription or "RAVE Chat Bridge"}"
          export CHAT_BRIDGE_TOKEN_FILE="/etc/rave/mattermost-bridge/outgoing_token"
          export CHAT_BRIDGE_BOT_TOKEN_FILE="/etc/rave/mattermost-bridge/bot_token"

          /opt/rave/mattermost-bridge/setup_baseline.sh

          export MATTERMOST_OUTGOING_TOKEN="$(cat /etc/rave/mattermost-bridge/outgoing_token)"
          export MATTERMOST_BOT_TOKEN="$(cat /etc/rave/mattermost-bridge/bot_token)"
          export OIDC_CLIENT_SECRET="$(cat ${config.sops.secrets."oidc/chat-control-client-secret".path})"
          export GITLAB_API_TOKEN="$(cat ${config.sops.secrets."gitlab/api-token".path})"

          envsubst < ${./services/mattermost-bridge/bridge_config.yaml} > /etc/rave/mattermost-bridge/config.yaml
          chown rave-bridge:rave-bridge /etc/rave/mattermost-bridge/config.yaml
          chmod 600 /etc/rave/mattermost-bridge/config.yaml
        '';
      };
    };

  # Create user and group for agents
  users.users.rave-agent = {
    isSystemUser = true;
    group = "rave-agent";
    home = "/var/lib/rave/agents";
    createHome = true;
    uid = 980;
  };
  
  users.groups.rave-agent = {
    gid = 980;
  };

  # Create user and group for chat bridge
  users.users.rave-bridge = {
    isSystemUser = true;
    group = "rave-bridge";
    home = "/var/lib/rave/mattermost-bridge";
    createHome = true;
    uid = 979;
  };
  
  users.groups.rave-bridge = {
    gid = 979;
  };

  # Environment variables for chat bridge are injected during preStart via envsubst

  # Log rotation configuration
  services.logrotate.extraConfig = lib.mkAfter ''
    /var/log/rave/agents/*/*.log {
      daily
      missingok
      rotate 14
      compress
      delaycompress
      notifempty
      copytruncate
      su rave-agent rave-agent
    }
    
    /var/log/rave/mattermost-bridge/*.log {
      daily
      missingok
      rotate 30
      compress
      delaycompress
      notifempty
      copytruncate
      su rave-bridge rave-bridge
    }
  '';

  # Firewall configuration for chat bridge metrics/health endpoint
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 9100 ];

  # Monitoring configuration
  services.prometheus.scrapeConfigs = lib.mkAfter [
    {
      job_name = "rave-chat-bridge";
      static_configs = [{
        targets = [ "127.0.0.1:9100" ];
      }];
      scrape_interval = "30s";
    }
  ];

  # Grafana dashboard for agent monitoring
  services.grafana.provision.dashboards.settings.providers = lib.mkAfter [
    {
      name = "rave-agents";
      type = "file";
      options.path = "/etc/grafana/dashboards/rave-agents.json";
    }
  ];

  # Create Grafana dashboard
  environment.etc."grafana/dashboards/rave-agents.json" = {
    text = builtins.toJSON {
      dashboard = {
        title = "RAVE Agents Dashboard";
        tags = [ "rave" "agents" "chat" ];
        panels = [
          {
            title = "Agent Status";
            type = "stat";
            targets = [{
              expr = "up{job='rave-chat-bridge'}";
            }];
          }
          {
            title = "Chat Bridge Commands";
            type = "graph";
            targets = [{
              expr = "rate(chat_control_commands_total[5m])";
            }];
          }
          {
            title = "Authentication Failures";
            type = "graph";
            targets = [{
              expr = "rate(chat_control_auth_failures_total[5m])";
            }];
          }
          {
            title = "Systemd Operations";
            type = "graph";
            targets = [{
              expr = "rate(chat_control_systemd_operations_total[5m])";
            }];
          }
        ];
      };
    };
  };

  # Install chat-control shared code and Mattermost bridge assets
  environment.etc."rave/chat-control/src" = {
    source = ./services/chat-control/src;
  };

  environment.etc."rave/mattermost-bridge/src" = {
    source = ./services/mattermost-bridge/src;
  };

  environment.etc."rave/mattermost-bridge/requirements.txt" = {
    source = ./services/mattermost-bridge/requirements.txt;
  };

  # Install Python dependencies for the Mattermost bridge
  systemd.services.rave-chat-bridge-deps = {
    description = "Install RAVE Chat Bridge Dependencies";
    wantedBy = [ "rave-chat-bridge.service" ];
    before = [ "rave-chat-bridge.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      
      ExecStart = pkgs.writeScript "install-bridge-deps" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        cd /opt/rave/mattermost-bridge

        # Install Python dependencies
        ${pkgs.python3}/bin/pip3 install -r requirements.txt --user --no-deps

        echo "Chat bridge dependencies installed"
      '';
    };
  };

  # Security monitoring alerts
  systemd.services.rave-security-monitor = {
    description = "RAVE Security Monitoring Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "rave-chat-bridge.service" ];
    
    serviceConfig = {
      Type = "simple";
      User = "rave-bridge";
      Group = "rave-bridge";
      
      ExecStart = pkgs.writeScript "security-monitor" ''
        #!${pkgs.python3}/bin/python3
        import time
        import subprocess
        import json
        
        while True:
            try:
                # Check for security events in audit logs
                result = subprocess.run([
                    "${pkgs.journalctl}/bin/journalctl", 
                    "-u", "rave-chat-bridge.service",
                    "--since", "1 minute ago",
                    "-o", "json"
                ], capture_output=True, text=True)
                
                for line in result.stdout.strip().split('\n'):
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                        message = event.get('MESSAGE', '')
                        
                        # Check for security issues
                        if any(alert in message.lower() for alert in [
                            'auth_failure', 'rate_limit_exceeded', 'security_validation_failed'
                        ]):
                            print(f"Security alert: {message}")
                            
                    except json.JSONDecodeError:
                        pass
                        
            except Exception as e:
                print(f"Security monitor error: {e}")
                
            time.sleep(60)  # Check every minute
      '';
      
      Restart = "always";
      RestartSec = "30s";
    };
  };

  # Backup configuration for agent data
  systemd.services.rave-backup = {
    description = "RAVE Agent Backup Service";
    serviceConfig = {
      Type = "oneshot";
      User = "rave-agent";
      Group = "rave-agent";
      
      ExecStart = pkgs.writeScript "rave-backup" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        BACKUP_DIR="/var/lib/rave/backups"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        
        mkdir -p "$BACKUP_DIR"
        
        # Backup agent configurations
        tar czf "$BACKUP_DIR/agent_configs_$TIMESTAMP.tar.gz" -C /etc/rave agents/
        
        # Backup agent data
        tar czf "$BACKUP_DIR/agent_data_$TIMESTAMP.tar.gz" -C /var/lib/rave agents/
        
        # Backup chat bridge configuration
        tar czf "$BACKUP_DIR/chat_bridge_$TIMESTAMP.tar.gz" -C /etc/rave mattermost-bridge/
        
        # Clean old backups (keep 7 days)
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
        
        echo "RAVE backup completed: $TIMESTAMP"
      '';
      
      MemoryMax = "512M";
      CPUQuota = "25%";
    };
  };

  systemd.timers.rave-backup = {
    description = "RAVE daily backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      AccuracySec = "1h";
    };
  };

  # Health check service
  systemd.services.rave-health-check = {
    description = "RAVE Health Check Service";
    serviceConfig = {
      Type = "oneshot";
      
      ExecStart = pkgs.writeScript "rave-health-check" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        echo "Checking RAVE system health..."
        
        # Check chat bridge health
        if curl -f http://127.0.0.1:9100/health > /dev/null 2>&1; then
          echo "✅ Chat bridge: healthy"
        else
          echo "❌ Chat bridge: unhealthy"
          exit 1
        fi

        # Check Mattermost
        if systemctl is-active --quiet mattermost; then
          echo "✅ Mattermost: active"
        else
          echo "❌ Mattermost: inactive"
          exit 1
        fi
        
        # Check PostgreSQL
        if systemctl is-active --quiet postgresql; then
          echo "✅ PostgreSQL: active"
        else
          echo "❌ PostgreSQL: inactive"
          exit 1
        fi
        
        echo "RAVE system health check passed"
      '';
    };
  };

  systemd.timers.rave-health-check = {
    description = "RAVE health check timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";  # Every 5 minutes
      Persistent = false;
    };
  };
}
