# Enhanced AI Agent Sandbox Configuration with Claude Ecosystem
{ config, pkgs, lib, ... }:

{
  system.stateVersion = "24.11";
  
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
    nodejs_18
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
      ExecStart = pkgs.writeScript "install-claude-tools" ''
        #!/bin/bash
        set -e
        
        echo "Installing Claude Code CLI..."
        ${pkgs.nodejs_18}/bin/npm install -g @anthropic-ai/claude-code
        
        echo "Installing Claude Code Router..."
        ${pkgs.nodejs_18}/bin/npm install -g @musistudio/claude-code-router
        
        echo "Installing vibe-kanban..."
        ${pkgs.nodejs_18}/bin/npm install -g vibe-kanban
        
        echo "Claude tools installation complete!"
      '';
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Auto-start vibe-kanban service
  systemd.services.vibe-kanban = {
    description = "Vibe Kanban Project Management";
    after = [ "install-claude-tools.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "agent";
      WorkingDirectory = "/home/agent/projects";
      Environment = "NODE_ENV=production";
      ExecStart = "${pkgs.nodejs_18}/bin/npx vibe-kanban --host 0.0.0.0 --port 3000";
      Restart = "always";
      RestartSec = 5;
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
      ];
      ExecStart = "${pkgs.nodejs_18}/bin/npx ccr serve --host 0.0.0.0 --port 3001";
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
        #!/bin/bash
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
echo "  • Claude Code CLI: $(which claude-code || echo 'installing...')"
echo "  • Claude Code Router: $(which ccr || echo 'installing...')  [http://localhost:3001]"
echo "  • vibe-kanban: $(which vibe-kanban || echo 'installing...')  [http://localhost:3000]"
echo "  • Node.js: $(node --version)"
echo "  • Python: $(python3 --version)"
echo "  • Rust: $(rustc --version)"
echo ""
echo "🌐 Web Services (Auto-started):"
echo "  • Vibe Kanban: http://localhost:3000 (Project Management)"
echo "  • Claude Code Router: http://localhost:3001 (AI Router)"
echo ""
echo "🔧 Service Status:"
systemctl --user is-active vibe-kanban.service || echo "  • vibe-kanban: starting..."
systemctl --user is-active claude-code-router.service || echo "  • claude-code-router: starting..."
echo ""
echo "🖥️ Desktop shortcuts available on Desktop"
echo "📁 Working directory: /home/agent/projects"
echo "🌐 SSH access: ssh -p 2223 agent@localhost"
echo ""
EOF
        chmod +x /home/agent/welcome.sh
        
        # Add welcome to bashrc
        echo "" >> /home/agent/.bashrc
        echo "# Welcome message" >> /home/agent/.bashrc
        echo "~/welcome.sh" >> /home/agent/.bashrc
        
        echo "Agent environment setup complete!"
      '';
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
  
  # Open firewall for web services
  networking.firewall.allowedTCPPorts = [ 3000 3001 ];
}