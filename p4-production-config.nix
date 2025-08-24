# P4 Production Matrix Service Integration Configuration
# Implements Phase P4: Matrix Service Integration - Communication Control Plane
# Extends P3 GitLab integration with Matrix homeserver and Element web client
{ config, pkgs, lib, ... }:

{
  # Import P3 GitLab configuration and Matrix services
  imports = [ 
    ./p3-production-config.nix 
    ./nixos/matrix.nix
    # sops-nix module imported at flake level
  ];
  
  # Override hostname for P4
  networking.hostName = lib.mkForce "rave-p4";
  
  # P4: Extend sops-nix secrets for Matrix integration
  sops.secrets = lib.mkMerge [
    {
      # Matrix-specific secrets
      "matrix/shared-secret" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
      };
      
      "matrix/admin-password" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
      };
      
      "matrix/app-service-token" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
      };
      
      # Database password for Matrix
      "database/matrix-password" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
      };
      
      # OIDC integration secrets for Matrix
      "oidc/matrix-client-secret" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
      };
      
      # GitLab OAuth application configuration for Matrix
      "gitlab/oauth-matrix-client-id" = {
        owner = "gitlab";
        group = "gitlab";
        mode = "0644";  # Can be readable by multiple services
      };
      
      "gitlab/oauth-matrix-redirect-uri" = {
        owner = "gitlab";
        group = "gitlab";
        mode = "0644";
      };
    }
  ];
  
  # P4: Enhanced nginx configuration for Matrix and Element
  services.nginx.virtualHosts."rave.local" = {
    # Inherit existing configuration from P3
    locations = lib.mkMerge [
      # Matrix and Element locations are configured in matrix.nix
      {
        # Health check endpoint for Matrix
        "/health/matrix" = {
          proxyPass = "http://127.0.0.1:8008/_matrix/client/versions";
          extraConfig = ''
            proxy_set_header Host $host;
            access_log off;
            
            # Return simplified health status
            proxy_intercept_errors on;
            error_page 200 = @matrix_healthy;
            error_page 500 502 503 504 = @matrix_unhealthy;
          '';
        };
        
        "@matrix_healthy" = {
          return = ''200 "Matrix: OK"'';
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
        
        "@matrix_unhealthy" = {
          return = ''503 "Matrix: Unavailable"'';
          extraConfig = ''
            add_header Content-Type text/plain;
          '';
        };
      }
    ];
    
    # Additional security headers for Matrix/Element
    extraConfig = lib.mkAfter ''
      # Content Security Policy for Element
      location /element/ {
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; media-src 'self' data: blob:; connect-src 'self' https://rave.local:3002; font-src 'self' data:; object-src 'none'; frame-src 'none'; worker-src 'self'; manifest-src 'self';" always;
      }
      
      # Specific headers for Matrix API
      location /matrix/ {
        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options DENY always;
        add_header X-XSS-Protection "1; mode=block" always;
      }
    '';
  };
  
  # P4: GitLab OAuth application configuration for Matrix
  # This creates the OAuth application during GitLab startup
  systemd.services.gitlab-matrix-oauth-setup = {
    description = "Configure GitLab OAuth application for Matrix integration";
    after = [ "gitlab.service" ];
    wants = [ "gitlab.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "gitlab";
      Group = "gitlab";
    };
    
    script = ''
      # Wait for GitLab to be ready
      echo "Waiting for GitLab to be ready..."
      for i in {1..30}; do
        if ${pkgs.curl}/bin/curl -f -s http://unix:/run/gitlab/gitlab-workhorse.socket:/_readiness > /dev/null 2>&1; then
          echo "GitLab is ready!"
          break
        fi
        echo "Attempt $i/30: GitLab not ready yet, waiting..."
        sleep 10
      done
      
      # Check if OAuth application already exists
      OAUTH_APP_FILE="/var/lib/gitlab/oauth-matrix-app-created"
      if [ -f "$OAUTH_APP_FILE" ]; then
        echo "GitLab OAuth application for Matrix already configured"
        exit 0
      fi
      
      # Create GitLab OAuth application for Matrix
      echo "Creating GitLab OAuth application for Matrix..."
      
      # Note: In production, this would use GitLab Rails console or API
      # For now, create a marker file with instructions
      cat > "$OAUTH_APP_FILE" << 'EOF'
# GitLab OAuth Application for Matrix Configuration
# 
# Manual setup required in GitLab admin interface:
# 1. Navigate to Admin Area > Applications
# 2. Create new application with these settings:
#    - Name: Matrix Synapse
#    - Redirect URI: https://rave.local:3002/matrix/_synapse/client/oidc/callback
#    - Scopes: openid, profile, email
#    - Confidential: Yes
# 3. Copy Application ID and Secret to secrets.yaml:
#    - Application ID goes to gitlab/oauth-matrix-client-id
#    - Secret goes to oidc/matrix-client-secret
# 4. Restart Matrix service after updating secrets
#
# OAuth Configuration Details:
# - Client ID: matrix-synapse (must match matrix.nix configuration)
# - Authorization URL: https://rave.local:3002/gitlab/oauth/authorize
# - Token URL: https://rave.local:3002/gitlab/oauth/token
# - User Info URL: https://rave.local:3002/gitlab/oauth/userinfo
EOF
      
      echo "GitLab OAuth application setup instructions created at $OAUTH_APP_FILE"
      echo "Manual configuration required - see file for details"
    '';
  };
  
  # P4: Matrix administration helper scripts
  systemd.services.setup-agent-environment.serviceConfig.ExecStart = lib.mkForce (pkgs.writeScript "setup-agent-env-p4" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    # Create directories (inherited from P3)
    mkdir -p /home/agent/{projects,.claude,.config,.claude-code-router,.ssh}
    
    # P4: Matrix integration environment setup
    cat > /home/agent/welcome.sh << 'WELCOME_EOF'
#!/bin/bash
echo "💬 RAVE P4 Matrix Integration Environment"
echo "========================================"
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
echo "🦊 P3 GitLab CI/CD Features (inherited):"
echo "  • GitLab CE instance with PostgreSQL backend"
echo "  • GitLab Runner with Docker + KVM executor"
echo "  • Secrets management via sops-nix"
echo "  • Large file handling (artifacts, LFS up to 10GB)"
echo "  • Integrated with existing nginx reverse proxy"
echo ""
echo "💬 P4 Matrix Communication Features:"
echo "  • Matrix Synapse homeserver with PostgreSQL backend"
echo "  • Element web client for Matrix interface"
echo "  • GitLab OIDC authentication integration"
echo "  • Secure room-based access controls"
echo "  • Federation disabled for security"
echo "  • Prepared for Appservice bridge integration"
echo ""
echo "🎯 Services & Access:"
echo "  • Vibe Kanban: https://rave.local:3002/"
echo "  • Grafana: https://rave.local:3002/grafana/"
echo "  • Claude Code Router: https://rave.local:3002/ccr-ui/"
echo "  • GitLab: https://rave.local:3002/gitlab/"
echo "  • Element (Matrix): https://rave.local:3002/element/"
echo "  • Matrix API: https://rave.local:3002/matrix/"
echo "  • Prometheus (internal): https://rave.local:3002/prometheus/"
echo ""
echo "💬 Matrix Configuration:"
echo "  • Homeserver: rave.local"
echo "  • Registration: Disabled (OIDC only)"
echo "  • Federation: Disabled for security"
echo "  • Max upload size: 100MB"
echo "  • Authentication: GitLab OIDC integration"
echo "  • Storage: PostgreSQL + file system media store"
echo ""
echo "🔐 Authentication Flow:"
echo "  1. Access Element at /element/"
echo "  2. Click 'Sign In'"
echo "  3. Choose 'GitLab' as identity provider"
echo "  4. Authenticate with GitLab credentials"
echo "  5. Grant Matrix permissions"
echo "  6. Automatically provisioned Matrix account"
echo ""
echo "🏗️ Agent Control Preparation:"
echo "  • Matrix rooms ready for agent communication"
echo "  • Appservice token configured for bridges"
echo "  • Admin controls for room management"
echo "  • Webhook endpoints ready for integration"
echo "  • Message routing prepared for P5 bridge"
echo ""
echo "⚠️ Next Steps (Phase P5):"
echo "  • Implement Matrix Appservice bridge for agent control"
echo "  • Configure automated agent room provisioning"
echo "  • Set up webhook integration with GitLab CI/CD"
echo "  • Add monitoring for Matrix service health"
echo ""
echo "📊 Resource Management:"
echo "  • Matrix Synapse: 4GB memory limit, 200% CPU quota"
echo "  • Element Web: Static files served by nginx"
echo "  • Shared PostgreSQL with GitLab (connection pooled)"
echo "  • Media storage with automatic cleanup"
echo ""
echo "🔑 Security Features:"
echo "  • End-to-end encryption supported in rooms"
echo "  • No federation (closed Matrix environment)"
echo "  • Rate limiting on all endpoints"
echo "  • OIDC authentication only (no local passwords)"
echo "  • Content Security Policy for Element client"
echo ""
echo "🔧 Administration:"
echo "  • Matrix admin tools: /home/agent/matrix-admin.sh"
echo "  • Room management via Element admin interface"
echo "  • Database backup: Daily automated backups"
echo "  • Log rotation: 14-day retention"
echo ""
echo "📖 Next Phase: P5 adds Matrix Appservice bridge for agent control"
WELCOME_EOF
    chmod +x /home/agent/welcome.sh
    
    # P4: Matrix administration helper script
    cat > /home/agent/matrix-admin.sh << 'MATRIX_ADMIN_EOF'
#!/bin/bash
echo "💬 RAVE P4 Matrix Administration Helper"
echo "======================================"
echo ""
echo "This script helps administer the Matrix Synapse homeserver."
echo ""
echo "📋 Matrix Service Status:"
echo "systemctl status matrix-synapse"
echo "systemctl status nginx"
echo ""
echo "📊 Matrix Metrics & Health:"
echo "curl -s http://127.0.0.1:8008/_synapse/metrics | head -20"
echo "curl -s https://rave.local:3002/health/matrix"
echo ""
echo "👥 User Management:"
echo "# Register admin user (if needed):"
echo "register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml"
echo ""
echo "# List users:"
echo "echo \"SELECT name, admin FROM users;\" | sudo -u postgres psql synapse"
echo ""
echo "🏠 Room Management:"
echo "# List rooms:"
echo "echo \"SELECT room_id, creator, join_rules FROM rooms;\" | sudo -u postgres psql synapse"
echo ""
echo "# Room statistics:"
echo "echo \"SELECT count(*) as total_rooms FROM rooms;\" | sudo -u postgres psql synapse"
echo ""
echo "🔧 Database Maintenance:"
echo "# Check database size:"
echo "echo \"SELECT pg_size_pretty(pg_database_size('synapse'));\" | sudo -u postgres psql synapse"
echo ""
echo "# Vacuum database:"
echo "echo \"VACUUM ANALYZE;\" | sudo -u postgres psql synapse"
echo ""
echo "📦 Media Management:"
echo "# Media store size:"
echo "du -sh /var/lib/matrix-synapse/media_store"
echo ""
echo "# Clean old media (30+ days):"
echo "find /var/lib/matrix-synapse/media_store -type f -mtime +30 -delete"
echo ""
echo "🔐 OIDC Configuration:"
echo "# Test GitLab OIDC endpoints:"
echo "curl -s https://rave.local:3002/gitlab/.well-known/openid_configuration | jq"
echo ""
echo "📝 Log Analysis:"
echo "# Recent Matrix logs:"
echo "journalctl -u matrix-synapse --since='1 hour ago'"
echo ""
echo "# Error logs:"
echo "journalctl -u matrix-synapse --priority=err --since='24 hours ago'"
echo ""
echo "💾 Backup & Restore:"
echo "# Manual backup:"
echo "systemctl start matrix-backup.service"
echo ""
echo "# List backups:"
echo "ls -la /var/lib/matrix-synapse/backups/"
echo ""
echo "🧪 Testing Matrix Integration:"
echo "# Test Matrix API:"
echo "curl -s https://rave.local:3002/matrix/_matrix/client/versions"
echo ""
echo "# Test Element client:"
echo "curl -s https://rave.local:3002/element/ | grep -o '<title>.*</title>'"
echo ""
echo "🔧 Troubleshooting:"
echo "echo 'Common issues and solutions:'"
echo "echo '1. Matrix not starting: Check database connection'"
echo "echo '2. OIDC not working: Verify GitLab OAuth app configuration'"
echo "echo '3. Element not loading: Check nginx proxy configuration'"
echo "echo '4. Media uploads failing: Check disk space and permissions'"
MATRIX_ADMIN_EOF
    chmod +x /home/agent/matrix-admin.sh
    
    # P4: GitLab OAuth setup helper for Matrix
    cat > /home/agent/setup-matrix-oauth.sh << 'OAUTH_SETUP_EOF'
#!/bin/bash
echo "🔐 RAVE P4 Matrix OAuth Setup Helper"
echo "==================================="
echo ""
echo "This script helps configure GitLab OAuth for Matrix integration."
echo ""
echo "📋 OAuth Application Setup in GitLab:"
echo "1. Access GitLab admin area: https://rave.local:3002/gitlab/admin/applications"
echo "2. Click 'New Application'"
echo "3. Fill in application details:"
echo "   - Name: Matrix Synapse"
echo "   - Redirect URI: https://rave.local:3002/matrix/_synapse/client/oidc/callback"
echo "   - Scopes: openid, profile, email"
echo "   - Confidential: Yes (checked)"
echo "4. Save the application"
echo "5. Copy Application ID and Secret"
echo ""
echo "🔑 Update secrets.yaml:"
echo "sops secrets.yaml"
echo "# Add/update these entries:"
echo "gitlab:"
echo "  oauth-matrix-client-id: \"[APPLICATION_ID_FROM_GITLAB]\""
echo "oidc:"
echo "  matrix-client-secret: \"[SECRET_FROM_GITLAB]\""
echo ""
echo "🔄 Restart services:"
echo "sudo systemctl restart matrix-synapse"
echo "sudo systemctl restart nginx"
echo ""
echo "🧪 Test OAuth flow:"
echo "1. Open https://rave.local:3002/element/"
echo "2. Click 'Sign In'"
echo "3. Click 'GitLab' button"
echo "4. Authenticate with GitLab credentials"
echo "5. Grant permissions to Matrix"
echo "6. Should redirect back to Element with successful login"
echo ""
echo "✅ Verification:"
echo "# Check if user was created in Matrix:"
echo "echo \"SELECT name, creation_ts FROM users;\" | sudo -u postgres psql synapse"
echo ""
echo "# Check Matrix logs for OIDC activity:"
echo "journalctl -u matrix-synapse --since='10 minutes ago' | grep -i oidc"
OAUTH_SETUP_EOF
    chmod +x /home/agent/setup-matrix-oauth.sh
    
    # Update bashrc with Matrix context
    echo "" >> /home/agent/.bashrc
    echo "# RAVE P4 Matrix Environment" >> /home/agent/.bashrc
    echo "export MATRIX_HOME_SERVER=\"https://rave.local:3002/matrix\"" >> /home/agent/.bashrc
    echo "export ELEMENT_URL=\"https://rave.local:3002/element\"" >> /home/agent/.bashrc
    echo "alias matrix-logs='journalctl -u matrix-synapse -f'" >> /home/agent/.bashrc
    echo "alias matrix-status='systemctl status matrix-synapse'" >> /home/agent/.bashrc
    echo "alias element-test='curl -s \$ELEMENT_URL | grep title'" >> /home/agent/.bashrc
    
    # Set secure permissions
    chmod 700 /home/agent/.ssh
    chown -R agent:users /home/agent
    
    echo "P4 Matrix integration environment setup complete!"
  '');
  
  # P4: Enhanced Prometheus monitoring for Matrix
  services.prometheus.scrapeConfigs = lib.mkAfter [
    {
      job_name = "matrix-synapse";
      static_configs = [
        {
          targets = [ "127.0.0.1:8008" ];
        }
      ];
      metrics_path = "/_synapse/metrics";
      scrape_interval = "30s";
      scrape_timeout = "10s";
    }
  ];
  
  # P4: Grafana dashboard for Matrix monitoring
  services.grafana.provision.dashboards.settings.providers = lib.mkAfter [
    {
      name = "matrix";
      type = "file";
      updateIntervalSeconds = 30;
      options.path = pkgs.writeTextDir "matrix-dashboard.json" (builtins.toJSON {
        dashboard = {
          id = null;
          title = "Matrix Synapse Monitoring";
          description = "RAVE P4 Matrix Synapse Performance and Health Dashboard";
          tags = [ "matrix" "synapse" "rave" "p4" ];
          timezone = "browser";
          refresh = "30s";
          time = {
            from = "now-1h";
            to = "now";
          };
          
          panels = [
            {
              id = 1;
              title = "Matrix Active Users";
              type = "stat";
              targets = [
                {
                  expr = "synapse_federation_client_events_processed_total";
                  legendFormat = "Active Users";
                }
              ];
              gridPos = { h = 8; w = 12; x = 0; y = 0; };
            }
            {
              id = 2;
              title = "Matrix Memory Usage";
              type = "graph";
              targets = [
                {
                  expr = "process_resident_memory_bytes{job=\"matrix-synapse\"}";
                  legendFormat = "Memory Usage";
                }
              ];
              gridPos = { h = 8; w = 12; x = 12; y = 0; };
            }
            {
              id = 3;
              title = "Matrix HTTP Requests";
              type = "graph";
              targets = [
                {
                  expr = "rate(synapse_http_server_requests_total[5m])";
                  legendFormat = "{{method}} {{servlet}}";
                }
              ];
              gridPos = { h = 8; w = 24; x = 0; y = 8; };
            }
          ];
        };
        
        overwrite = true;
        inputs = [];
        folderId = null;
      });
    }
  ];
  
  # P4: Update firewall for Matrix services
  networking.firewall = lib.mkMerge [
    {
      # Matrix-specific ports
      allowedTCPPorts = [ 8008 ];  # Matrix Synapse HTTP
      
      # Note: Port 8448 (Matrix federation) is not opened since federation is disabled
    }
  ];
  
  # P4: System optimization for Matrix workload
  boot.kernel.sysctl = lib.mkMerge [
    {
      # Additional kernel tuning for Matrix
      "net.ipv4.tcp_keepalive_time" = 600;
      "net.ipv4.tcp_keepalive_intvl" = 60;
      "net.ipv4.tcp_keepalive_probes" = 3;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
    }
  ];
}