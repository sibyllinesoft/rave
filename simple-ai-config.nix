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
  
  # Enable sudo without password
  security.sudo.wheelNeedsPassword = false;
  
  # Basic services
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  
  # Network
  networking.hostName = "ai-sandbox";
  networking.firewall.enable = false;
  
  # Minimal desktop
  services.xserver.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.displayManager.autoLogin.enable = true;
  services.xserver.displayManager.autoLogin.user = "agent";
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
    after = [ "install-claude-tools.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = "/home/agent/projects";
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
    after = [ "install-claude-tools.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = "/home/agent";
      Environment = [
        "NODE_ENV=production"
        "CCR_HOST=0.0.0.0"
        "CCR_PORT=3001"
        "PATH=/home/agent/.local/bin:${pkgs.nodejs_20}/bin:/run/current-system/sw/bin"
        "HOME=/home/agent"
      ];
      ExecStart = "/home/agent/.local/bin/ccr serve --host 0.0.0.0 --port 3001";
      Restart = "always";
      RestartSec = 5;
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
  "defaultProvider": "ollama",
  "server": {
    "host": "0.0.0.0",
    "port": 3001
  }
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
        location /ccr-ui {
          proxy_pass http://127.0.0.1:3001;
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
          
          # Rewrite path for upstream
          rewrite ^/ccr-ui/(.*) /$1 break;
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
  
  # Open firewall for web services
  networking.firewall.allowedTCPPorts = [ 3000 3001 3002 ];
}