# Auth Manager

Auth Manager is a lightweight Go service that provides SSO bridging between Authentik and applications (like Mattermost) that don't natively support federated identity.

## Architecture

Auth-manager supports two modes of operation:

### Mode 1: Webhook-based Pre-provisioning

```
Authentik (IdP)
     │
     │ webhook (user created/updated/login)
     ▼
┌─────────────────┐
│  Auth Manager   │──→ Shadow Store (PostgreSQL)
│                 │
│                 │──→ Mattermost API (user created)
└─────────────────┘
```

Users are pre-provisioned to Mattermost when they sign up in Authentik.
They still need to click "Login with Authentik" in Mattermost.

### Mode 2: ForwardAuth Auto-login (Full SSO)

```
User ──→ Traefik ──→ Authentik Outpost ──→ Auth Manager ──→ Mattermost
              │            │                     │
              │      (forward-auth)        (forward-auth)
              │            │                     │
              │     X-Authentik-Email      Set-Cookie:
              │     X-Authentik-Name       MMAUTHTOKEN
              │                            MMUSERID
              └──────────────────────────────────────────→ Mattermost
                                                (with session cookies)
```

This provides true SSO where users are automatically logged into Mattermost
after authenticating with Authentik - no additional login required.

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Liveness probe |
| `/readyz` | GET | Readiness probe (checks shadow store) |
| `/webhook/authentik` | POST | Receives Authentik webhook notifications |
| `/auth/mattermost` | GET | ForwardAuth endpoint for Mattermost session injection |
| `/api/v1/sync` | POST | Manual user sync trigger |
| `/api/v1/shadow-users` | GET | List all shadow users |
| `/metrics` | GET | Prometheus metrics |

## Configuration

Environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTH_MANAGER_LISTEN_ADDR` | HTTP listen address | `:8088` |
| `AUTH_MANAGER_MATTERMOST_URL` | Public Mattermost URL | `https://localhost:8443/mattermost` |
| `AUTH_MANAGER_MATTERMOST_INTERNAL_URL` | Internal Mattermost API URL | `http://127.0.0.1:8065` |
| `AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN` | Mattermost admin/bot token | _(required)_ |
| `AUTH_MANAGER_WEBHOOK_SECRET` | Secret for validating Authentik webhooks | _(auto-generated)_ |
| `AUTH_MANAGER_DATABASE_URL` | PostgreSQL connection string | _(in-memory if empty)_ |

All `_TOKEN` and `_SECRET` variables also support `_FILE` suffix for reading from files.

## Quick Start

```bash
# From repo root
nix develop

cd apps/auth-manager
cp .env.example .env  # Edit with your values
go run ./cmd/auth-manager
```

## Setup for Full SSO (Mode 2)

Full SSO requires:

1. **Authentik Proxy Provider** - Create a proxy provider for Mattermost in Authentik
2. **Authentik Outpost** - Deploy the embedded outpost for forward-auth
3. **Traefik Configuration** - Chain the forward-auth middlewares

### NixOS Declarative Configuration (Recommended)

When using the RAVE NixOS modules, full SSO is configured automatically. Add to your configuration:

```nix
services.rave.authentik = {
  enable = true;
  # ... other authentik config ...

  # Proxy provider for ForwardAuth SSO
  proxyProviders = {
    mattermost-sso = {
      enable = true;
      name = "Mattermost SSO";
      slug = "mattermost-sso";
      externalHost = "https://your-domain.com:8443";
      mode = "forward_single";
      authorizationFlow = "default-provider-authorization-implicit-consent";
      skipPathRegex = "^/(api/v4/(websocket|users/login)|static/).*";
      application = {
        name = "Mattermost (SSO)";
        launchUrl = "https://your-domain.com:8443/mattermost";
        description = "Mattermost with ForwardAuth SSO";
      };
      addToOutpost = true;
    };
  };
};

services.rave.auth-manager = {
  enable = true;
  mattermost = {
    url = "https://your-domain.com:8443/mattermost";
    internalUrl = "http://127.0.0.1:8065";
    adminTokenFile = "/run/secrets/auth-manager/mattermost-admin-token";
  };
};
```

The NixOS modules automatically:
- Create the Authentik proxy provider and add it to the embedded outpost
- Configure Traefik middlewares: `authentik-forward-auth` → `mattermost-auth`
- Chain the middlewares on the Mattermost route

### Manual Configuration

If not using NixOS, configure manually:

#### Step 1: Create Authentik Proxy Provider

In Authentik Admin:
1. Go to **Applications > Providers**
2. Create a **Proxy Provider**:
   - Name: `mattermost-proxy`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Mode: `Forward auth (single application)`
   - External host: `https://your-domain.com`

#### Step 2: Create Authentik Application

1. Go to **Applications > Applications**
2. Create application:
   - Name: `Mattermost`
   - Slug: `mattermost`
   - Provider: Select `mattermost-proxy`

#### Step 3: Configure Outpost

1. Go to **Applications > Outposts**
2. Edit the embedded outpost or create a new one
3. Add the `mattermost` application to the outpost

#### Step 4: Traefik Configuration

Configure two ForwardAuth middlewares in order:

```yaml
# traefik dynamic config
http:
  middlewares:
    authentik-forward-auth:
      forwardAuth:
        address: "http://127.0.0.1:9130/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader: true
        authResponseHeaders:
          - X-Authentik-Username
          - X-Authentik-Groups
          - X-Authentik-Email
          - X-Authentik-Name
          - X-Authentik-Uid

    mattermost-auth:
      forwardAuth:
        address: "http://127.0.0.1:8088/auth/mattermost"
        authRequestHeaders:
          - X-Authentik-Email
          - X-Authentik-Username
          - X-Authentik-Name
          - Cookie
        addAuthCookiesToResponse:
          - MMAUTHTOKEN
          - MMUSERID

  routers:
    mattermost:
      rule: "Host(`your-domain.com`) && PathPrefix(`/mattermost`)"
      middlewares:
        - authentik-forward-auth
        - mattermost-auth
        - mattermost-strip-prefix
      service: mattermost
```

## Authentik Webhook Setup (Mode 1)

For pre-provisioning users via webhooks:

1. In Authentik Admin, go to **Events > Transports**
2. Create a new **Webhook** transport:
   - Name: `auth-manager`
   - Webhook URL: `http://auth-manager:8088/webhook/authentik`
3. Go to **Events > Rules**
4. Create a notification rule binding the transport to user events

## Manual Sync

You can manually trigger a user sync via the API:

```bash
curl -X POST http://localhost:8088/api/v1/sync \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "name": "Test User", "username": "testuser"}'
```

## Metrics

- `auth_manager_webhooks_received_total` - Number of webhook events received
- `auth_manager_users_provisioned_total` - Number of users provisioned to downstream services

## Development

```bash
# Run tests
go test ./...

# Build binary
go build -o auth-manager ./cmd/auth-manager
```

## Secrets Configuration

Add to `config/secrets.yaml`:

```yaml
auth-manager:
  webhook-secret: <generate-random-secret>
  mattermost-admin-token: <mattermost-personal-access-token>
```

Generate a webhook secret:
```bash
openssl rand -base64 32
```

Get Mattermost admin token:
1. Log into Mattermost as admin
2. Go to Profile > Security > Personal Access Tokens
3. Create a token with `create_user` and `manage_system` permissions
