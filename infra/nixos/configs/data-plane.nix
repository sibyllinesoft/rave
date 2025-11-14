{ lib, ... }:
{
  imports = [ ./production.nix ];

  config = {
    services.rave.gitlab.enable = lib.mkForce false;
    services.rave.mattermost.enable = lib.mkForce false;
    services.rave.monitoring.enable = lib.mkForce false;
    services.rave.penpot.enable = lib.mkForce false;
    services.rave.outline.enable = lib.mkForce false;
    services.rave.n8n.enable = lib.mkForce false;
    services.rave.nats.enable = lib.mkForce false;
    services.rave.pomerium.enable = lib.mkForce false;
    services.rave.auth-manager.enable = lib.mkForce false;
    services.rave.nginx.enable = lib.mkForce false;

    services.rave.postgresql.enable = lib.mkForce true;
    services.rave.postgresql.listenAddresses = "0.0.0.0";

    services.rave.redis = {
      enable = lib.mkForce true;
      bind = "0.0.0.0";
      clientHost = "0.0.0.0";
      dockerHost = "0.0.0.0";
    };

    networking.firewall.allowedTCPPorts = lib.mkAfter [ 5432 6379 ];
  };
}
