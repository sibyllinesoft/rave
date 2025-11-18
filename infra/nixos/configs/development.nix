{ lib, ... }:
{
  imports = [
    ./production.nix
  ];

  config = {
    services.rave.outline.enable = lib.mkForce false;
    services.rave.n8n.enable = lib.mkForce false;
    services.rave.penpot.enable = lib.mkForce false;
    services.rave.gitlab.useSecrets = lib.mkForce false;

    virtualisation.memorySize = lib.mkForce 8192;
    virtualisation.diskSize = lib.mkForce (30 * 1024);
  };
}
