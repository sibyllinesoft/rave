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
    services.rave.traefik.enable = lib.mkForce false;

    services.rave.postgresql.enable = lib.mkForce true;
    services.rave.postgresql.listenAddresses = "0.0.0.0";
    services.postgresql.authentication = ''
      local   all     all                     trust
      host    all     all     127.0.0.1/32    trust
      host    all     all     ::1/128         trust
      host    all     all     172.17.0.0/16   md5
      host    all     all     10.244.0.0/16   md5
      host    all     all     10.0.0.0/8      md5
    '';

    services.rave.redis = {
      enable = lib.mkForce true;
      bind = "0.0.0.0";
      clientHost = "0.0.0.0";
      dockerHost = "0.0.0.0";
    };

    networking.firewall.allowedTCPPorts = lib.mkAfter [ 5432 6379 ];
  };
}
