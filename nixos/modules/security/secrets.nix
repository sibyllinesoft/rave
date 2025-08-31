# nixos/modules/security/secrets.nix
# Cryptographically secure secret generation for RAVE services
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.secrets;
  
  # Script to generate secure secrets at VM creation time
  generateSecrets = pkgs.writeScript "generate-rave-secrets.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    SECRETS_DIR="/var/lib/rave/secrets"
    
    echo "🔐 Generating cryptographically secure secrets..."
    
    # Create secrets directory with proper permissions
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    
    # Function to generate a random password
    generate_password() {
      local length=$1
      ${pkgs.openssl}/bin/openssl rand -base64 $((length * 3 / 4)) | tr -d '\n'
    }
    
    # Function to generate a hex secret
    generate_hex_secret() {
      local length=$1
      ${pkgs.openssl}/bin/openssl rand -hex $length
    }
    
    # Generate database passwords
    if [ ! -f "$SECRETS_DIR/gitlab-db-password" ]; then
      generate_password 32 > "$SECRETS_DIR/gitlab-db-password"
      chmod 600 "$SECRETS_DIR/gitlab-db-password"
      echo "✅ Generated GitLab database password"
    fi
    
    if [ ! -f "$SECRETS_DIR/penpot-db-password" ]; then
      generate_password 32 > "$SECRETS_DIR/penpot-db-password"
      chmod 600 "$SECRETS_DIR/penpot-db-password"
      echo "✅ Generated Penpot database password"
    fi
    
    # Generate application secrets
    if [ ! -f "$SECRETS_DIR/gitlab-secret-key-base" ]; then
      generate_hex_secret 64 > "$SECRETS_DIR/gitlab-secret-key-base"
      chmod 600 "$SECRETS_DIR/gitlab-secret-key-base"
      echo "✅ Generated GitLab secret key base"
    fi
    
    if [ ! -f "$SECRETS_DIR/gitlab-otp-key-base" ]; then
      generate_hex_secret 64 > "$SECRETS_DIR/gitlab-otp-key-base"
      chmod 600 "$SECRETS_DIR/gitlab-otp-key-base"
      echo "✅ Generated GitLab OTP key base"
    fi
    
    if [ ! -f "$SECRETS_DIR/gitlab-db-key-base" ]; then
      generate_hex_secret 64 > "$SECRETS_DIR/gitlab-db-key-base"
      chmod 600 "$SECRETS_DIR/gitlab-db-key-base"
      echo "✅ Generated GitLab database key base"
    fi
    
    # Generate OAuth client secrets
    if [ ! -f "$SECRETS_DIR/penpot-oauth-secret" ]; then
      generate_password 48 > "$SECRETS_DIR/penpot-oauth-secret"
      chmod 600 "$SECRETS_DIR/penpot-oauth-secret"
      echo "✅ Generated Penpot OAuth client secret"
    fi
    
    if [ ! -f "$SECRETS_DIR/element-oauth-secret" ]; then
      generate_password 48 > "$SECRETS_DIR/element-oauth-secret"
      chmod 600 "$SECRETS_DIR/element-oauth-secret"
      echo "✅ Generated Element OAuth client secret"
    fi
    
    # Generate NATS credentials
    if [ ! -f "$SECRETS_DIR/nats-system-user" ]; then
      generate_password 24 > "$SECRETS_DIR/nats-system-user"
      chmod 600 "$SECRETS_DIR/nats-system-user"
      echo "✅ Generated NATS system user credentials"
    fi
    
    # Generate Redis AUTH tokens
    if [ ! -f "$SECRETS_DIR/redis-auth-token" ]; then
      generate_hex_secret 32 > "$SECRETS_DIR/redis-auth-token"
      chmod 600 "$SECRETS_DIR/redis-auth-token"
      echo "✅ Generated Redis AUTH token"
    fi
    
    # Generate JWT signing keys
    if [ ! -f "$SECRETS_DIR/jwt-signing-key" ]; then
      # Generate a strong HMAC key for JWT signing
      generate_hex_secret 64 > "$SECRETS_DIR/jwt-signing-key"
      chmod 600 "$SECRETS_DIR/jwt-signing-key"
      echo "✅ Generated JWT signing key"
    fi
    
    echo "🔐 All secrets generated successfully!"
    echo "📁 Secrets stored in: $SECRETS_DIR"
    
    # Set proper ownership
    chown -R root:root "$SECRETS_DIR"
  '';
  
  # Script to set up database users with generated passwords
  setupDatabaseUsers = pkgs.writeScript "setup-database-users.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    SECRETS_DIR="/var/lib/rave/secrets"
    
    if [ ! -d "$SECRETS_DIR" ]; then
      echo "❌ Secrets directory not found. Run generate-rave-secrets.sh first."
      exit 1
    fi
    
    echo "🔧 Setting up database users with secure passwords..."
    
    # Wait for PostgreSQL to be ready
    for i in {1..30}; do
      if sudo -u postgres psql -c '\q' 2>/dev/null; then
        break
      fi
      echo "Waiting for PostgreSQL to start... ($i/30)"
      sleep 2
    done
    
    # Set GitLab database password
    if [ -f "$SECRETS_DIR/gitlab-db-password" ]; then
      GITLAB_DB_PASS=$(cat "$SECRETS_DIR/gitlab-db-password")
      sudo -u postgres psql -c "ALTER USER gitlab WITH PASSWORD '$GITLAB_DB_PASS';"
      echo "✅ Updated GitLab database user password"
    fi
    
    # Set Penpot database password  
    if [ -f "$SECRETS_DIR/penpot-db-password" ]; then
      PENPOT_DB_PASS=$(cat "$SECRETS_DIR/penpot-db-password")
      sudo -u postgres psql -c "ALTER USER penpot WITH PASSWORD '$PENPOT_DB_PASS';"
      echo "✅ Updated Penpot database user password"
    fi
    
    echo "🔧 Database users configured with secure passwords!"
  '';

in {
  options = {
    services.rave.secrets = {
      enable = mkEnableOption "RAVE cryptographic secret management";
      
      secretsDir = mkOption {
        type = types.path;
        default = "/var/lib/rave/secrets";
        description = "Directory to store generated secrets";
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Generate secrets at system activation
    system.activationScripts.rave-secrets = {
      text = ''
        # Generate secrets if they don't exist
        ${generateSecrets}
      '';
      deps = [ "var" ];
    };
    
    # Service to set up database users after PostgreSQL starts
    systemd.services.rave-setup-database = {
      description = "RAVE Database User Setup";
      after = [ "postgresql.service" "rave-secrets.service" ];
      wants = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = setupDatabaseUsers;
        RemainAfterExit = true;
        User = "root";
      };
    };
    
    # Service wrapper for secret generation (for dependencies)
    systemd.services.rave-secrets = {
      description = "RAVE Secret Generation";
      wantedBy = [ "multi-user.target" ];
      before = [ "gitlab.service" "postgresql.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = generateSecrets;
        RemainAfterExit = true;
        User = "root";
      };
    };
    
    # Helper scripts for manual secret management
    environment.systemPackages = [
      (pkgs.writeScriptBin "rave-generate-secrets" generateSecrets)
      (pkgs.writeScriptBin "rave-setup-database" setupDatabaseUsers)
    ];
  };
}