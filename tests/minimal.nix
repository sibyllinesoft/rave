{ pkgs }:

pkgs.nixosTest {
  name = "rave-minimal";

  nodes.machine = { lib, ... }: {
    imports = [
      ../infra/nixos/configs/production.nix
      ({ lib, ... }: {
        services.rave.gitlab.enable = lib.mkForce false;
        services.rave.gitlab.useSecrets = lib.mkForce false;
        services.rave.mattermost.enable = lib.mkForce false;
        services.rave.monitoring.enable = lib.mkForce false;
        services.rave.penpot.enable = lib.mkForce false;
        services.rave.n8n.enable = lib.mkForce false;
        services.rave.outline.enable = lib.mkForce false;
        services.rave.coturn.enable = lib.mkForce false;

        virtualisation.memorySize = lib.mkForce 2048;
        virtualisation.cores = lib.mkForce 2;
      })
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.wait_until_succeeds("systemctl is-active nginx")
    machine.wait_until_succeeds("systemctl is-active postgresql")

    machine.wait_until_succeeds(
        "curl -k -sSf --max-time 20 https://localhost"
    )
  '';
}
