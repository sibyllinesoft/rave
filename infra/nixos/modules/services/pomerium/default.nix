{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.rave.pomerium;

  pathOrString = types.either types.path types.str;

  yamlFormat = pkgs.formats.yaml { };

  trimTrailingSlash = value:
    if value == "/" then "/"
    else lib.removeSuffix "/" value;

  derivedAuthenticateUrl =
    let trimmed = trimTrailingSlash cfg.publicUrl;
    in if cfg.authenticateUrl != null then cfg.authenticateUrl else "${trimmed}/authenticate";

  filterNullOrEmpty = attrs:
    filterAttrs (_: v: v != null && v != [] && v != {}) attrs;

  policyToConfig = policy:
    let
      normalizedPrefix =
        if policy.path == null then null
        else if lib.hasPrefix "/" policy.path then policy.path else "/${policy.path}";
    in filterNullOrEmpty {
      name = policy.name;
      from = policy.from;
      prefix = normalizedPrefix;
      to = policy.to;
      pass_identity_headers = policy.passIdentityHeaders;
      preserve_host = policy.preserveHost;
      allow_public_unauthenticated = policy.allowPublicUnauthenticated;
      set_request_headers = policy.setRequestHeaders;
      allowed_domains = policy.allowedDomains;
      allowed_emails = policy.allowedEmails;
      timeout = policy.timeout;
    };

  pomeriumConfig =
    let
      tlsSettings =
        if cfg.tls.enable then
          filterNullOrEmpty {
            insecure_server = false;
            certificate_file = cfg.tls.certificateFile;
            certificate_key_file = cfg.tls.keyFile;
          }
        else {
          insecure_server = true;
        };
      base = filterNullOrEmpty (
        {
          address = ":${toString cfg.httpPort}";
          grpc_address = ":${toString cfg.grpcPort}";
          shared_secret = "$SHARED_SECRET";
          cookie_secret = "$COOKIE_SECRET";
          authenticate_service_url = derivedAuthenticateUrl;
          idp_provider = cfg.idp.provider;
          idp_provider_url = cfg.idp.providerUrl;
          idp_client_id = cfg.idp.clientId;
          idp_client_secret = "$IDP_CLIENT_SECRET";
          idp_scopes = cfg.idp.scopes;
          routes = map policyToConfig cfg.policies;
          pass_identity_headers = cfg.passIdentityHeaders;
          authorize_service_url = cfg.authorizeServiceUrl;
          forward_auth_url = cfg.forwardAuthUrl;
        }
        // tlsSettings
      );
    in recursiveUpdate base cfg.extraSettings;

  configTemplate = yamlFormat.generate "pomerium-config.yml" pomeriumConfig;

  exportSecret = name: inline: file:
    if file != null then ''
      if [ ! -s ${lib.escapeShellArg file} ]; then
        echo "Missing ${name} secret at ${file}" >&2
        exit 1
      fi
      export ${name}="$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg file})"
    '' else ''
      export ${name}=${lib.escapeShellArg inline}
    '';

  startScript = pkgs.writeShellScript "rave-pomerium-run" ''
    set -euo pipefail
    umask 077

    runtime_dir=/run/pomerium
    mkdir -p "$runtime_dir"

    ${exportSecret "SHARED_SECRET" cfg.sharedSecret cfg.sharedSecretFile}
    ${exportSecret "COOKIE_SECRET" cfg.cookieSecret cfg.cookieSecretFile}
    ${exportSecret "IDP_CLIENT_SECRET" cfg.idp.clientSecret cfg.idp.clientSecretFile}

    ${pkgs.gettext}/bin/envsubst '$SHARED_SECRET $COOKIE_SECRET $IDP_CLIENT_SECRET' < ${configTemplate} > "$runtime_dir/config.yaml"

    bundle="$runtime_dir/ca-bundle.pem"
    cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt > "$bundle"
    ${
      optionalString (cfg.idp.providerCaFile != null) ''
    if [ -s ${lib.escapeShellArg cfg.idp.providerCaFile} ]; then
      cat ${lib.escapeShellArg cfg.idp.providerCaFile} >> "$bundle"
    fi
      ''
    }
    export SSL_CERT_FILE="$bundle"

    exec ${lib.getExe cfg.package} --config "$runtime_dir/config.yaml"
  '';

  policyModule = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional friendly name displayed in Pomerium logs.";
      };

      from = mkOption {
        type = types.str;
        description = "Public URL users visit for this route (scheme + host only).";
      };

      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional path prefix enforced for the policy (set when from contains no path).";
      };

      to = mkOption {
        type = types.str;
        description = "Upstream service URL (http/https) that Pomerium proxies to.";
      };

      allowedDomains = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of email domains allowed to access the route.";
      };

      allowedEmails = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Explicit list of email addresses allowed to access the route.";
      };

      allowPublicUnauthenticated = mkOption {
        type = types.bool;
        default = false;
        description = "When true, bypasses authentication for the route (useful for smoke tests).";
      };

      passIdentityHeaders = mkOption {
        type = types.bool;
        default = true;
        description = "Forward identity headers like X-Pomerium-Claim-* to upstream services.";
      };

      preserveHost = mkOption {
        type = types.bool;
        default = true;
        description = "Forward the incoming Host header to the upstream service.";
      };

      setRequestHeaders = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Optional static headers to inject before proxying the request.";
      };

      timeout = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional duration (e.g., 30s) before the route times out.";
      };
    };
  });

in
{
  options.services.rave.pomerium = {
    enable = mkEnableOption "Pomerium identity-aware access proxy";

    package = mkOption {
      type = types.package;
      default = pkgs.pomerium;
      description = "Pomerium package to run.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "https://localhost:8443/pomerium";
      description = "Base URL exposed via nginx for Pomerium managed routes.";
    };

    authenticateUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override for the authenticate service URL. When null, `${publicUrl}/authenticate` is used.";
    };

    authorizeServiceUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional URL of an existing authorize service when running multi-binary deployments.";
    };

    forwardAuthUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional forward-auth endpoint for nginx/envoy integrations.";
    };

    httpPort = mkOption {
      type = types.int;
      default = 8740;
      description = "Loopback HTTP port Pomerium listens on (nginx proxies to this address).";
    };

    grpcPort = mkOption {
      type = types.int;
      default = 8741;
      description = "Loopback gRPC port for internal services.";
    };

    tls = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable TLS termination directly in Pomerium.";
      };

      certificateFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to the TLS certificate served by Pomerium.";
      };

      keyFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to the TLS private key served by Pomerium.";
      };
    };

    passIdentityHeaders = mkOption {
      type = types.bool;
      default = true;
      description = "Set global pass_identity_headers flag (routes can still override).";
    };

    sharedSecret = mkOption {
      type = types.nullOr types.str;
      default = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";
      description = "Base64-encoded shared secret used for signing internal service communication.";
    };

    sharedSecretFile = mkOption {
      type = types.nullOr pathOrString;
      default = null;
      description = "Optional file containing the shared secret (takes precedence over inline value).";
    };

    cookieSecret = mkOption {
      type = types.nullOr types.str;
      default = "ZmVkY2JhOTg3NjU0MzIxMGZlZGNiYTk4NzY1NDMyMTA=";
      description = "Base64-encoded secret for encrypting Pomerium session cookies.";
    };

    cookieSecretFile = mkOption {
      type = types.nullOr pathOrString;
      default = null;
      description = "Optional file containing the cookie secret (takes precedence over inline value).";
    };

    idp = {
      provider = mkOption {
        type = types.str;
        default = "gitlab";
        description = "Identity provider ID (e.g., gitlab, google, github, oidc).";
      };

      providerUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Explicit issuer URL for self-hosted providers (defaults vary by provider).";
      };

      clientId = mkOption {
        type = types.nullOr types.str;
        default = "pomerium-dev-client";
        description = "OAuth/OIDC client ID registered with the IdP.";
      };

      clientSecret = mkOption {
        type = types.nullOr types.str;
        default = "pomerium-dev-secret";
        description = "OAuth/OIDC client secret (use file override for production).";
      };

      clientSecretFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Path to a secret file containing the IdP client secret.";
      };
      providerCaFile = mkOption {
        type = types.nullOr pathOrString;
        default = null;
        description = "Optional PEM file trusted when contacting the IdP issuer.";
      };

      scopes = mkOption {
        type = types.listOf types.str;
        default = [ "openid" "profile" "email" ];
        description = "Additional scopes requested during login.";
      };
    };

    policies = mkOption {
      type = types.listOf policyModule;
      default = [];
      description = "List of proxy policies/routes managed by Pomerium.";
    };

    extraSettings = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = "Raw attrset merged into the generated config for advanced tuning.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.sharedSecret != null) || (cfg.sharedSecretFile != null);
        message = "services.rave.pomerium.sharedSecret or sharedSecretFile must be set.";
      }
      {
        assertion = (cfg.cookieSecret != null) || (cfg.cookieSecretFile != null);
        message = "services.rave.pomerium.cookieSecret or cookieSecretFile must be set.";
      }
      {
        assertion = (cfg.idp.clientSecret != null) || (cfg.idp.clientSecretFile != null);
        message = "services.rave.pomerium.idp.clientSecret or clientSecretFile must be set.";
      }
      {
        assertion = (!cfg.tls.enable) || ((cfg.tls.certificateFile != null) && (cfg.tls.keyFile != null));
        message = "services.rave.pomerium.tls certificateFile/keyFile must be set when TLS is enabled.";
      }
    ];

    systemd.services.pomerium = {
      description = "RAVE Pomerium Identity Proxy";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ]
        ++ lib.optionals config.security.rave.localCerts.enable [ "generate-localhost-certs.service" ];
      wants = [ "network-online.target" ];
      requires = lib.optionals config.security.rave.localCerts.enable [ "generate-localhost-certs.service" ];
      path = with pkgs; [ coreutils gettext ];
      serviceConfig = {
        Type = "simple";
        ExecStart = startScript;
        Restart = "on-failure";
        RuntimeDirectory = "pomerium";
        RuntimeDirectoryMode = "0750";
      };
    };
  };
}
