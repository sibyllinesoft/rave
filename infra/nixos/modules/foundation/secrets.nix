{ config, lib, pkgs, ... }:
let
  cfg = config.services.rave;
  inherit (lib) mkDefault mkIf types mkOption;
in {
  options.services.rave.devMode = mkOption {
    type = types.bool;
    default = false;
    description = "Enable lightweight, insecure defaults for local development (no SOPS/Age required).";
  };

  config = mkIf cfg.devMode {
    # Provide an insecure-but-convenient Authentik env file so developers can boot quickly.
    services.rave.authentik.environmentFile = mkDefault (pkgs.writeText "authentik.dev.env" ''
AUTHENTIK_SECRET_KEY=dev-authentik-secret
AUTHENTIK_BOOTSTRAP_PASSWORD=devpassword123
AUTHENTIK_BOOTSTRAP_EMAIL=admin@auth.localtest.me
AUTHENTIK_POSTGRESQL__PASSWORD=dev-authentik-db
RAVE_GITLAB_CLIENT_ID=rave-gitlab
RAVE_GITLAB_CLIENT_SECRET=dev-gitlab-secret
RAVE_MATTERMOST_CLIENT_ID=dev-mattermost
RAVE_MATTERMOST_CLIENT_SECRET=dev-mattermost-secret
RAVE_GRAFANA_CLIENT_ID=rave-grafana
RAVE_GRAFANA_CLIENT_SECRET=dev-grafana-secret
RAVE_PENPOT_CLIENT_ID=rave-penpot
RAVE_PENPOT_CLIENT_SECRET=dev-penpot-secret
RAVE_OUTLINE_CLIENT_ID=rave-outline
RAVE_OUTLINE_CLIENT_SECRET=dev-outline-secret
RAVE_N8N_CLIENT_ID=rave-n8n
RAVE_N8N_CLIENT_SECRET=dev-n8n-secret
RAVE_GOOGLE_CLIENT_ID=dummy-google-client-id
RAVE_GOOGLE_CLIENT_SECRET=dummy-google-client-secret
RAVE_GITHUB_CLIENT_ID=dummy-github-client-id
RAVE_GITHUB_CLIENT_SECRET=dummy-github-client-secret
'');

    # Avoid blocking builds on SOPS while in devMode.
    services.rave.gitlab.useSecrets = mkDefault false;
  };
}
