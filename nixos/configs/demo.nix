{ lib, ... }:
{
  imports = [
    ./production.nix
  ];

  config = {
    services.rave.monitoring.enable = lib.mkForce false;
    services.rave.penpot.enable = lib.mkForce false;
    services.rave.outline.enable = lib.mkForce false;
    services.rave.n8n.enable = lib.mkForce false;

    services.rave.mattermost.ciBridge.enable = lib.mkForce false;

    virtualisation.memorySize = lib.mkForce 6144;
    virtualisation.diskSize = lib.mkForce (24 * 1024);
  };
}
