{ lib, pkgs, ... }:
{
  imports = [
    ./complete-production.nix
  ];

  config =
    let
      repoEnvFile = ../../../.env;
      envFileLines =
        if builtins.pathExists repoEnvFile
        then map lib.strings.trim (lib.splitString "\n" (builtins.readFile repoEnvFile))
        else [];
      fromEnvFile = key:
        let
          parseLine = line:
            if line == "" || lib.hasPrefix "#" line then null
            else
              let matched = builtins.match "${key}=(.*)" line;
              in if matched == null then null else lib.strings.trim (builtins.head matched);
          values = lib.filter (v: v != null) (map parseLine envFileLines);
          stripQuotes = value:
            let len = lib.stringLength value;
            in if len >= 2 && lib.hasPrefix "\"" value && lib.hasSuffix "\"" value
               then lib.strings.substring 1 (len - 2) value
               else value;
        in if values == [] then null else stripQuotes (lib.head values);
      requireSecret = name:
        let
          fromEnv = builtins.getEnv name;
          fromFile = fromEnvFile name;
          candidate =
            if fromEnv != "" then fromEnv
            else if fromFile != null && fromFile != "" then fromFile
            else "";
        in if candidate != "" then candidate else builtins.throw "Set ${name} in your shell or .env before building the production image.";
      googleClientId = requireSecret "GOOGLE_OAUTH_CLIENT_ID";
      googleClientSecret = requireSecret "GOOGLE_OAUTH_CLIENT_SECRET";
      githubClientId = requireSecret "GITHUB_OAUTH_CLIENT_ID";
      githubClientSecret = requireSecret "GITHUB_OAUTH_CLIENT_SECRET";
      googleClientIdFile = pkgs.writeText "authentik-google-client-id" googleClientId;
      googleClientSecretFile = pkgs.writeText "authentik-google-client-secret" googleClientSecret;
      githubClientIdFile = pkgs.writeText "authentik-github-client-id" githubClientId;
      githubClientSecretFile = pkgs.writeText "authentik-github-client-secret" githubClientSecret;
    in {
      # Run the “full” stack but keep things working without external SOPS/AGE state.
      services.rave.gitlab.useSecrets = lib.mkForce false;

      # Disable Pomerium so Traefik terminates TLS directly (per request).
      services.rave.pomerium.enable = lib.mkForce false;

      # Feed Authentik OAuth sources from the developer .env credentials.
      services.rave.authentik.oauthSources.google = {
        clientIdFile = googleClientIdFile;
        clientSecretFile = googleClientSecretFile;
      };
      services.rave.authentik.oauthSources.github = {
        clientIdFile = githubClientIdFile;
        clientSecretFile = githubClientSecretFile;
      };

      # Point GitLab's OAuth provider at the same Google credentials baked into the QCOW.
      services.rave.gitlab.oauth.clientId = lib.mkForce googleClientId;
      services.rave.gitlab.oauth.clientSecretFile = lib.mkForce googleClientSecretFile;
    };
}
