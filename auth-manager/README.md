# Auth Manager

Auth Manager is a lightweight Go service that sits *behind* Pomerium. Pomerium continues to own the OAuth/OIDC contract; once a user is authenticated it forwards signed identity headers (and the JWT assertion) to Auth Manager. Auth Manager's job is to take that identity context, mint or update \"shadow\" local accounts in community-edition applications (Mattermost, etc.), and short-circuit their legacy login flows.

## Current skeleton

- HTTP server with `/healthz`, `/api/v1/shadow-users`, `/bridge/mattermost`, and JWT helper endpoints (`/api/v1/tokens/*`) for downstream services.
- Minimal Mattermost REST client that can upsert users + mint sessions (requires an admin/bot token).
- In-memory shadow user store plus placeholder data model.
- Environment-driven configuration so the service can run inside the RAVE VM or locally.
- Graceful shutdown wiring and structured logging scaffolding.

## Quick start

```bash
cd auth-manager
# ensure Go 1.21+ is available
cp .env.example .env  # optional, set environment variables
GO113MODULE=on go run ./cmd/auth-manager
```

Environment variables (all optional today):

| Variable | Description | Default |
| --- | --- | --- |
| `AUTH_MANAGER_LISTEN_ADDR` | HTTP listen address | `:8088` |
| `AUTH_MANAGER_MATTERMOST_URL` | Base URL for Mattermost that will receive shadow auth events | `http://127.0.0.1:8065` |
| `AUTH_MANAGER_SOURCE_IDP` | Friendly name for the upstream IdP | `gitlab` |
| `AUTH_MANAGER_SIGNING_KEY` / `_FILE` | HMAC key for issuing Auth Manager JWTs | randomly generated at boot |
| `AUTH_MANAGER_DATABASE_URL` | If set, enable the PostgreSQL-backed shadow store (standard DSN) | _(empty)_ |
| `AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN` / `_FILE` | Personal access token (or bot token) with rights to create users + sessions | _(empty)_ |
| `AUTH_MANAGER_POMERIUM_SHARED_SECRET` / `_FILE` | Shared secret that matches the one configured in Pomerium so we can verify `X-Pomerium-Jwt-Assertion` | _none (required)_ |

## Pomerium forwarding contract

1. Configure the relevant Pomerium policy/route so that requests are first sent to Auth Manager (e.g., `/bridge/mattermost`).  
2. Pomerium must attach `X-Pomerium-Jwt-Assertion` and the `X-Pomerium-Claim-*` headers. Auth Manager validates the JWT with the shared secret above and records the identity in its shadow-user store.
3. Auth Manager responds with JSON describing the shadow user plus the Mattermost session token (`MMAUTHTOKEN`) that the caller can convert into cookies before redirecting the browser to Mattermost.

## Token bridging API

- `POST /api/v1/tokens/issue` (requires a valid Pomerium assertion) — body `{ "subject": "...", "audience": ["service"], "ttl_seconds": 300, "claims": { ... } }`. The subject defaults to the authenticated user. Returns the signed JWT plus its expiry timestamp.
- `POST /api/v1/tokens/validate` (same auth) — body `{ "token": "..." }`. Returns the verified claims if the token checks out.

Tokens are signed with `AUTH_MANAGER_SIGNING_KEY` (HS256) and are independent from Pomerium's shared secret so key rotation can happen without touching the proxy.

## Operational endpoints

- `GET /healthz` — lightweight liveness probe.
- `GET /readyz` — readiness probe that confirms the configured shadow store responds (PostgreSQL ping when enabled).
- `GET /metrics` — Prometheus exposition (`auth_manager_tokens_issued_total`, `auth_manager_mattermost_sessions_total`, etc.).

## Roadmap hooks

- Wire `/api/v1/oauth/exchange` to consume OAuth callbacks.
- Synchronize generated shadow identities into Mattermost via its REST API.
- Emit short-lived session tokens that Pomerium (or nginx forward-auth) can validate.
- Persist state in PostgreSQL or Redis instead of the in-memory map provided here.

## Handoff notes

- See `TODO.md` in this directory for the current implementation plan, status checkpoints, and sequencing for the next agent.
- Pomerium is now the sole upstream identity broker; Auth Manager should never call GitLab/Google directly. Instead, extend the bridge endpoints so they can manipulate downstream apps once Pomerium calls in with a verified identity.
- Local Go toolchain on this host currently fails before compilation (`runExitHooks redeclared`); consider using `nix develop` or a containerized Go 1.21 toolchain until the system compiler is repaired.
