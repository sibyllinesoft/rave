# Authentik in RAVE

RAVE now ships Authentik by default, running the upstream `ghcr.io/goauthentik/server`
and `worker` containers inside the VM. The module wires Authentik into the shared PostgreSQL and
Redis instances, publishes it behind Traefik (default URL: `https://auth.localtest.me:8443/`), and
adds it to the landing-page + status dashboards. This guide covers the secrets you must provide,
how to customise the baked-in defaults, and how to make Pomerium optional now that Authentik is
always present.

## 1. Prerequisites

- `nix` + `sops` set up (same requirements as the standard production build).
- Local Age key that can decrypt `config/secrets.yaml`.
- TLS trusted for any new hostnames you plan to expose (run `rave tls issue --domain auth.localtest.me`
  if you stick with the defaults).

## 2. Add Authentik secrets

Use `sops config/secrets.yaml` and add three encrypted entries:

```yaml
authentik:
    secret-key: <random 50+ char string>
    bootstrap-password: <initial admin password>
database:
    authentik-password: <DB password Authentik will use>
```

The Nix config already maps those selectors to the following runtime paths:

| Selector | Path inside VM | Purpose |
| --- | --- | --- |
| `["authentik"]["secret-key"]` | `/run/secrets/authentik/secret-key` | `AUTHENTIK_SECRET_KEY` |
| `["authentik"]["bootstrap-password"]` | `/run/secrets/authentik/bootstrap-password` | admin password |
| `["database"]["authentik-password"]` | `/run/secrets/database/authentik-password` | PostgreSQL user |

Commit the encrypted file and keep the private Age key outside the repo.

## 3. Customise Authentik (optional)

AuthentiK defaults:
- Public URL: `https://auth.localtest.me:8443/`
- Internal port: `127.0.0.1:9130`
- Metrics: `127.0.0.1:9131`

Tune them by extending `services.rave.authentik` in a small overlay module if you need different
ports or domains.

## 4. (Optional) Disable Pomerium

When Authentik is fronting the stack you can skip Pomerium entirely. Set
`RAVE_DISABLE_POMERIUM=1` alongside the build so the VM comes up with Traefik exposed directly:

```bash
export RAVE_DISABLE_POMERIUM=1
rave vm build-image --profile production
```

The rest of the stack (GitLab, Mattermost, Grafana, etc.) still works, and the welcome dashboard
will omit the Pomerium instructions.

## 5. First boot checklist

1. Launch the VM (`rave vm launch-local --profile production --https-port 8443`).
2. Ensure `authentik-server.service` and `authentik-worker.service` are running:
   ```bash
   rave vm logs localhost authentik-server --follow
   ```
3. Visit `https://auth.localtest.me:8443/` (add the domain to your local certificate via
   `rave tls issue --domain auth.localtest.me` if needed).
4. Sign in with the bootstrap admin account, rotate the password, and configure your providers.
5. Wire Authentik into Traefik or downstream apps as desired (the reverse proxy already forwards
   `X-Forwarded-*` headers and HSTS).

## 6. Customising the module

`infra/nixos/modules/services/authentik/default.nix` exposes knobs for:

- `services.rave.authentik.publicUrl` — host/path Traefik should route.
- `services.rave.authentik.bootstrap.*` — initial admin email / password.
- `services.rave.authentik.database.*` and `.redis.*` — point at external stores if needed.
- `services.rave.authentik.email.*` — enable SMTP notifications.
- `services.rave.authentik.extraEnv` — pass additional `AUTHENTIK_*` settings.

## 7. Enabling Google/GitHub login buttons

Authentik now ships with two managed OAuth sources out of the box:

- `google` – uses the official Google OAuth/OIDC endpoints.
- `github` – talks to github.com (you can override the URLs for GHE).

Add the following entries to `config/secrets.yaml` (encrypted via `sops`) so the CLI can
install them into `/run/secrets/authentik/**` during `rave secrets install`:

```yaml
authentik:
  google-client-id: <Google OAuth client ID>
  google-client-secret: <Google OAuth client secret>
  github-client-id: <GitHub OAuth client ID>
  github-client-secret: <GitHub OAuth client secret>
```

On boot the VM runs a helper that reads those secrets and reconciles the corresponding
Authentik `OAuthSource` objects (including binding them to the default authentication flow and
identification stage), so the login buttons appear automatically. To tweak or add further
providers, override `services.rave.authentik.oauthSources` in Nix. Each entry lets you disable
the source, change the scopes, point at alternative endpoints (GitHub Enterprise, Okta, etc.),
or add custom stages/flows.

Drop an override module into `config/overrides` or pass `--arg modules` to `nix build` if you need
per-tenant tweaks.

That’s it—Authentik is now a first-class, always-on layer in the image, so downstream services can
standardise on it while Pomerium remains an optional value add.
