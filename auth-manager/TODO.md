# Auth Manager — Implementation Plan

## Objective
Provide a downstream control plane for Pomerium-managed applications. Pomerium remains the OAuth/OIDC broker; Auth Manager consumes the identity context it forwards (JWT + headers), then minting/synchronizing local accounts and session artifacts for community-edition apps (Mattermost, etc.) that only understand local users.

## Current Status (2025-11-11)
- Skeleton Go service exists with `/healthz`, `/api/v1/shadow-users`, `/api/v1/oauth/exchange` (placeholder) and an in-memory store.
- Environment-driven config + graceful shutdown wiring are in place.
- No persistence, OAuth flow, or downstream integrations have been implemented yet.

## Work Plan
1. **Pomerium contract & identity ingestion**
   - [x] Document which Pomerium headers / JWT claims Auth Manager will trust and how the shared secret is supplied.
   - [x] Implement middleware that validates `X-Pomerium-Jwt-Assertion`, extracts identity fields, and places them in request context.
   - [x] Expose a bridging endpoint (e.g. `/bridge/mattermost`) that Pomerium can target before hitting the legacy app, returning actionable responses (shadow user info, next-hop URL, etc.).
   - [x] Add unit tests around JWT verification + claim parsing (use a shared-secret fixture).

2. **Shadow user lifecycle + persistence**
   - [x] Replace `MemoryStore` with a pluggable storage backend (PostgreSQL preferred; fall back to in-memory for dev).
   - [x] Model `shadow_users` table (identity key, profile, timestamps, external references).
   - [x] Add optimistic locking or upsert semantics consistent with Mattermost expectations.

3. **Mattermost + downstream fan-out**
   - [x] Create client wrapper for Mattermost REST API segments needed to create/update users and trigger session creation.
   - [x] Decide on transport for handing session assertions (direct API calls vs. posting to a shared Redis channel). _Decision: direct REST calls from Auth Manager + JSON response back to Pomerium._
   - [x] Document expected configuration knobs (admin token/URL) and thread them through `Config`.

4. **Session/token bridging**
   - [x] Introduce signing/crypto material for the app-facing assertions (separate from the Pomerium shared secret).
   - [x] Generate the tokens/cookies that downstream apps expect (e.g., Mattermost session tokens) and hand them to Pomerium/clients.
   - [x] Provide a validate/introspect endpoint for other internal callers if needed.

5. **Operational hardening**
   - [x] Logging/metrics: hook in structured logging + Prometheus counters for auth flows and downstream fan-out.
   - [x] Add readiness/liveness probes distinct from `/healthz`.
   - [ ] Provide systemd unit + NixOS module once the binary stabilizes.

## Testing/Dev Notes
- Target Go 1.21 or newer. Local toolchain currently reports errors; validate inside `nix develop` shell or container before merging.
- Add integration tests using dockerised GitLab CE + Mattermost stub when fan-out work starts.

## Handoff Checklist
- Secrets locations + IdP setup documented in README.
- At least one end-to-end flow demonstrated (GitLab login → shadow user persisted → Mattermost session minted).
- Provide CLI smoke test instructions once endpoints solidify.
