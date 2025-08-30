# Company Template Configuration
# Extends development.nix with dynamic SSH key injection for company deployments
#
# Usage:
# {
#   imports = [ ./company-template.nix ];
#   companyName = "demo-corp";
#   sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample...";
# }

{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    companyName = mkOption {
      type = types.str;
      description = "Company name for hostname and identification";
      example = "demo-corp";
    };

    sshPublicKey = mkOption {
      type = types.str;
      description = "SSH public key content for authorized access";
      example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample...";
    };
  };

  config = {
    # Import the base development configuration
    imports = [ ./development.nix ];

    # Override hostname based on company name
    networking.hostName = mkForce "rave-${config.companyName}";

    # Override SSH authorized keys with provided key
    users.users.root.openssh.authorizedKeys.keys = mkForce [
      config.sshPublicKey
    ];

    # Optionally disable password authentication for better security
    # Uncomment if you want key-only authentication
    # services.openssh.settings.PasswordAuthentication = mkForce false;
    # services.openssh.settings.PermitRootLogin = mkForce "prohibit-password";

    # Add company identification to MOTD
    users.motd = mkForce ''
      Welcome to RAVE Development VM
      Company: ${config.companyName}
      Hostname: ${config.networking.hostName}
      
      Services running:
      - nginx (reverse proxy with SSL): https://localhost:8443/
      - NATS Server: nats://localhost:4222
      - PostgreSQL: postgresql://localhost:5432
      - Redis: redis://localhost:6379
      - VM status page: http://localhost:8889/
      
      For support, contact the development team.
    '';

    # Optional: Add company-specific environment variable
    environment.variables = {
      RAVE_COMPANY = config.companyName;
    };

    # Optional: Custom systemd service for company-specific initialization
    systemd.services.company-init = {
      description = "Company-specific initialization for ${config.companyName}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Company-specific initialization can go here
        echo "Initialized RAVE VM for ${config.companyName}" > /var/log/company-init.log
        echo "SSH access configured with provided public key" >> /var/log/company-init.log
      '';
    };
  };
}