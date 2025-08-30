# Enhanced AI Agent Sandbox Configuration with Claude Ecosystem
{ config, pkgs, lib, ... }:

let
  # Import the simplified vibe-kanban derivation
  vibe-kanban = pkgs.callPackage ./vibe-kanban-simple.nix {};
in

{
  system.stateVersion = "24.11";
  
  # Allow unfree packages (needed for steam-run binary compatibility)
  nixpkgs.config.allowUnfree = true;
  
  # User configuration
  users.users.agent = {
    isNormalUser = true;
    description = "AI Agent";
    extraGroups = [ "wheel" ];
    password = "agent";
    shell = pkgs.bash;
  };
  
  # Enable sudo without password (consider restricting in production)
  security.sudo.wheelNeedsPassword = false;
  
  # Intrusion Prevention with fail2ban
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    jails = {
      sshd = {
        settings = {
          enabled = true;
          filter = "sshd";
          action = "iptables[name=SSH, port=ssh, protocol=tcp]";
          backend = "systemd";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };
    };
  };
  
  # SSH Security Hardening
  services.openssh = {
    enable = true;
    settings = {
      # Disable password authentication - use keys only
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      AuthenticationMethods = "publickey";
      
      # Security hardening
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;
      UsePAM = false;
      X11Forwarding = false;
      
      # Connection limits and timeouts
      MaxAuthTries = 3;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      LoginGraceTime = 60;
      MaxSessions = 10;
      
      # Protocol and cipher hardening
      Protocol = 2;
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
        "aes256-ctr"
        "aes192-ctr"
        "aes128-ctr"
      ];
      KexAlgorithms = [
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
        "diffie-hellman-group14-sha256"
      ];
      Macs = [
        "hmac-sha2-256-etm@openssh.com"
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256"
        "hmac-sha2-512"
      ];
    };
    
    # SSH key injection mechanism for cloud deployment
    authorizedKeysFiles = [
      "/home/agent/.ssh/authorized_keys"
      "/etc/ssh/authorized_keys.d/%u"
    ];
  };
  
  # Network Security
  networking.hostName = "ai-sandbox";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3000 3001 3002 ];
    # Restrict SSH access to specific interfaces if needed
    interfaces = {
      # Allow SSH from any interface for now, restrict in production
    };
  };
  
  # Minimal desktop
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "agent";
  services.xserver.desktopManager.xfce.enable = true;
  
  # Set Chromium as default browser
  environment.sessionVariables = {
    BROWSER = "chromium";
  };
  
  # XFCE default applications
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    text/html=chromium.desktop
    x-scheme-handler/http=chromium.desktop
    x-scheme-handler/https=chromium.desktop
    x-scheme-handler/about=chromium.desktop
    x-scheme-handler/unknown=chromium.desktop
  '';
  
  # Rust development environment will be available through packages
  
  # Core development packages
  environment.systemPackages = with pkgs; [
    # Browser and core tools
    chromium
    git
    curl
    wget
    vim
    nano
    
    # Development runtimes  
    nodejs_20
    python3
    python3Packages.pip
    python3Packages.virtualenv
    
    # Rust ecosystem for vibe-kanban
    rustc
    cargo
    cargo-watch
    
    # Package managers
    pnpm
    yarn
    
    # Database tools for vibe-kanban
    sqlite
    
    # Terminal tools
    tmux
    screen
    htop
    tree
    
    # Development utilities
    jq
    unzip
    zip
    
    # Desktop utilities
    xdg-utils
    
    # Binary compatibility layer for non-NixOS executables
    steam-run
    
    # Reverse proxy
    nginx
    
    # Precompiled vibe-kanban
    vibe-kanban
  ];
  
  # SSH key setup service for cloud deployment
  systemd.services.setup-ssh-keys = {
    description = "Setup SSH keys from cloud metadata or environment";
    before = [ "sshd.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeScript "setup-ssh-keys" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Create SSH directory for agent user
        mkdir -p /home/agent/.ssh
        chmod 700 /home/agent/.ssh
        chown agent:users /home/agent/.ssh
        
        # Try to get SSH keys from cloud metadata (AWS, GCP, etc.)
        SSH_KEY_ENV="SSH_PUBLIC_KEY"
        SSH_KEY_FILE="/etc/ssh-public-key"
        AUTHORIZED_KEYS_FILE="/home/agent/.ssh/authorized_keys"
        
        # Check for environment variable
        if [ -n "''${!SSH_KEY_ENV}" ]; then
          echo "Adding SSH key from environment variable"
          echo "''${!SSH_KEY_ENV}" > "$AUTHORIZED_KEYS_FILE"
          chmod 600 "$AUTHORIZED_KEYS_FILE"
          chown agent:users "$AUTHORIZED_KEYS_FILE"
          echo "SSH key configured from environment"
        # Check for key file
        elif [ -f "$SSH_KEY_FILE" ]; then
          echo "Adding SSH key from file"
          cp "$SSH_KEY_FILE" "$AUTHORIZED_KEYS_FILE"
          chmod 600 "$AUTHORIZED_KEYS_FILE" 
          chown agent:users "$AUTHORIZED_KEYS_FILE"
          echo "SSH key configured from file"
        # Try cloud metadata services
        elif command -v curl >/dev/null; then
          # AWS EC2 metadata
          if curl -f -m 10 -s http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key 2>/dev/null > "$AUTHORIZED_KEYS_FILE"; then
            chmod 600 "$AUTHORIZED_KEYS_FILE"
            chown agent:users "$AUTHORIZED_KEYS_FILE"
            echo "SSH key configured from AWS metadata"
          # GCP metadata  
          elif curl -f -m 10 -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys 2>/dev/null > "$AUTHORIZED_KEYS_FILE"; then
            chmod 600 "$AUTHORIZED_KEYS_FILE"
            chown agent:users "$AUTHORIZED_KEYS_FILE"
            echo "SSH key configured from GCP metadata"
          else
            echo "WARNING: No SSH keys found! SSH access will not work."
            echo "Please provide SSH key via:"
            echo "  - SSH_PUBLIC_KEY environment variable"
            echo "  - /etc/ssh-public-key file"
            echo "  - Cloud provider metadata"
          fi
        else
          echo "WARNING: No SSH keys configured and curl not available"
        fi
        
        # Set up system-wide authorized keys directory
        mkdir -p /etc/ssh/authorized_keys.d
        chmod 755 /etc/ssh/authorized_keys.d
      '';
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Install Claude tools via npm at system startup
  systemd.services.install-claude-tools = {
    description = "Install Claude Code ecosystem tools";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      WorkingDirectory = "/home/agent";
      Environment = [
        "PATH=${pkgs.nodejs_20}/bin:${pkgs.unzip}/bin:${pkgs.zip}/bin:/run/current-system/sw/bin"
        "HOME=/home/agent"
      ];
      ExecStart = pkgs.writeScript "install-claude-tools" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Set npm to install to user directory
        echo "Setting up npm user directory..."
        mkdir -p /home/agent/.local/bin
        ${pkgs.nodejs_20}/bin/npm config set prefix /home/agent/.local
        
        echo "Installing Claude Code CLI..."
        ${pkgs.nodejs_20}/bin/npm install -g @anthropic-ai/claude-code
        
        echo "Installing Claude Code Router..."
        ${pkgs.nodejs_20}/bin/npm install -g @musistudio/claude-code-router
        
        echo "vibe-kanban already compiled and installed system-wide"
        
        echo "Claude tools installation complete!"
        echo "Installed tools:"
        ls -la /home/agent/.local/bin/
      '';
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Vibe Kanban service (precompiled from npm)
  systemd.services.vibe-kanban = {
    description = "Vibe Kanban Project Management";
    after = [ "setup-agent-environment.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = "/home/agent";
      Environment = [
        "PATH=/home/agent/.local/bin:${pkgs.nodejs_20}/bin:/run/current-system/sw/bin"
        "HOME=/home/agent"
        "PORT=3000"  # Set specific port for consistency
      ];
      ExecStart = "${vibe-kanban}/bin/vibe-kanban";
      Restart = "always";
      RestartSec = 10;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Auto-start Claude Code Router service
  systemd.services.claude-code-router = {
    description = "Claude Code Router Multi-Provider AI";
    after = [ "setup-agent-environment.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = "/home/agent";
      Environment = [
        "NODE_ENV=production"
        "CCR_HOST=0.0.0.0"
        "CCR_PORT=3456"
        "PATH=/home/agent/.local/bin:${pkgs.nodejs_20}/bin:/run/current-system/sw/bin"
        "HOME=/home/agent"
      ];
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "/home/agent/.local/bin/ccr start";
      Restart = "always";
      RestartSec = 10;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Create startup script for agent user
  systemd.services.setup-agent-environment = {
    description = "Setup agent user environment";
    after = [ "install-claude-tools.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agent";
      WorkingDirectory = "/home/agent";
      ExecStart = pkgs.writeScript "setup-agent-env" ''
        #!${pkgs.bash}/bin/bash
        set -e
        
        # Create useful directories
        mkdir -p /home/agent/projects
        mkdir -p /home/agent/.claude
        mkdir -p /home/agent/.config
        
        # Create Claude Code Router config
        mkdir -p /home/agent/.claude-code-router
        cat > /home/agent/.claude-code-router/config.json << 'EOF'
{
  "PORT": 3456,
  "HOST": "0.0.0.0",
  "providers": {
    "openrouter": {
      "enabled": false,
      "apiKey": ""
    },
    "deepseek": {
      "enabled": false,
      "apiKey": ""
    },
    "gemini": {
      "enabled": false,
      "apiKey": ""
    },
    "ollama": {
      "enabled": true,
      "baseURL": "http://localhost:11434"
    }
  },
  "defaultProvider": "ollama"
}
EOF
        
        # Create desktop shortcuts
        mkdir -p /home/agent/Desktop
        
        # Vibe Kanban desktop shortcut
        cat > /home/agent/Desktop/vibe-kanban.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Vibe Kanban
Comment=Project Management Dashboard
Exec=chromium --app=http://localhost:3000
Icon=applications-office
Terminal=false
Categories=Office;ProjectManagement;
EOF
        chmod +x /home/agent/Desktop/vibe-kanban.desktop
        
        # Claude Code Router desktop shortcut  
        cat > /home/agent/Desktop/claude-code-router.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude Code Router
Comment=Multi-Provider AI Router
Exec=chromium --app=http://localhost:3001
Icon=applications-development
Terminal=false
Categories=Development;
EOF
        chmod +x /home/agent/Desktop/claude-code-router.desktop
        
        # Create a welcome script with service status
        cat > /home/agent/welcome.sh << 'EOF'
#!/bin/bash
echo "🚀 AI Agent Sandbox Environment Ready!"
echo "======================================"
echo ""
echo "📦 Pre-installed tools:"
echo "  • Claude Code CLI: $(/home/agent/.local/bin/claude-code --version 2>/dev/null || echo 'installing...')"
echo "  • Claude Code Router: $(/home/agent/.local/bin/ccr --version 2>/dev/null || echo 'installing...')  [http://localhost:3001]"
echo "  • vibe-kanban: $(${vibe-kanban}/bin/vibe-kanban --version 2>/dev/null || echo 'system-installed')  [http://localhost:3000]"
echo "  • Node.js: $(node --version)"
echo "  • Python: $(python3 --version)"
echo "  • Rust: $(rustc --version)"
echo ""
echo "🌐 Web Services (Auto-started):"
echo "  • Vibe Kanban: http://localhost:3000 (Project Management)"
echo "  • Claude Code Router: http://localhost:3001 (AI Router)"
echo ""
echo "🔗 Unified Access (via nginx proxy on :3002):"
echo "  • Vibe Kanban: http://localhost:3002/ (Project Management)"
echo "  • CCR UI: http://localhost:3002/ccr-ui (Claude Code Router Interface)"
echo ""
echo "🔧 Service Status:"
sudo systemctl is-active vibe-kanban.service 2>/dev/null || echo "  • vibe-kanban: starting..."
sudo systemctl is-active claude-code-router.service 2>/dev/null || echo "  • claude-code-router: starting..."
echo ""
echo "🖥️ Desktop shortcuts available on Desktop"
echo "📁 Working directory: /home/agent/projects"
echo "🌐 SSH access: ssh -p 2223 agent@localhost"
echo ""
echo "💡 If services aren't running, check: sudo systemctl status vibe-kanban claude-code-router"
echo ""
EOF
        chmod +x /home/agent/welcome.sh
        
        # Set up user environment in bashrc
        echo "" >> /home/agent/.bashrc
        echo "# AI Agent Environment Setup" >> /home/agent/.bashrc
        echo "export BROWSER=chromium" >> /home/agent/.bashrc
        echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
        echo "" >> /home/agent/.bashrc
        echo "# Welcome message" >> /home/agent/.bashrc
        echo "~/welcome.sh" >> /home/agent/.bashrc
        
        # Set user default browser for XFCE
        mkdir -p /home/agent/.config/xfce4
        cat > /home/agent/.config/xfce4/helpers.rc << 'EOF'
WebBrowser=chromium
EOF
        
        echo "Agent environment setup complete!"
      '';
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Enable nginx service for reverse proxy
  services.nginx = {
    enable = true;
    httpConfig = ''
      server {
        listen 3002;
        server_name _;
        
        # Route /ccr-ui to Claude Code Router
        location /ccr-ui/ {
          proxy_pass http://127.0.0.1:3456/ui/;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # WebSocket support
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Timeouts
          proxy_connect_timeout 60s;
          proxy_send_timeout 60s;
          proxy_read_timeout 60s;
        }
        
        # Redirect /ccr-ui to /ccr-ui/
        location = /ccr-ui {
          return 301 /ccr-ui/;
        }
        
        # Default route to vibe-kanban
        location / {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # WebSocket support
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Timeouts
          proxy_connect_timeout 60s;
          proxy_send_timeout 60s;
          proxy_read_timeout 60s;
        }
      }
    '';
  };
  
}