# Auth Manager — Implementation Plan

## Objective
Provision users from Authentik to downstream community-edition apps (Mattermost, n8n) that only understand local users. Auth-manager receives webhook notifications from Authentik when users are created/updated/login and pre-provisions them to downstream services.

## Current Status (2025-11-28)
- Simplified webhook-based architecture (removed Pomerium dependency)
- Receives Authentik webhook notifications for user events
- Provisions users to Mattermost via REST API
- Shadow user store (PostgreSQL or in-memory) tracks provisioned users
- Manual sync endpoint for testing/recovery

## Completed
1. **Webhook handler for Authentik events**
   - [x] Parse Authentik webhook payload (standard + custom body mapping)
   - [x] Validate webhook secret (Bearer token in Authorization header)
   - [x] Extract user info from various payload formats
   - [x] Filter for user-related events (model_created, model_updated, login)

2. **Shadow user persistence**
   - [x] PostgreSQL backend with upsert semantics
   - [x] In-memory fallback for development
   - [x] Track provider, subject, email, name, attributes

3. **Mattermost provisioning**
   - [x] REST API client for user creation
   - [x] Ensure user exists (create if needed)
   - [x] Circuit breaker for resilience

4. **Operational**
   - [x] Health/readiness probes
   - [x] Prometheus metrics
   - [x] Structured logging
   - [x] Manual sync endpoint

## Remaining Work

### Phase 1: NixOS Integration
- [ ] Update auth-manager NixOS module for new config (remove Pomerium settings)
- [ ] Add Authentik webhook transport configuration via NixOS
- [ ] Wire secrets (webhook secret, Mattermost token) through sops-nix
- [ ] Add to complete-production.nix

### Phase 2: Integration Testing
- [ ] Docker compose for local testing (PostgreSQL + Mattermost + auth-manager)
- [ ] Mock Authentik webhook sender for testing
- [ ] Test webhook → provision flow
- [ ] Test circuit breaker behavior

### Phase 3: E2E Testing
- [ ] Full stack test with real Authentik
- [ ] Create user in Authentik → verify provisioned to Mattermost
- [ ] User logs into Mattermost via OIDC → verify already exists
- [ ] Test user update propagation

### Future Enhancements
- [ ] n8n provisioning (if API becomes available)
- [ ] User deprovisioning (delete/disable handling)
- [ ] Group/team sync to Mattermost
- [ ] Bulk sync endpoint for initial population
- [ ] Retry queue for failed provisions
