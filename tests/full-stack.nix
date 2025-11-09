{ pkgs, sopsModule }:

let
  testLib = import (pkgs.path + "/nixos/lib/testing-python.nix") {
    inherit pkgs;
    system = pkgs.stdenv.hostPlatform.system;
  };
in
testLib.runTest {
  name = "rave-full-stack";

  nodes.machine = { lib, ... }: {
    imports = [
      sopsModule
      ../nixos/configs/production.nix
      ({ lib, ... }: {
        services.rave.gitlab.useSecrets = lib.mkForce false;
        services.rave.mattermost.gitlab.apiTokenFile = lib.mkForce "/var/lib/rave/gitlab-ci-token";

        systemd.services.gitlab-ci-token = {
          description = "Generate GitLab PAT for chat bridge tests";
          wantedBy = [ "multi-user.target" ];
          after = [ "gitlab.service" ];
          requires = [ "gitlab.service" ];
          environment = {
            HOME = "/var/gitlab/state/home";
            RAILS_ENV = "production";
            RAVE_TEST_TOKEN = "rave-ci-bridge-test-token";
          };
          serviceConfig = {
            Type = "oneshot";
            User = "gitlab";
            Group = "gitlab";
            TimeoutStartSec = "900s";
          };
          script = ''
            set -euo pipefail
            TOKEN_PATH=/var/lib/rave/gitlab-ci-token
            if [ -s "$TOKEN_PATH" ]; then
              exit 0
            fi

            mkdir -p /var/lib/rave
            /run/current-system/sw/bin/gitlab-rails runner - <<'RUBY'
  token_value = ENV.fetch("RAVE_TEST_TOKEN")
  token_name = "rave-ci-bridge-test-token"
  user = User.find_by_username("root") || User.first
  raise "root user missing" unless user
  existing = PersonalAccessToken.find_by(name: token_name, user: user)
  existing&.destroy!
  token = PersonalAccessToken.new(
    name: token_name,
    user: user,
    scopes: [:api, :read_api]
  )
  token.set_token(token_value)
  token.expires_at = 30.days.from_now
  token.save!
RUBY
            printf '%s\n' "$RAVE_TEST_TOKEN" > "$TOKEN_PATH"
            chown gitlab:gitlab "$TOKEN_PATH"
            chmod 0400 "$TOKEN_PATH"
          '';
        };

        systemd.services."gitlab-mattermost-ci-bridge".after = lib.mkAfter [ "gitlab-ci-token.service" ];
        systemd.services."gitlab-mattermost-ci-bridge".wants = lib.mkAfter [ "gitlab-ci-token.service" ];

        virtualisation.memorySize = lib.mkForce 12288;
        virtualisation.cores = lib.mkForce 4;
        virtualisation.graphics = lib.mkForce false;
      })
    ];
  };

  testScript = ''
    machine.start()

    machine.wait_for_unit("multi-user.target", timeout=1800)
    machine.wait_for_unit("gitlab.service", timeout=1800)
    machine.wait_for_unit("postgresql.service", timeout=900)
    machine.wait_for_unit("mattermost.service", timeout=900)
    machine.wait_for_unit("gitlab-mattermost-ci-bridge.service", timeout=900)
    machine.wait_for_unit("grafana.service", timeout=600)

    machine.wait_until_succeeds("systemctl is-active gitlab.service", timeout=600)
    machine.wait_until_succeeds("systemctl is-active mattermost.service", timeout=600)
    machine.wait_until_succeeds("systemctl is-active gitlab-mattermost-ci-bridge.service", timeout=600)
    machine.wait_until_succeeds("systemctl is-active grafana.service", timeout=600)
    machine.wait_until_succeeds("systemctl is-active nats.service", timeout=600)

    machine.wait_until_succeeds("test -s /var/lib/rave/gitlab-ci-token", timeout=120)
    machine.wait_until_succeeds("test -s /var/lib/rave/gitlab-mattermost-ci.json", timeout=120)

    machine.wait_until_succeeds(
      "journalctl -u gitlab-mattermost-ci-bridge -n 200 | grep -F '[ci-bridge]'",
      timeout=300
    )

    machine.wait_until_succeeds(
      "curl -k -sSf --max-time 60 https://localhost/mattermost/login",
      timeout=600
    )

    machine.wait_until_succeeds(
      "curl -k -sSf --max-time 60 https://localhost/grafana/login",
      timeout=600
    )
  '';
}
