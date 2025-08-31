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
    wantedBy = []; # Don't auto-start, controlled by Matrix bridge
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

# Matrix integration
matrix:
  homeserver_url: "https://rave.local:3002/matrix"
  bridge_url: "http://127.0.0.1:9000"
  
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
      
      # Matrix Bridge service
      rave-matrix-bridge = {
        description = "RAVE Matrix Bridge Service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "postgresql.service" "matrix-synapse.service" ];
        wants = [ "network-online.target" ];
        requires = [ "postgresql.service" ];
        
        serviceConfig = {
          Type = "simple";
          User = "rave-bridge";
          Group = "rave-bridge";
          
          ExecStart = "${pkgs.python3}/bin/python3 -m src.main";
          WorkingDirectory = "/opt/rave/matrix-bridge";
          
          Environment = [
            "PYTHONPATH=/opt/rave/matrix-bridge"
            "CONFIG_FILE=/etc/rave/matrix-bridge/config.yaml"
            "REGISTRATION_FILE=/etc/rave/matrix-bridge/registration.yaml"
          ];
          
          # Security hardening (same as agents)
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
            "/var/lib/rave/matrix-bridge"
            "/var/log/rave/matrix-bridge"
          ];
          
          ReadOnlyPaths = [
            "/etc/rave/matrix-bridge"
            "/opt/rave/matrix-bridge"
          ];
          
          # Resource limits
          MemoryMax = "1G";
          CPUQuota = "50%";
          TasksMax = 512;
          LimitNOFILE = 8192;
          LimitNPROC = 256;
          
          # Restart configuration
          Restart = "always";
          RestartSec = "10s";
          StartLimitInterval = "5m";
          StartLimitBurst = 5;
          
          # Logging
          StandardOutput = "journal";
          StandardError = "journal";
          SyslogIdentifier = "rave-matrix-bridge";
        };
        
        preStart = ''
          # Create directories
          mkdir -p /var/lib/rave/matrix-bridge
          mkdir -p /var/log/rave/matrix-bridge
          mkdir -p /etc/rave/matrix-bridge
          
          # Set permissions
          chown rave-bridge:rave-bridge /var/lib/rave/matrix-bridge
          chown rave-bridge:rave-bridge /var/log/rave/matrix-bridge
          
          # Copy configuration files (with secrets substitution)
          envsubst < ${./services/matrix-bridge/bridge_config.yaml} > /etc/rave/matrix-bridge/config.yaml
          envsubst < ${./services/matrix-bridge/registration.yaml} > /etc/rave/matrix-bridge/registration.yaml
          
          chown rave-bridge:rave-bridge /etc/rave/matrix-bridge/*
          chmod 600 /etc/rave/matrix-bridge/*
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

  # Create user and group for Matrix bridge
  users.users.rave-bridge = {
    isSystemUser = true;
    group = "rave-bridge";
    home = "/var/lib/rave/matrix-bridge";
    createHome = true;
    uid = 979;
  };
  
  users.groups.rave-bridge = {
    gid = 979;
  };

  # Environment setup for Matrix bridge
  systemd.services.rave-matrix-bridge.environment = lib.mkIf (config.sops.secrets ? "matrix/as-token") {
    MATRIX_AS_TOKEN = config.sops.secrets."matrix/as-token".path;
    MATRIX_HS_TOKEN = config.sops.secrets."matrix/hs-token".path;
    GITLAB_CLIENT_SECRET = config.sops.secrets."oidc/matrix-client-secret".path;
  };

  # Update Matrix Synapse configuration to include bridge
  services.matrix-synapse.settings = lib.mkMerge [
    {
      app_service_config_files = [ "/etc/rave/matrix-bridge/registration.yaml" ];
    }
  ];

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
    
    /var/log/rave/matrix-bridge/*.log {
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

  # Firewall configuration for Matrix bridge
  networking.firewall.allowedTCPPorts = [ 9001 ];  # Metrics port

  # Monitoring configuration
  services.prometheus.scrapeConfigs = lib.mkAfter [
    {
      job_name = "rave-matrix-bridge";
      static_configs = [{
        targets = [ "127.0.0.1:9001" ];
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
        tags = [ "rave" "agents" "matrix" ];
        panels = [
          {
            title = "Agent Status";
            type = "stat";
            targets = [{
              expr = "up{job='rave-matrix-bridge'}";
            }];
          }
          {
            title = "Matrix Bridge Commands";
            type = "graph";
            targets = [{
              expr = "rate(matrix_bridge_commands_total[5m])";
            }];
          }
          {
            title = "Authentication Failures";
            type = "graph";
            targets = [{
              expr = "rate(matrix_bridge_auth_failures_total[5m])";
            }];
          }
          {
            title = "Systemd Operations";
            type = "graph";
            targets = [{
              expr = "rate(matrix_bridge_systemd_operations_total[5m])";
            }];
          }
        ];
      };
    };
  };

  # Install Matrix bridge code
  environment.etc."rave/matrix-bridge/src" = {
    source = ./services/matrix-bridge/src;
  };

  # Install Python dependencies for Matrix bridge
  systemd.services.rave-matrix-bridge-deps = {
    description = "Install RAVE Matrix Bridge Dependencies";
    wantedBy = [ "rave-matrix-bridge.service" ];
    before = [ "rave-matrix-bridge.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      
      ExecStart = pkgs.writeScript "install-bridge-deps" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        cd /opt/rave/matrix-bridge
        
        # Install Python dependencies
        ${pkgs.python3}/bin/pip3 install -r requirements.txt --user --no-deps
        
        echo "Matrix bridge dependencies installed"
      '';
    };
  };

  # Security monitoring alerts
  systemd.services.rave-security-monitor = {
    description = "RAVE Security Monitoring Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "rave-matrix-bridge.service" ];
    
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
                    "-u", "rave-matrix-bridge.service",
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
        
        # Backup Matrix bridge configuration
        tar czf "$BACKUP_DIR/matrix_bridge_$TIMESTAMP.tar.gz" -C /etc/rave matrix-bridge/
        
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
        
        # Check Matrix bridge health
        if curl -f http://127.0.0.1:9000/health > /dev/null 2>&1; then
          echo "✅ Matrix bridge: healthy"
        else
          echo "❌ Matrix bridge: unhealthy"
          exit 1
        fi
        
        # Check Matrix Synapse
        if systemctl is-active --quiet matrix-synapse; then
          echo "✅ Matrix Synapse: active"
        else
          echo "❌ Matrix Synapse: inactive"
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