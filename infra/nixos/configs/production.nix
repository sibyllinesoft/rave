{ lib, pkgs, ... }:
{
  imports = [
    ./complete-production.nix
  ];

  config =
    let
      defaultSecretValues = {
        GOOGLE_OAUTH_CLIENT_ID = "local-google-client-id";
        GOOGLE_OAUTH_CLIENT_SECRET = "local-google-client-secret";
        GITHUB_OAUTH_CLIENT_ID = "local-github-client-id";
        GITHUB_OAUTH_CLIENT_SECRET = "local-github-client-secret";
      };
      requireSecret = name:
        let
          fromEnv = builtins.getEnv name;
          fallbackValue = defaultSecretValues.${name} or "";
          candidate =
            if fromEnv != "" then fromEnv
            else fallbackValue;
        in if candidate != ""
           then lib.trace "⚠️ Using ${name}=${candidate}; override via environment for real deployments." candidate
           else builtins.throw "Set ${name} in your shell or .env before building the production image.";
      googleClientId = requireSecret "GOOGLE_OAUTH_CLIENT_ID";
      googleClientSecret = requireSecret "GOOGLE_OAUTH_CLIENT_SECRET";
      githubClientId = requireSecret "GITHUB_OAUTH_CLIENT_ID";
      githubClientSecret = requireSecret "GITHUB_OAUTH_CLIENT_SECRET";
      googleClientIdFile = pkgs.writeText "authentik-google-client-id" googleClientId;
      googleClientSecretFile = pkgs.writeText "authentik-google-client-secret" googleClientSecret;
      githubClientIdFile = pkgs.writeText "authentik-github-client-id" githubClientId;
      githubClientSecretFile = pkgs.writeText "authentik-github-client-secret" githubClientSecret;
      parseCsvEnv = name:
        let raw = builtins.getEnv name;
        in if raw == "" then [] else lib.filter (s: s != "") (lib.splitString "," raw);
      allowedEmails = parseCsvEnv "RAVE_AUTHENTIK_ALLOWED_EMAILS";
      allowedDomains = parseCsvEnv "RAVE_AUTHENTIK_ALLOWED_DOMAINS";
    in {
      # Serve front-door via auth.localtest.me so Authentik/GitLab/Mattermost share the same host
      services.rave.traefik.host = lib.mkForce "auth.localtest.me";

      # Run the “full” stack but keep things working without external SOPS/AGE state.
      services.rave.gitlab.useSecrets = lib.mkForce false;

      # Disable Pomerium so Traefik terminates TLS directly (per request).
      services.rave.pomerium.enable = lib.mkForce false;

      # Feed Authentik OAuth sources from the developer .env credentials.
      # Set explicit fields so we don’t lose defaults if the module changes.
      services.rave.authentik.oauthSources = {
        google = {
          displayName = "Google";
          slug = "google";
          providerType = "google";
          clientIdFile = googleClientIdFile;
          clientSecretFile = googleClientSecretFile;
          extraScopes = [ "openid" "email" "profile" ];
          enrollmentFlow = "default-source-enrollment";
          authorizationUrl = "https://accounts.google.com/o/oauth2/v2/auth";
          accessTokenUrl = "https://oauth2.googleapis.com/token";
          profileUrl = "https://openidconnect.googleapis.com/v1/userinfo";
          oidcWellKnownUrl = "https://accounts.google.com/.well-known/openid-configuration";
        };
        github = {
          displayName = "GitHub";
          slug = "github";
          providerType = "github";
          clientIdFile = githubClientIdFile;
          clientSecretFile = githubClientSecretFile;
          extraScopes = [ "read:user" "user:email" ];
          enrollmentFlow = "default-source-enrollment";
          authorizationUrl = "https://github.com/login/oauth/authorize";
          accessTokenUrl = "https://github.com/login/oauth/access_token";
          profileUrl = "https://api.github.com/user";
        };
      };
      # Ensure Authentik generates callbacks on the forwarded host/port we expose locally.
      services.rave.authentik.publicUrl = lib.mkForce "https://auth.localtest.me:18443/";
      services.rave.authentik.defaultExternalPort = lib.mkForce "18443";
      services.rave.authentik.allowedEmails = allowedEmails;
      services.rave.authentik.allowedDomains = allowedDomains;

    };
}
