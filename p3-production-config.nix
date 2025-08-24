# P3 Production GitLab Service Integration Configuration
# Implements Phase P3: GitLab Service Integration - Critical Infrastructure Component
# Extends P2 observability with GitLab CI/CD and runner capabilities
{ config, pkgs, lib, ... }:

{
  # Import P2 observability configuration and GitLab services
  imports = [ 
    ./p2-production-config.nix 
    ./nixos/gitlab.nix
    # sops-nix module imported at flake level
  ];
  
  # Override hostname for P3
  networking.hostName = lib.mkDefault "rave-p3";
  
  # P3: Configure sops-nix secrets
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    
    # Secrets used by GitLab and related services
    secrets = {
      "gitlab/root-password" = {
        owner = "gitlab";
        group = "gitlab";
        mode = "0600";
      };
      
      "gitlab/admin-token" = {
        owner = "gitlab";
        group = "gitlab";  
        mode = "0600";
      };
      
      "gitlab/runner-token" = {
        owner = "gitlab-runner";
        group = "gitlab-runner";
        mode = "0600";
      };
      
      "gitlab/secret-key-base" = {
        owner = "gitlab";
        group = "gitlab";
        mode = "0600";
      };
      
      "gitlab/db-password" = {
        owner = "gitlab";
        group = "gitlab";
        mode = "0600";
      };
    };
    
    # Age key for decryption (production deployment)
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };
  
  # P3: Enhanced nginx configuration for GitLab proxy
  services.nginx.virtualHosts."rave.local".locations = lib.mkMerge [
    {
      # GitLab main interface
      "/gitlab/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Ssl on;
          
          # GitLab specific headers
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Handle large file uploads (artifacts, LFS)
          client_max_body_size 1G;
          proxy_request_buffering off;
          proxy_read_timeout 300;
          proxy_connect_timeout 300;
          proxy_send_timeout 300;
        '';
      };
      
      # GitLab redirect
      "= /gitlab" = {
        return = "301 /gitlab/";
      };
      
      # GitLab CI/CD artifacts and LFS
      "~ ^/gitlab/.*/-/(artifacts|archive|raw)/" = {
        proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket:";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Large file handling
          client_max_body_size 10G;
          proxy_request_buffering off;
        '';
      };
    }
  ];
  
  # P3: Update system environment for GitLab integration
  systemd.services.setup-agent-environment.serviceConfig.ExecStart = lib.mkDefault (pkgs.writeScript "setup-agent-env-p3" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    # Create directories
    mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
    
    # P3: GitLab integration environment setup
    cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "🦊 RAVE P3 GitLab Integration Environment"
echo "========================================="
echo ""
echo "🔒 P1 Security Features (inherited):"
echo "  • SSH key authentication only"
echo "  • Enhanced firewall with rate limiting"
echo "  • Security headers on all HTTPS responses"
echo "  • Kernel hardening and memory protection"
echo ""
echo "📈 P2 Observability Features (inherited):"
echo "  • Prometheus metrics collection (3-day retention)"
echo "  • Grafana dashboards and visualization"
echo "  • Node Exporter for system metrics"
echo "  • Memory-disciplined configuration (SAFE mode)"
echo "  • System health alerting rules"
echo ""
echo "🦊 P3 GitLab CI/CD Features:"
echo "  • GitLab CE instance with PostgreSQL backend"
echo "  • GitLab Runner with Docker + KVM executor"
echo "  • Secrets management via sops-nix"
echo "  • Large file handling (artifacts, LFS up to 10GB)"
echo "  • Integrated with existing nginx reverse proxy"
echo ""
echo "🎯 Services & Access:"
echo "  • Vibe Kanban: https://rave.local:3002/"
echo "  • Grafana: https://rave.local:3002/grafana/"
echo "  • Claude Code Router: https://rave.local:3002/ccr-ui/"
echo "  • GitLab: https://rave.local:3002/gitlab/"
echo "  • Prometheus (internal): https://rave.local:3002/prometheus/"
echo ""
echo "🔧 GitLab Configuration:"
echo "  • Root login: root / [configured in secrets]"
echo "  • Repository storage: /var/lib/gitlab/repositories"
echo "  • Runner executor: docker (privileged for KVM access)"
echo "  • Database: PostgreSQL with shared connection pool"
echo "  • Memory limits: GitLab 8GB, Runner 4GB"
echo ""
echo "🚀 CI/CD Capabilities:"
echo "  • Docker-in-Docker builds"
echo "  • KVM access for sandbox VM provisioning"
echo "  • Artifact storage and LFS support"
echo "  • Webhook integration ready"
echo "  • Auto-scaling runner configuration"
echo ""
echo "⚠️ Next Steps (Phase P4):"
echo "  • Configure GitLab OAuth for OIDC authentication"
echo "  • Add Matrix/Element service integration"
echo "  • Set up automated backup procedures"
echo "  • Configure external runners (if needed)"
echo ""
echo "📊 Resource Management:"
echo "  • GitLab: 8GB memory limit, 50% CPU quota"
echo "  • GitLab Runner: 4GB memory limit, 25% CPU quota"
echo "  • Shared PostgreSQL with connection pooling"
echo "  • Artifact cleanup policies enabled"
echo ""
echo "🔑 Secrets Management:"
echo "  • sops-nix encryption for all sensitive data"
echo "  • Age-based team key management"
echo "  • Secure service-to-service communication"
echo "  • Automated secret rotation support"
echo ""
echo "📖 Next Phase: P4 adds Matrix/Element chat integration"
WELCOME_EOF
    chmod +x /home/agent/welcome.sh
    
    # P3: GitLab setup helper script  
    cat > /home/agent/setup-gitlab.sh << 'GITLAB_SETUP_EOF'
#!/bin/bash
echo "🦊 RAVE P3 GitLab Setup Helper"
echo "==============================="
echo ""
echo "This script helps configure GitLab post-deployment."
echo ""
echo "📋 Initial GitLab Setup:"
echo "1. Access GitLab at https://rave.local:3002/gitlab/"
echo "2. Sign in as root with password from secrets"
echo "3. Complete initial setup wizard"
echo "4. Create first project and test CI/CD pipeline"
echo ""
echo "🏃‍♂️ GitLab Runner Registration:"
echo "echo 'Runner should auto-register on startup'"
echo "echo 'Check runner status: systemctl status gitlab-runner'"
echo "echo 'View runner logs: journalctl -u gitlab-runner -f'"
echo ""
echo "🔧 Admin Tasks:"
echo "echo 'Configure OAuth applications in Admin -> Applications'"
echo "echo 'Set up webhooks for external integrations'"  
echo "echo 'Configure artifact expiration policies'"
echo "echo 'Set up backup schedules'"
echo ""
echo "🔐 Security Configuration:"
echo "echo 'Review sign-up restrictions in Admin -> Settings'"
echo "echo 'Configure 2FA requirements'"
echo "echo 'Set up LDAP/OIDC integration (Phase P4)'"
echo "echo 'Review permissions and access controls'"
echo ""
echo "📊 Monitoring Setup:"
echo "echo 'GitLab metrics available at /gitlab/-/metrics'"
echo "echo 'Add GitLab scrape targets to Prometheus'"
echo "echo 'Import GitLab Grafana dashboards'"
echo ""
echo "🧪 Testing CI/CD:"
echo "cat << 'CI_EXAMPLE_EOF'"
echo "# Example .gitlab-ci.yml for testing:"
echo "test:"
echo "  script:"
echo "    - echo 'Hello from GitLab CI'"
echo "    - docker --version"
echo "    - ls /dev/kvm  # Verify KVM access"
echo "CI_EXAMPLE_EOF"
GITLAB_SETUP_EOF
    chmod +x /home/agent/setup-gitlab.sh
    
    # Update bashrc with GitLab context
    echo "" >> /home/agent/.bashrc
    echo "# RAVE P3 GitLab Environment" >> /home/agent/.bashrc
    echo "export BROWSER=chromium" >> /home/agent/.bashrc
    echo "export PATH=\$PATH:/home/agent/.local/bin" >> /home/agent/.bashrc
    echo "export SAFE=1" >> /home/agent/.bashrc
    echo "export FULL_PIPE=0" >> /home/agent/.bashrc
    echo "export NODE_OPTIONS=\"--max-old-space-size=1536\"" >> /home/agent/.bashrc
    echo "~/welcome.sh" >> /home/agent/.bashrc
    
    # Set secure permissions
    chmod 700 /home/agent/.ssh
    chown -R agent:users /home/agent
    
    echo "P3 GitLab integration environment setup complete!"
  '');
}