{ pkgs, sopsModule, overlays ? [] }:

let
  testLib = import (pkgs.path + "/nixos/lib/testing-python.nix") {
    inherit pkgs;
    system = pkgs.stdenv.hostPlatform.system;
  };
in
testLib.runTest {
  name = "rave-minimal-vm";

  nodes.machine = { lib, ... }: {
    imports = [
      sopsModule
      ../infra/nixos/configs/production.nix
      ({ lib, ... }: {
        nixpkgs.overlays = overlays;
        services.rave.gitlab.enable = lib.mkForce true;
        services.rave.gitlab.useSecrets = lib.mkForce false;
        services.rave.mattermost.enable = lib.mkForce false;
        services.rave.monitoring.enable = lib.mkForce false;
        services.rave.penpot.enable = lib.mkForce false;
        services.rave.n8n.enable = lib.mkForce false;
        services.rave.outline.enable = lib.mkForce false;
        services.rave.coturn.enable = lib.mkForce false;
        services.rave.nats.enable = lib.mkForce false;

        virtualisation.memorySize = lib.mkForce 8192;
        virtualisation.cores = lib.mkForce 4;
        virtualisation.graphics = lib.mkForce false;
      })
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target", timeout=1200)
    machine.wait_for_unit("gitlab.service", timeout=1800)
    machine.wait_for_unit("postgresql.service", timeout=600)

    machine.wait_until_succeeds("systemctl is-active gitlab.service", timeout=600)
    machine.wait_until_succeeds("systemctl is-active postgresql.service", timeout=300)
    machine.wait_until_succeeds("systemctl is-active nginx.service", timeout=300)

    machine.wait_until_succeeds(
      "curl -k -sSf --max-time 45 https://localhost/gitlab/-/health",
      timeout=600
    )
  '';
}
