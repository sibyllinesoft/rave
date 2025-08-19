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
        
        # Create a welcome script
        cat > /home/agent/welcome.sh << 'EOF'
#!/bin/bash
echo "🚀 AI Agent Sandbox Environment Ready!"
echo "======================================"
echo ""
echo "📦 Pre-installed tools:"
echo "  • Claude Code CLI: $(which claude-code || echo 'installing...')"
echo "  • Claude Code Router: $(which ccr || echo 'installing...')"
echo "  • vibe-kanban: $(which vibe-kanban || echo 'installing...')"
echo "  • Node.js: $(node --version)"
echo "  • Python: $(python3 --version)"
echo "  • Rust: $(rustc --version)"
echo ""
echo "🌐 Quick start:"
echo "  • Launch Chromium for browser automation"
echo "  • Use 'claude-code' for AI assistance"
echo "  • Use 'vibe-kanban' for project management"
echo "  • SSH access: ssh -p 2222 agent@localhost"
echo ""
echo "📁 Working directory: /home/agent/projects"
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
}